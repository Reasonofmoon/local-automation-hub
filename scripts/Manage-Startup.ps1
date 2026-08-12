[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Action = 'Status',

    [string]$RepositoryRoot = '',

    [string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$shortcutName = 'Local Automation Hub.lnk'

function Get-ResolvedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return $resolved.ProviderPath
}

function Get-ManagedShortcutPath {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startupFolder)) {
        throw 'Windows Startup folder could not be resolved.'
    }
    return Join-Path $startupFolder $shortcutName
}

function New-ShortcutArguments {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    return '"' + $ScriptPath + '"'
}

function Get-StatusRecord {
    param(
        [Parameter(Mandatory)]
        [string]$ShortcutPath
    )

    $record = [ordered]@{
        Action       = 'Status'
        ShortcutPath = $ShortcutPath
        Installed    = $false
        TargetPath   = ''
        Arguments    = ''
        WorkingDirectory = ''
    }

    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
        return [pscustomobject]$record
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $record.Installed = $true
    $record.TargetPath = [string]$shortcut.TargetPath
    $record.Arguments = [string]$shortcut.Arguments
    $record.WorkingDirectory = [string]$shortcut.WorkingDirectory
    return [pscustomobject]$record
}

$root = Get-ResolvedPath -Path $RepositoryRoot
$mainPath = Get-ResolvedPath -Path (Join-Path $root 'main.ahk')
$shortcutPath = Get-ManagedShortcutPath

switch ($Action) {
    'Status' {
        $status = Get-StatusRecord -ShortcutPath $shortcutPath
        $status | Format-List
        break
    }

    'Install' {
        $ahkPath = Get-ResolvedPath -Path $AutoHotkeyPath
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ahkPath
        $shortcut.Arguments = New-ShortcutArguments -ScriptPath $mainPath
        $shortcut.WorkingDirectory = $root
        $shortcut.Description = 'Local Automation Hub'
        $shortcut.Save()
        Write-Host "Installed: $shortcutPath"
        Write-Host "Target: $ahkPath"
        break
    }

    'Remove' {
        if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Host "Removed: $shortcutPath"
        } else {
            Write-Host "Not installed: $shortcutPath"
        }
        break
    }
}
