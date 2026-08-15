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
        primaryError := ""
        cleanupError := ""
        try {
            try {
                this.inputAdapter.SetClipboardText(body)
                this.inputAdapter.Paste(targetSnapshot)
            } catch as caughtError {
                primaryError := caughtError
            } finally {
                try this.inputAdapter.WaitForPasteHandoff()
                catch as waitError {
                    cleanupError := waitError
                }
                try this.inputAdapter.RestoreClipboard(savedClipboard)
                catch as restoreError {
                    ; Wait is the first cleanup step, so it wins if both cleanup steps fail.
                    if !IsObject(cleanupError)
                        cleanupError := restoreError
                }
                savedClipboard := ""
            }
        }
        if IsObject(primaryError)
            throw primaryError
        if IsObject(cleanupError)
            throw cleanupError
        return true
    }
}

class Win32InputAdapter {
    __New(postPasteDelayMs := 150) {
        this.capturedTarget := ""
        this.postPasteDelayMs := Max(0, Integer(postPasteDelayMs))
    }

    CaptureBeforePalette() {
        this.capturedTarget := ""
        windowHandle := WinExist("A")
        if !windowHandle
            throw Error("Snippet insertion requires an active target before opening the palette")

        processId := WinGetPID("ahk_id " windowHandle)
        focusedControl := ""
        try focusedControl := ControlGetFocus("ahk_id " windowHandle)
        controlHandle := 0
        controlClass := ""
        controlStyle := 0
        if (focusedControl != "") {
            try controlHandle := ControlGetHwnd(focusedControl, "ahk_id " windowHandle)
            try controlClass := ControlGetClassNN(focusedControl, "ahk_id " windowHandle)
            try controlStyle := ControlGetStyle(focusedControl, "ahk_id " windowHandle)
        }

        this.capturedTarget := Map(
            "windowHandle", windowHandle,
            "processId", processId,
            "controlHandle", controlHandle,
            "controlClass", controlClass,
            "controlStyle", controlStyle,
            "isStandardControl", controlHandle != 0 && IsStandardTextControl(controlClass)
        )
        return this.capturedTarget
    }

    EnsureSafeTarget() {
        if !IsObject(this.capturedTarget)
            throw Error("Snippet insertion requires a captured pre-palette target")

        targetSnapshot := this.capturedTarget
        this.capturedTarget := ""
        windowHandle := targetSnapshot["windowHandle"]
        if !WinExist("ahk_id " windowHandle)
            throw Error("Snippet insertion target no longer exists")
        if WinGetPID("ahk_id " windowHandle) != targetSnapshot["processId"]
            throw Error("Snippet insertion target process changed")

        targetProcessId := targetSnapshot["processId"]
        if IsProcessElevated(targetProcessId) && !IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
            throw Error("Snippet insertion is blocked for elevated targets")

        this.ValidateTargetSnapshot(targetSnapshot, true)

        WinActivate("ahk_id " windowHandle)
        if !WinWaitActive("ahk_id " windowHandle, , 1)
            throw Error("Snippet insertion target could not be activated")

        if targetSnapshot["isStandardControl"] {
            ControlFocus(targetSnapshot["controlHandle"], "ahk_id " windowHandle)
            currentControl := ControlGetFocus("ahk_id " windowHandle)
            currentControlHandle := currentControl = "" ? 0 : ControlGetHwnd(currentControl, "ahk_id " windowHandle)
            if currentControlHandle != targetSnapshot["controlHandle"]
                throw Error("Snippet insertion is blocked because focus changed before input")
        }
        return targetSnapshot
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot)
            throw Error("Snippet insertion target snapshot is invalid")
        for key in ["windowHandle", "processId", "controlHandle", "controlClass", "controlStyle", "isStandardControl"] {
            if !targetSnapshot.Has(key)
                throw Error("Snippet insertion target snapshot is invalid")
        }
        windowHandle := targetSnapshot["windowHandle"]
        if !WinExist("ahk_id " windowHandle)
            throw Error("Snippet insertion target no longer exists")
        if WinGetPID("ahk_id " windowHandle) != targetSnapshot["processId"]
            throw Error("Snippet insertion target process changed")
        if WinExist("A") != windowHandle
            throw Error("Snippet insertion is blocked because focus changed before input")

        targetProcessId := targetSnapshot["processId"]
        if IsProcessElevated(targetProcessId) && !IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
            throw Error("Snippet insertion is blocked for elevated targets")

        this.ValidateTargetSnapshot(targetSnapshot, true)
        if targetSnapshot["controlHandle"] {
            currentMetadata := ""
            try currentMetadata := this.ReadCurrentControlMetadata(windowHandle, targetSnapshot["controlHandle"])
            catch as metadataError {
                if targetSnapshot["isStandardControl"]
                    throw Error("Snippet insertion is blocked because the captured standard control metadata is unavailable")
                return true
            }
            ValidateCurrentControlMetadata(
                targetSnapshot,
                currentMetadata["controlClass"],
                currentMetadata["controlStyle"],
                currentMetadata["styleAvailable"]
            )
        } else {
            ValidateCurrentControlMetadata(
                targetSnapshot,
                targetSnapshot["controlClass"],
                targetSnapshot["controlStyle"]
            )
        }
        if targetSnapshot["isStandardControl"] {
            currentControl := ControlGetFocus("ahk_id " windowHandle)
            currentControlHandle := currentControl = "" ? 0 : ControlGetHwnd(currentControl, "ahk_id " windowHandle)
            if currentControlHandle != targetSnapshot["controlHandle"]
                throw Error("Snippet insertion is blocked because focus changed before input")
        }
        return true
    }

    ReadCurrentControlMetadata(windowHandle, controlHandle) {
        if !controlHandle
            throw Error("Snippet insertion target control handle is unavailable")
        controlTitle := "ahk_id " controlHandle
        windowTitle := "ahk_id " windowHandle
        controlClass := ControlGetClassNN(controlTitle, windowTitle)
        if controlClass = ""
            throw Error("Snippet insertion target control class is unavailable")
        controlStyle := 0
        styleAvailable := true
        try controlStyle := ControlGetStyle(controlTitle, windowTitle)
        catch
            styleAvailable := false
        return Map("controlClass", controlClass, "controlStyle", controlStyle, "styleAvailable", styleAvailable)
    }

    ValidateTargetSnapshot(targetSnapshot, allowCustomControl := false) {
        if !IsObject(targetSnapshot)
            throw Error("Snippet insertion target snapshot is invalid")
        if !targetSnapshot.Has("controlHandle") || !targetSnapshot.Has("controlClass") || !targetSnapshot.Has("controlStyle")
            throw Error("Snippet insertion target snapshot is invalid")
        controlClass := targetSnapshot["controlClass"]
        controlStyle := targetSnapshot["controlStyle"]
        if IsPasswordControl(controlClass, controlStyle)
            throw Error("Snippet insertion is blocked for password controls")
        if allowCustomControl && !IsStandardTextControl(controlClass)
            return true
        if !targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because the focused control handle is unavailable")
        if !IsStandardTextControl(controlClass)
            throw Error("Snippet insertion is blocked because the focused control is not a standard Edit or RichEdit control")
        return true
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

    WaitForPasteHandoff() {
        if this.postPasteDelayMs > 0
            Sleep(this.postPasteDelayMs)
        return true
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

ValidateCurrentControlMetadata(targetSnapshot, currentControlClass, currentControlStyle, styleAvailable := true) {
    if !IsObject(targetSnapshot)
        throw Error("Snippet insertion target snapshot is invalid")
    for key in ["controlClass", "controlStyle", "isStandardControl"] {
        if !targetSnapshot.Has(key)
            throw Error("Snippet insertion target snapshot is invalid")
    }

    if RegExMatch(String(currentControlClass), "i)(password|credential)")
        throw Error("Snippet insertion is blocked for password controls")
    if styleAvailable && IsPasswordControl(currentControlClass, currentControlStyle)
        throw Error("Snippet insertion is blocked for password controls")
    if !targetSnapshot["isStandardControl"]
        return true
    if !styleAvailable
        throw Error("Snippet insertion is blocked because the captured standard control metadata is unavailable")
    if !IsStandardTextControl(currentControlClass)
        throw Error("Snippet insertion is blocked because the current control is not the captured standard control")

    expectedClass := StrLower(String(targetSnapshot["controlClass"]))
    actualClass := StrLower(String(currentControlClass))
    expectedStyle := Integer(targetSnapshot["controlStyle"])
    actualStyle := Integer(currentControlStyle)
    if (expectedClass != actualClass || expectedStyle != actualStyle)
        throw Error("Snippet insertion is blocked because the captured control metadata changed")
    return true
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
