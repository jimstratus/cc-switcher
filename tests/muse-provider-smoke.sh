#!/usr/bin/env bash
# Purpose: Verify the Bash Muse mapping, extra environment, and restoration contract.
# Usage: bash tests/muse-provider-smoke.sh
# Prerequisites: bash and jq.

set -e

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/bash/cc-switcher.sh" >/dev/null

# Force the envVars jq query through a CRLF fixture that also decorates the key.
# This deterministically exercises both defensive normalizations on every CI OS.
real_jq=$(command -v jq)
jq() {
  if [[ "$*" == *"to_entries[]"* ]]; then
    "$real_jq" "$@" | while IFS=$'\t' read -r key value; do
      key="${key%$'\r'}"
      value="${value%$'\r'}"
      printf '%s\r\t%s\r\n' "$key" "$value"
    done
  else
    "$real_jq" "$@"
  fi
}

claude() {
  [[ "$ANTHROPIC_BASE_URL" == "https://api.meta.ai" ]]
  [[ "$ANTHROPIC_AUTH_TOKEN" == "$MODEL_API_KEY" ]]
  [[ "$ANTHROPIC_MODEL" == "muse-spark-1.2" ]]
  [[ "$ANTHROPIC_DEFAULT_OPUS_MODEL" == "muse-spark-1.2" ]]
  [[ "$ANTHROPIC_DEFAULT_SONNET_MODEL" == "muse-spark-1.2" ]]
  [[ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" == "muse-spark-1.2" ]]
  [[ "$CLAUDE_CODE_SUBAGENT_MODEL" == "muse-spark-1.2" ]]
  [[ "$ENABLE_TOOL_SEARCH" == "true" ]]
  [[ "${1:-}" == "--muse-smoke" ]]
}

export MODEL_API_KEY="sk-test-muse-1234567890"
export ANTHROPIC_BASE_URL="original-base-url"
export CLAUDE_CODE_SUBAGENT_MODEL="original-subagent"
unset ENABLE_TOOL_SEARCH

cc-muse --muse-smoke >/dev/null

[[ "$ANTHROPIC_BASE_URL" == "original-base-url" ]]
[[ "$CLAUDE_CODE_SUBAGENT_MODEL" == "original-subagent" ]]
[[ -z "${ENABLE_TOOL_SEARCH:-}" ]]

echo "PASS: Bash Muse provider mapping and restore"
