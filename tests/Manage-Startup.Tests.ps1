[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$manageScript = Join-Path $PSScriptRoot '..\scripts\Manage-Startup.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('local-automation-hub-startup-test-' + [guid]::NewGuid().ToString('N'))
$repositoryRoot = Join-Path $tempRoot 'repo'
$startupFolder = Join-Path $tempRoot 'startup'
$mainPath = Join-Path $repositoryRoot 'main.ahk'
$autoHotkeyPath = Join-Path $env:SystemRoot 'System32\cmd.exe'

function Invoke-ManageStartup {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Remove', 'Status')]
        [string]$Action,

        [int]$TimeoutSeconds = 15
    )

    function ConvertTo-ProcessArgument {
        param([Parameter(Mandatory)][string]$Value)

        $builder = [System.Text.StringBuilder]::new()
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $Value.ToCharArray()) {
            if ($character -eq '\') {
                $backslashes++
                continue
            }
            if ($character -eq '"') {
                [void]$builder.Append('\', ($backslashes * 2) + 1)
                [void]$builder.Append('"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) {
                [void]$builder.Append('\', $backslashes)
                $backslashes = 0
            }
            [void]$builder.Append($character)
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append('\', $backslashes * 2)
        }
        [void]$builder.Append('"')
        return $builder.ToString()
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $manageScript,
        '-Action', $Action,
        '-RepositoryRoot', $repositoryRoot,
        '-StartupFolder', $startupFolder,
        '-AutoHotkeyPath', $autoHotkeyPath
    )
    $startInfo.Arguments = [string]::Join(' ', ($arguments | ForEach-Object {
        ConvertTo-ProcessArgument -Value ([string]$_)
    }))

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Failed to start Manage-Startup.ps1 child process.'
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
            Output = $outputTask.Result + $errorTask.Result
            ExitCode = if ($timedOut) { -1 } else { $process.ExitCode }
            TimedOut = $timedOut
        }
    } catch {
        return [pscustomobject]@{
            Output = ''
            ExitCode = -1
            TimedOut = $false
            Error = $_.Exception.Message
        }
    } finally {
        $process.Dispose()
    }
}

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

New-Item -ItemType Directory -Path $repositoryRoot, $startupFolder -Force | Out-Null
Set-Content -LiteralPath $mainPath -Value '#Requires AutoHotkey v2.0' -Encoding UTF8
$shortcutPath = Join-Path $startupFolder 'Local Automation Hub.lnk'

try {
    $status = Invoke-ManageStartup -Action Status
    Assert-Condition ($status.ExitCode -eq 0) 'status exits successfully for an empty injected Startup folder'
    Assert-Condition (-not $status.TimedOut) 'status stays within its process timeout'
    Assert-Condition ($status.Output -match 'State\s*:\s*Absent') 'status distinguishes an absent shortcut'

    $install = Invoke-ManageStartup -Action Install
    Assert-Condition ($install.ExitCode -eq 0) 'install creates a managed shortcut in the injected folder'
    Assert-Condition (Test-Path -LiteralPath $shortcutPath -PathType Leaf) 'install creates only the injected shortcut'

    $status = Invoke-ManageStartup -Action Status
    Assert-Condition ($status.Output -match 'State\s*:\s*Managed') 'status identifies an exact owned shortcut as managed'

    $idempotent = Invoke-ManageStartup -Action Install
    Assert-Condition ($idempotent.ExitCode -eq 0) 'install is idempotent for an exact managed shortcut'
    Assert-Condition ($idempotent.Output -match '(?i)already managed') 'idempotent install reports the managed state'

    Remove-Item -LiteralPath $shortcutPath -Force
    $shell = New-Object -ComObject WScript.Shell
    $conflict = $shell.CreateShortcut($shortcutPath)
    $conflict.TargetPath = $autoHotkeyPath
    $conflict.Arguments = '"unowned-script.ahk"'
    $conflict.WorkingDirectory = $repositoryRoot
    $conflict.Description = 'Unowned shortcut'
    $conflict.Save()

    $status = Invoke-ManageStartup -Action Status
    Assert-Condition ($status.Output -match 'State\s*:\s*Conflict') 'status identifies an unowned fixed-name shortcut as a conflict'

    $conflictingInstall = Invoke-ManageStartup -Action Install
    Assert-Condition ($conflictingInstall.ExitCode -ne 0) 'install aborts on an unowned fixed-name shortcut'
    Assert-Condition (Test-Path -LiteralPath $shortcutPath -PathType Leaf) 'conflicting install preserves the unowned shortcut'

    $conflictingRemove = Invoke-ManageStartup -Action Remove
    Assert-Condition ($conflictingRemove.ExitCode -ne 0) 'remove aborts on an unowned fixed-name shortcut'
    Assert-Condition (Test-Path -LiteralPath $shortcutPath -PathType Leaf) 'conflicting remove preserves the unowned shortcut'

    Remove-Item -LiteralPath $shortcutPath -Force
    $install = Invoke-ManageStartup -Action Install
    Assert-Condition ($install.ExitCode -eq 0) 'install succeeds after the conflict is removed'
    $remove = Invoke-ManageStartup -Action Remove
    Assert-Condition ($remove.ExitCode -eq 0) 'remove deletes an exact managed shortcut'
    Assert-Condition (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) 'managed remove deletes only the managed shortcut'

    Write-Host 'PASS: startup ownership contract'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
