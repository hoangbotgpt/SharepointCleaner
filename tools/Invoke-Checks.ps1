#Requires -Version 7.4
<#
.SYNOPSIS
Runs the project quality gate: UTF-8 BOM check, PSScriptAnalyzer and Pester.

.EXAMPLE
pwsh ./tools/Invoke-Checks.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$FixEncoding
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$failed = $false

# 1. Encoding: files with non-ASCII text must have a UTF-8 BOM (Windows PowerShell 5.1 compatibility)
$psFiles = Get-ChildItem -Path $root -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|reports|logs)[\\/]' }
foreach ($file in $psFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom -or -not ($bytes | Where-Object { $_ -gt 0x7F } | Select-Object -First 1)) { continue }
    if ($FixEncoding) {
        $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
        [IO.File]::WriteAllText($file.FullName, $text, [Text.UTF8Encoding]::new($true))
        Write-Host "Đã thêm BOM: $($file.FullName)"
    } else {
        Write-Host "Thiếu UTF-8 BOM: $($file.FullName) (chạy lại với -FixEncoding)" -ForegroundColor Red
        $failed = $true
    }
}

# 2. PSScriptAnalyzer
Import-Module PSScriptAnalyzer
$issues = @(
    Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Settings PSGallery -Severity Warning, Error
    Invoke-ScriptAnalyzer -Path (Join-Path $root 'scripts') -Recurse -Settings PSGallery -Severity Warning, Error -ExcludeRule PSAvoidUsingWriteHost
    Invoke-ScriptAnalyzer -Path (Join-Path $root 'tools') -Recurse -Settings PSGallery -Severity Warning, Error -ExcludeRule PSAvoidUsingWriteHost
)
if ($issues.Count -gt 0) {
    $issues | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-Host
    $failed = $true
} else {
    Write-Host 'PSScriptAnalyzer: không có vấn đề.' -ForegroundColor Green
}

# 3. Pester
if (-not $SkipTests) {
    Import-Module Pester -MinimumVersion 5.5
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $root 'tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { $failed = $true }
}

if ($failed) { exit 1 }
