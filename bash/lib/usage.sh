# =============================================================================
# usage.sh — Token usage tracking
# Uses SQLite to store session history; attempts to read token counts from
# Claude Code's session JSONL files after exit.
# =============================================================================

set -euo pipefail

CC_USAGE_DB="${CCSWITCHER_ROOT}/data/.usage.db"
CC_USAGE_LOG="${CCSWITCHER_ROOT}/data/.usage-log.jsonl"

# In-memory session tracking
_CC_SESSION_STARTED_AT=""
_CC_SESSION_PROVIDER=""
_CC_SESSION_LATEST_FILE=""

#------------------------------------------------------------------------------
# Internal: ensure SQLite DB and table exist
#------------------------------------------------------------------------------
_usage_db_init() {
  if [[ ! -f "$CC_USAGE_DB" ]]; then
    sqlite3 "$CC_USAGE_DB" \
      "CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL,
        provider TEXT NOT NULL,
        opus_model TEXT,
        duration_sec REAL DEFAULT 0,
        turns INTEGER DEFAULT 0,
        tokens_in INTEGER DEFAULT 0,
        tokens_out INTEGER DEFAULT 0,
        cache_read INTEGER DEFAULT 0,
        cache_create INTEGER DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_sessions_ts ON sessions(ts);
      CREATE TABLE IF NOT EXISTS schema_version (version INTEGER DEFAULT 1);" \
      2>/dev/null || true
  fi
}

#------------------------------------------------------------------------------
# write-cc-session-start — called before claude launches
#------------------------------------------------------------------------------
write_cc_session_start() {
  local provider_name="$1"
  local opus_model="$2"

  _CC_SESSION_STARTED_AT=$(date +%s)
  _CC_SESSION_PROVIDER="$provider_name"
  _CC_SESSION_LATEST_FILE=""

  # Seed the jsonl log for compatibility
  mkdir -p "$(dirname "$CC_USAGE_LOG")"
}

#------------------------------------------------------------------------------
# write-cc-session-end — called after claude exits; aggregates tokens
#------------------------------------------------------------------------------
write_cc_session_end() {
  local provider_name="${1:-$_CC_SESSION_PROVIDER}"
  local ended_at=${_CC_SESSION_STARTED_AT:-$(date +%s)}
  local now
  now=$(date +%s)
  local duration=$(( now - ended_at ))

  # Try to find new/updated session JSONL files from this session
  local tokens_in=0 tokens_out=0 cache_read=0 cache_create=0 turns=0
  local sessions_root="$HOME/.claude/projects"

  if [[ -d "$sessions_root" ]]; then
    local -a jsonl_files
    # Find jsonl files modified since session start (with a buffer)
    while IFS= read -r -d '' f; do
      local mtime
      mtime=$(stat -c %Y "$f" 2>/dev/null) || continue
      if (( mtime >= ended_at - 5 )); then
        jsonl_files+=("$f")
      fi
    done < <(find "$sessions_root" -name "*.jsonl" -print0 2>/dev/null)

    for f in "${jsonl_files[@]:-}"; do
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip non-message lines
        local msg_type
        msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue
        [[ "$msg_type" != "user" ]] && [[ "$msg_type" != "assistant" ]] && continue

        local input_tokens output_tokens
        input_tokens=$(echo "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null) || input_tokens=0
        output_tokens=$(echo "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null) || output_tokens=0
        local cr
        cr=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null) || cr=0
        local cc
        cc=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null) || cc=0

        tokens_in=$(( tokens_in + input_tokens ))
        tokens_out=$(( tokens_out + output_tokens ))
        cache_read=$(( cache_read + cr ))
        cache_create=$(( cache_create + cc ))
        ((turns++))
      done < "$f"
    done
  fi

  # Write JSONL log for compatibility
  local ts_iso
  ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "{\"ts\":\"$ts_iso\",\"provider\":\"$provider_name\",\"durationSec\":$duration,\"turns\":$turns,\"tokensIn\":$tokens_in,\"tokensOut\":$tokens_out,\"cacheRead\":$cache_read,\"cacheCreate\":$cache_create}"
  } >> "$CC_USAGE_LOG"

  # Insert into SQLite
  _usage_db_init
  sqlite3 "$CC_USAGE_DB" \
    "INSERT INTO sessions (ts, provider, opus_model, duration_sec, turns, tokens_in, tokens_out, cache_read, cache_create)
     VALUES ('$ts_iso', '$provider_name', '', $duration, $turns, $tokens_in, $tokens_out, $cache_read, $cache_create);" \
    2>/dev/null || true
}

#------------------------------------------------------------------------------
# get-cc-usage — display token usage history
#------------------------------------------------------------------------------
get_cc_usage() {
  local last="${1:-20}"

  _usage_db_init

  if [[ ! -f "$CC_USAGE_DB" ]]; then
    echo "[cc-usage] No usage data yet ($CC_USAGE_DB)"
    return
  fi

  echo ""
  echo " cc-switcher usage (last $last sessions) "
  echo "================================================================================"

  # Print last N sessions from JSONL (more detailed)
  if [[ -f "$CC_USAGE_LOG" ]]; then
    printf "%-19s %-32s %8s %7s %9s %9s\n" "When" "Provider" "Duration" "Turns" "Tokens In" "Tokens Out"
    echo "--------------------------------------------------------------------------------"

    tail -n "$last" "$CC_USAGE_LOG" 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ts provider durationSec turns tokensIn tokensOut
      ts=$(echo "$line" | jq -r '.ts // empty' 2>/dev/null) || continue
      provider=$(echo "$line" | jq -r '.provider // empty' 2>/dev/null) || continue
      durationSec=$(echo "$line" | jq -r '.durationSec // 0' 2>/dev/null)
      turns=$(echo "$line" | jq -r '.turns // 0' 2>/dev/null)
      tokensIn=$(echo "$line" | jq -r '.tokensIn // 0' 2>/dev/null)
      tokensOut=$(echo "$line" | jq -r '.tokensOut // 0' 2>/dev/null)

      local when
      when=$(date -d "$ts" +"%Y-%m-%d %H:%M" 2>/dev/null) || when="$ts"
      printf "%-19s %-32s %7ss %7s %9s %9s\n" \
        "$when" "$provider" "$durationSec" "$turns" \
        "$(printf '%d' "$tokensIn" 2>/dev/null)" \
        "$(printf '%d' "$tokensOut" 2>/dev/null)"
    done
  else
    # Fallback to SQLite
    sqlite3 -header -column "$CC_USAGE_DB" \
      "SELECT ts, provider, duration_sec, turns, tokens_in, tokens_out
       FROM sessions ORDER BY id DESC LIMIT $last" 2>/dev/null || echo "  (no data)"
  fi

  echo ""
  echo "--------------------------------------------------------------------------------"

  # Aggregate totals from JSONL
  if [[ -f "$CC_USAGE_LOG" ]]; then
    local total_in total_out total_sessions
    total_in=$(awk -F'"tokensIn":' '{gsub(/[^0-9].*/,"",$2); s+=$2} END {print s+0}' "$CC_USAGE_LOG")
    total_out=$(awk -F'"tokensOut":' '{gsub(/[^0-9].*/,"",$2); s+=$2} END {print s+0}' "$CC_USAGE_LOG")
    total_sessions=$(wc -l < "$CC_USAGE_LOG" 2>/dev/null) || total_sessions=0
    echo "Total ($total_sessions sessions): $(printf '%d' "$total_in" 2>/dev/null) in, $(printf '%d' "$total_out" 2>/dev/null) out"
  fi

  echo ""
}