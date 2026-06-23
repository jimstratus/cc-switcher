# API key safety & spend control

> A 5-minute read **before** you paste your first key. API keys are passwords that
> cost real money. This page is the short list of habits that keep you safe.
> New to all this? Start with the [Getting Started guide](onboarding.md) first.

---

## TL;DR (the 6 rules)

1. **Treat keys like credit-card numbers.** Never share, screenshot, or paste them into chats, issues, or code.
2. **Keep keys out of git.** Put them in a file git ignores (`.env`) or your shell profile — never in tracked files.
3. **Prepay, don't auto-bill.** Use prepaid credits where possible so you *can't* be charged more than you loaded.
4. **Set a per-key spend cap** on providers that support it (OpenRouter does).
5. **One key per purpose**, and delete keys you're not using.
6. **If a key leaks, revoke it immediately** — don't wait, don't "fix it later."

---

## 1. Where to put your keys (and where NOT to)

✅ **Safe places**
- Your shell profile: `~/.bashrc`, `~/.zshrc`, or PowerShell `$PROFILE`.
- A dedicated ignored file you `source`, e.g. `~/.cc-switcher.env` (copy from [`.env.example`](../.env.example)).
- A real secrets manager (1Password, `pass`, system keychain) if you want to level up.

❌ **Never put keys in**
- Source code, config files, or anything tracked by git.
- Commit messages, GitHub issues, Discord/Slack, or screenshots.
- A file literally named `.env` that you then `git add -f` (the `-f` defeats the gitignore — don't).

cc-switcher's `.gitignore` already ignores `.env` and `.env.local`. The committed
[`.env.example`](../.env.example) is a **template with empty values** — safe to share; your filled-in copy is not.

```bash
# Good: keep secrets in an ignored file, load it from your profile
cp .env.example ~/.cc-switcher.env        # fill in your keys here
echo '[ -f ~/.cc-switcher.env ] && source ~/.cc-switcher.env' >> ~/.bashrc
```

> 🔎 **Quick self-check:** run `git status` and `git diff --staged` before every commit.
> If you ever see a key in the diff, **stop** — unstage it and revoke the key.

---

## 2. Controlling spend (don't get a surprise bill)

| Lever | How | Providers |
|---|---|---|
| **Prepaid credits** | Load a fixed amount; you can't exceed it | OpenRouter, MiniMax credits, DeepSeek top-up |
| **Per-key credit limit** | Set a cap when you create the key | OpenRouter (`Create Key → limit`) |
| **Flat subscription** | Fixed monthly price, quota-limited (no per-token bill) | Z.AI GLM, MiniMax/Xiaomi/Kimi plans, OpenCode Go |
| **Free tiers** | $0 — make mistakes here | `cc-nemotron`, `cc-owl`, `cc-nvidia`, Ollama free |
| **Watch usage** | `cc-usage` (token history) · `cc-pricing` (live rates) | cc-switcher built-ins |

**Beginner-safe default:** start on a **free model** (`cc-nemotron`) to learn the workflow, then
move to **OpenRouter with a $10 prepaid balance and a per-key cap**. You physically cannot overspend.

> 💸 Coding agents generate a lot of **output** tokens, and output is the priciest part. A long
> autonomous run on a premium model (Gemini/Grok/Opus) is where surprise costs come from — prefer
> the cheap tier (DeepSeek, MiMo, MiniMax, GLM) for long sessions. See the
> [pricing cheat-sheet](onboarding.md#8-pricing-cheat-sheet-all-providers).

---

## 3. If a key leaks (or you're not sure)

Act in this order — it takes two minutes:

1. **Revoke/delete the key** in the provider's dashboard (links below). This instantly makes it useless.
2. **Create a fresh key** and update your `~/.cc-switcher.env` / profile.
3. **Check usage/billing** for anything you didn't do.
4. If it was committed to git, revoking is what actually protects you — **rotating the key matters more
   than scrubbing history**, because anything pushed should be considered public forever.

| Provider | Manage / revoke keys |
|---|---|
| OpenRouter | <https://openrouter.ai/settings/keys> |
| DeepSeek | <https://platform.deepseek.com> → API Keys |
| MiniMax | <https://platform.minimax.io> → API Keys |
| Z.AI | <https://z.ai/manage-apikey/apikey-list> |
| Xiaomi MiMo | <https://platform.xiaomimimo.com> → API Keys |
| Moonshot/Kimi | <https://platform.moonshot.ai> → Console |
| NVIDIA NIM | <https://build.nvidia.com/settings/api-keys> |
| Ollama Cloud | <https://ollama.com/settings/keys> |
| OpenCode Go | <https://opencode.ai/auth> |

---

## 4. A note on the free "stealth" models

`cc-owl` (Owl Alpha) is a **free cloaked/stealth model** — its provider may **log your prompts and
completions** to improve the model. It's great for throwaway exploration, but **don't send secrets,
proprietary code, or anything sensitive** through it. The same caution applies to any free tier: you're
often paying with data instead of money. For private work, use a paid provider with a clear data policy.

---

## 5. `--yolo` / `--dangerously-skip-permissions`

cc-switcher can launch Claude Code with permission prompts disabled (`--yolo`, or `CC_YOLO=1`). That lets
the AI run commands and edit files **without asking you first**. It's convenient but removes your safety
net — only use it in a directory/project you're willing to let the agent change freely, ideally one under
version control so you can `git diff` and undo. When in doubt, leave it off.

---

*Part of the [cc-switcher](../README.md) docs. Questions or a security concern? See
[CONTRIBUTING.md](../CONTRIBUTING.md).*
