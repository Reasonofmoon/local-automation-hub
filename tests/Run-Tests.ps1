[CmdletBinding()]
param(
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $ahk)) {
    throw "AutoHotkey executable not found: $ahk"
}

$testFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*-tests.ahk' -File | Sort-Object Name
if ($Only) {
    $requested = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $testFiles = @($testFiles | Where-Object {
        $stem = $_.BaseName -replace '-tests$',''
        $requested -contains $stem.ToLowerInvariant()
    })
}
if (-not $testFiles) {
    throw 'No test files selected.'
}

$failures = 0
foreach ($test in $testFiles) {
    Write-Host "[VALIDATE] $($test.FullName)"
    $validationOutput = (& $ahk '/ErrorStdOut=UTF-8' '/Validate' $test.FullName 2>&1 | Out-String)
    if ($validationOutput.Trim()) {
        Write-Host $validationOutput.TrimEnd()
    }
    $validationExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    if ($validationExit -ne 0 -or $validationOutput -match '==>|(?i)error') {
        $failures++
        continue
    }
    Write-Host "[TEST] $($test.Name)"
    $testOutput = (& $ahk $test.FullName 2>&1 | Out-String)
    if ($testOutput.Trim()) {
        Write-Host $testOutput.TrimEnd()
    }
    $testExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    if ($testExit -ne 0 -or $testOutput -match '(?m)^FAIL(?:URES=|:)') {
        $failures++
    }
}
if ($failures -gt 0) {
    throw "$failures test file(s) failed."
}
Write-Host "PASS: $($testFiles.Count) test file(s)"
