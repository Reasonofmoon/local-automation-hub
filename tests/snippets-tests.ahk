#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\Snippets.ahk

class FakeInputAdapter {
    __New(clipboardText := "") {
        this._clipboardText := clipboardText
        this._insertedText := ""
        this._directText := ""
        this._pasteCount := 0
        this._captureCount := 0
        this._captured := false
        this._snapshot := ""
        this._events := []
        this.isPasswordControl := false
        this.isCustomControl := false
        this.isTargetElevated := false
        this.isHubElevated := false
        this.targetDestroyed := false
        this.processReplaced := false
        this.failCapture := false
        this.failPaste := false
        this.hasFocusDrift := false
    }

    CaptureBeforePalette() {
        this._captureCount += 1
        this._captured := false
        this._snapshot := ""
        if this.failCapture
            throw Error("Target capture failed")
        this._captured := true
        this._snapshot := Map(
            "windowHandle", 100,
            "processId", 200,
            "controlHandle", this.isCustomControl ? 0 : 300,
            "controlClass", this.isCustomControl ? "Chrome_RenderWidgetHostHWND1" : "Edit1",
            "controlStyle", this.isPasswordControl ? 0x20 : 0,
            "isStandardControl", !this.isCustomControl
        )
        return this._snapshot
    }

    EnsureSafeTarget() {
        if !this._captured
            throw Error("Snippet insertion requires a captured pre-palette target")
        targetSnapshot := this._snapshot
        this._captured := false
        this._snapshot := ""
        if this.targetDestroyed
            throw Error("Snippet insertion target no longer exists")
        if this.processReplaced
            throw Error("Snippet insertion target process changed")
        if this.isPasswordControl
            throw Error("Snippet insertion is blocked for password controls")
        if this.isTargetElevated && !this.isHubElevated
            throw Error("Snippet insertion is blocked for elevated targets")
        if this.hasFocusDrift && !this.isCustomControl
            throw Error("Snippet insertion is blocked because focus changed before input")
        return targetSnapshot
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot) || !targetSnapshot.Has("windowHandle")
            throw Error("Snippet insertion target snapshot is invalid")
        if this.targetDestroyed
            throw Error("Snippet insertion target no longer exists")
        if this.processReplaced
            throw Error("Snippet insertion target process changed")
        if this.isPasswordControl
            throw Error("Snippet insertion is blocked for password controls")
        if this.isTargetElevated && !this.isHubElevated
            throw Error("Snippet insertion is blocked for elevated targets")
        if this.hasFocusDrift && !this.isCustomControl
            throw Error("Snippet insertion is blocked because focus changed before input")
        return true
    }

    WaitForPasteHandoff() {
        this._events.Push("wait")
    }

    CaptureClipboard() {
        return this._clipboardText
    }

    SetClipboardText(text) {
        this._clipboardText := text
    }

    Paste(targetSnapshot) {
        this.ConfirmSafeTarget(targetSnapshot)
        if this.failPaste
            throw Error("Paste failed")
        this._events.Push("paste")
        this._insertedText := this._clipboardText
        this._pasteCount += 1
    }

    RestoreClipboard(value) {
        this._events.Push("restore")
        this._clipboardText := value
    }

    SendText(targetSnapshot, text) {
        this.ConfirmSafeTarget(targetSnapshot)
        this._directText := text
    }

    CaptureCount() {
        return this._captureCount
    }

    EventSummary() {
        result := ""
        for index, eventName in this._events
            result .= (index = 1 ? "" : ",") eventName
        return result
    }

    ClipboardText() {
        return this._clipboardText
    }

    InsertedText() {
        return this._insertedText
    }

    DirectText() {
        return this._directText
    }

    PasteCount() {
        return this._pasteCount
    }
}

class FakeCommandRegistry {
    __New() {
        this._commands := []
    }

    Register(id, label, tags, risk, handler) {
        this._commands.Push(Map("id", id, "label", label, "tags", tags, "risk", risk, "handler", handler))
    }

    CommandIds() {
        ids := []
        for command in this._commands
            ids.Push(command["id"])
        return ids
    }
}

singleAdapter := FakeInputAdapter("before")
singleAdapter.CaptureBeforePalette()
singleService := SnippetService(Map("single", Map("title", "Single", "tags", ["lesson"], "body", "Great work!")), singleAdapter)
singleService.Insert("single")
AssertEqual("Great work!", singleAdapter.DirectText(), "sends a single-line snippet directly")
AssertEqual("before", singleAdapter.ClipboardText(), "does not change clipboard for single-line snippet")

directDriftAdapter := FakeInputAdapter("before")
directDriftAdapter.hasFocusDrift := true
directDriftAdapter.CaptureBeforePalette()
directDriftService := SnippetService(Map("single", "safe"), directDriftAdapter)
AssertThrows(() => directDriftService.Insert("single"), "blocks focus drift before direct send")
AssertEqual("", directDriftAdapter.DirectText(), "does not send text after focus drift")
AssertEqual("before", directDriftAdapter.ClipboardText(), "does not change clipboard after direct-send focus drift")

adapter := FakeInputAdapter("before")
adapter.CaptureBeforePalette()
service := SnippetService(Map("multi", Map("title", "Multi", "tags", ["lesson"], "body", "line 1\nline 2")), adapter)
service.Insert("multi")
AssertEqual("before", adapter.ClipboardText(), "restores clipboard")
AssertEqual("line 1`nline 2", adapter.InsertedText(), "inserts configured body")
AssertEqual(1, adapter.PasteCount(), "pastes multiline snippet once")
AssertEqual("paste,wait,restore", adapter.EventSummary(), "waits for paste handoff before clipboard restoration")

pasteDriftAdapter := FakeInputAdapter("before")
pasteDriftAdapter.hasFocusDrift := true
pasteDriftAdapter.CaptureBeforePalette()
pasteDriftService := SnippetService(Map("multi", "line 1`nline 2"), pasteDriftAdapter)
AssertThrows(() => pasteDriftService.Insert("multi"), "blocks focus drift before paste")
AssertEqual("", pasteDriftAdapter.InsertedText(), "does not paste after focus drift")
AssertEqual(0, pasteDriftAdapter.PasteCount(), "does not invoke paste after focus drift")
AssertEqual("before", pasteDriftAdapter.ClipboardText(), "restores clipboard after focus drift before paste")

adapter.isPasswordControl := true
adapter.CaptureBeforePalette()
AssertThrows(() => service.Insert("multi"), "blocks password controls")
AssertEqual("before", adapter.ClipboardText(), "does not alter clipboard for password controls")

customAdapter := FakeInputAdapter("before")
customAdapter.isCustomControl := true
customAdapter.CaptureBeforePalette()
customService := SnippetService(Map("multi", "line 1\nline 2"), customAdapter)
customService.Insert("multi")
AssertEqual("line 1`nline 2", customAdapter.InsertedText(), "pastes multiline text into custom controls")

destroyedAdapter := FakeInputAdapter("before")
destroyedAdapter.CaptureBeforePalette()
destroyedAdapter.targetDestroyed := true
destroyedService := SnippetService(Map("multi", "line 1\nline 2"), destroyedAdapter)
AssertThrows(() => destroyedService.Insert("multi"), "blocks destroyed captured windows")
AssertEqual(0, destroyedAdapter.PasteCount(), "does not paste after target destruction")

replacedAdapter := FakeInputAdapter("before")
replacedAdapter.CaptureBeforePalette()
replacedAdapter.processReplaced := true
replacedService := SnippetService(Map("single", "safe"), replacedAdapter)
AssertThrows(() => replacedService.Insert("single"), "blocks process replacement for the captured window")
AssertEqual("", replacedAdapter.DirectText(), "does not type after process replacement")

elevatedAdapter := FakeInputAdapter("before")
elevatedAdapter.isTargetElevated := true
elevatedAdapter.isHubElevated := false
elevatedAdapter.CaptureBeforePalette()
elevatedService := SnippetService(Map("single", "safe"), elevatedAdapter)
AssertThrows(() => elevatedService.Insert("single"), "blocks elevated targets from non-elevated hub")
AssertEqual("", elevatedAdapter.DirectText(), "does not type into rejected elevated target")

failingPasteAdapter := FakeInputAdapter("before")
failingPasteAdapter.failPaste := true
failingPasteAdapter.CaptureBeforePalette()
failingPasteService := SnippetService(Map("multi", "line 1`nline 2"), failingPasteAdapter)
AssertThrows(() => failingPasteService.Insert("multi"), "surfaces paste failure")
AssertEqual("before", failingPasteAdapter.ClipboardText(), "restores clipboard after paste failure")
AssertEqual("wait,restore", failingPasteAdapter.EventSummary(), "waits for paste handoff before restoring after paste failure")

repeatedAdapter := FakeInputAdapter("before")
firstSnapshot := repeatedAdapter.CaptureBeforePalette()
repeatedAdapter.isCustomControl := true
secondSnapshot := repeatedAdapter.CaptureBeforePalette()
AssertTrue(firstSnapshot["controlHandle"] != secondSnapshot["controlHandle"], "replaces the previous palette target")
repeatedService := SnippetService(Map("single", "safe"), repeatedAdapter)
repeatedService.Insert("single")
AssertThrows(() => repeatedService.Insert("single"), "consumes a captured target only once")

staleAdapter := FakeInputAdapter("before")
staleAdapter.CaptureBeforePalette()
staleAdapter.failCapture := true
AssertThrows(() => staleAdapter.CaptureBeforePalette(), "reports the second capture failure")
staleService := SnippetService(Map("single", "safe"), staleAdapter)
AssertThrows(() => staleService.Insert("single"), "does not reuse a snapshot after capture failure")
AssertEqual("", staleAdapter.DirectText(), "does not type through a stale snapshot")

searchService := SnippetService(Map(
    "feedback", Map("title", "Feedback", "tags", ["lesson", "student"], "body", "Great work!"),
    "meeting", Map("title", "Meeting", "tags", ["calendar"], "body", "Agenda")
), FakeInputAdapter())
AssertEqual(1, searchService.Search("student").Length, "searches snippet tags")
AssertEqual("feedback", searchService.Search("feedback")[1]["id"], "searches snippet ids")
fakeRegistry := FakeCommandRegistry()
RegisterSnippetCommands(fakeRegistry, searchService)
AssertEqual("snippet.feedback", fakeRegistry.CommandIds()[1], "registers one palette command per snippet")
AssertEqual("snippet.meeting", fakeRegistry.CommandIds()[2], "uses each snippet config id in palette command")

ExitWithTestResult()
