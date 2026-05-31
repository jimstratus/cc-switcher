# =============================================================================
# codex.sh — OpenAI Codex OAuth device flow + launcher
# Token cached at ~/.config/codex-oauth/token.json
# =============================================================================

set -euo pipefail

CC_CODEX_TOKEN_CACHE="${HOME}/.config/codex-oauth/token.json"

#------------------------------------------------------------------------------
# Get cached Codex OAuth token (returns empty if missing or expired)
#------------------------------------------------------------------------------
get_cc_codex_token() {
  if [[ ! -f "$CC_CODEX_TOKEN_CACHE" ]]; then
    echo ""
    return 0
  fi
  local access_token expires_at now
  access_token=$(jq -r '.access_token // empty' "$CC_CODEX_TOKEN_CACHE" 2>/dev/null) || return 0
  expires_at=$(jq -r '.expires_at // empty' "$CC_CODEX_TOKEN_CACHE" 2>/dev/null) || return 0
  now=$(date +%s)
  if [[ -z "$access_token" ]] || [[ -n "$expires_at" ]] && (( expires_at <= now )); then
    echo ""
    return 0
  fi
  echo "$access_token"
}

#------------------------------------------------------------------------------
# cc-codex-login — OAuth device code flow
#------------------------------------------------------------------------------
invoke_cc_codex_login() {
  echo "[cc-codex] OAuth device code flow..." >&2

  local resp device_code user_code verify_uri
  resp=$(curl -s -X POST "https://oauth.openai.com/v1/device_authorization" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=chatbot&scope=platform") || {
    echo "[cc-codex] Failed to initiate device flow: $resp" >&2
    return 1
  }

  device_code=$(echo "$resp" | jq -r '.device_code')
  user_code=$(echo "$resp" | jq -r '.user_code')
  verify_uri=$(echo "$resp" | jq -r '.verification_uri')

  if [[ -z "$device_code" ]] || [[ "$device_code" == "null" ]]; then
    echo "[cc-codex] Failed to get device code. Response: $resp" >&2
    return 1
  fi

  echo "[cc-codex] URL:  $verify_uri"
  echo "[cc-codex] Code: $user_code"

  # Try to open browser (macOS open, Linux xdg-open)
  if command -v open &>/dev/null; then
    open "$verify_uri" &>/dev/null &
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$verify_uri" &>/dev/null &
  fi

  local deadline=$(( $(date +%s) + 120 ))
  while (( $(date +%s) < deadline )); do
    sleep 5
    local token_resp
    token_resp=$(curl -s -X POST "https://oauth.openai.com/v1/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$device_code&client_id=chatbot")

    local access_token
    access_token=$(echo "$token_resp" | jq -r '.access_token // empty')
    if [[ -n "$access_token" ]] && [[ "$access_token" != "null" ]]; then
      local cache_dir
      cache_dir=$(dirname "$CC_CODEX_TOKEN_CACHE")
      mkdir -p "$cache_dir"
      echo "$token_resp" | jq '.' > "$CC_CODEX_TOKEN_CACHE"
      echo "[cc-codex] Login successful."
      return 0
    fi

    local error
    error=$(echo "$token_resp" | jq -r '.error // empty')
    if [[ -n "$error" ]] && [[ "$error" != "authorization_pending" ]]; then
      echo "[cc-codex] Polling error: $error — $token_resp"
      break
    fi
  done

  echo "[cc-codex] Timeout. Manual code: $user_code | URL: $verify_uri"
}

#------------------------------------------------------------------------------
# cc-codex-logout — remove cached token
#------------------------------------------------------------------------------
invoke_cc_codex_logout() {
  if [[ -f "$CC_CODEX_TOKEN_CACHE" ]]; then
    rm -f "$CC_CODEX_TOKEN_CACHE"
    echo "[cc-codex] Logged out."
  else
    echo "[cc-codex] No cached token."
  fi
}

#------------------------------------------------------------------------------
# cc-codex — launch via Codex OAuth
#------------------------------------------------------------------------------
invoke_cc_codex() {
  invoke_cc_provider "codex" "" "$@"
}