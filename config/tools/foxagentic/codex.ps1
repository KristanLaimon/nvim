# This launcher is added only to FoxVim terminal PATHs; shell profiles stay untouched.
$codexArguments = @($args)
$sessionId = $null
if ($args.Count -eq 0 -and $env:FOX_AGENTIC_TOKEN -and $env:FOX_AGENTIC_SERVER) {
    $sessionId = & $env:FOX_AGENTIC_NVIM --headless -u NONE -i NONE -n -l $env:FOX_AGENTIC_BRIDGE create
    if ($LASTEXITCODE -eq 0 -and $sessionId -is [string] -and $sessionId -match '^[a-zA-Z0-9_-]+$') {
        $codexArguments = @('resume', $sessionId)
    } else {
        $sessionId = $null
    }
}
$bindingToken, $bindingServer = $env:FOX_AGENTIC_TOKEN, $env:FOX_AGENTIC_SERVER
try {
    $env:FOX_AGENTIC_TOKEN, $env:FOX_AGENTIC_SERVER = $null, $null
    & $env:FOX_AGENTIC_REAL_CODEX @codexArguments
    $codexStatus = $LASTEXITCODE
} finally {
    $env:FOX_AGENTIC_TOKEN, $env:FOX_AGENTIC_SERVER = $bindingToken, $bindingServer
}
if ($sessionId) {
    & $env:FOX_AGENTIC_NVIM --headless -u NONE -i NONE -n -l $env:FOX_AGENTIC_BRIDGE finish $sessionId 2>$null | Out-Null
}
exit $codexStatus
