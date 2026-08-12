#Requires AutoHotkey v2.0

class SnippetService {
    __New(snippets, inputAdapter, appContext := unset) {
        if !IsObject(snippets)
            throw TypeError("Snippets must be a map")
        if !IsObject(inputAdapter)
            throw TypeError("Input adapter must be an object")
        this.snippets := snippets
        this.inputAdapter := inputAdapter
        this.appContext := IsSet(appContext) ? appContext : ""
    }

    Search(query) {
        query := StrLower(Trim(String(query)))
        matches := []
        for id, rawSnippet in this.snippets {
            snippet := NormalizeSnippet(id, rawSnippet)
            haystack := StrLower(snippet["id"] " " snippet["title"] " " JoinSnippetTags(snippet["tags"]))
            if (query = "" || InStr(haystack, query))
                matches.Push(snippet)
        }
        return matches
    }

    Insert(id) {
        if IsObject(this.appContext) && this.appContext.IsCancelled()
            throw Error("Snippet insertion cancelled")
        id := String(id)
        if !this.snippets.Has(id)
            throw Error("Unknown snippet: " id)
        targetSnapshot := this.inputAdapter.EnsureSafeTarget()
        body := NormalizeSnippet(id, this.snippets[id])["body"]
        if !InStr(body, "`n") {
            this.inputAdapter.SendText(targetSnapshot, body)
            return true
        }

        savedClipboard := this.inputAdapter.CaptureClipboard()
        try {
            this.inputAdapter.SetClipboardText(body)
            this.inputAdapter.Paste(targetSnapshot)
        } finally {
            this.inputAdapter.RestoreClipboard(savedClipboard)
            savedClipboard := ""
        }
        return true
    }
}

class Win32InputAdapter {
    EnsureSafeTarget() {
        targetSnapshot := this.CaptureTargetSnapshot()
        this.ValidateTargetSnapshot(targetSnapshot)

        targetProcessId := WinGetPID("ahk_id " targetSnapshot["windowHandle"])
        if IsProcessElevated(targetProcessId) && !IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
            throw Error("Snippet insertion is blocked for elevated targets")
        return targetSnapshot
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot)
            throw Error("Snippet insertion target snapshot is invalid")
        currentTarget := this.CaptureTargetSnapshot()
        if !SameSnippetTarget(targetSnapshot, currentTarget)
            throw Error("Snippet insertion is blocked because focus changed before input")
        this.ValidateTargetSnapshot(currentTarget)
        targetProcessId := WinGetPID("ahk_id " currentTarget["windowHandle"])
        if IsProcessElevated(targetProcessId) && !IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
            throw Error("Snippet insertion is blocked for elevated targets")
        return true
    }

    CaptureTargetSnapshot() {
        windowHandle := WinExist("A")
        if !windowHandle
            throw Error("Snippet insertion requires an active window")
        focusedControl := ControlGetFocus("ahk_id " windowHandle)
        if (focusedControl = "")
            throw Error("Snippet insertion requires a focused standard text control; browser and custom controls are blocked")
        controlHandle := ControlGetHwnd(focusedControl, "ahk_id " windowHandle)
        if !controlHandle
            throw Error("Snippet insertion is blocked because the focused control handle is unavailable")
        controlClass := ControlGetClassNN(focusedControl, "ahk_id " windowHandle)
        controlStyle := ControlGetStyle(focusedControl, "ahk_id " windowHandle)
        return Map(
            "windowHandle", windowHandle,
            "controlHandle", controlHandle,
            "controlClass", controlClass,
            "controlStyle", controlStyle
        )
    }

    ValidateTargetSnapshot(targetSnapshot) {
        controlClass := targetSnapshot["controlClass"]
        controlStyle := targetSnapshot["controlStyle"]
        if !IsStandardTextControl(controlClass)
            throw Error("Snippet insertion is blocked because the focused control is not a standard Edit or RichEdit control")
        if IsPasswordControl(controlClass, controlStyle)
            throw Error("Snippet insertion is blocked for password controls")
    }

    CaptureClipboard() {
        return ClipboardAll()
    }

    SetClipboardText(text) {
        A_Clipboard := String(text)
        if !ClipWait(1)
            throw Error("Could not set clipboard for multiline snippet")
    }

    Paste(targetSnapshot) {
        this.ConfirmSafeTarget(targetSnapshot)
        Send("^v")
    }

    RestoreClipboard(savedClipboard) {
        A_Clipboard := savedClipboard
    }

    SendText(targetSnapshot, text) {
        this.ConfirmSafeTarget(targetSnapshot)
        SendText(String(text))
    }
}

RegisterSnippetCommands(registry, service) {
    for snippet in service.Search("") {
        snippetId := snippet["id"]
        registry.Register(
            "snippet." snippetId,
            "Snippet: " snippet["title"],
            snippet["tags"],
            "low",
            InsertSnippet.Bind(service, snippetId)
        )
    }
}

InsertSnippet(service, snippetId, *) {
    return service.Insert(snippetId)
}

NormalizeSnippet(id, rawSnippet) {
    id := String(id)
    if IsObject(rawSnippet) {
        if !rawSnippet.Has("body")
            throw ValueError("Snippet body is required: " id)
        title := rawSnippet.Has("title") ? String(rawSnippet["title"]) : id
        tags := rawSnippet.Has("tags") && IsObject(rawSnippet["tags"]) ? rawSnippet["tags"] : []
        body := String(rawSnippet["body"])
    } else {
        title := id
        tags := ["snippet"]
        body := String(rawSnippet)
    }
    return Map("id", id, "title", title, "tags", tags, "body", DecodeSnippetBody(body))
}

DecodeSnippetBody(value) {
    marker := "__LOCAL_AUTOMATION_HUB_SNIPPET_BACKSLASH__"
    value := StrReplace(String(value), "\\", marker)
    value := StrReplace(value, "\n", "`n")
    return StrReplace(value, marker, "\")
}

JoinSnippetTags(tags) {
    result := ""
    for index, tag in tags
        result .= (index = 1 ? "" : " ") String(tag)
    return result
}

IsPasswordControl(controlClass, controlStyle) {
    if RegExMatch(String(controlClass), "i)(password|credential)")
        return true
    return (Integer(controlStyle) & 0x20) != 0
}

IsStandardTextControl(controlClass) {
    controlClass := String(controlClass)
    return RegExMatch(controlClass, "i)^(Edit|RichEdit\d*[A-Za-z]*)\d*$") != 0
}

SameSnippetTarget(firstTarget, secondTarget) {
    return firstTarget["windowHandle"] = secondTarget["windowHandle"]
        && firstTarget["controlHandle"] = secondTarget["controlHandle"]
        && firstTarget["controlClass"] = secondTarget["controlClass"]
        && firstTarget["controlStyle"] = secondTarget["controlStyle"]
}

IsProcessElevated(processId) {
    processHandle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", processId, "Ptr")
    if !processHandle
        throw OSError("Could not inspect target process elevation")
    tokenHandle := 0
    try {
        if !DllCall("OpenProcessToken", "Ptr", processHandle, "UInt", 0x0008, "Ptr*", &tokenHandle)
            throw OSError("Could not inspect target process token")
        elevation := 0
        returnedLength := 0
        if !DllCall("GetTokenInformation", "Ptr", tokenHandle, "Int", 20, "UInt*", &elevation, "UInt", 4, "UInt*", &returnedLength)
            throw OSError("Could not read target process elevation")
        return elevation != 0
    } finally {
        if tokenHandle
            DllCall("CloseHandle", "Ptr", tokenHandle)
        DllCall("CloseHandle", "Ptr", processHandle)
    }
}
