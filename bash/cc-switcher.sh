# =============================================================================
# cc-switcher.sh — Claude Code multi-provider launcher (bash port v3.3.0)
# This file is sourced into interactive shells: it must not alter shell options
# (set -e/-u/pipefail would leak into the user's session).
# =============================================================================

export CCSWITCHER_ROOT="${CCSWITCHER_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)}"
export CCSWITCHER_VERSION="3.3.0"

# Load library files in dependency order
# shellcheck source=lib/core.sh
source "${CCSWITCHER_ROOT}/lib/core.sh"
# shellcheck source=lib/providers.sh
source "${CCSWITCHER_ROOT}/lib/providers.sh"
# shellcheck source=lib/codex.sh
source "${CCSWITCHER_ROOT}/lib/codex.sh"
# shellcheck source=lib/pricing.sh
source "${CCSWITCHER_ROOT}/lib/pricing.sh"
# shellcheck source=lib/doctor.sh
source "${CCSWITCHER_ROOT}/lib/doctor.sh"
# shellcheck source=lib/completers.sh
source "${CCSWITCHER_ROOT}/lib/completers.sh"
# shellcheck source=lib/usage.sh
source "${CCSWITCHER_ROOT}/lib/usage.sh"
# shellcheck source=lib/update-check.sh
source "${CCSWITCHER_ROOT}/lib/update-check.sh"

# =============================================================================
# Public aliases / functions
# =============================================================================

cc-deepseek()       { invoke_cc_provider "deepseek" "" "$@"; }
cc-glm()            { invoke_cc_provider "glm" "" "$@"; }
cc-kimi()           { invoke_cc_provider "kimi" "" "$@"; }
cc-minimax()        { invoke_cc_provider "minimax" "" "$@"; }
cc-mimo()           { invoke_cc_provider "mimo" "" "$@"; }
cc-nvidia()         { invoke_cc_nvidia "$@"; }
cc-qwen()           { invoke_cc_provider "qwen" "" "$@"; }
cc-xiaomi()         { invoke_cc_provider "xiaomi" "" "$@"; }
cc-openrouter()     { invoke_cc_openrouter "$@"; }
cc-opencode()       { invoke_cc_opencode "$@"; }
cc-opencode-minimax(){ invoke_cc_provider "opencode-minimax" "" "$@"; }
cc-minimax-or()     { invoke_cc_provider "minimax-or" "" "$@"; }
cc-codex()          { invoke_cc_codex "$@"; }
cc-codex-login()    { invoke_cc_codex_login; }
cc-codex-logout()   { invoke_cc_codex_logout; }
cc-zai-glm51()      { invoke_cc_provider "zai-glm51" "" "$@"; }
cc-gemini()         { invoke_cc_provider "gemini" "" "$@"; }
cc-grok()           { invoke_cc_provider "grok" "" "$@"; }
cc-nemotron()       { invoke_cc_provider "nemotron" "" "$@"; }
cc-owl()            { invoke_cc_provider "owl-alpha" "" "$@"; }
cc-ollama-glm()     { invoke_cc_provider "ollama-glm" "" "$@"; }
cc-ollama-minimax() { invoke_cc_provider "ollama-minimax" "" "$@"; }

# Utility commands
cc-launch()         { invoke_cc_launch_menu; }
cc-doctor()         { invoke_cc_doctor "$@"; }
cc-pricing()        { get_cc_pricing; }
cc-status()         { get_cc_status; }
cc-usage()          { get_cc_usage "$@"; }
cc-reset()          { reset_cc "$@"; }
cc-yolo()           { invoke_cc_yolo "$@"; }
cc-help()           { show_cc_help; }

# =============================================================================
# Banner
# =============================================================================

_cc_check_updated

case "${CC_BANNER:-compact}" in
  minimal)
    echo "[cc-switcher v${CCSWITCHER_VERSION} loaded — type cc-help]$_cc_updated_flag"
    ;;
  full)
    show_cc_help
    ;;
  *)
    echo "[cc-switcher v${CCSWITCHER_VERSION} — cc-help for details]$_cc_updated_flag"
    ;;
esac