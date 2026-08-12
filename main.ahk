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
#Include src\system\ExplorerSelection.ahk
#Include src\modules\FileOrganizer.ahk

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
    fileOrganizer := FileOrganizer(A_ScriptDir "\var\state\file-undo.ini")
    RegisterFileOrganizerCommands(registry, fileOrganizer)
    return registry
}

RegisterFileOrganizerCommands(registry, organizer) {
    registry.Register(
        "files.organize-selected",
        "Files: Organize selected Explorer files",
        ["files", "organize", "explorer", "move"],
        "high",
        ApplySelectedExplorerFiles.Bind(organizer)
    )
    registry.Register(
        "files.undo-last-organize",
        "Files: Undo last organize",
        ["files", "undo", "organize"],
        "high",
        UndoLastOrganizedFiles.Bind(organizer)
    )
}

ApplySelectedExplorerFiles(organizer, *) {
    paths := ExplorerSelection().GetRegularFiles()
    plan := organizer.BuildPlan(paths, FormatTime(A_Now, "yyyy-MM-dd"))
    return organizer.ApplyPlan(plan, ConfirmFileOrganizerPreview)
}

UndoLastOrganizedFiles(organizer, *) {
    return organizer.UndoLast(ConfirmFileOrganizerPreview)
}

ConfirmFileOrganizerPreview(preview) {
    return MsgBox(preview, "Local Automation Hub", "YesNo Icon?") = "Yes"
}
