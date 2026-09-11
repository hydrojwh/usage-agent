param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $windowsRoot "build.ps1") -Configuration $Configuration

$output = Join-Path $windowsRoot "Usage.Windows\bin\$Configuration"
$artifacts = Join-Path $windowsRoot "artifacts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

$archive = Join-Path $artifacts "Usage-Windows-$Version.zip"
$files = @(
    (Join-Path $output "Usage.Windows.exe"),
    (Join-Path $output "Usage.Windows.exe.config"),
    (Join-Path $output "Usage.Windows.Core.dll"),
    (Join-Path $output "THIRD_PARTY_NOTICES.md")
)
Compress-Archive -LiteralPath $files -DestinationPath $archive -Force
Write-Host "Windows distribution archive: $archive"
