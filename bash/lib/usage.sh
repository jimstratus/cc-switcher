# =============================================================================
# usage.sh — Token usage tracking
# Uses SQLite to store session history; attempts to read token counts from
# Claude Code's session JSONL files after exit.
# =============================================================================

CC_USAGE_DB="${CCSWITCHER_ROOT}/data/.usage.db"
CC_USAGE_LOG="${CCSWITCHER_ROOT}/data/.usage-log.jsonl"

# In-memory session tracking
_CC_SESSION_STARTED_AT=""
_CC_SESSION_PROVIDER=""

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
      CREATE INDEX IF NOT EXISTS idx_sessions_ts ON sessions(ts);" \
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

  # Seed the jsonl log for compatibility
  mkdir -p "$(dirname "$CC_USAGE_LOG")"
}

#------------------------------------------------------------------------------
# write-cc-session-end — called after claude exits; aggregates tokens
#------------------------------------------------------------------------------
write_cc_session_end() {
  local provider_name="${1:-$_CC_SESSION_PROVIDER}"
  local started_at=${_CC_SESSION_STARTED_AT:-$(date +%s)}
  local now
  now=$(date +%s)
  local duration=$(( now - started_at ))

  # Try to find new/updated session JSONL files from this session
  local tokens_in=0 tokens_out=0 cache_read=0 cache_create=0 turns=0
  local sessions_root="$HOME/.claude/projects"

  if [[ -d "$sessions_root" ]]; then
    local -a jsonl_files=()
    # Find jsonl files modified since session start (with a buffer)
    local f mtime
    while IFS= read -r -d '' f; do
      mtime=$(stat -c %Y "$f" 2>/dev/null) || continue
      if (( mtime >= started_at - 5 )); then
        jsonl_files+=("$f")
      fi
    done < <(find "$sessions_root" -name "*.jsonl" -print0 2>/dev/null)

    # One jq pass per file: sum usage across user/assistant messages
    local agg in_t out_t cr_t cc_t turns_t
    for f in "${jsonl_files[@]}"; do
      agg=$(jq -rs '
        [ .[] | select(.type == "user" or .type == "assistant") | (.message.usage // {}) ]
        | "\(map(.input_tokens // 0) | add // 0) \(map(.output_tokens // 0) | add // 0) \(map(.cache_read_input_tokens // 0) | add // 0) \(map(.cache_creation_input_tokens // 0) | add // 0) \(length)"
      ' "$f" 2>/dev/null) || continue
      read -r in_t out_t cr_t cc_t turns_t <<< "$agg"
      tokens_in=$(( tokens_in + in_t ))
      tokens_out=$(( tokens_out + out_t ))
      cache_read=$(( cache_read + cr_t ))
      cache_create=$(( cache_create + cc_t ))
      turns=$(( turns + turns_t ))
    done
  fi

  # Write JSONL log for compatibility
  local ts_iso
  ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -cn \
    --arg ts "$ts_iso" --arg provider "$provider_name" \
    --argjson durationSec "$duration" --argjson turns "$turns" \
    --argjson tokensIn "$tokens_in" --argjson tokensOut "$tokens_out" \
    --argjson cacheRead "$cache_read" --argjson cacheCreate "$cache_create" \
    '$ARGS.named' >> "$CC_USAGE_LOG" 2>/dev/null || true

  # Insert into SQLite (single-quotes in provider doubled for SQL)
  local provider_sql="${provider_name//\'/\'\'}"
  _usage_db_init
  sqlite3 "$CC_USAGE_DB" \
    "INSERT INTO sessions (ts, provider, opus_model, duration_sec, turns, tokens_in, tokens_out, cache_read, cache_create)
     VALUES ('$ts_iso', '$provider_sql', '', $duration, $turns, $tokens_in, $tokens_out, $cache_read, $cache_create);" \
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

    tail -n "$last" "$CC_USAGE_LOG" 2>/dev/null \
      | jq -r 'select(.ts and .provider)
          | [.ts, .provider, (.durationSec // 0), (.turns // 0), (.tokensIn // 0), (.tokensOut // 0)]
          | @tsv' 2>/dev/null \
      | while IFS=$'\t' read -r ts provider durationSec turns tokensIn tokensOut; do
      local when
      when=$(date -d "$ts" +"%Y-%m-%d %H:%M" 2>/dev/null) || when="$ts"
      printf "%-19s %-32s %7ss %7s %9s %9s\n" \
        "$when" "$provider" "$durationSec" "$turns" "$tokensIn" "$tokensOut"
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
    local total_in=0 total_out=0 total_sessions=0
    read -r total_in total_out total_sessions < <(
      jq -rs '"\(map(.tokensIn // 0) | add // 0) \(map(.tokensOut // 0) | add // 0) \(length)"' \
        "$CC_USAGE_LOG" 2>/dev/null
    ) || true
    echo "Total ($total_sessions sessions): $total_in in, $total_out out"
  fi

  echo ""
}