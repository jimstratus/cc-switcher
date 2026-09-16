# =============================================================================
# completers.ps1 — Tab completion for cc-openrouter / cc-opencode / cc-nvidia
# Pulls cached OpenRouter pricing for live model IDs.
# =============================================================================

function Register-CCCompleters {
    # cc-openrouter / cc-opencode: complete from OpenRouter model catalog
    $orCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)
        $models = Get-CCLivePricing
        if (-not $models) { return @() }
        $matches = $models | Where-Object { $_.id -like "*$wordToComplete*" } |
            Select-Object -First 30 -ExpandProperty id
        $matches | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                "'$_'", $_, 'ParameterValue', $_
            )
        }
    }
    Register-ArgumentCompleter -CommandName 'cc-openrouter','Invoke-CC-OpenRouter' `
        -ParameterName 'Model' -ScriptBlock $orCompleter

    # cc-opencode: a smaller curated list since OpenCode Go's model API isn't public
    $ocModels = @('minimax-m3','glm-5.1','glm-5-turbo','kimi-k2.6','qwen3.6-plus',
                  'mimo-v2-pro','mimo-v2-omni')
    $ocCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)
        $script:_ocModelList | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    $script:_ocModelList = $ocModels
    Register-ArgumentCompleter -CommandName 'cc-opencode','Invoke-CC-OpenCode' `
        -ParameterName 'Model' -ScriptBlock $ocCompleter

    # cc-nvidia: well-known NIM model families
    $nvCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)
        $script:_nvModelList | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    $script:_nvModelList = @(
        'moonshotai/kimi-k3',
        'nvidia/nemotron-3-ultra-550b-a55b',
        'nvidia/nemotron-3.5-lightning-30b-a3b',
        'meta/llama-3.3-70b-instruct',
        'qwen/qwen3-235b-a22b',
        'deepseek-ai/deepseek-r1',
        'nvidia/llama-3.1-nemotron-70b-instruct',
        'mistralai/mistral-nemo-12b-instruct'
    )
    Register-ArgumentCompleter -CommandName 'cc-nvidia','Invoke-CC-Nvidia' `
        -ParameterName 'Model' -ScriptBlock $nvCompleter
}
