@{
    RootModule        = 'cc-switcher.psm1'
    ModuleVersion     = '3.3.1'
    GUID              = 'a1f2c0e1-cc01-4cc0-9cc0-0001cc000001'
    Author            = 'Ryan Mander'
    Description       = 'Claude Code multi-provider launcher (DeepSeek, MiMo, GLM, Qwen, MiniMax, Kimi, NVIDIA NIM, Codex, etc.) with tier mapping per provider, live pricing, health checks, token usage tracking, and tab completion.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-CCLaunch','Invoke-CCProvider','Reset-CC','Get-CC-Status',
        'Invoke-CC-DeepSeek','Invoke-CC-Glm','Invoke-CC-Kimi',
        'Invoke-CC-MiniMax','Invoke-CC-MiMo','Invoke-CC-Nvidia','Invoke-CC-Qwen','Invoke-CC-Xiaomi',
        'Invoke-CC-Codex','Invoke-CC-Codex-Login','Invoke-CC-Codex-Logout',
        'Invoke-CC-OpenRouter','Invoke-CC-OpenCode','Invoke-CC-OpenCode-MiniMax',
        'Invoke-CC-ZAI-GLM51','Invoke-CC-Yolo',
        'Invoke-CC-Owl-Alpha','Invoke-CC-Nemotron',
        'Invoke-CC-Gemini','Invoke-CC-Grok','Invoke-CC-MiniMax-OR',
        'Invoke-CC-Ollama-Glm','Invoke-CC-Ollama-MiniMax',
        'Invoke-CC-Launch-Menu','Invoke-CC-Pick',
        'Invoke-CC-Doctor','Get-CCPricing','Get-CCUsage','Show-CCHelp',
        'Get-CCProviders','Get-CCCatalog','Get-CCLivePricing'
    )
    AliasesToExport   = @(
        'cc-deepseek','cc-glm','cc-kimi','cc-minimax','cc-mimo','cc-nvidia','cc-qwen','cc-xiaomi',
        'cc-codex','cc-codex-login','cc-codex-logout',
        'cc-opencode','cc-opencode-minimax','cc-openrouter','cc-zai-glm51',
        'cc-owl','cc-nemotron',
        'cc-gemini','cc-grok','cc-minimax-or','cc-ollama-glm','cc-ollama-minimax',
        'cc-launch','cc-pick','cc-doctor','cc-pricing','cc-status','cc-usage',
        'cc-reset','cc-yolo','cc-help'
    )
    PrivateData = @{ PSData = @{
        Tags         = @('claude','llm','launcher','provider-switcher')
        ProjectUri   = 'https://github.com/jimstratus/cc-switcher'
        LicenseUri   = 'https://github.com/jimstratus/cc-switcher/blob/main/LICENSE'
        ReleaseNotes = 'See CHANGELOG.md'
    }}
}
