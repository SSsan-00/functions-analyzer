[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $repoRoot "src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj"
$publishProfile = "win-x64-single-file"
$publishDirectory = Join-Path $repoRoot "src\FunctionsAnalyzer.Gui\bin\Release\net9.0-windows\win-x64\publish"
$exePath = Join-Path $publishDirectory "FunctionsAnalyzer.exe"

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}

dotnet publish $projectPath -p:PublishProfile=$publishProfile
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Publish completed, but the expected exe was not found: $exePath"
}

Write-Host "Release exe created:"
Write-Host $exePath
