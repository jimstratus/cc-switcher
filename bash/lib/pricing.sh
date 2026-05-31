# =============================================================================
# pricing.sh — OpenRouter live pricing with disk-persisted cache
# =============================================================================

OR_PRICING_CACHE_FILE="${CCSWITCHER_ROOT}/data/.pricing-cache.json"
OR_PRICING_TTL_SEC=300

# In-memory cache
_OR_PRICING_CACHE=""
_OR_PRICING_CACHE_TIME=0

#------------------------------------------------------------------------------
# get-cc-live-pricing — fetch from network or cache, return JSON array
#------------------------------------------------------------------------------
get_cc_live_pricing() {
  local now
  now=$(date +%s)

  # Memory cache check
  if [[ -n "$_OR_PRICING_CACHE" ]] && (( _OR_PRICING_CACHE_TIME > 0 )); then
    local age=$(( now - _OR_PRICING_CACHE_TIME ))
    if (( age < OR_PRICING_TTL_SEC )); then
      echo "$_OR_PRICING_CACHE"
      return 0
    fi
  fi

  # Disk cache check
  if [[ -f "$OR_PRICING_CACHE_FILE" ]]; then
    local fetched_at cached_data age
    fetched_at=$(jq -r '.fetchedAt // 0' "$OR_PRICING_CACHE_FILE" 2>/dev/null) || fetched_at=0
    age=$(( now - fetched_at ))
    if (( age < OR_PRICING_TTL_SEC )); then
      cached_data=$(jq -c '.data' "$OR_PRICING_CACHE_FILE" 2>/dev/null) || cached_data="[]"
      _OR_PRICING_CACHE="$cached_data"
      _OR_PRICING_CACHE_TIME="$fetched_at"
      echo "$cached_data"
      return 0
    fi
  fi

  # Network fetch
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "[]"
    return 0
  fi

  local resp
  resp=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    "https://openrouter.ai/api/v1/models") || {
    echo "[]"
    return 0
  }

  local data
  data=$(echo "$resp" | jq -c '.data // []' 2>/dev/null) || data="[]"

  # Persist to disk
  local fetched_at
  fetched_at=$(date +%s)
  echo "{\"fetchedAt\":$fetched_at,\"data\":$data}" > "$OR_PRICING_CACHE_FILE"

  _OR_PRICING_CACHE="$data"
  _OR_PRICING_CACHE_TIME="$fetched_at"
  echo "$data"
}

#------------------------------------------------------------------------------
# get-cc-pricing — display pricing table
#------------------------------------------------------------------------------
get_cc_pricing() {
  local models
  models=$(get_cc_live_pricing) || models="[]"

  echo ""
  echo " Live pricing (OpenRouter, ${OR_PRICING_TTL_SEC}s cache) "
  echo "======================================================================"
  printf "%-35s %10s %12s %12s\n" "Model" " \$/1M in" "\$/1M out" "Context"
  echo "----------------------------------------------------------------------"

  # Collect slash-model IDs from catalog
  local provider_lines
  provider_lines=$(list_cc_providers 2>/dev/null) || provider_lines=""
  local seen_ids=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r id command display_name quality_tier base_url auth_var flagship standard fast context_flagship timeout_ms disable_noness <<< "$line"

    for mid in "$flagship" "$standard" "$fast"; do
      # Skip if already shown
      if [[ "$seen_ids" == *" $mid "* ]]; then
        continue
      fi
      # Only OpenRouter-style (slash in name)
      if [[ "$mid" != *"/"* ]]; then
        continue
      fi

      seen_ids=" $seen_ids$mid "
      local prompt_price comp_price ctx_len
      prompt_price="-"
      comp_price="-"
      ctx_len="-"

      # Extract from models JSON
      local entry
      entry=$(echo "$models" | jq -c ".[] | select(.id == \"$mid\")" 2>/dev/null | head -1) || entry=""
      if [[ -n "$entry" ]]; then
        local pp cp cl
        pp=$(echo "$entry" | jq -r '.pricing.prompt // empty')
        cp=$(echo "$entry" | jq -r '.pricing.completion // empty')
        cl=$(echo "$entry" | jq -r '.context_length // empty')
        if [[ -n "$pp" ]] && [[ "$pp" != "null" ]]; then
          prompt_price=$(printf "%.2f" "$(awk "BEGIN {print $pp * 1e6}")" 2>/dev/null) || prompt_price="$pp"
        fi
        if [[ -n "$cp" ]] && [[ "$cp" != "null" ]]; then
          comp_price=$(printf "%.2f" "$(awk "BEGIN {print $cp * 1e6}")" 2>/dev/null) || comp_price="$cp"
        fi
        if [[ -n "$cl" ]] && [[ "$cl" != "null" ]]; then
          ctx_len=$(printf "%d" "$cl" 2>/dev/null) || ctx_len="$cl"
        fi
      fi

      printf "%-35s %10s %12s %12s\n" "$mid" "$prompt_price" "$comp_price" "$ctx_len"
    done
  done <<< "$provider_lines"

  echo ""
}