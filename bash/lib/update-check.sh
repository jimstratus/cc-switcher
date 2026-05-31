# =============================================================================
# update-check.sh — Notice when cc-switcher.sh has been updated since last load
# Cheap mtime comparison, no network.
# =============================================================================

set -euo pipefail

CC_LAST_LOAD_FILE="${CCSWITCHER_ROOT}/data/.last-load"
_cc_updated_flag=""

#------------------------------------------------------------------------------
# Check if cc-switcher.sh has been updated since last load
#------------------------------------------------------------------------------
_cc_check_updated() {
  local entry="${CCSWITCHER_ROOT}/cc-switcher.sh"
  [[ ! -f "$entry" ]] && return

  local current
  current=$(stat -c %Y "$entry" 2>/dev/null) || return

  if [[ ! -f "$CC_LAST_LOAD_FILE" ]]; then
    echo "$current" > "$CC_LAST_LOAD_FILE"
    return
  fi

  local prev
  prev=$(cat "$CC_LAST_LOAD_FILE" 2>/dev/null) || prev=0
  echo "$current" > "$CC_LAST_LOAD_FILE"

  if (( current > prev )); then
    _cc_updated_flag=" [updated since last shell]"
  fi
}

#------------------------------------------------------------------------------
# show-cc-help — banner/usage display
#------------------------------------------------------------------------------
show_cc_help() {
  echo ""
  echo " cc-switcher v${CCSWITCHER_VERSION} "
  printf '%s\n' "======================================================================"
  echo ""
  echo " Providers (alphabetical, /model switches tiers in-session) "
  printf '%s\n' "----------------------------------------------------------------------"

  local provider_lines
  provider_lines=$(list_cc_providers 2>/dev/null) || provider_lines=""

  local -a providers_sorted=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    providers_sorted+=("$line")
  done <<< "$provider_lines"

  # Sort: slow last, then alphabetical
  local line cmd tier
  for line in "${providers_sorted[@]}"; do
    IFS='|' read -r id command display_name quality_tier _ <<< "$line"
    case "$quality_tier" in
      slow)  cmd="zzz_$command" ;;
      free)  cmd="free_$command" ;;
      *)     cmd="$command" ;;
    esac
    printf '%s|%s|%s\n' "$cmd" "$command" "$quality_tier"
  done | sort | while IFS='|' read -r _ cmd tier; do
    local tag=""
    case "$tier" in
      flagship) tag="          " ;;
      free)     tag="   [free] " ;;
      slow)     tag="   [SLOW] " ;;
      *)        tag="   [$tier] " ;;
    esac
    # Find display name
    for l in "${providers_sorted[@]}"; do
      IFS='|' read -r id command display_name _ <<< "$l"
      [[ "$command" == "$cmd" ]] && echo "  $cmd  $tag  $display_name"
    done
  done

  echo ""
  echo " Generic launchers (pass model id) "
  printf '%s\n' "----------------------------------------------------------------------"
  echo "  cc-openrouter <model>          Any OpenRouter model"
  echo "  cc-opencode <model>            Any OpenCode Go model"
  echo "  cc-nvidia <model>             Any NVIDIA NIM model (omit for tier defaults)"
  echo ""
  echo " Utilities "
  printf '%s\n' "----------------------------------------------------------------------"
  echo "  cc-launch     Interactive numbered menu"
  echo "  cc-doctor     Validate API keys + ping endpoints"
  echo "  cc-pricing    Live pricing table (OpenRouter, 5-min cache)"
  echo "  cc-status     Show current provider env state"
  echo "  cc-usage      Token usage history (last 20 sessions)"
  echo "  cc-reset      Clear overrides, restore native Anthropic"
  echo "  cc-yolo       Native Anthropic + --dangerously-skip-permissions"
  echo ""
  echo " Flags "
  printf '%s\n' "----------------------------------------------------------------------"
  echo "  --yolo                   Add to any command for --dangerously-skip-permissions"
  echo "  \$CC_YOLO=1               Auto-applies --yolo to every cc-* launch"
  echo ""
  echo " Files "
  printf '%s\n' "----------------------------------------------------------------------"
  echo "  Catalog:  ${CCSWITCHER_ROOT}/data/providers.json"
  echo ""
}