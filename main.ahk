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
    RegisterSystemDiagnostics(registry, context)
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

RegisterSystemDiagnostics(registry, context) {
    registry.Register(
        "system.diagnostics",
        "System: Diagnostics",
        ["system", "diagnostics", "status", "health"],
        "low",
        RunSystemDiagnostics.Bind(registry)
    )
}

RunSystemDiagnostics(registry, context, *) {
    report := BuildSystemDiagnosticsReport(registry, context)
    context.Notify(report, "info")
    return Map("success", true, "id", "system.diagnostics", "report", report)
}

BuildSystemDiagnosticsReport(registry, context) {
    lines := [
        "Local Automation Hub diagnostics",
        "Repository: " context.rootDir,
        ""
    ]

    configErrors := HubConfig.Validate(context.config)
    lines.Push("Configuration errors: " (configErrors.Length = 0 ? "none" : configErrors.Length))
    for _, configError in configErrors
        lines.Push("  - " configError)

    missingExecutables := FindConfiguredMissingExecutables(context.config)
    lines.Push("Missing executables: " (missingExecutables.Length = 0 ? "none" : missingExecutables.Length))
    for _, missing in missingExecutables
        lines.Push("  - " missing)

    duplicateIds := FindDuplicateCommandIds(registry)
    lines.Push("Duplicate command IDs: " (duplicateIds.Length = 0 ? "none (registry enforces unique IDs)" : duplicateIds.Length))
    for _, duplicateId in duplicateIds
        lines.Push("  - " duplicateId)

    duplicateHotkeys := FindDuplicateHotkeys()
    lines.Push("Duplicate hotkeys: " (duplicateHotkeys.Length = 0 ? "none" : duplicateHotkeys.Length))
    for _, duplicateHotkey in duplicateHotkeys
        lines.Push("  - " duplicateHotkey)

    for _, directoryName in ["var\logs", "var\state"] {
        directoryPath := context.rootDir "\" directoryName
        lines.Push(directoryName " directory: " GetDirectoryDiagnostic(directoryPath))
    }

    lines.Push("Credential targets (names only):")
    targets := GetCredentialTargetNames(context.config)
    if (targets.Length = 0)
        lines.Push("  - none configured")
    else
        for _, target in targets
            lines.Push("  - " target)

    lines.Push("Kakao login automation: unsupported/currently absent")
    lines.Push("Capability evidence: docs/harness/runs/2026-08-12-local-automation-hub/kakao-ui-capability.md")
    return JoinLines(lines)
}

FindConfiguredMissingExecutables(config) {
    missing := []
    if IsObject(config) && config.Has("General") && IsObject(config["General"]) && config["General"].Has("KakaoPath") {
        kakaoPath := String(config["General"]["KakaoPath"])
        if !IsExecutableAvailable(kakaoPath)
            missing.Push("General.KakaoPath: " kakaoPath)
    }
    if !IsObject(config) || !config.Has("Workspace") || !IsObject(config["Workspace"])
        return missing
    for modeId, mode in config["Workspace"] {
        if !IsObject(mode) || !mode.Has("Items") || !(mode["Items"] is Array)
            continue
        for _, rawItem in mode["Items"] {
            try item := ParseWorkspaceItem(rawItem)
            catch
                continue
            if (item["kind"] = "app" && !IsExecutableAvailable(item["value"]))
                missing.Push("Workspace." modeId ": " item["value"])
        }
    }
    return missing
}

IsExecutableAvailable(path) {
    path := Trim(String(path))
    if (path = "")
        return false
    if IsRegularFile(path)
        return true
    if (InStr(path, "\") || InStr(path, "/") || InStr(path, ":"))
        return false
    for _, directory in StrSplit(EnvGet("PATH"), ";") {
        directory := Trim(directory, " `t")
        if (directory = "")
            continue
        if IsRegularFile(directory "\" path)
            return true
    }
    return false
}

IsRegularFile(path) {
    try {
        if !FileExist(path)
            return false
        return !InStr(FileGetAttrib(path), "D")
    } catch
        return false
}

FindDuplicateCommandIds(registry) {
    seen := Map()
    duplicates := []
    for _, command in registry.All() {
        id := String(command["id"])
        if seen.Has(id)
            duplicates.Push(id)
        else
            seen[id] := true
    }
    return duplicates
}

FindDuplicateHotkeys() {
    configured := ["CapsLock & Space", "^!Esc"]
    seen := Map()
    duplicates := []
    for _, hotkey in configured {
        if seen.Has(hotkey)
            duplicates.Push(hotkey)
        else
            seen[hotkey] := true
    }
    return duplicates
}

GetDirectoryDiagnostic(path) {
    path := String(path)
    if !DirExist(path)
        return "missing (created on first use; no write probe performed)"
    try {
        attributes := FileGetAttrib(path)
        if InStr(attributes, "R")
            return "unwritable (read-only attribute)"
        return "present (write probe not performed)"
    } catch
        return "unwritable or inaccessible"
}

GetCredentialTargetNames(config) {
    targets := []
    if !IsObject(config) || !config.Has("KakaoAccounts") || !IsObject(config["KakaoAccounts"])
        return targets
    for alias, target in config["KakaoAccounts"]
        targets.Push(String(alias) " -> " String(target))
    return targets
}

JoinLines(lines) {
    result := ""
    for index, line in lines
        result .= (index = 1 ? "" : "`n") line
    return result
}
