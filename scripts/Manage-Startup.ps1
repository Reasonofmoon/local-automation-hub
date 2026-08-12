[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Action = 'Status',

    [string]$RepositoryRoot = '',

    [string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',

    # Tests may inject a temporary folder. The default is always the real user Startup folder.
    [string]$StartupFolder = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$shortcutName = 'Local Automation Hub.lnk'
$ownershipMarker = 'Local Automation Hub; managed-by=LocalAutomationHub'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return $resolved.ProviderPath
}

function Get-CanonicalPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$RequireExists
    )

    if ($RequireExists) {
        return Resolve-ExistingPath -Path $Path
    }
    return [IO.Path]::GetFullPath($Path)
}

function Get-StartupDirectory {
    if (-not [string]::IsNullOrWhiteSpace($StartupFolder)) {
        return [IO.Path]::GetFullPath($StartupFolder)
    }
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) {
        throw 'Windows Startup folder could not be resolved.'
    }
    return $startup
}

function Get-ShortcutPath {
    return Join-Path (Get-StartupDirectory) $shortcutName
}

function New-ShortcutArguments {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    return '"' + $ScriptPath + '"'
}

function Compare-WindowsPath {
    param(
        [AllowEmptyString()]
        [string]$Left,
        [AllowEmptyString()]
        [string]$Right
    )

    $leftValue = ([IO.Path]::GetFullPath($Left)).TrimEnd('\')
    $rightValue = ([IO.Path]::GetFullPath($Right)).TrimEnd('\')
    return [StringComparer]::OrdinalIgnoreCase.Equals($leftValue, $rightValue)
}

function Get-ShortcutIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$ShortcutPath
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return [pscustomobject]@{
        TargetPath       = [string]$shortcut.TargetPath
        Arguments        = [string]$shortcut.Arguments
        WorkingDirectory = [string]$shortcut.WorkingDirectory
        Description      = [string]$shortcut.Description
    }
}

function Test-ManagedShortcut {
    param(
        [Parameter(Mandatory)]
        [psobject]$Identity,
        [Parameter(Mandatory)]
        [string]$ExpectedTargetPath,
        [Parameter(Mandatory)]
        [string]$ExpectedArguments,
        [Parameter(Mandatory)]
        [string]$ExpectedWorkingDirectory
    )

    return (Compare-WindowsPath -Left $Identity.TargetPath -Right $ExpectedTargetPath) `
        -and ([StringComparer]::Ordinal.Equals($Identity.Arguments, $ExpectedArguments)) `
        -and (Compare-WindowsPath -Left $Identity.WorkingDirectory -Right $ExpectedWorkingDirectory) `
        -and ([StringComparer]::Ordinal.Equals($Identity.Description, $ownershipMarker))
}

function Get-ShortcutStatus {
    param(
        [Parameter(Mandatory)]
        [string]$ShortcutPath,
        [Parameter(Mandatory)]
        [string]$ExpectedTargetPath,
        [Parameter(Mandatory)]
        [string]$ExpectedArguments,
        [Parameter(Mandatory)]
        [string]$ExpectedWorkingDirectory
    )

    $record = [ordered]@{
        Action           = 'Status'
        State            = 'Absent'
        Installed        = $false
        ShortcutPath     = $ShortcutPath
        TargetPath       = ''
        Arguments        = ''
        WorkingDirectory = ''
        OwnershipMarker  = ''
    }

    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
        return [pscustomobject]$record
    }

    try {
        $identity = Get-ShortcutIdentity -ShortcutPath $ShortcutPath
        $record.TargetPath = $identity.TargetPath
        $record.Arguments = $identity.Arguments
        $record.WorkingDirectory = $identity.WorkingDirectory
        $record.OwnershipMarker = $identity.Description
        if (Test-ManagedShortcut -Identity $identity -ExpectedTargetPath $ExpectedTargetPath `
                -ExpectedArguments $ExpectedArguments -ExpectedWorkingDirectory $ExpectedWorkingDirectory) {
            $record.State = 'Managed'
            $record.Installed = $true
        } else {
            $record.State = 'Conflict'
        }
    } catch {
        # A fixed-name non-shortcut file is still an unowned conflict and must be preserved.
        $record.State = 'Conflict'
    }
    return [pscustomobject]$record
}

$root = Resolve-ExistingPath -Path $RepositoryRoot
$mainPath = Resolve-ExistingPath -Path (Join-Path $root 'main.ahk')
$shortcutPath = Get-ShortcutPath
$expectedTargetPath = Resolve-ExistingPath -Path $AutoHotkeyPath
$expectedArguments = New-ShortcutArguments -ScriptPath $mainPath
$expectedWorkingDirectory = $root

switch ($Action) {
    'Status' {
        Get-ShortcutStatus -ShortcutPath $shortcutPath -ExpectedTargetPath $expectedTargetPath `
            -ExpectedArguments $expectedArguments -ExpectedWorkingDirectory $expectedWorkingDirectory | Format-List
        break
    }

    'Install' {
        $startup = Get-StartupDirectory
        if (-not (Test-Path -LiteralPath $startup -PathType Container)) {
            New-Item -ItemType Directory -Path $startup -Force | Out-Null
        }
        $status = Get-ShortcutStatus -ShortcutPath $shortcutPath -ExpectedTargetPath $expectedTargetPath `
            -ExpectedArguments $expectedArguments -ExpectedWorkingDirectory $expectedWorkingDirectory
        if ($status.State -eq 'Managed') {
            Write-Host "Already managed: $shortcutPath"
            break
        }
        if ($status.State -eq 'Conflict') {
            throw "Refusing to overwrite unowned Startup shortcut: $shortcutPath"
        }

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $expectedTargetPath
        $shortcut.Arguments = $expectedArguments
        $shortcut.WorkingDirectory = $expectedWorkingDirectory
        $shortcut.Description = $ownershipMarker
        $shortcut.Save()
        Write-Host "Installed: $shortcutPath"
        break
    }

    'Remove' {
        $status = Get-ShortcutStatus -ShortcutPath $shortcutPath -ExpectedTargetPath $expectedTargetPath `
            -ExpectedArguments $expectedArguments -ExpectedWorkingDirectory $expectedWorkingDirectory
        if ($status.State -eq 'Absent') {
            Write-Host "Not installed: $shortcutPath"
            break
        }
        if ($status.State -eq 'Conflict') {
            throw "Refusing to remove unowned Startup shortcut: $shortcutPath"
        }
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host "Removed: $shortcutPath"
        break
    }
}
