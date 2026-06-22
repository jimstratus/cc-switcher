# =============================================================================
# core.sh — invoke-cc-launch, reset-cc, get-cc-status
# Sets ANTHROPIC_* env vars, optionally launches `claude`, restores on exit.
# =============================================================================

# Associative array to hold the env snapshot for restore
declare -A _CC_SNAPSHOT

# Single source of truth for the env vars managed by snapshot/restore and reset
_CC_MANAGED_VARS=(
  ANTHROPIC_BASE_URL
  ANTHROPIC_AUTH_TOKEN
  ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL
  ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL
  ANTHROPIC_SMALL_FAST_MODEL
  API_TIMEOUT_MS
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
  CLAUDE_CODE_MAX_OUTPUT_TOKENS
  CLAUDE_CODE_MAX_CONTEXT_TOKENS
  DISABLE_COMPACT
)

# API key env vars shown by cc-status and checked by cc-doctor
_CC_API_KEY_VARS=(
  ANTHROPIC_API_KEY
  OPENROUTER_API_KEY
  DEEPSEEK_API_KEY
  MINIMAX_API_KEY
  NVIDIA_API_KEY
  OPENCODE_GO_API_KEY
  ZAI_API_KEY
  KIMI_API_KEY
  XIAOMI_API_KEY
)

#------------------------------------------------------------------------------
# Portable helpers (GNU coreutils on Linux vs BSD utils on macOS)
#------------------------------------------------------------------------------

# Epoch mtime of a file. GNU: stat -c %Y; BSD/macOS: stat -f %m.
_cc_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# Format an ISO-8601 UTC timestamp (e.g. 2026-06-21T04:46:02Z) for display.
# GNU: date -d; BSD/macOS: date -j -f. Echoes the raw input if neither parses.
_cc_fmt_ts() {
  local ts="$1"
  date -d "$ts" +"%Y-%m-%d %H:%M" 2>/dev/null \
    || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +"%Y-%m-%d %H:%M" 2>/dev/null \
    || printf '%s' "$ts"
}

#------------------------------------------------------------------------------
# Internal: snapshot all env vars we touch
#------------------------------------------------------------------------------
_cc_snapshot_save() {
  local key
  _CC_SNAPSHOT=()
  for key in "${_CC_MANAGED_VARS[@]}"; do
    _CC_SNAPSHOT["$key"]="${!key-}"
  done
}

#------------------------------------------------------------------------------
# Internal: restore snapshot after claude exits
#------------------------------------------------------------------------------
_cc_snapshot_restore() {
  local key
  for key in "${!_CC_SNAPSHOT[@]}"; do
    if [[ -z "${_CC_SNAPSHOT[$key]}" ]]; then
      unset "$key" 2>/dev/null || true
    else
      export "$key=${_CC_SNAPSHOT[$key]}"
    fi
  done
}

#------------------------------------------------------------------------------
# Internal: transform --yolo to --dangerously-skip-permissions in args
# Returns transformed args via global _CC_TRANSFORMED_ARGS
#------------------------------------------------------------------------------
_cc_transform_yolo() {
  local -a result=()
  local yolo_active=false
  _CC_YOLO_ACTIVE=false

  for arg in "$@"; do
    if [[ "$arg" == "--yolo" ]]; then
      result+=("--dangerously-skip-permissions")
      yolo_active=true
    else
      result+=("$arg")
    fi
  done

  if [[ "$yolo_active" == true ]] || [[ "${CC_YOLO:-}" == "1" ]]; then
    _CC_YOLO_ACTIVE=true
  fi

  _CC_TRANSFORMED_ARGS=("${result[@]}")
}

#------------------------------------------------------------------------------
# invoke-cc-launch — the core launch function
# Args: provider_name base_url auth_token opus_model sonnet_model haiku_model
# Options as env vars:
#   CC_OPUS_OVERRIDE   - override model for all tiers
#   CC_FLAGSHP_CONTEXT - flagship context (0 = no auto-context)
#   CC_DISABLE_NONESS  - set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
#   CC_EXTRA_ENV_*     - extra env vars (prefix stripped, set in ExtraEnv)
#   CC_YOLO            - auto-apply --dangerously-skip-permissions
#   CC_EXTRA_ARGS      - additional claude arguments (split on spaces)
#------------------------------------------------------------------------------
invoke_cc_launch() {
  local provider_name="$1"
  local base_url="$2"
  local auth_token="$3"
  local opus_model="$4"
  local sonnet_model="$5"
  local haiku_model="$6"
  local timeout_ms="${7:-3000000}"
  local flagship_context="${8:-0}"
  local disable_noness="${9:-false}"
  shift 9

  if [[ -z "$auth_token" ]]; then
    echo "[ERROR] Auth token is empty for provider: $provider_name" >&2
    echo "        Set the relevant API key env var in your ~/.bashrc." >&2
    return 1
  fi

  echo "[cc] Launching: $provider_name"
  echo "[cc]   Opus   -> $opus_model"
  echo "[cc]   Sonnet -> $sonnet_model"
  echo "[cc]   Haiku  -> $haiku_model"
  echo "[cc]   URL    -> $base_url"

  # Snapshot
  _cc_snapshot_save

  # Apply env overrides
  export ANTHROPIC_BASE_URL="$base_url"
  export ANTHROPIC_AUTH_TOKEN="$auth_token"
  export ANTHROPIC_MODEL="$opus_model"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model"
  export ANTHROPIC_SMALL_FAST_MODEL="$haiku_model"
  export API_TIMEOUT_MS="$timeout_ms"

  if [[ "$disable_noness" == "true" ]]; then
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
  fi

  # Model override (when user passes a specific model to cc-openrouter etc)
  if [[ -n "${CC_OPUS_OVERRIDE:-}" ]]; then
    export ANTHROPIC_MODEL="$CC_OPUS_OVERRIDE"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$CC_OPUS_OVERRIDE"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$CC_OPUS_OVERRIDE"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$CC_OPUS_OVERRIDE"
  fi

  # Auto-derive extended-context env vars when flagship context >= 500K
  if (( flagship_context >= 500000 )); then
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$flagship_context"
    export DISABLE_COMPACT="1"
    if (( flagship_context >= 1000000 )); then
      local context_display
      context_display="$(awk "BEGIN {printf \"%.1fM\", $flagship_context/1048576}")"
    else
      local context_display
      context_display="$(awk "BEGIN {printf \"%dK\", $flagship_context/1000}")"
    fi
    echo "[cc]   Context-> $context_display (auto, DISABLE_COMPACT=1; /compact manually near limit)"
  fi

  # Extra env vars set via CC_EXTRA_ENV_<NAME>. Applied after the auto-context
  # block so a provider's envVars can override the auto-derived values, and
  # added to the snapshot so they are restored when claude exits.
  local extra_env_vars
  extra_env_vars=$(compgen -v CC_EXTRA_ENV_ || true)
  if [[ -n "$extra_env_vars" ]]; then
    for var in $extra_env_vars; do
      local env_name="${var#CC_EXTRA_ENV_}"
      local env_val="${!var}"
      if [[ -z "${_CC_SNAPSHOT[$env_name]+x}" ]]; then
        _CC_SNAPSHOT["$env_name"]="${!env_name-}"
      fi
      export "$env_name=$env_val"
    done
  fi

  # --yolo / CC_YOLO handling
  _cc_transform_yolo "$@"
  set -- "${_CC_TRANSFORMED_ARGS[@]}"

  if [[ "$_CC_YOLO_ACTIVE" == "true" ]]; then
    echo "[cc]   YOLO mode: --dangerously-skip-permissions"
    local has_dangerously=false
    for arg in "$@"; do
      if [[ "$arg" == "--dangerously-skip-permissions" ]]; then
        has_dangerously=true
        break
      fi
    done
    if [[ "$has_dangerously" == "false" ]]; then
      set -- "--dangerously-skip-permissions" "$@"
    fi
  fi

  # Record session start
  write_cc_session_start "$provider_name" "$opus_model"

  # Launch claude
  if (($# > 0)); then
    claude "$@"
  else
    claude
  fi
  local exit_code=$?

  # Restore on exit
  _cc_snapshot_restore

  # Best-effort token aggregation after claude exits
  write_cc_session_end "$provider_name"

  return $exit_code
}

#------------------------------------------------------------------------------
# cc-yolo — native Anthropic + --dangerously-skip-permissions
#------------------------------------------------------------------------------
invoke_cc_yolo() {
  echo "[cc] Launching native Anthropic in YOLO mode"
  reset_cc --quiet
  set -- "--dangerously-skip-permissions" "$@"
  claude "$@"
}

#------------------------------------------------------------------------------
# reset-cc — clear all provider overrides
#------------------------------------------------------------------------------
reset_cc() {
  local quiet=false
  if [[ "${1:-}" == "--quiet" ]]; then
    quiet=true
  fi

  for var in "${_CC_MANAGED_VARS[@]}"; do
    unset "$var" 2>/dev/null || true
  done

  if [[ "$quiet" != "true" ]]; then
    echo "[cc] Provider overrides cleared. Native Anthropic restored."
  fi
}

#------------------------------------------------------------------------------
# cc-status — show current env state
#------------------------------------------------------------------------------
get_cc_status() {
  echo ""
  echo " cc-switcher status "
  echo "----------------------------------------------------------------------"

  # Subset of _CC_MANAGED_VARS whose values are safe to print (no auth token),
  # plus CC_YOLO
  local rows=(
    ANTHROPIC_BASE_URL
    ANTHROPIC_MODEL
    ANTHROPIC_DEFAULT_OPUS_MODEL
    ANTHROPIC_DEFAULT_SONNET_MODEL
    ANTHROPIC_DEFAULT_HAIKU_MODEL
    API_TIMEOUT_MS
    CLAUDE_CODE_MAX_CONTEXT_TOKENS
    CLAUDE_CODE_MAX_OUTPUT_TOKENS
    DISABLE_COMPACT
    CC_YOLO
  )

  local var val
  for var in "${rows[@]}"; do
    val="${!var-}"
    if [[ -z "$val" ]]; then
      val="(unset — Anthropic default)"
    fi
    printf "%-38s %s\n" "$var" "$val"
  done

  echo ""
  echo " API keys "
  echo "----------------------------------------------------------------------"

  for key in "${_CC_API_KEY_VARS[@]}"; do
    local val="${!key-}"
    local status
    if [[ -z "$val" ]]; then
      status="(not set)"
    else
      status="(set, len=${#val})"
    fi
    printf "%-22s %s\n" "$key" "$status"
  done

  echo ""
}