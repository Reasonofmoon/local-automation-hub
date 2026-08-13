#Requires AutoHotkey v2.0
#Include ..\core\Logger.ahk
#Include ..\core\CommandRegistry.ahk

class OrcaWorkspaceService {
    __New(folderPicker, processAdapter, presenter, scriptPath, appContext) {
        if !IsObject(folderPicker) || !HasMethod(folderPicker, "Select")
            throw TypeError("Orca folder picker must provide Select")
        if !IsObject(processAdapter) || !HasMethod(processAdapter, "Open")
            throw TypeError("Orca process adapter must provide Open")
        if !IsObject(presenter) || !HasMethod(presenter, "Show")
            throw TypeError("Orca presenter must provide Show")
        if !IsObject(appContext) || !HasMethod(appContext, "IsCancelled")
            throw TypeError("Orca app context must provide IsCancelled")
        this.folderPicker := folderPicker
        this.processAdapter := processAdapter
        this.presenter := presenter
        this.scriptPath := String(scriptPath)
        this.appContext := appContext
    }

    OpenAiDevelopment() {
        if this.appContext.IsCancelled()
            throw Error("Orca workspace creation cancelled")

        selectedPath := String(this.folderPicker.Select())
        if (selectedPath = "")
            return Map("success", false, "cancelled", true)

        if this.appContext.IsCancelled()
            throw Error("Orca workspace creation cancelled")

        try {
            result := this.processAdapter.Open(this.scriptPath, selectedPath)
            if !IsObject(result)
                throw Error("Orca workspace adapter returned an invalid result")
        } catch as caughtError {
            result := OrcaFailureResult(SafeErrorMessage(caughtError))
        }
        this.presenter.Show(FormatOrcaWorkspaceResult(result))
        return result
    }
}

class Win32OrcaFolderPicker {
    Select() {
        return DirSelect("*" A_MyDocuments, 3, "Select an existing Git checkout")
    }
}

class Win32OrcaWorkspacePresenter {
    Show(message) {
        MsgBox(String(message), "Orca AI Development Workspace")
        return true
    }
}

class Win32OrcaProcessAdapter {
    static GitRootResolutionCallCount := 1
    static OrcaStatusCallCount := 1
    static RepositoryListCallCount := 1
    static RepositoryAddCallCount := 1
    static TerminalListCallCount := 1
    static ExecutableLookupCallCount := 4
    static TerminalCreateCallCount := 4
    static TerminalWaitCallCount := 4
    static MaximumBoundedProcessCallCount := 1 + 1 + 1 + 1 + 1 + 4 + 4 + 4
    static ProcessTimeoutOverheadMs := 5000

    __New(readyTimeoutMs := 60000, powershellPath := "powershell.exe", totalProcessTimeoutMs := unset) {
        this.perAgentReadyTimeoutMs := Max(1, Integer(readyTimeoutMs))
        this.readyTimeoutMs := this.perAgentReadyTimeoutMs
        minimumTotalTimeoutMs := this.perAgentReadyTimeoutMs * Win32OrcaProcessAdapter.MaximumBoundedProcessCallCount
            + Win32OrcaProcessAdapter.ProcessTimeoutOverheadMs
        if IsSet(totalProcessTimeoutMs)
            this.totalProcessTimeoutMs := Max(this.perAgentReadyTimeoutMs, Integer(totalProcessTimeoutMs))
        else
            this.totalProcessTimeoutMs := Max(this.perAgentReadyTimeoutMs, minimumTotalTimeoutMs)
        this.powershellPath := String(powershellPath)
    }

    Open(scriptPath, selectedPath) {
        scriptPath := String(scriptPath)
        selectedPath := String(selectedPath)
        if (scriptPath = "")
            throw Error("Orca workspace adapter script path is empty")
        if (selectedPath = "")
            throw Error("Orca workspace selection is empty")

        arguments := [
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", scriptPath,
            "-SelectedPath", selectedPath,
            "-ReadyTimeoutMs", String(this.perAgentReadyTimeoutMs)
        ]
        processResult := OrcaRunProcess(this.powershellPath, arguments, this.totalProcessTimeoutMs)
        if processResult["timedOut"]
            throw Error("Orca workspace adapter timed out")
        if processResult["exitCode"] != 0 {
            detail := Trim(String(processResult["stderr"]))
            throw Error("Orca workspace adapter exited with code " processResult["exitCode"] (detail = "" ? "" : ": " detail))
        }
        rawResult := Trim(String(processResult["stdout"]))
        if (rawResult = "")
            throw Error("Orca workspace adapter returned no JSON" (Trim(String(processResult["stderr"])) = "" ? "" : ": " Trim(String(processResult["stderr"]))))
        return OrcaJsonParse(rawResult)
    }
}

RegisterOrcaWorkspaceCommand(registry, service) {
    registry.Register(
        "workspace.ai-development",
        "Workspace: Orca AI development",
        ["workspace", "orca", "codex", "claude", "grok", "gemini"],
        "medium",
        RunOrcaAiDevelopment.Bind(service)
    )
    return registry
}

RunOrcaAiDevelopment(service, *) {
    return service.OpenAiDevelopment()
}

OrcaFailureResult(message) {
    return Map(
        "success", false,
        "repositoryRoot", "",
        "created", [],
        "reused", [],
        "skipped", [],
        "failed", [],
        "error", String(message)
    )
}

FormatOrcaWorkspaceResult(result) {
    if !IsObject(result)
        return "Orca AI workspace failed`n`nError: invalid result"
    if result.Has("cancelled") && result["cancelled"]
        return "Orca AI workspace cancelled."

    repositoryRoot := OrcaResultText(result, "repositoryRoot", "")
    lines := ["Orca AI workspace: " (repositoryRoot = "" ? "unresolved" : repositoryRoot), ""]
    lines.Push("Created: " OrcaFormatAgentList(OrcaResultList(result, "created")))
    lines.Push("Reused: " OrcaFormatAgentList(OrcaResultList(result, "reused")))
    lines.Push("Skipped: " OrcaFormatAgentDetails(OrcaResultList(result, "skipped")))
    lines.Push("Failed: " OrcaFormatAgentDetails(OrcaResultList(result, "failed")))

    if result.Has("error") && Trim(String(result["error"])) != ""
        lines.Push("Error: " SafeLogger.Redact(String(result["error"])))
    return OrcaJoinLines(lines)
}

OrcaResultText(result, key, fallback := "") {
    if !IsObject(result) || !result.Has(key)
        return String(fallback)
    return String(result[key])
}

OrcaResultList(result, key) {
    if !IsObject(result) || !result.Has(key) || !(result[key] is Array)
        return []
    return result[key]
}

OrcaFormatAgentList(items) {
    names := []
    for _, item in items {
        if IsObject(item)
            names.Push(OrcaResultText(item, "agent", OrcaResultText(item, "title", "unknown")))
        else
            names.Push(String(item))
    }
    return names.Length = 0 ? "none" : OrcaJoinComma(names)
}

OrcaFormatAgentDetails(items) {
    details := []
    for _, item in items {
        if IsObject(item) {
            name := OrcaResultText(item, "agent", OrcaResultText(item, "title", "unknown"))
            reason := OrcaResultText(item, "reason", OrcaResultText(item, "error", "unspecified"))
            details.Push(name " (" SafeLogger.Redact(reason) ")")
        } else {
            details.Push(String(item))
        }
    }
    return details.Length = 0 ? "none" : OrcaJoinComma(details)
}

OrcaJoinComma(items) {
    result := ""
    for index, item in items
        result .= (index = 1 ? "" : ", ") String(item)
    return result
}

OrcaJoinLines(lines) {
    result := ""
    for index, line in lines
        result .= (index = 1 ? "" : "`n") String(line)
    return result
}

OrcaRunProcess(applicationPath, arguments, timeoutMs) {
    stdoutRead := 0
    stdoutWrite := 0
    stderrRead := 0
    stderrWrite := 0
    processHandle := 0
    threadHandle := 0
    jobHandle := 0
    try {
        securityAttributes := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
        NumPut("UInt", securityAttributes.Size, securityAttributes, 0)
        NumPut("Ptr", 0, securityAttributes, A_PtrSize)
        NumPut("Int", 1, securityAttributes, A_PtrSize * 2)
        if !DllCall("Kernel32.dll\CreatePipe", "PtrP", &stdoutRead, "PtrP", &stdoutWrite, "Ptr", securityAttributes.Ptr, "UInt", 0)
            throw Error("Orca workspace adapter could not create stdout pipe")
        if !DllCall("Kernel32.dll\SetHandleInformation", "Ptr", stdoutRead, "UInt", 1, "UInt", 0)
            throw Error("Orca workspace adapter could not configure stdout pipe")
        if !DllCall("Kernel32.dll\CreatePipe", "PtrP", &stderrRead, "PtrP", &stderrWrite, "Ptr", securityAttributes.Ptr, "UInt", 0)
            throw Error("Orca workspace adapter could not create stderr pipe")
        if !DllCall("Kernel32.dll\SetHandleInformation", "Ptr", stderrRead, "UInt", 1, "UInt", 0)
            throw Error("Orca workspace adapter could not configure stderr pipe")

        commandLine := OrcaJoinArguments([applicationPath, arguments*])
        commandBuffer := Buffer((StrLen(commandLine) + 1) * 2, 0)
        StrPut(commandLine, commandBuffer, "UTF-16")
        startupInfo := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
        NumPut("UInt", startupInfo.Size, startupInfo, 0)
        NumPut("UInt", 0x100, startupInfo, 60)
        stdinOffset := A_PtrSize = 8 ? 80 : 56
        stdoutOffset := A_PtrSize = 8 ? 88 : 60
        stderrOffset := A_PtrSize = 8 ? 96 : 64
        NumPut("Ptr", DllCall("Kernel32.dll\GetStdHandle", "Int", -10, "Ptr"), startupInfo, stdinOffset)
        NumPut("Ptr", stdoutWrite, startupInfo, stdoutOffset)
        NumPut("Ptr", stderrWrite, startupInfo, stderrOffset)
        processInfo := Buffer(A_PtrSize * 2 + 8, 0)

        jobHandle := DllCall("Kernel32.dll\CreateJobObjectW", "Ptr", 0, "Ptr", 0, "Ptr")
        if !jobHandle
            throw Error("Orca workspace adapter could not create a process job")
        extendedLimitInfo := Buffer(A_PtrSize = 8 ? 144 : 112, 0)
        NumPut("UInt", 0x2000, extendedLimitInfo, 16)
        if !DllCall("Kernel32.dll\SetInformationJobObject", "Ptr", jobHandle, "Int", 9, "Ptr", extendedLimitInfo.Ptr, "UInt", extendedLimitInfo.Size)
            throw Error("Orca workspace adapter could not configure its process job")

        creationFlags := 0x08000000 | 0x00000004
        if !DllCall("Kernel32.dll\CreateProcessW", "Ptr", 0, "Ptr", commandBuffer.Ptr, "Ptr", 0, "Ptr", 0, "Int", 1, "UInt", creationFlags, "Ptr", 0, "Ptr", 0, "Ptr", startupInfo.Ptr, "Ptr", processInfo.Ptr)
            throw Error("Orca workspace adapter could not start PowerShell")
        processHandle := NumGet(processInfo, 0, "Ptr")
        threadHandle := NumGet(processInfo, A_PtrSize, "Ptr")
        if !DllCall("Kernel32.dll\AssignProcessToJobObject", "Ptr", jobHandle, "Ptr", processHandle) {
            DllCall("Kernel32.dll\TerminateProcess", "Ptr", processHandle, "UInt", 1)
            throw Error("Orca workspace adapter could not assign PowerShell to its process job")
        }
        if (DllCall("Kernel32.dll\ResumeThread", "Ptr", threadHandle, "UInt") = 0xFFFFFFFF) {
            DllCall("Kernel32.dll\TerminateJobObject", "Ptr", jobHandle, "UInt", 1)
            throw Error("Orca workspace adapter could not resume PowerShell")
        }
        DllCall("Kernel32.dll\CloseHandle", "Ptr", stdoutWrite)
        stdoutWrite := 0
        DllCall("Kernel32.dll\CloseHandle", "Ptr", stderrWrite)
        stderrWrite := 0
        stdoutText := ""
        stderrText := ""
        startedAt := A_TickCount
        timedOut := false
        loop {
            OrcaDrainPipe(stdoutRead, &stdoutText)
            OrcaDrainPipe(stderrRead, &stderrText)
            waitResult := DllCall("Kernel32.dll\WaitForSingleObject", "Ptr", processHandle, "UInt", 0)
            if (waitResult = 0)
                break
            if (A_TickCount - startedAt >= timeoutMs) {
                timedOut := true
                DllCall("Kernel32.dll\TerminateJobObject", "Ptr", jobHandle, "UInt", 1)
                DllCall("Kernel32.dll\WaitForSingleObject", "Ptr", processHandle, "UInt", 0xFFFFFFFF)
                break
            }
            Sleep(10)
        }
        loop 20 {
            stdoutAvailable := OrcaDrainPipe(stdoutRead, &stdoutText)
            stderrAvailable := OrcaDrainPipe(stderrRead, &stderrText)
            if !(stdoutAvailable || stderrAvailable)
                break
            Sleep(5)
        }
        exitCode := -1
        if !timedOut
            DllCall("Kernel32.dll\GetExitCodeProcess", "Ptr", processHandle, "UIntP", &exitCode)
        return Map("exitCode", timedOut ? -1 : exitCode, "timedOut", timedOut, "stdout", stdoutText, "stderr", stderrText)
    } finally {
        if threadHandle
            DllCall("Kernel32.dll\CloseHandle", "Ptr", threadHandle)
        if processHandle
            DllCall("Kernel32.dll\CloseHandle", "Ptr", processHandle)
        if jobHandle
            DllCall("Kernel32.dll\CloseHandle", "Ptr", jobHandle)
        if stdoutWrite
            DllCall("Kernel32.dll\CloseHandle", "Ptr", stdoutWrite)
        if stderrWrite
            DllCall("Kernel32.dll\CloseHandle", "Ptr", stderrWrite)
        if stdoutRead
            DllCall("Kernel32.dll\CloseHandle", "Ptr", stdoutRead)
        if stderrRead
            DllCall("Kernel32.dll\CloseHandle", "Ptr", stderrRead)
    }
}

OrcaDrainPipe(pipeHandle, &text) {
    available := 0
    if !DllCall("Kernel32.dll\PeekNamedPipe", "Ptr", pipeHandle, "Ptr", 0, "UInt", 0, "Ptr", 0, "UIntP", &available, "Ptr", 0)
        return false
    if (available = 0)
        return false
    chunk := Buffer(available, 0)
    bytesRead := 0
    if DllCall("Kernel32.dll\ReadFile", "Ptr", pipeHandle, "Ptr", chunk.Ptr, "UInt", available, "UIntP", &bytesRead, "Ptr", 0)
        text .= StrGet(chunk.Ptr, bytesRead, "UTF-8")
    return bytesRead > 0
}

OrcaJoinArguments(arguments) {
    commandLine := ""
    for index, argument in arguments
        commandLine .= (index = 1 ? "" : " ") OrcaQuoteWindowsArgument(argument)
    return commandLine
}

OrcaQuoteWindowsArgument(value) {
    value := String(value)
    result := '"'
    slashCount := 0
    loop parse value {
        character := A_LoopField
        if (character = "\") {
            slashCount += 1
            continue
        }
        if (character = '"') {
            result .= OrcaRepeatText("\", slashCount * 2 + 1) '"'
            slashCount := 0
            continue
        }
        if (slashCount > 0) {
            result .= OrcaRepeatText("\", slashCount)
            slashCount := 0
        }
        result .= character
    }
    if (slashCount > 0)
        result .= OrcaRepeatText("\", slashCount * 2)
    return result '"'
}

OrcaRepeatText(text, count) {
    result := ""
    loop count
        result .= text
    return result
}

OrcaJsonParse(text) {
    parser := OrcaJsonReader(String(text))
    value := parser.ReadValue()
    parser.SkipWhitespace()
    if parser.Position <= StrLen(parser.Text)
        throw Error("Unexpected trailing JSON content")
    return value
}

class OrcaJsonReader {
    __New(text) {
        this.Text := text
        this.Position := 1
    }

    SkipWhitespace() {
        while this.Position <= StrLen(this.Text) {
            character := SubStr(this.Text, this.Position, 1)
            if !InStr(" `t`r`n", character)
                break
            this.Position += 1
        }
    }

    ReadValue() {
        this.SkipWhitespace()
        if this.Position > StrLen(this.Text)
            throw Error("Unexpected end of JSON")
        character := SubStr(this.Text, this.Position, 1)
        if (character = "{")
            return this.ReadObject()
        if (character = "[")
            return this.ReadArray()
        if (character = '"')
            return this.ReadString()
        if (SubStr(this.Text, this.Position, 4) = "true") {
            this.Position += 4
            return true
        }
        if (SubStr(this.Text, this.Position, 5) = "false") {
            this.Position += 5
            return false
        }
        if (SubStr(this.Text, this.Position, 4) = "null") {
            this.Position += 4
            return ""
        }
        return this.ReadNumber()
    }

    ReadObject() {
        objectValue := Map()
        this.Position += 1
        this.SkipWhitespace()
        if (SubStr(this.Text, this.Position, 1) = "}") {
            this.Position += 1
            return objectValue
        }
        loop {
            this.SkipWhitespace()
            key := this.ReadString()
            this.SkipWhitespace()
            this.Expect(":")
            objectValue[key] := this.ReadValue()
            this.SkipWhitespace()
            delimiter := SubStr(this.Text, this.Position, 1)
            if (delimiter = "}") {
                this.Position += 1
                return objectValue
            }
            this.Expect(",")
        }
    }

    ReadArray() {
        arrayValue := []
        this.Position += 1
        this.SkipWhitespace()
        if (SubStr(this.Text, this.Position, 1) = "]") {
            this.Position += 1
            return arrayValue
        }
        loop {
            arrayValue.Push(this.ReadValue())
            this.SkipWhitespace()
            delimiter := SubStr(this.Text, this.Position, 1)
            if (delimiter = "]") {
                this.Position += 1
                return arrayValue
            }
            this.Expect(",")
        }
    }

    ReadString() {
        this.Expect('"')
        value := ""
        while this.Position <= StrLen(this.Text) {
            character := SubStr(this.Text, this.Position, 1)
            this.Position += 1
            if (character = '"')
                return value
            if (character != "\") {
                value .= character
                continue
            }
            if this.Position > StrLen(this.Text)
                throw Error("Unterminated JSON escape")
            escape := SubStr(this.Text, this.Position, 1)
            this.Position += 1
            if (escape = '"')
                value .= '"'
            else if (escape = "\")
                value .= "\"
            else if (escape = "/")
                value .= "/"
            else if (escape = "b")
                value .= Chr(8)
            else if (escape = "f")
                value .= Chr(12)
            else if (escape = "n")
                value .= "`n"
            else if (escape = "r")
                value .= "`r"
            else if (escape = "t")
                value .= "`t"
            else if (escape = "u") {
                hex := SubStr(this.Text, this.Position, 4)
                if !RegExMatch(hex, "i)^[0-9a-f]{4}$")
                    throw Error("Invalid JSON unicode escape")
                value .= Chr("0x" hex)
                this.Position += 4
            } else {
                throw Error("Invalid JSON escape")
            }
        }
        throw Error("Unterminated JSON string")
    }

    ReadNumber() {
        remaining := SubStr(this.Text, this.Position)
        if !RegExMatch(remaining, "^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?", &match)
            throw Error("Invalid JSON value")
        token := match[0]
        this.Position += StrLen(token)
        return InStr(token, ".") || InStr(token, "e") || InStr(token, "E") ? Float(token) : Integer(token)
    }

    Expect(expected) {
        if (SubStr(this.Text, this.Position, 1) != expected)
            throw Error("Invalid JSON: expected " expected)
        this.Position += 1
    }
}
