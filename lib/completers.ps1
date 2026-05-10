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
    $ocModels = @('minimax-m2.7','glm-5.1','glm-5-turbo','kimi-k2.6','qwen3.6-plus',
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
        'meta/llama-4-maverick-17b-128e-instruct',
        'meta/llama-4-scout-17b-16e-instruct',
        'meta/llama-3.3-70b-instruct',
        'moonshotai/kimi-k2-instruct',
        'qwen/qwen3-235b-a22b',
        'deepseek-ai/deepseek-r1',
        'nvidia/llama-3.1-nemotron-70b-instruct',
        'mistralai/mistral-nemo-12b-instruct'
    )
    Register-ArgumentCompleter -CommandName 'cc-nvidia','Invoke-CC-Nvidia' `
        -ParameterName 'Model' -ScriptBlock $nvCompleter
}
