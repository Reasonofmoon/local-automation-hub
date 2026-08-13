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

ExitWithTestResult()
