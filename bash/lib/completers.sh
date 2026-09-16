# =============================================================================
# completers.sh — bash tab completion for model IDs
# Registered for: cc-openrouter, cc-opencode, cc-nvidia
# =============================================================================

#------------------------------------------------------------------------------
# Completion for cc-openrouter: offer model IDs from OpenRouter catalog
#------------------------------------------------------------------------------
_cc_completer_openrouter() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Try to get models from pricing cache first
  local cache_file="${CCSWITCHER_ROOT}/data/.pricing-cache.json"
  if [[ -f "$cache_file" ]]; then
    local models
    models=$(jq -r '.data[].id' "$cache_file" 2>/dev/null) || models=""
    while IFS= read -r model; do
      if [[ -n "$cur" ]] && [[ "$model" != *"$cur"* ]]; then
        continue
      fi
      COMPREPLY+=("$model")
    done <<< "$models"
    if ((${#COMPREPLY[@]} > 0)); then
      return 0
    fi
  fi

  # Fallback to catalog models
  local catalog_models=(
    "moonshotai/kimi-k3"
    "z-ai/glm-5.3"
    "z-ai/glm-5.3-flash"
    "qwen/qwen3.8-max-0902"
    "qwen/qwen3.8-27b"
    "qwen/qwen3.8-flash"
    "minimax/minimax-m3"
    "xiaomi/mimo-v2.5-pro"
    "xiaomi/mimo-v2.5"
    "xiaomi/mimo-v2-flash"
    "deepseek-ai/deepseek-v4-pro"
    "moonshotai/kimi-k3"
    "nvidia/nemotron-3-ultra-550b-a55b"
    "nvidia/nemotron-3.5-lightning-30b-a3b"
    "mistralai/mistral-nemo-12b-instruct"
    "nvidia/llama-3.1-nemotron-70b-instruct"
  )
  mapfile -t COMPREPLY < <(compgen -W "${catalog_models[*]}" -- "$cur")
}

#------------------------------------------------------------------------------
# Completion for cc-opencode: curated list from OpenCode Go
#------------------------------------------------------------------------------
_cc_completer_opencode() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local models=(
    "minimax-m3"
    "glm-5.1"
    "glm-5-turbo"
    "kimi-k2.6"
    "qwen3.6-plus"
    "mimo-v2-pro"
    "mimo-v2-omni"
  )
  mapfile -t COMPREPLY < <(compgen -W "${models[*]}" -- "$cur")
}

#------------------------------------------------------------------------------
# Completion for cc-nvidia: well-known NVIDIA NIM model families
#------------------------------------------------------------------------------
_cc_completer_nvidia() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  local models=(
    "meta/llama-4-maverick-17b-128e-instruct"
    "meta/llama-4-scout-17b-16e-instruct"
    "meta/llama-3.3-70b-instruct"
    "qwen/qwen3-235b-a22b"
    "deepseek-ai/deepseek-r1"
    "nvidia/llama-3.1-nemotron-70b-instruct"
    "mistralai/mistral-nemo-12b-instruct"
  )
  mapfile -t COMPREPLY < <(compgen -W "${models[*]}" -- "$cur")
}

# Register completions (called once at load time)
_register_cc_completers() {
  # Only register if the complete builtin is available (i.e. running under bash)
  if ! type complete &>/dev/null; then
    return
  fi

  complete -F _cc_completer_openrouter cc-openrouter invoke_cc_openrouter
  complete -F _cc_completer_opencode cc-opencode invoke_cc_opencode
  complete -F _cc_completer_nvidia cc-nvidia invoke_cc_nvidia
}

_register_cc_completers
unset -f _register_cc_completers
