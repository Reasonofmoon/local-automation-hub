#Requires AutoHotkey v2.0
#SingleInstance Force

#Include src\core\AppContext.ahk
#Include src\core\CommandRegistry.ahk
#Include src\core\Config.ahk
#Include src\core\Logger.ahk
#Include src\core\Palette.ahk
#Include src\modules\Snippets.ahk
#Include src\modules\Workspaces.ahk
#Include src\modules\OrcaWorkspace.ahk
#Include src\modules\WindowManager.ahk
#Include src\system\ExplorerSelection.ahk
#Include src\modules\FileOrganizer.ahk

HOTKEY_MANIFEST := [
    Map("hotkey", "CapsLock & Space", "handler", ShowPalette),
    Map("hotkey", "^!Esc", "handler", CancelAutomation)
]

if (!IsSet(MAIN_STARTUP_HEADLESS) || !MAIN_STARTUP_HEADLESS) {
    hub := InitializeHub(A_ScriptDir, true)
    context := hub["context"]
    registry := hub["registry"]
    palette := hub["palette"]
}

ShowPalette(*) {
    global palette
    palette.Show()
}

CancelAutomation(*) {
    global context
    context.Cancel("Emergency stop requested")
}

InitializeHub(rootDir, registerHotkeys := true) {
    rootDir := String(rootDir)
    configPath := FileExist(rootDir "\config\settings.local.ini")
        ? rootDir "\config\settings.local.ini"
        : rootDir "\config\settings.example.ini"
    logger := SafeLogger(rootDir)
    configLoadError := ""
    try {
        config := HubConfig.Load(configPath)
    } catch as caughtError {
        ; Keep startup safe: no configured module is constructed after a load failure.
        config := CreateEmptyConfig()
        configLoadError := SafeLogger.Redact(SafeErrorMessage(caughtError))
    }
    context := AppContext(rootDir, config, logger)
    context.configLoadError := configLoadError
    if (configLoadError != "")
        context.Notify("Configuration load failed; diagnostics-only mode. " configLoadError, "error")
    validationErrors := HubConfig.Validate(config)
    if (validationErrors.Length > 0)
        context.Notify("Configuration validation failed: " validationErrors.Length " issue(s)", "error")
    registry := CommandRegistry()
    RegisterSystemDiagnostics(registry, context)
    inputAdapter := Win32InputAdapter()
    if (configLoadError = "") {
        RegisterBuiltInCommands(registry, context)
        snippets := SnippetService(config["Snippets"], inputAdapter, context)
        RegisterSnippetCommands(registry, snippets)
    }
    aiWorkspaceLauncher := OrcaWorkspaceService(
        Win32OrcaFolderPicker(),
        Win32OrcaProcessAdapter(),
        Win32OrcaWorkspacePresenter(),
        rootDir "\scripts\Open-OrcaAiWorkspace.ps1",
        context
    )
    RegisterOrcaWorkspaceCommand(registry, aiWorkspaceLauncher)
    palette := CommandPalette(registry, context, inputAdapter)

    if registerHotkeys
        RegisterManifestHotkeys()
    return Map("context", context, "registry", registry, "palette", palette, "inputAdapter", inputAdapter, "snippets", IsSet(snippets) ? snippets : "")
}

RegisterBuiltInCommands(registry, context) {
    workspaceRunnerService := WorkspaceService(Win32WorkspaceRunner(), context.config["Workspace"])
    activeWindowManager := WindowManager(Win32WindowAdapter())
    RegisterWorkspaceCommands(registry, workspaceRunnerService)
    RegisterWindowCommands(registry, activeWindowManager)
    organizerService := FileOrganizer(A_ScriptDir "\var\state\file-undo.ini")
    RegisterFileOrganizerCommands(registry, organizerService)
    return registry
}

CreateEmptyConfig() {
    return Map(
        "General", Map(),
        "KakaoAccounts", Map(),
        "Snippets", Map(),
        "Workspace", Map()
    )
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

RegisterSystemDiagnostics(registry, context, presenter := unset) {
    if !IsSet(presenter)
        presenter := PresentDiagnosticsReport
    if !IsObject(presenter) || !HasMethod(presenter, "Call")
        throw TypeError("Diagnostics presenter must be callable")
    registry.Register(
        "system.diagnostics",
        "System: Diagnostics",
        ["system", "diagnostics", "status", "health"],
        "low",
        InvokeSystemDiagnostics.Bind(registry, presenter)
    )
}

InvokeSystemDiagnostics(registry, presenter, context, *) {
    return RunSystemDiagnostics(registry, context, presenter)
}

RunSystemDiagnostics(registry, context, presenter := unset, *) {
    if !IsSet(presenter)
        presenter := PresentDiagnosticsReport
    report := BuildSystemDiagnosticsReport(registry, context)
    context.Notify(report, "info")
    presenter.Call(report)
    return Map("success", true, "id", "system.diagnostics", "report", report)
}

PresentDiagnosticsReport(report) {
    MsgBox(String(report), "Local Automation Hub Diagnostics")
    return true
}

BuildSystemDiagnosticsReport(registry, context) {
    lines := [
        "Local Automation Hub diagnostics",
        "Repository: " context.rootDir,
        ""
    ]

    if (context.configLoadError != "") {
        lines.Push("Configuration load: failed (diagnostics-only mode)")
        lines.Push("  - " context.configLoadError)
    } else {
        lines.Push("Configuration load: succeeded")
    }

    configErrors := HubConfig.Validate(context.config)
    lines.Push("Configuration errors: " (configErrors.Length = 0 ? "none" : configErrors.Length))
    for _, configError in configErrors
        lines.Push("  - " configError)

    missingExecutables := FindConfiguredMissingExecutables(context.config)
    lines.Push("Missing executables: " (missingExecutables.Length = 0 ? "none" : missingExecutables.Length))
    for _, missing in missingExecutables
        lines.Push("  - " missing)

    duplicateIds := FindDuplicateCommandIds(registry)
    lines.Push("Duplicate command IDs: " (duplicateIds.Length = 0 ? "none (CommandRegistry prevents duplicates at registration)" : duplicateIds.Length))
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
        candidate := directory "\" path
        if IsRegularFile(candidate)
            return true
        if !RegExMatch(path, "i)\.[^\\/]+$") {
            pathext := EnvGet("PATHEXT")
            if (pathext = "")
                pathext := ".COM;.EXE;.BAT;.CMD"
            for _, extension in StrSplit(pathext, ";") {
                extension := Trim(extension, " `t")
                if (extension = "")
                    continue
                if (SubStr(extension, 1, 1) != ".")
                    extension := "." extension
                if IsRegularFile(candidate extension)
                    return true
            }
        }
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
    global HOTKEY_MANIFEST
    seen := Map()
    duplicates := []
    for _, entry in HOTKEY_MANIFEST {
        hotkey := String(entry["hotkey"])
        if seen.Has(hotkey)
            duplicates.Push(hotkey)
        else
            seen[hotkey] := true
    }
    return duplicates
}

RegisterManifestHotkeys() {
    global HOTKEY_MANIFEST
    duplicates := FindDuplicateHotkeys()
    if (duplicates.Length > 0)
        throw Error("Duplicate hotkeys in HOTKEY_MANIFEST: " JoinLines(duplicates))
    for _, entry in HOTKEY_MANIFEST
        Hotkey(entry["hotkey"], entry["handler"])
}

GetDirectoryDiagnostic(path) {
    path := String(path)
    if !DirExist(path)
        return "missing (created on first use; no write probe performed)"
    try {
        attributes := FileGetAttrib(path)
        if InStr(attributes, "R")
            return "unwritable (read-only attribute)"
        probePath := path "\.local-automation-hub-write-probe-" A_TickCount "-" Random(100000, 999999) ".tmp"
        try {
            handle := FileOpen(probePath, "w")
            if !IsObject(handle)
                return "unwritable (write probe failed)"
            handle.Close()
            if (FileGetSize(probePath) != 0)
                return "unwritable (write probe was not zero-byte)"
            return "writable (zero-byte probe passed)"
        } finally {
            try FileDelete(probePath)
        }
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
