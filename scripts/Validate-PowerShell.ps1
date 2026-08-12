[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$startupScript = Join-Path $PSScriptRoot 'Manage-Startup.ps1'
$startupCommand = Get-Command $startupScript -Syntax -ErrorAction Stop
if ($startupCommand -notmatch '(?i)-Action') {
    throw 'Manage-Startup.ps1 must expose -Action'
}
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | Sort-Object FullName
$parseFailures = [System.Collections.Generic.List[string]]::new()

foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in $errors) {
        $parseFailures.Add("$($file.FullName):$($error.Extent.StartLineNumber): $($error.Message)")
    }
}

if ($parseFailures.Count -gt 0) {
    throw "PowerShell parse failures:`n$($parseFailures -join "`n")"
}

Write-Host "PASS: $($files.Count) PowerShell file(s) parsed"
