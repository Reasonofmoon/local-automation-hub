#Requires AutoHotkey v2.0

class WorkspaceService {
    __New(runner, modes := Map()) {
        if !IsObject(runner) || !HasMethod(runner, "ActivateApp") || !HasMethod(runner, "Run")
            throw TypeError("Workspace runner must provide ActivateApp and Run")
        if !IsObject(modes)
            throw TypeError("Workspace modes must be a map")
        this.runner := runner
        this.modes := modes
    }

    RunMode(modeId) {
        modeId := Trim(String(modeId))
        if !this.modes.Has(modeId)
            return this.FailureResult("mode", modeId, "Unknown workspace mode: " modeId)
        mode := this.modes[modeId]
        if !IsObject(mode) || !mode.Has("Items") || !(mode["Items"] is Array)
            return this.FailureResult("mode", modeId, "Workspace mode items are invalid: " modeId)
        return this.RunItems(mode["Items"])
    }

    RunItems(items) {
        result := Map("succeeded", [], "skipped", [], "failed", [])
        if !(items is Array) {
            result["failed"].Push(Map("item", "", "error", "Workspace items must be an array"))
            return result
        }
        for _, rawItem in items {
            try {
                item := ParseWorkspaceItem(rawItem)
                if (item["kind"] = "app" && this.runner.ActivateApp(item["value"])) {
                    result["skipped"].Push(item)
                    continue
                }
                this.runner.Run(item["value"])
                result["succeeded"].Push(item)
            } catch as error {
                result["failed"].Push(Map("item", String(rawItem), "value", WorkspaceItemValue(rawItem), "error", error.Message))
            }
        }
        return result
    }

    FailureResult(kind, value, message) {
        return Map(
            "succeeded", [],
            "skipped", [],
            "failed", [Map("kind", kind, "value", value, "error", message)]
        )
    }
}

class Win32WorkspaceRunner {
    ActivateApp(path) {
        processName := GetWorkspaceProcessName(path)
        windowHandle := WinExist("ahk_exe " processName)
        if !windowHandle
            return false
        WinActivate("ahk_id " windowHandle)
        return true
    }

    Run(value) {
        Run(String(value))
        return true
    }
}

RegisterWorkspaceCommands(registry, service) {
    for modeId, mode in service.modes {
        registry.Register(
            "workspace." modeId,
            "Workspace: " modeId,
            ["workspace", "launch"],
            "medium",
            RunWorkspaceMode.Bind(service, modeId)
        )
    }
}

RunWorkspaceMode(service, modeId, *) {
    return service.RunMode(modeId)
}

ParseWorkspaceItem(rawItem) {
    rawItem := Trim(String(rawItem))
    if !RegExMatch(rawItem, "i)^(app|folder|url)\|([^|]+)$", &match)
        throw ValueError("Workspace item must be app|value, folder|value, or url|value")
    value := Trim(match[2])
    if (value = "")
        throw ValueError("Workspace item value cannot be empty")
    return Map("kind", StrLower(match[1]), "value", value, "item", rawItem)
}

WorkspaceItemValue(rawItem) {
    rawItem := String(rawItem)
    separator := InStr(rawItem, "|")
    return separator ? Trim(SubStr(rawItem, separator + 1)) : ""
}

GetWorkspaceProcessName(path) {
    SplitPath(String(path), &fileName)
    return fileName != "" ? fileName : String(path)
}
