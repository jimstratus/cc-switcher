# =============================================================================
# codex.sh — Unsupported direct Codex guard + legacy token-cache cleanup
# Historical token cache: ~/.config/codex-oauth/token.json
# =============================================================================

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
  # Token is valid only with a numeric, future expires_at (matches Get-CC-CodexToken)
  if [[ -z "$access_token" ]] || ! [[ "$expires_at" =~ ^[0-9]+$ ]] || (( expires_at <= now )); then
    echo ""
    return 0
  fi
  echo "$access_token"
}

#------------------------------------------------------------------------------
# Explain why direct Codex OAuth cannot back Claude Code
#------------------------------------------------------------------------------
show_cc_codex_unsupported() {
  echo "[ERROR] Direct ChatGPT OAuth cannot be used as a Claude Code provider." >&2
  echo "        ChatGPT OAuth tokens do not authenticate api.openai.com, and that API" >&2
  echo "        does not implement Claude Code's Anthropic Messages protocol." >&2
  echo "        For native Codex: codex login --device-auth" >&2
  echo "        For GPT via Claude Code: cc-openrouter openai/gpt-5.4" >&2
}

invoke_cc_codex_login() {
  # A successful device login would still yield an unusable token here, so fail
  # before asking the user to authenticate or persisting another bearer token.
  show_cc_codex_unsupported
  return 1
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
# cc-codex — disabled direct Codex launch path (migration guard)
#------------------------------------------------------------------------------
invoke_cc_codex() {
  show_cc_codex_unsupported
  return 1
}