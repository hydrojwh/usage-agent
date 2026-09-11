param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$solution = Join-Path $windowsRoot "Usage.Windows.sln"

msbuild $solution /t:Rebuild /p:Configuration=$Configuration /p:Platform="Any CPU"

$tests = Join-Path $windowsRoot "Usage.Windows.Tests\bin\$Configuration\Usage.Windows.Tests.exe"
& $tests

$appDirectory = Join-Path $windowsRoot "Usage.Windows\bin\$Configuration"
Write-Host "Usage for Windows built at: $appDirectory"
