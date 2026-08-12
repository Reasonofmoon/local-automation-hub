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
        this.inputAdapter.EnsureSafeTarget()
        body := NormalizeSnippet(id, this.snippets[id])["body"]
        if !InStr(body, "`n") {
            this.inputAdapter.SendText(body)
            return true
        }

        savedClipboard := this.inputAdapter.CaptureClipboard()
        try {
            this.inputAdapter.SetClipboardText(body)
            this.inputAdapter.Paste()
        } finally {
            this.inputAdapter.RestoreClipboard(savedClipboard)
            savedClipboard := ""
        }
        return true
    }
}

class Win32InputAdapter {
    EnsureSafeTarget() {
        focusedControl := ControlGetFocus("A")
        if (focusedControl = "")
            throw Error("Snippet insertion requires a focused control")
        controlClass := ControlGetClassNN(focusedControl, "A")
        controlStyle := ControlGetStyle(focusedControl, "A")
        if IsPasswordControl(controlClass, controlStyle)
            throw Error("Snippet insertion is blocked for password controls")

        targetProcessId := WinGetPID("A")
        if IsProcessElevated(targetProcessId) && !IsProcessElevated(DllCall("GetCurrentProcessId", "UInt"))
            throw Error("Snippet insertion is blocked for elevated targets")
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

    Paste() {
        Send("^v")
    }

    RestoreClipboard(savedClipboard) {
        A_Clipboard := savedClipboard
    }

    SendText(text) {
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
