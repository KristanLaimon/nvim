$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    & go run build.go
    if ($LASTEXITCODE -ne 0) { throw "FoxQuery build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
