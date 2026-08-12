[CmdletBinding()]
param(
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $ahk)) {
    throw "AutoHotkey executable not found: $ahk"
}

function Invoke-AhkProcess {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 10
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $quotedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in $Arguments) {
        $text = [string]$argument
        $quoted = [System.Text.StringBuilder]::new()
        [void]$quoted.Append('"')
        $backslashes = 0
        foreach ($character in $text.ToCharArray()) {
            if ($character -eq '\') {
                $backslashes++
                continue
            }
            if ($character -eq '"') {
                [void]$quoted.Append('\', ($backslashes * 2) + 1)
                [void]$quoted.Append('"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) {
                [void]$quoted.Append('\', $backslashes)
                $backslashes = 0
            }
            [void]$quoted.Append($character)
        }
        if ($backslashes -gt 0) {
            [void]$quoted.Append('\', $backslashes * 2)
        }
        [void]$quoted.Append('"')
        $quotedArguments.Add($quoted.ToString())
    }
    $startInfo.Arguments = [string]::Join(' ', $quotedArguments)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ Output = ''; Error = 'Failed to start AutoHotkey process.'; ExitCode = -1; TimedOut = $false }
        }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
        }
        [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outputTask, $errorTask))
        return [pscustomobject]@{
            Output = $outputTask.Result
            Error = $errorTask.Result
            ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
            TimedOut = $timedOut
        }
    } catch {
        return [pscustomobject]@{ Output = ''; Error = $_.Exception.Message; ExitCode = -1; TimedOut = $false }
    } finally {
        $process.Dispose()
    }
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

$moduleFiles = @()
if (-not $Only -or $requested -contains 'snippets') {
    $moduleFiles += Join-Path $PSScriptRoot '..\src\modules\Snippets.ahk'
}
if (-not $Only -or $requested -contains 'workspaces') {
    $moduleFiles += Join-Path $PSScriptRoot '..\src\modules\Workspaces.ahk'
}
if (-not $Only -or $requested -contains 'windows') {
    $moduleFiles += Join-Path $PSScriptRoot '..\src\modules\WindowManager.ahk'
}
if (-not $Only -or $requested -contains 'file-organizer') {
    $moduleFiles += Join-Path $PSScriptRoot '..\src\system\ExplorerSelection.ahk'
    $moduleFiles += Join-Path $PSScriptRoot '..\src\modules\FileOrganizer.ahk'
}
if (-not $Only -or $requested -contains 'credential') {
    $moduleFiles += Join-Path $PSScriptRoot '..\src\modules\CredentialStore.ahk'
}

$failures = 0
foreach ($module in $moduleFiles) {
    $modulePath = [System.IO.Path]::GetFullPath($module)
    Write-Host "[VALIDATE] $modulePath"
    $moduleResult = Invoke-AhkProcess -Path $ahk -Arguments @('/ErrorStdOut=UTF-8', '/Validate', $modulePath)
    $moduleOutput = $moduleResult.Output + $moduleResult.Error
    Write-Host "[RESULT] exit=$($moduleResult.ExitCode) timedOut=$($moduleResult.TimedOut)"
    if ($moduleOutput.Trim()) {
        Write-Host $moduleOutput.TrimEnd()
    }
    if ($moduleResult.TimedOut -or $moduleResult.ExitCode -ne 0 -or $moduleOutput -match '==>|(?i)error') {
        $failures++
    }
}
foreach ($test in $testFiles) {
    Write-Host "[VALIDATE] $($test.FullName)"
    $validationResult = Invoke-AhkProcess -Path $ahk -Arguments @('/ErrorStdOut=UTF-8', '/Validate', $test.FullName)
    $validationOutput = $validationResult.Output + $validationResult.Error
    Write-Host "[RESULT] exit=$($validationResult.ExitCode) timedOut=$($validationResult.TimedOut)"
    if ($validationOutput.Trim()) {
        Write-Host $validationOutput.TrimEnd()
    }
    if ($validationResult.TimedOut -or $validationResult.ExitCode -ne 0 -or $validationOutput -match '==>|(?i)error') {
        $failures++
        continue
    }
    Write-Host "[TEST] $($test.Name)"
    $testResult = Invoke-AhkProcess -Path $ahk -Arguments @('/ErrorStdOut=UTF-8', $test.FullName)
    $testOutput = $testResult.Output + $testResult.Error
    Write-Host "[RESULT] exit=$($testResult.ExitCode) timedOut=$($testResult.TimedOut)"
    if ($testOutput.Trim()) {
        Write-Host $testOutput.TrimEnd()
    }
    if ($testResult.TimedOut -or $testResult.ExitCode -ne 0 -or $testOutput -match '(?m)^FAIL(?:URES=|:)' -or $testResult.Output -notmatch '(?m)^PASS\r?$') {
        $failures++
    }
}
if ($failures -gt 0) {
    throw "$failures test file(s) failed."
}
Write-Host "PASS: $($testFiles.Count) test file(s)"
