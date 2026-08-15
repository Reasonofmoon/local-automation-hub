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
        primaryError := ""
        cleanupError := ""
        try {
            try {
                body := NormalizeSnippet(id, this.snippets[id])["body"]
                if !InStr(body, "`n") {
                    this.inputAdapter.SendText(targetSnapshot, body)
                } else {
                    savedClipboard := this.inputAdapter.CaptureClipboard()
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
                    } catch as caughtError {
                        if !IsObject(primaryError)
                            primaryError := caughtError
                    }
                }
            } catch as caughtError {
                if !IsObject(primaryError)
                    primaryError := caughtError
            }
        } finally {
            try {
                if HasMethod(this.inputAdapter, "CompleteTarget")
                    this.inputAdapter.CompleteTarget(targetSnapshot)
                else if HasMethod(this.inputAdapter, "ReleaseTargetWatcher")
                    this.inputAdapter.ReleaseTargetWatcher(targetSnapshot)
            } catch as targetCleanupError {
                if !IsObject(cleanupError)
                    cleanupError := targetCleanupError
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
    __New(postPasteDelayMs := 150, watcherApi := unset, targetBoundary := unset) {
        this.capturedTarget := ""
        this.postPasteDelayMs := Max(0, Integer(postPasteDelayMs))
        if IsSet(watcherApi)
            this.destroyWatcher := SnippetTargetWatcher(watcherApi)
        else
            this.destroyWatcher := SnippetTargetWatcher()
        this.targetBoundary := IsSet(targetBoundary) ? targetBoundary : Win32InputBoundary()
        this.lastCleanupError := ""
    }

    CaptureBeforePalette() {
        try this.ReleaseCapturedTarget()
        catch as cleanupError {
            throw cleanupError
        }
        windowHandle := this.targetBoundary.ActiveWindow()
        if !windowHandle
            throw Error("Snippet insertion requires an active target before opening the palette")

        processId := this.targetBoundary.ProcessId(windowHandle)
        if !processId
            throw Error("Snippet insertion target process is unavailable")

        watchGeneration := this.destroyWatcher.Replace(windowHandle, processId)
        try {
            controlHandle := this.GetFocusedControlHandle(windowHandle)
            this.destroyWatcher.SetControlHandle(watchGeneration, controlHandle)
            currentMetadata := this.ReadCurrentControlMetadata(windowHandle, controlHandle)
            this.capturedTarget := Map(
                "windowHandle", windowHandle,
                "processId", processId,
                "controlHandle", controlHandle,
                "controlClass", currentMetadata["controlClass"],
                "controlStyle", currentMetadata["controlStyle"],
                "isStandardControl", IsStandardTextControl(currentMetadata["controlClass"]),
                "watchGeneration", watchGeneration
            )
            this.ValidateTargetSnapshot(this.capturedTarget, true)
            return this.capturedTarget
        } catch as caughtError {
            try this.ReleaseTargetWatcher(Map("watchGeneration", watchGeneration))
            catch as cleanupError {
                this.lastCleanupError := cleanupError
            }
            throw caughtError
        }
    }

    EnsureSafeTarget() {
        if !IsObject(this.capturedTarget)
            throw Error("Snippet insertion requires a captured pre-palette target")

        targetSnapshot := this.capturedTarget
        this.capturedTarget := ""
        try {
            this.RequireTargetWatcher(targetSnapshot)
            windowHandle := targetSnapshot["windowHandle"]
            if !this.targetBoundary.WindowExists(windowHandle)
                throw Error("Snippet insertion target no longer exists")
            if this.targetBoundary.ProcessId(windowHandle) != targetSnapshot["processId"]
                throw Error("Snippet insertion target process changed")

            targetProcessId := targetSnapshot["processId"]
            if this.targetBoundary.TargetProcessIsElevated(targetProcessId)
                && !this.targetBoundary.CurrentProcessIsElevated()
                throw Error("Snippet insertion is blocked for elevated targets")

            this.ValidateTargetSnapshot(targetSnapshot, true)

            this.targetBoundary.Activate(windowHandle)
            if !this.targetBoundary.WaitActive(windowHandle, 1)
                throw Error("Snippet insertion target could not be activated")

            if targetSnapshot["isStandardControl"]
                this.targetBoundary.Focus(targetSnapshot["controlHandle"], windowHandle)
            this.ValidateFocusedTarget(targetSnapshot)
            this.ValidateLiveTarget(targetSnapshot)
            return targetSnapshot
        } catch as caughtError {
            try this.ReleaseTargetWatcher(targetSnapshot)
            catch as cleanupError {
                this.lastCleanupError := cleanupError
            }
            throw caughtError
        }
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot)
            throw Error("Snippet insertion target snapshot is invalid")
        for key in ["windowHandle", "processId", "controlHandle", "controlClass", "controlStyle", "isStandardControl", "watchGeneration"] {
            if !targetSnapshot.Has(key)
                throw Error("Snippet insertion target snapshot is invalid")
        }
        this.RequireTargetWatcher(targetSnapshot)
        windowHandle := targetSnapshot["windowHandle"]
        if !this.targetBoundary.WindowExists(windowHandle)
            throw Error("Snippet insertion target no longer exists")
        if this.targetBoundary.ProcessId(windowHandle) != targetSnapshot["processId"]
            throw Error("Snippet insertion target process changed")
        if this.targetBoundary.ActiveWindow() != windowHandle
            throw Error("Snippet insertion is blocked because focus changed before input")

        targetProcessId := targetSnapshot["processId"]
        if this.targetBoundary.TargetProcessIsElevated(targetProcessId)
            && !this.targetBoundary.CurrentProcessIsElevated()
            throw Error("Snippet insertion is blocked for elevated targets")

        this.ValidateTargetSnapshot(targetSnapshot, true)
        this.ValidateFocusedTarget(targetSnapshot)
        this.ValidateLiveTarget(targetSnapshot)
        return true
    }

    ReadCurrentControlMetadata(windowHandle, controlHandle) {
        if !controlHandle
            throw Error("Snippet insertion target control handle is unavailable")
        if !this.targetBoundary.IsDescendantOfWindow(controlHandle, windowHandle)
            throw Error("Snippet insertion target control is outside the captured window")
        controlClass := this.targetBoundary.GetWindowClassName(controlHandle)
        controlStyle := this.targetBoundary.GetWindowStyle(controlHandle)
        return Map("controlClass", controlClass, "controlStyle", controlStyle, "styleAvailable", true)
    }

    GetFocusedControlHandle(windowHandle) {
        controlHandle := this.targetBoundary.GetFocusedControlHandle(windowHandle)
        if !controlHandle
            throw Error("Snippet insertion requires an exact focused control HWND")
        if !this.targetBoundary.IsDescendantOfWindow(controlHandle, windowHandle)
            throw Error("Snippet insertion focused control is outside the captured window")
        return controlHandle
    }

    ValidateFocusedTarget(targetSnapshot) {
        currentControlHandle := this.GetFocusedControlHandle(targetSnapshot["windowHandle"])
        if currentControlHandle != targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because focus changed before input")
        return true
    }

    ValidateLiveTarget(targetSnapshot) {
        currentMetadata := this.ReadCurrentControlMetadata(
            targetSnapshot["windowHandle"],
            targetSnapshot["controlHandle"]
        )
        ValidateCurrentControlMetadata(
            targetSnapshot,
            currentMetadata["controlClass"],
            currentMetadata["controlStyle"],
            currentMetadata["styleAvailable"]
        )
        return true
    }

    RequireTargetWatcher(targetSnapshot) {
        if !IsObject(this.destroyWatcher)
            throw Error("Snippet insertion destroy watcher is unavailable")
        if !targetSnapshot.Has("watchGeneration")
            throw Error("Snippet insertion target watcher identity is unavailable")
        if this.destroyWatcher.IsInvalidated(targetSnapshot["watchGeneration"])
            throw Error("Snippet insertion target was destroyed or recreated")
        return true
    }

    ReleaseTargetWatcher(targetSnapshot) {
        if IsObject(this.destroyWatcher) && IsObject(targetSnapshot) && targetSnapshot.Has("watchGeneration") {
            if !this.destroyWatcher.Release(targetSnapshot["watchGeneration"])
                throw Error("Snippet insertion destroy watcher cleanup failed")
        }
        return true
    }

    CompleteTarget(targetSnapshot) {
        return this.ReleaseTargetWatcher(targetSnapshot)
    }

    ReleaseCapturedTarget() {
        targetSnapshot := this.capturedTarget
        if IsObject(this.destroyWatcher) {
            cleanupSucceeded := IsObject(targetSnapshot) && targetSnapshot.Has("watchGeneration")
                ? this.destroyWatcher.Release(targetSnapshot["watchGeneration"])
                : this.destroyWatcher.Release()
            if !cleanupSucceeded
                throw Error("Snippet insertion destroy watcher cleanup failed")
        }
        this.capturedTarget := ""
        return true
    }

    GetWindowClassName(controlHandle) {
        classBuffer := Buffer(512, 0)
        characterCount := DllCall("GetClassNameW", "Ptr", controlHandle, "Ptr", classBuffer, "Int", 256, "Int")
        if !characterCount
            throw Error("Snippet insertion target live control class is unavailable")
        controlClass := StrGet(classBuffer, characterCount, "UTF-16")
        if Trim(controlClass) = ""
            throw Error("Snippet insertion target live control class is unavailable")
        return controlClass
    }

    GetWindowStyle(controlHandle) {
        DllCall("SetLastError", "UInt", 0)
        style := DllCall(
            A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW",
            "Ptr", controlHandle,
            "Int", -16,
            "Ptr"
        )
        if (style = 0 && A_LastError != 0)
            throw Error("Snippet insertion target live control style is unavailable")
        return Integer(style)
    }

    IsDescendantOfWindow(controlHandle, windowHandle) {
        return this.targetBoundary.IsDescendantOfWindow(controlHandle, windowHandle)
    }

    ValidateTargetSnapshot(targetSnapshot, allowCustomControl := false) {
        if !IsObject(targetSnapshot)
            throw Error("Snippet insertion target snapshot is invalid")
        if !targetSnapshot.Has("controlHandle") || !targetSnapshot.Has("controlClass") || !targetSnapshot.Has("controlStyle")
            throw Error("Snippet insertion target snapshot is invalid")
        controlClass := targetSnapshot["controlClass"]
        controlStyle := targetSnapshot["controlStyle"]
        if !targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because the focused control handle is unavailable")
        if Trim(String(controlClass)) = ""
            throw Error("Snippet insertion is blocked because the focused control class is unavailable")
        if IsPasswordControl(controlClass, controlStyle)
            throw Error("Snippet insertion is blocked for password controls")
        if allowCustomControl && !IsStandardTextControl(controlClass)
            return true
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
        this.targetBoundary.PasteToTarget()
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
        this.targetBoundary.SendTextToTarget(String(text))
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

    if !styleAvailable
        throw Error("Snippet insertion is blocked because live target metadata is unavailable")
    if Trim(String(currentControlClass)) = ""
        throw Error("Snippet insertion is blocked because live target metadata is unavailable")
    if RegExMatch(String(currentControlClass), "i)(password|credential)")
        throw Error("Snippet insertion is blocked for password controls")
    if IsPasswordControl(currentControlClass, currentControlStyle)
        throw Error("Snippet insertion is blocked for password controls")
    if !targetSnapshot["isStandardControl"]
        return true
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

GetGUIThreadFocusHandle(windowHandle) {
    processId := 0
    threadId := DllCall("GetWindowThreadProcessId", "Ptr", windowHandle, "UInt*", &processId, "UInt")
    if !threadId
        throw Error("Snippet insertion target GUI thread is unavailable")
    structureSize := A_PtrSize = 8 ? 72 : 48
    guiThreadInfo := Buffer(structureSize, 0)
    NumPut("UInt", structureSize, guiThreadInfo, 0)
    if !DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", guiThreadInfo.Ptr)
        throw Error("Snippet insertion target focused HWND is unavailable")
    return NumGet(guiThreadInfo, 8 + A_PtrSize, "Ptr")
}

class SnippetTargetWatcher {
    __New(watchApi := unset, expiryMs := 30000) {
        if IsSet(watchApi)
            this.watchApi := watchApi
        else
            this.watchApi := Win32WinEventApi()
        this.registration := ""
        this.generation := 0
        this.expiryMs := Max(0, Integer(expiryMs))
        this.expiryCallback := ""
        this.lastCleanupError := ""
    }

    __Delete() {
        this.Release()
    }

    Replace(windowHandle, processId, controlHandle := 0) {
        if !this.Release()
            throw Error("Snippet insertion destroy watcher cleanup failed")
        this.generation += 1
        generation := this.generation
        callback := ObjBindMethod(this, "OnWinEvent", generation)
        registration := this.watchApi.Install(windowHandle, processId, controlHandle, callback)
        if !IsObject(registration)
            throw Error("Snippet insertion destroy watcher could not be installed")
        registration["generation"] := generation
        registration["windowHandle"] := windowHandle
        registration["processId"] := processId
        registration["controlHandle"] := controlHandle
        registration["invalidated"] := false
        this.registration := registration
        if this.expiryMs > 0 {
            this.expiryCallback := ObjBindMethod(this, "Expire", generation)
            SetTimer(this.expiryCallback, -this.expiryMs)
        }
        return generation
    }

    SetControlHandle(generation, controlHandle) {
        if !IsObject(this.registration) || this.registration["generation"] != generation
            throw Error("Snippet insertion destroy watcher identity is unavailable")
        this.registration["controlHandle"] := controlHandle
        return true
    }

    IsInvalidated(generation) {
        if !IsObject(this.registration) || this.registration["generation"] != generation
            throw Error("Snippet insertion destroy watcher identity is unavailable")
        return this.registration["invalidated"]
    }

    Release(generation := 0) {
        if !IsObject(this.registration)
            return true
        if generation && this.registration["generation"] != generation
            return true
        registration := this.registration
        this.lastCleanupError := ""
        try {
            uninstallResult := this.watchApi.Uninstall(registration)
            if (uninstallResult != true)
                throw Error("Snippet insertion destroy watcher cleanup failed")
        } catch as cleanupError {
            this.lastCleanupError := cleanupError
            return false
        }
        this.registration := ""
        if IsObject(this.expiryCallback) {
            try SetTimer(this.expiryCallback, 0)
            this.expiryCallback := ""
        }
        return true
    }

    Expire(generation) {
        if IsObject(this.registration) && this.registration["generation"] = generation {
            this.registration["invalidated"] := true
            this.Release(generation)
        }
    }

    OnWinEvent(generation, hookHandle, event, windowHandle, objectId, childId, eventThreadId, eventTime) {
        if !IsObject(this.registration) || this.registration["generation"] != generation
            return
        if (event != 0x8001 || hookHandle != this.registration["hook"] || objectId != 0 || childId != 0)
            return
        if (windowHandle = this.registration["windowHandle"]
            || (this.registration["controlHandle"] && windowHandle = this.registration["controlHandle"]))
            this.registration["invalidated"] := true
    }
}

class Win32WinEventApi {
    Install(windowHandle, processId, controlHandle, callback) {
        callbackPointer := CallbackCreate(callback, "Fast")
        try {
            hookHandle := DllCall(
                "SetWinEventHook",
                "UInt", 0x8001,
                "UInt", 0x8001,
                "Ptr", 0,
                "Ptr", callbackPointer,
                "UInt", processId,
                "UInt", 0,
                "UInt", 0,
                "Ptr"
            )
            if !hookHandle
                throw Error("Snippet insertion destroy watcher could not be installed")
            return Map(
                "hook", hookHandle,
                "callback", callbackPointer,
                "windowHandle", windowHandle,
                "processId", processId,
                "controlHandle", controlHandle,
                "hookUninstalled", false,
                "callbackReleased", false
            )
        } catch {
            CallbackFree(callbackPointer)
            throw
        }
    }

    Uninstall(registration) {
        if !IsObject(registration)
            throw Error("Snippet insertion destroy watcher registration is invalid")
        if !registration.Has("hookUninstalled")
            registration["hookUninstalled"] := false
        if !registration.Has("callbackReleased")
            registration["callbackReleased"] := false

        if !registration["hookUninstalled"] {
            hookHandle := registration["hook"]
            if hookHandle {
                if !DllCall("UnhookWinEvent", "Ptr", hookHandle)
                    throw Error("Snippet insertion destroy watcher cleanup failed")
                registration["hook"] := 0
            }
            registration["hookUninstalled"] := true
        }

        if !registration["callbackReleased"] {
            callbackPointer := registration["callback"]
            if callbackPointer
                CallbackFree(callbackPointer)
            registration["callback"] := 0
            registration["callbackReleased"] := true
        }
        return true
    }
}

class Win32InputBoundary {
    ActiveWindow() {
        return WinExist("A")
    }

    WindowExists(windowHandle) {
        return WinExist("ahk_id " windowHandle) != 0
    }

    ProcessId(windowHandle) {
        return WinGetPID("ahk_id " windowHandle)
    }

    GetFocusedControlHandle(windowHandle) {
        focusedControl := ""
        try focusedControl := ControlGetFocus("ahk_id " windowHandle)
        controlHandle := 0
        if (focusedControl != "")
            try controlHandle := ControlGetHwnd(focusedControl, "ahk_id " windowHandle)
        if !controlHandle
            controlHandle := GetGUIThreadFocusHandle(windowHandle)
        return controlHandle
    }

    IsDescendantOfWindow(controlHandle, windowHandle) {
        rootWindow := DllCall("GetAncestor", "Ptr", controlHandle, "UInt", 2, "Ptr")
        return rootWindow = windowHandle
    }

    GetWindowClassName(controlHandle) {
        classBuffer := Buffer(512, 0)
        characterCount := DllCall("GetClassNameW", "Ptr", controlHandle, "Ptr", classBuffer, "Int", 256, "Int")
        if !characterCount
            throw Error("Snippet insertion target live control class is unavailable")
        controlClass := StrGet(classBuffer, characterCount, "UTF-16")
        if Trim(controlClass) = ""
            throw Error("Snippet insertion target live control class is unavailable")
        return controlClass
    }

    GetWindowStyle(controlHandle) {
        DllCall("SetLastError", "UInt", 0)
        style := DllCall(
            A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW",
            "Ptr", controlHandle,
            "Int", -16,
            "Ptr"
        )
        if (style = 0 && A_LastError != 0)
            throw Error("Snippet insertion target live control style is unavailable")
        return Integer(style)
    }

    Activate(windowHandle) {
        return WinActivate("ahk_id " windowHandle)
    }

    WaitActive(windowHandle, timeoutSeconds := 1) {
        return WinWaitActive("ahk_id " windowHandle, , timeoutSeconds)
    }

    Focus(controlHandle, windowHandle) {
        return ControlFocus(controlHandle, "ahk_id " windowHandle)
    }

    TargetProcessIsElevated(processId) {
        return IsProcessElevated(processId)
    }

    CurrentProcessIsElevated() {
        return IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
    }

    SendTextToTarget(text) {
        return SendText(String(text))
    }

    PasteToTarget() {
        return Send("^v")
    }
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
