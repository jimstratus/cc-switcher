# Live Model Catalog Audit
Date: 2026-09-16
Project: cc-switcher
Tags: providers, model-catalog, openrouter, direct-api, verification

## Context
The provider catalog needed a current-model review for GLM, MiniMax, Kimi,
Qwen, and the surrounding direct and OpenRouter routes.

## What we tried
1. Queried the public OpenRouter model registry for every OpenRouter-backed
   catalog tier.
2. Queried authenticated model listings from Atlas, DeepSeek, MiniMax, NVIDIA,
   Ollama, and Z.AI without printing credentials.
3. Compared the returned IDs and context windows to the catalog before updating
   PowerShell and Bash in lockstep.

## What happened
GLM-5.3, Tencent Hy4 preview, Kimi K3, Qwen3.8, DeepSeek V4.1 Flash, current NVIDIA IDs, and
Ollama GLM-5.3 all replaced stale entries. MiniMax M3 remained current. The
OpenRouter MiMo V2-Flash and Owl Alpha IDs were absent; MiMo now uses V2.5 as
its supported fast fallback. Owl Alpha was confirmed as Meituan's LongCat 2.0
stealth identity, so `cc-owl` now deliberately preserves its familiar command
while targeting `meituan/longcat-2.0`. A forced Anthropic Messages tool call
succeeded against the public successor.

## Root cause / why
Model catalogs evolve independently across gateways. A model's marketing name,
an old accepted compatibility alias, and the current list-model ID can differ.
Only the live list-model endpoint can establish that a launcher's configured ID
is currently routable.

## Takeaway
For model refreshes, audit every tier against the live gateway list, not just
the requested flagship models. Preserve command semantics when an upstream
model disappears; only repoint it when a direct successor is evidenced and
document the compatibility decision.

## References
- `data/providers.json`
- `bash/data/providers.json`
- `https://openrouter.ai/api/v1/models`
- `https://api-docs.deepseek.com/quick_start/pricing/`
- `https://cloud.tencent.cn/document/product/1823/130079`
