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
    __New(readyTimeoutMs := 60000, powershellPath := "powershell.exe") {
        this.readyTimeoutMs := Max(1, Integer(readyTimeoutMs))
        this.powershellPath := String(powershellPath)
    }

    Open(scriptPath, selectedPath) {
        scriptPath := String(scriptPath)
        selectedPath := String(selectedPath)
        if (scriptPath = "")
            throw Error("Orca workspace adapter script path is empty")
        if (selectedPath = "")
            throw Error("Orca workspace selection is empty")

        outputPath := A_Temp "\\local-automation-hub-orca-" A_TickCount "-" Random(100000, 999999) ".json"
        command := OrcaBuildPowerShellCommand(this.powershellPath, scriptPath, selectedPath, outputPath)
        try {
            processId := 0
            Run(command, , "Hide", &processId)
            if !OrcaWaitForProcess(processId, this.readyTimeoutMs)
                throw Error("Orca workspace adapter timed out")
            if !FileExist(outputPath)
                throw Error("Orca workspace adapter returned no JSON")
            rawResult := FileRead(outputPath, "UTF-8")
            if (Trim(rawResult) = "")
                throw Error("Orca workspace adapter returned no JSON")
            return OrcaJsonParse(rawResult)
        } finally {
            try FileDelete(outputPath)
        }
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

OrcaBuildPowerShellCommand(powershellPath, scriptPath, selectedPath, outputPath) {
    arguments := [
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", scriptPath,
        "-SelectedPath", selectedPath,
        "-ReadyTimeoutMs", "60000"
    ]
    redirect := ">" OrcaQuoteArgument(outputPath) " 2>" OrcaQuoteArgument(outputPath ".err")
    command := OrcaQuoteArgument(powershellPath)
    for _, argument in arguments
        command .= " " OrcaQuoteArgument(argument)
    return command " " redirect
}

OrcaQuoteArgument(value) {
    value := String(value)
    return '"' StrReplace(value, '"', '""') '"'
}

OrcaWaitForProcess(processId, timeoutMs) {
    startedAt := A_TickCount
    while ProcessExist(processId) {
        if (A_TickCount - startedAt >= timeoutMs) {
            try ProcessClose(processId)
            return false
        }
        Sleep(25)
    }
    return true
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
            if (character != "\\") {
                value .= character
                continue
            }
            if this.Position > StrLen(this.Text)
                throw Error("Unterminated JSON escape")
            escape := SubStr(this.Text, this.Position, 1)
            this.Position += 1
            if (escape = '"' || escape = "\\" || escape = "/")
                value .= escape
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
