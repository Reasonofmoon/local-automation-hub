#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\OrcaWorkspace.ahk

class FakeOrcaFolderPicker {
    __New(path := "") {
        this.path := String(path)
        this.callCount := 0
    }

    Select() {
        this.callCount += 1
        return this.path
    }
}

class FakeOrcaProcessAdapter {
    __New(result := unset, failure := "") {
        this.result := IsSet(result) ? result : Map(
            "success", true,
            "repositoryRoot", "C:\\projects\\lesson-platform",
            "created", [],
            "reused", [],
            "skipped", [],
            "failed", []
        )
        this.failure := String(failure)
        this.callCount := 0
        this.scriptPath := ""
        this.selectedPath := ""
    }

    Open(scriptPath, selectedPath) {
        this.callCount += 1
        this.scriptPath := String(scriptPath)
        this.selectedPath := String(selectedPath)
        if (this.failure != "")
            throw Error(this.failure)
        return this.result
    }
}

class FakeOrcaPresenter {
    __New() {
        this.callCount := 0
        this.messages := []
    }

    Show(message) {
        this.callCount += 1
        this.messages.Push(String(message))
        return true
    }
}

class FakeOrcaAppContext {
    __New(cancelled := false) {
        this.cancelled := cancelled
    }

    IsCancelled() {
        return this.cancelled
    }
}

class CancellingOrcaAppContext {
    __New() {
        this.calls := 0
    }

    IsCancelled() {
        this.calls += 1
        return this.calls > 1
    }
}

class FakeOrcaCommandRegistry {
    __New() {
        this.commands := []
    }

    Register(id, label, tags, risk, handler) {
        this.commands.Push(Map("id", id, "label", label, "tags", tags, "risk", risk, "handler", handler))
        return this.commands[this.commands.Length]
    }
}

AssertThrowsContains(callback, expectedText, message := "expected an exception containing text") {
    global TestFailures
    threw := false
    matched := false
    try {
        callback()
    } catch as caughtError {
        threw := true
        matched := InStr(String(caughtError.Message), String(expectedText)) > 0
    }
    if !threw || !matched {
        TestFailures += 1
        FileAppend("FAIL: " message "`n", "*")
    }
}

selectedPath := "C:\\projects\\lesson-platform"
picker := FakeOrcaFolderPicker(selectedPath)
processAdapter := FakeOrcaProcessAdapter(Map(
    "success", true,
    "repositoryRoot", selectedPath,
    "created", ["Codex"],
    "reused", ["Grok"],
    "skipped", [Map("agent", "Gemini", "reason", "command not found")],
    "failed", [Map("agent", "Claude", "reason", "wait failed")]
))
presenter := FakeOrcaPresenter()
service := OrcaWorkspaceService(
    picker,
    processAdapter,
    presenter,
    "C:\\hub\\scripts\\Open-OrcaAiWorkspace.ps1",
    FakeOrcaAppContext()
)
result := service.OpenAiDevelopment()
AssertEqual(1, picker.callCount, "selected folder invokes the picker once")
AssertEqual(1, processAdapter.callCount, "selected folder invokes adapter once")
AssertEqual(selectedPath, processAdapter.selectedPath, "passes selected path as a separate argument")
AssertEqual("C:\\hub\\scripts\\Open-OrcaAiWorkspace.ps1", processAdapter.scriptPath, "passes adapter script path")
AssertEqual(1, presenter.callCount, "shows aggregate result once")
AssertTrue(result["success"], "returns adapter success result")
AssertTrue(InStr(presenter.messages[1], "Created: Codex") > 0, "summary includes created agents")
AssertTrue(InStr(presenter.messages[1], "Reused: Grok") > 0, "summary includes reused agents")
AssertTrue(InStr(presenter.messages[1], "Skipped: Gemini (command not found)") > 0, "summary includes skipped reason")
AssertTrue(InStr(presenter.messages[1], "Failed: Claude (wait failed)") > 0, "summary includes failed reason")

cancelledBeforePicker := FakeOrcaFolderPicker(selectedPath)
cancelledBeforePickerService := OrcaWorkspaceService(
    cancelledBeforePicker,
    FakeOrcaProcessAdapter(),
    FakeOrcaPresenter(),
    "script.ps1",
    FakeOrcaAppContext(true)
)
AssertThrows(() => cancelledBeforePickerService.OpenAiDevelopment(), "cancellation before picker aborts")
AssertEqual(0, cancelledBeforePicker.callCount, "cancellation before picker does not open picker")

cancelledPicker := FakeOrcaFolderPicker("")
cancelledAdapter := FakeOrcaProcessAdapter()
cancelledPresenter := FakeOrcaPresenter()
cancelledPickerService := OrcaWorkspaceService(
    cancelledPicker,
    cancelledAdapter,
    cancelledPresenter,
    "script.ps1",
    FakeOrcaAppContext()
)
cancelledResult := cancelledPickerService.OpenAiDevelopment()
AssertTrue(cancelledResult["cancelled"], "closing picker returns cancellation result")
AssertEqual(0, cancelledAdapter.callCount, "picker cancellation makes zero adapter calls")
AssertEqual(0, cancelledPresenter.callCount, "picker cancellation shows no result dialog")

cancelledAfterPicker := FakeOrcaFolderPicker(selectedPath)
cancelledAfterAdapter := FakeOrcaProcessAdapter()
cancelledAfterPickerService := OrcaWorkspaceService(
    cancelledAfterPicker,
    cancelledAfterAdapter,
    FakeOrcaPresenter(),
    "script.ps1",
    CancellingOrcaAppContext()
)
AssertThrows(() => cancelledAfterPickerService.OpenAiDevelopment(), "cancellation after picker aborts")
AssertEqual(1, cancelledAfterPicker.callCount, "cancellation after picker still opens picker once")
AssertEqual(0, cancelledAfterAdapter.callCount, "cancellation after picker makes zero adapter calls")

adapterFailurePresenter := FakeOrcaPresenter()
adapterFailureService := OrcaWorkspaceService(
    FakeOrcaFolderPicker(selectedPath),
    FakeOrcaProcessAdapter(unset, "adapter unavailable"),
    adapterFailurePresenter,
    "script.ps1",
    FakeOrcaAppContext()
)
adapterFailureResult := adapterFailureService.OpenAiDevelopment()
AssertFalse(adapterFailureResult["success"], "adapter failure returns an unsuccessful result")
AssertEqual("adapter unavailable", adapterFailureResult["error"], "adapter failure is summarized")
AssertEqual(1, adapterFailurePresenter.callCount, "adapter failure presents once")
AssertTrue(InStr(adapterFailurePresenter.messages[1], "adapter unavailable") > 0, "adapter failure message is visible")

registry := FakeOrcaCommandRegistry()
RegisterOrcaWorkspaceCommand(registry, service)
AssertEqual(1, registry.commands.Length, "registers one Orca command")
AssertEqual("workspace.ai-development", registry.commands[1]["id"], "uses exact Orca command id")
AssertEqual("medium", registry.commands[1]["risk"], "registers medium command risk")

; Contract tests exercise the real Win32 process boundary.  The fake scripts
; are harmless PowerShell processes and never invoke Orca or an agent CLI.
adapterTestRoot := A_Temp "\orca-adapter-contract-" A_TickCount "-" Random(100000, 999999)
DirCreate(adapterTestRoot)
successScript := adapterTestRoot "\fake adapter success script.ps1"
successScriptBody := "param([string]$SelectedPath, [int]$ReadyTimeoutMs)`n"
    . "[Console]::Error.WriteLine('adapter-stderr-ignored')`n"
    . "[ordered]@{ success = $true; selectedPath = $SelectedPath; readyTimeoutMs = $ReadyTimeoutMs } | ConvertTo-Json -Compress`n"
FileAppend(successScriptBody, successScript, "UTF-8")
selectedContractPath := adapterTestRoot "\selected path & spaces [x]; $HOME"
contractAdapter := Win32OrcaProcessAdapter(1257, "powershell.exe")
contractResult := contractAdapter.Open(successScript, selectedContractPath)
AssertTrue(contractResult["success"], "Win32 adapter captures stdout JSON")
AssertEqual(selectedContractPath, contractResult["selectedPath"], "selected path arrives as one exact argv value")
AssertEqual(1257, contractResult["readyTimeoutMs"], "same ReadyTimeoutMs is forwarded to PowerShell")
AssertTrue(contractAdapter.HasOwnProp("perAgentReadyTimeoutMs"), "adapter stores the per-agent ready timeout separately")
AssertTrue(contractAdapter.HasOwnProp("totalProcessTimeoutMs"), "adapter stores a distinct total process timeout")
if contractAdapter.HasOwnProp("perAgentReadyTimeoutMs")
    AssertEqual(1257, contractAdapter.perAgentReadyTimeoutMs, "per-agent timeout preserves the requested value")
if contractAdapter.HasOwnProp("totalProcessTimeoutMs")
    AssertTrue(contractAdapter.totalProcessTimeoutMs >= (1257 * 4 + 5000), "total timeout budgets four sequential agent waits plus bounded overhead")

delayedScript := adapterTestRoot "\fake adapter delayed success script.ps1"
delayedScriptBody := "param([string]$SelectedPath, [int]$ReadyTimeoutMs)`n"
    . "Start-Sleep -Milliseconds 250`n"
    . "[ordered]@{ success = $true; selectedPath = $SelectedPath; readyTimeoutMs = $ReadyTimeoutMs } | ConvertTo-Json -Compress`n"
FileAppend(delayedScriptBody, delayedScript, "UTF-8")
delayedPerAgentTimeoutMs := 100
delayedAdapter := Win32OrcaProcessAdapter(delayedPerAgentTimeoutMs, "powershell.exe")
delayedStartedAt := A_TickCount
delayedResult := unset
delayedFailure := ""
try {
    delayedResult := delayedAdapter.Open(delayedScript, selectedContractPath)
} catch as caughtError {
    delayedFailure := String(caughtError.Message)
}
delayedElapsedMs := A_TickCount - delayedStartedAt
AssertEqual("", delayedFailure, "process may outlive one per-agent wait within the total budget")
if delayedAdapter.HasOwnProp("totalProcessTimeoutMs") {
    AssertTrue(delayedElapsedMs > delayedPerAgentTimeoutMs, "delayed process runs longer than one per-agent timeout")
    AssertTrue(delayedElapsedMs < delayedAdapter.totalProcessTimeoutMs, "delayed process completes before the total process timeout")
}
if IsObject(delayedResult) {
    AssertTrue(delayedResult["success"], "delayed process returns its JSON result")
    AssertEqual(delayedPerAgentTimeoutMs, delayedResult["readyTimeoutMs"], "delayed process still receives the per-agent timeout")
}

failureScript := adapterTestRoot "\fake adapter failure script.ps1"
failureScriptBody := "param([string]$SelectedPath, [int]$ReadyTimeoutMs)`n"
    . "[Console]::Error.WriteLine('adapter-stderr-marker')`n"
    . "exit 7`n"
FileAppend(failureScriptBody, failureScript, "UTF-8")
AssertThrowsContains(
    () => contractAdapter.Open(failureScript, selectedContractPath),
    "adapter-stderr-marker",
    "nonzero exit maps captured stderr into adapter failure"
)
AssertThrowsContains(
    () => contractAdapter.Open(failureScript, selectedContractPath),
    "exited with code 7",
    "nonzero exit maps the exact process exit code"
)

timeoutMarker := adapterTestRoot "\timeout marker.txt"
timeoutScript := adapterTestRoot "\fake adapter timeout script.ps1"
timeoutScriptBody := "param([string]$SelectedPath, [int]$ReadyTimeoutMs)`n"
    . "Start-Sleep -Milliseconds 3000`n"
    . "Set-Content -LiteralPath $SelectedPath -Value 'late'`n"
FileAppend(timeoutScriptBody, timeoutScript, "UTF-8")
timeoutAdapter := Win32OrcaProcessAdapter(100, "powershell.exe", 100)
AssertThrowsContains(
    () => timeoutAdapter.Open(timeoutScript, timeoutMarker),
    "timed out",
    "timeout reports a bounded owned-process failure"
)
Sleep(500)
AssertFalse(FileExist(timeoutMarker), "timeout terminates the owned process before its late write")
try DirDelete(adapterTestRoot, true)

ExitWithTestResult()
