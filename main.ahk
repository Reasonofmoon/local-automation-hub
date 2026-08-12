#Requires AutoHotkey v2.0
#SingleInstance Force

#Include src\core\AppContext.ahk
#Include src\core\CommandRegistry.ahk
#Include src\core\Config.ahk
#Include src\core\Logger.ahk
#Include src\core\Palette.ahk
#Include src\modules\Snippets.ahk
#Include src\modules\Workspaces.ahk
#Include src\modules\WindowManager.ahk

rootDir := A_ScriptDir
configPath := FileExist(rootDir "\config\settings.local.ini")
    ? rootDir "\config\settings.local.ini"
    : rootDir "\config\settings.example.ini"
config := HubConfig.Load(configPath)
logger := SafeLogger(rootDir)
context := AppContext(rootDir, config, logger)
validationErrors := HubConfig.Validate(config)
if (validationErrors.Length > 0)
    context.Notify("Configuration validation failed: " validationErrors.Length " issue(s)", "error")
registry := CommandRegistry()
RegisterBuiltInCommands(registry, context)
snippets := SnippetService(config["Snippets"], Win32InputAdapter(), context)
RegisterSnippetCommands(registry, snippets)
palette := CommandPalette(registry, context)

CapsLock & Space::ShowPalette()
^!Esc::CancelAutomation()

ShowPalette() {
    global palette
    palette.Show()
}

CancelAutomation() {
    global context
    context.Cancel("Emergency stop requested")
}

RegisterBuiltInCommands(registry, context) {
    workspaceService := WorkspaceService(Win32WorkspaceRunner(), context.config["Workspace"])
    windowService := WindowManager(Win32WindowAdapter())
    RegisterWorkspaceCommands(registry, workspaceService)
    RegisterWindowCommands(registry, windowService)
    return registry
}
