# =============================================================================
# doctor.sh — cc-doctor health check
# Validates API keys exist, format-checks them, optionally pings endpoints.
# =============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# test-cc-api-key — check a single API key
# Returns: "ok|malformed|missing|len=<n>|prefix=..."
#------------------------------------------------------------------------------
test_cc_api_key() {
  local key_name="$1"
  local val="${!key_name:-}"

  if [[ -z "$val" ]]; then
    echo "missing"
    return
  fi

  # Pattern-based format checks
  case "$key_name" in
    OPENROUTER_API_KEY)
      if [[ "$val" =~ ^sk-or-[A-Za-z0-9_-]{20,}$ ]]; then
        echo "ok:${#val}"
      else
        echo "malformed:${#val}:${val:0:8}"
      fi
      ;;
    DEEPSEEK_API_KEY)
      if [[ "$val" =~ ^sk-[A-Za-z0-9]{20,}$ ]]; then
        echo "ok:${#val}"
      else
        echo "malformed:${#val}:${val:0:8}"
      fi
      ;;
    ANTHROPIC_API_KEY)
      if [[ "$val" =~ ^sk-ant-[A-Za-z0-9_-]{20,}$ ]]; then
        echo "ok:${#val}"
      else
        echo "malformed:${#val}:${val:0:8}"
      fi
      ;;
    NVIDIA_API_KEY)
      if [[ "$val" =~ ^nvapi-[A-Za-z0-9_-]{20,}$ ]]; then
        echo "ok:${#val}"
      else
        echo "malformed:${#val}:${val:0:8}"
      fi
      ;;
    MINIMAX_API_KEY|ZAI_API_KEY|KIMI_API_KEY|OPENCODE_GO_API_KEY|XIAOMI_API_KEY)
      if [[ ${#val} -ge 20 ]]; then
        echo "ok:${#val}"
      else
        echo "malformed:${#val}:${val:0:8}"
      fi
      ;;
    *)
      echo "ok:${#val}"
      ;;
  esac
}

#------------------------------------------------------------------------------
# test-cc-endpoint — ping a URL, return reachable|unreachable|latency|code|error
#------------------------------------------------------------------------------
test_cc_endpoint() {
  local url="$1"
  local timeout_sec="${2:-5}"

  local start end latency
  start=$(date +%s%3N)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "$timeout_sec" \
    --connect-timeout "$timeout_sec" \
    "$url" 2>/dev/null) || http_code="000"
  end=$(date +%s%3N)
  latency=$(( end - start ))

  if [[ "$http_code" == "000" ]]; then
    echo "unreachable:0:000"
  else
    echo "reachable:${latency}:${http_code}"
  fi
}

#------------------------------------------------------------------------------
# invoke-cc-doctor
#------------------------------------------------------------------------------
invoke_cc_doctor() {
  local no_network=false
  if [[ "${1:-}" == "--no-network" ]]; then
    no_network=true
  fi

  echo ""
  echo " cc-switcher doctor "
  echo "======================================================================"

  echo ""
  echo " API keys "
  echo "----------------------------------------------------------------------"

  local keys=(
    "OPENROUTER_API_KEY"
    "DEEPSEEK_API_KEY"
    "MINIMAX_API_KEY"
    "NVIDIA_API_KEY"
    "OPENCODE_GO_API_KEY"
    "ZAI_API_KEY"
    "KIMI_API_KEY"
    "XIAOMI_API_KEY"
    "ANTHROPIC_API_KEY"
  )

  for k in "${keys[@]}"; do
    local result detail
    result=$(test_cc_api_key "$k")
    IFS=':' read -r status len prefix <<< "$result"

    case "$status" in
      ok)
        detail="len=$len"
        echo "  [OK]  $k $detail"
        ;;
      malformed)
        detail="len=$len, prefix=${prefix}..."
        echo "  [?]   $k $detail"
        ;;
      missing)
        detail="(env var unset)"
        echo "  [--]  $k $detail"
        ;;
    esac
  done

  if [[ "$no_network" == "true" ]]; then
    echo ""
    echo "[doctor] Skipped network checks (--no-network)"
    return
  fi

  echo ""
  echo " Endpoint reachability "
  echo "----------------------------------------------------------------------"

  local provider_lines
  provider_lines=$(list_cc_providers 2>/dev/null) || provider_lines=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r id command display_name quality_tier base_url auth_var flagship standard fast context_flagship timeout_ms disable_noness <<< "$line"

    # Check if we have auth for this provider
    local has_key=false
    if [[ "$auth_var" == "_codex_oauth_token" ]]; then
      # Special case: codex uses OAuth
      has_key=$(get_cc_codex_token >/dev/null 2>&1 && echo true || echo false)
    elif [[ -n "$auth_var" ]]; then
      local val="${!auth_var}"
      [[ -n "$val" ]] && has_key=true
    fi

    if [[ "$has_key" != "true" ]]; then
      echo "  [--] $command (no API key)"
      continue
    fi

    local ping_result latency http_code
    ping_result=$(test_cc_endpoint "$base_url" 5)
    IFS=':' read -r reachable lat code <<< "$ping_result"

    if [[ "$reachable" == "reachable" ]]; then
      echo "  [OK]  $command ${lat}ms  HTTP $code  -> $base_url"
    else
      echo "  [X]   $command unreachable -> $base_url"
    fi
  done <<< "$provider_lines"

  echo ""
}