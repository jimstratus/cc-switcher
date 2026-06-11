# =============================================================================
# providers.sh — Load providers.json, cc-deepseek / cc-glm / etc functions
# =============================================================================

CC_CATALOG_PATH="${CCSWITCHER_ROOT}/data/providers.json"

#------------------------------------------------------------------------------
# Internal: find a provider entry by id (direct key lookup, single jq call)
#------------------------------------------------------------------------------
_get_provider_by_id() {
  jq -ce --arg id "$1" '.providers[$id] // empty' "$CC_CATALOG_PATH" 2>/dev/null
}

#------------------------------------------------------------------------------
# List all providers in a parseable format (one jq pass for the whole catalog)
#------------------------------------------------------------------------------
list_cc_providers() {
  jq -r '.providers | to_entries[] | [
      .key,
      .value.command,
      .value.displayName,
      .value.qualityTier,
      .value.baseUrl,
      .value.authVar,
      .value.tiers.flagship,
      .value.tiers.standard,
      .value.tiers.fast,
      (.value.contextByTier.flagship // .value.context // 0),
      (.value.timeoutMs // 3000000),
      (.value.disableNonEssential == true)
    ] | map(tostring) | join("|")' "$CC_CATALOG_PATH" 2>/dev/null
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

  local provider_json
  provider_json=$(_get_provider_by_id "$id") || {
    echo "[ERROR] Unknown provider id: $id" >&2
    return 1
  }

  # Fetch all provider fields in one jq pass
  local display_name base_url auth_var flagship standard fast
  local context_flagship timeout_ms disable_noness requires_oauth
  IFS='|' read -r display_name base_url auth_var flagship standard fast \
      context_flagship timeout_ms disable_noness requires_oauth < <(
    echo "$provider_json" | jq -r '[
        .displayName, .baseUrl, .authVar,
        .tiers.flagship, .tiers.standard, .tiers.fast,
        (.contextByTier.flagship // .context // 0),
        (.timeoutMs // 3000000),
        (.disableNonEssential == true),
        (.requiresOAuth == true)
      ] | map(tostring) | join("|")')

  # Auth token
  local auth_token
  if [[ "$requires_oauth" == "true" ]]; then
    auth_token=$(get_cc_codex_token)
    if [[ -z "$auth_token" ]]; then
      echo "[ERROR] OAuth token missing. Run 'cc-codex-login' first." >&2
      return 1
    fi
  else
    auth_token="${!auth_var:-}"
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

  # Extra env vars from catalog (envVars block), passed via CC_EXTRA_ENV_* so
  # core.sh applies them after the auto-context block and restores them on exit
  local -a extra_env_names=()
  local ek ev
  while IFS=$'\t' read -r ek ev; do
    [[ -z "$ek" ]] && continue
    export "CC_EXTRA_ENV_${ek}=${ev}"
    extra_env_names+=("CC_EXTRA_ENV_${ek}")
  done < <(echo "$provider_json" | jq -r '(.envVars // {}) | to_entries[] | "\(.key)\t\(.value)"')

  local rc=0
  invoke_cc_launch \
    "$display_name" \
    "$base_url" \
    "$auth_token" \
    "$opus" \
    "$sonnet_model" \
    "$haiku_model" \
    "$timeout_ms" \
    "$context_flagship" \
    "$disable_noness" \
    "${claude_args[@]}" || rc=$?

  local n
  for n in "${extra_env_names[@]}"; do
    unset "$n"
  done
  return $rc
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
# cc-nvidia — NVIDIA NIM launcher; optional model overrides all tiers,
# otherwise the catalog's nvidia entry supplies tier defaults
#------------------------------------------------------------------------------
invoke_cc_nvidia() {
  local model="${1:-}"
  if (($# > 0)); then shift; fi
  invoke_cc_provider "nvidia" "$model" "$@"
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

  local i=1
  for line in "${providers_sorted[@]}"; do
    IFS='|' read -r _ command display_name quality_tier _ <<< "$line"
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
  IFS='|' read -r _ command _ <<< "$selected"

  echo "Launching $command..."
  if declare -F "$command" >/dev/null 2>&1; then
    "$command"
  else
    echo "[ERROR] No handler for $command yet"
    return 1
  fi
}
