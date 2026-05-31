# =============================================================================
# providers.sh — Load providers.json, cc-deepseek / cc-glm / etc functions
# =============================================================================

CC_CATALOG_PATH="${CCSWITCHER_ROOT}/data/providers.json"
declare -A _CC_CATALOG_LOADED

#------------------------------------------------------------------------------
# jq-based catalog read (memoized)
#------------------------------------------------------------------------------
_get_cc_catalog() {
  local key="$1"
  if [[ -z "${_CC_CATALOG_LOADED[$key]:-}" ]]; then
    _CC_CATALOG_LOADED[$key]="$(jq -e ".$key" "$CC_CATALOG_PATH" 2>/dev/null || echo 'null')"
  fi
  echo "${_CC_CATALOG_LOADED[$key]}"
}

#------------------------------------------------------------------------------
# Get providers as JSON array string (each provider object as a line)
#------------------------------------------------------------------------------
get_cc_providers_json() {
  jq -c '.providers | to_entries[]' "$CC_CATALOG_PATH" 2>/dev/null
}

#------------------------------------------------------------------------------
# List all providers in a parseable format
#------------------------------------------------------------------------------
list_cc_providers() {
  while IFS= read -r entry; do
    local id command display_name quality_tier base_url auth_var
    local flagship standard fast context context_by_tier timeout_ms
    local disable_noness requires_oauth
    id=$(echo "$entry" | jq -r '.key')
    command=$(echo "$entry" | jq -r '.value.command')
    display_name=$(echo "$entry" | jq -r '.value.displayName')
    quality_tier=$(echo "$entry" | jq -r '.value.qualityTier')
    base_url=$(echo "$entry" | jq -r '.value.baseUrl')
    auth_var=$(echo "$entry" | jq -r '.value.authVar')
    flagship=$(echo "$entry" | jq -r '.value.tiers.flagship')
    standard=$(echo "$entry" | jq -r '.value.tiers.standard')
    fast=$(echo "$entry" | jq -r '.value.tiers.fast')
    context=$(echo "$entry" | jq -r '.value.context // 0')
    timeout_ms=$(echo "$entry" | jq -r '.value.timeoutMs // 3000000')
    disable_noness=$(echo "$entry" | jq -r '.value.disableNonEssential == true')
    requires_oauth=$(echo "$entry" | jq -r '.value.requiresOAuth == true')

    # contextByTier (may be null)
    local context_flagship="$context"
    local ctx_tier
    ctx_tier=$(echo "$entry" | jq -r '.value.contextByTier.flagship // empty')
    if [[ -n "$ctx_tier" ]] && [[ "$ctx_tier" != "null" ]]; then
      context_flagship="$ctx_tier"
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$id" "$command" "$display_name" "$quality_tier" "$base_url" \
      "$auth_var" "$flagship" "$standard" "$fast" \
      "$context_flagship" "$timeout_ms" "$disable_noness"
  done < <(get_cc_providers_json)
}

#------------------------------------------------------------------------------
# Internal: find a provider entry by id
#------------------------------------------------------------------------------
_get_provider_by_id() {
  local id="$1"
  get_cc_providers_json | while IFS= read -r entry; do
    local key
    key=$(echo "$entry" | jq -r '.key')
    if [[ "$key" == "$id" ]]; then
      echo "$entry"
      return 0
    fi
  done
  return 1
}

#------------------------------------------------------------------------------
# Internal: get catalog value for a provider
#------------------------------------------------------------------------------
_get_provider_field() {
  local id="$1"
  local field="$2"
  local provider_json
  provider_json=$(_get_provider_by_id "$id") || return 1
  echo "$provider_json" | jq -r ".value.$field // empty"
}

#------------------------------------------------------------------------------
# invoke-cc-provider — single dispatcher for catalog-driven providers
# Args: id model_override [claude_args...]
#------------------------------------------------------------------------------
invoke_cc_provider() {
  local id="$1"
  local model_override="${2:-}"
  shift 2
  local -a claude_args=("$@")

  # Fetch provider data from catalog
  local command display_name quality_tier base_url auth_var
  local flagship standard fast context_flagship timeout_ms disable_noness requires_oauth

  command=$(_get_provider_field "$id" "command") || {
    echo "[ERROR] Unknown provider id: $id" >&2
    return 1
  }
  display_name=$(_get_provider_field "$id" "displayName")
  quality_tier=$(_get_provider_field "$id" "qualityTier")
  base_url=$(_get_provider_field "$id" "baseUrl")
  auth_var=$(_get_provider_field "$id" "authVar")
  flagship=$(_get_provider_field "$id" "tiers.flagship")
  standard=$(_get_provider_field "$id" "tiers.standard")
  fast=$(_get_provider_field "$id" "tiers.fast")
  timeout_ms=$(_get_provider_field "$id" "timeoutMs")
  disable_noness=$(_get_provider_field "$id" "disableNonEssential")
  requires_oauth=$(_get_provider_field "$id" "requiresOAuth")

  # context: use contextByTier.flagship if available, else context
  local context_flagship
  context_flagship=$(_get_provider_field "$id" "contextByTier.flagship") || context_flagship="0"
  if [[ "$context_flagship" == "null" ]] || [[ -z "$context_flagship" ]]; then
    context_flagship=$(_get_provider_field "$id" "context") || context_flagship="0"
  fi
  if [[ "$context_flagship" == "null" ]] || [[ -z "$context_flagship" ]]; then
    context_flagship="0"
  fi

  # Auth token
  local auth_token
  if [[ "$requires_oauth" == "true" ]]; then
    auth_token=$(get_cc_codex_token) || {
      echo "[ERROR] OAuth token missing. Run 'cc-codex-login' first." >&2
      return 1
    }
  else
    auth_token="${!auth_var}"
  fi

  # Model override or catalog default per tier
  local opus sonnet_model haiku_model
  if [[ -n "$model_override" ]]; then
    opus="$model_override"
    sonnet_model="$model_override"
    haiku_model="$model_override"
  else
    opus="$flagship"
    sonnet_model="$standard"
    haiku_model="$fast"
  fi

  # DisableNonEss boolean
  local disable_noness_bool="false"
  if [[ "$disable_noness" == "true" ]]; then
    disable_noness_bool="true"
  fi

  # Extra env vars from catalog (envVars block)
  local extra_env_json
  extra_env_json=$(echo "$(_get_provider_by_id "$id")" | jq -c '.value.envVars // {}')
  if [[ "$extra_env_json" != "{}" ]]; then
    local extra_keys
    extra_keys=$(echo "$extra_env_json" | jq -r 'keys[]')
    for ek in $extra_keys; do
      local ev
      ev=$(echo "$extra_env_json" | jq -r ".$ek")
      eval "export $ek=\$ev"
    done
  fi

  invoke_cc_launch \
    "$display_name" \
    "$base_url" \
    "$auth_token" \
    "$opus" \
    "$sonnet_model" \
    "$haiku_model" \
    "$timeout_ms" \
    "$context_flagship" \
    "$disable_noness_bool" \
    "${claude_args[@]}"
}

#------------------------------------------------------------------------------
# cc-openrouter — generic OpenRouter launcher (model param required)
#------------------------------------------------------------------------------
invoke_cc_openrouter() {
  local model="${1:-moonshotai/kimi-k2.6}"
  shift || true
  local -a claude_args=("$@")

  local auth="${OPENROUTER_API_KEY:-}"
  if [[ -z "$auth" ]]; then
    echo "[ERROR] OPENROUTER_API_KEY is not set." >&2
    return 1
  fi

  echo "[cc] OpenRouter model: $model"

  CC_OPUS_OVERRIDE="$model" \
  invoke_cc_launch \
    "OpenRouter ($model)" \
    "https://openrouter.ai/api/v1" \
    "$auth" \
    "$model" "$model" "$model" \
    3000000 0 false \
    "${claude_args[@]}"
}

#------------------------------------------------------------------------------
# cc-opencode — generic OpenCode Go launcher (model param required)
#------------------------------------------------------------------------------
invoke_cc_opencode() {
  local model="${1:-minimax-m2.7}"
  shift || true
  local -a claude_args=("$@")

  local auth="${OPENCODE_GO_API_KEY:-}"
  if [[ -z "$auth" ]]; then
    echo "[ERROR] OPENCODE_GO_API_KEY is not set." >&2
    return 1
  fi

  echo "[cc] OpenCode Go model: $model"

  CC_OPUS_OVERRIDE="$model" \
  invoke_cc_launch \
    "OpenCode Go ($model)" \
    "https://opencode.ai/zen/go" \
    "$auth" \
    "$model" "$model" "$model" \
    3000000 0 true \
    "${claude_args[@]}"
}

#------------------------------------------------------------------------------
# cc-nvidia — generic NVIDIA NIM launcher
#------------------------------------------------------------------------------
invoke_cc_nvidia() {
  local model="$1"
  shift || true
  local -a claude_args=("$@")

  local auth="${NVIDIA_API_KEY:-}"
  if [[ -z "$auth" ]]; then
    echo "[ERROR] NVIDIA_API_KEY is not set." >&2
    return 1
  fi

  local flagship standard fast
  flagship="moonshotai/kimi-k2-instruct"
  standard="meta/llama-4-maverick-17b-128e-instruct"
  fast="meta/llama-4-scout-17b-16e-instruct"

  if [[ -n "$model" ]]; then
    CC_OPUS_OVERRIDE="$model" \
    invoke_cc_launch \
      "NVIDIA NIM ($model)" \
      "https://integrate.api.nvidia.com/v1" \
      "$auth" \
      "$model" "$model" "$model" \
      3000000 0 true \
      "${claude_args[@]}"
  else
    invoke_cc_launch \
      "NVIDIA NIM" \
      "https://integrate.api.nvidia.com/v1" \
      "$auth" \
      "$flagship" "$standard" "$fast" \
      3000000 0 true \
      "${claude_args[@]}"
  fi
}
#------------------------------------------------------------------------------
# invoke-cc-launch-menu — interactive numbered provider picker
#------------------------------------------------------------------------------
invoke_cc_launch_menu() {
  local provider_lines
  provider_lines=$(list_cc_providers) || provider_lines=""

  local -a providers_sorted=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    providers_sorted+=("$line")
  done <<< "$provider_lines"

  echo ""
  echo " cc-launch — pick a provider "
  echo "======================================================================"

  local -a display_lines=()
  local i=1
  for line in "${providers_sorted[@]}"; do
    IFS='|' read -r id command display_name quality_tier _ <<< "$line"
    local tag=""
    case "$quality_tier" in
      flagship) tag="" ;;
      free)     tag="[free] " ;;
      slow)     tag="[SLOW] " ;;
      *)        tag="[$quality_tier] " ;;
    esac
    printf "  %2d) %-20s %s%s\n" "$i" "$command" "$tag" "$display_name"
    ((i++))
  done

  echo ""
  echo "  0) Cancel"
  echo ""
  printf "Choice: "
  local choice
  read -r choice

  if [[ -z "$choice" ]] || [[ "$choice" == "0" ]]; then
    echo "Cancelled."
    return 0
  fi

  local idx=$((choice - 1))
  if (( idx < 0 || idx >= ${#providers_sorted[@]} )); then
    echo "Invalid choice: $choice"
    return 1
  fi

  local selected="${providers_sorted[$idx]}"
  IFS='|' read -r id command _ <<< "$selected"

  echo "Launching $command..."
  case "$command" in
    cc-deepseek)       cc-deepseek ;;
    cc-glm)            cc-glm ;;
    cc-kimi)           cc-kimi ;;
    cc-minimax)        cc-minimax ;;
    cc-mimo)           cc-mimo ;;
    cc-nvidia)         cc-nvidia ;;
    cc-qwen)           cc-qwen ;;
    cc-xiaomi)         cc-xiaomi ;;
    cc-opencode)       cc-opencode ;;
    cc-opencode-minimax) cc-opencode-minimax ;;
    cc-codex)          cc-codex ;;
    cc-zai-glm51)      cc-zai-glm51 ;;
    *)
      echo "[ERROR] No handler for $command yet"
      return 1
      ;;
  esac
}
