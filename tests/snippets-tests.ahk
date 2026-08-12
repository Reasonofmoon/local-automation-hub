#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\modules\Snippets.ahk

class FakeInputAdapter {
    __New(clipboardText := "") {
        this._clipboardText := clipboardText
        this._insertedText := ""
        this._directText := ""
        this._pasteCount := 0
        this.isPasswordControl := false
        this.isCustomControl := false
        this.isTargetElevated := false
        this.isHubElevated := false
        this.failPaste := false
        this.hasFocusDrift := false
    }

    EnsureSafeTarget() {
        if this.isPasswordControl
            throw Error("Snippet insertion is blocked for password controls")
        if this.isCustomControl
            throw Error("Snippet insertion is blocked because the focused control is not a standard Edit or RichEdit control")
        if this.isTargetElevated && !this.isHubElevated
            throw Error("Snippet insertion is blocked for elevated targets")
        return Map("target", "original")
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot) || !targetSnapshot.Has("target")
            throw Error("Snippet insertion target snapshot is invalid")
        if this.hasFocusDrift
            throw Error("Snippet insertion is blocked because focus changed before input")
        return this.EnsureSafeTarget()
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
        this._insertedText := this._clipboardText
        this._pasteCount += 1
    }

    RestoreClipboard(value) {
        this._clipboardText := value
    }

    SendText(targetSnapshot, text) {
        this.ConfirmSafeTarget(targetSnapshot)
        this._directText := text
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
singleService := SnippetService(Map("single", Map("title", "Single", "tags", ["lesson"], "body", "Great work!")), singleAdapter)
singleService.Insert("single")
AssertEqual("Great work!", singleAdapter.DirectText(), "sends a single-line snippet directly")
AssertEqual("before", singleAdapter.ClipboardText(), "does not change clipboard for single-line snippet")

directDriftAdapter := FakeInputAdapter("before")
directDriftAdapter.hasFocusDrift := true
directDriftService := SnippetService(Map("single", "safe"), directDriftAdapter)
AssertThrows(() => directDriftService.Insert("single"), "blocks focus drift before direct send")
AssertEqual("", directDriftAdapter.DirectText(), "does not send text after focus drift")
AssertEqual("before", directDriftAdapter.ClipboardText(), "does not change clipboard after direct-send focus drift")

adapter := FakeInputAdapter("before")
service := SnippetService(Map("multi", Map("title", "Multi", "tags", ["lesson"], "body", "line 1\nline 2")), adapter)
service.Insert("multi")
AssertEqual("before", adapter.ClipboardText(), "restores clipboard")
AssertEqual("line 1`nline 2", adapter.InsertedText(), "inserts configured body")
AssertEqual(1, adapter.PasteCount(), "pastes multiline snippet once")

pasteDriftAdapter := FakeInputAdapter("before")
pasteDriftAdapter.hasFocusDrift := true
pasteDriftService := SnippetService(Map("multi", "line 1`nline 2"), pasteDriftAdapter)
AssertThrows(() => pasteDriftService.Insert("multi"), "blocks focus drift before paste")
AssertEqual("", pasteDriftAdapter.InsertedText(), "does not paste after focus drift")
AssertEqual(0, pasteDriftAdapter.PasteCount(), "does not invoke paste after focus drift")
AssertEqual("before", pasteDriftAdapter.ClipboardText(), "restores clipboard after focus drift before paste")

adapter.isPasswordControl := true
AssertThrows(() => service.Insert("multi"), "blocks password controls")
AssertEqual("before", adapter.ClipboardText(), "does not alter clipboard for password controls")

customControlAdapter := FakeInputAdapter("before")
customControlAdapter.isCustomControl := true
customControlService := SnippetService(Map("single", "safe"), customControlAdapter)
AssertThrows(() => customControlService.Insert("single"), "blocks unknown or custom focused controls")
AssertEqual("", customControlAdapter.DirectText(), "does not type into unknown or custom focused controls")

elevatedAdapter := FakeInputAdapter("before")
elevatedAdapter.isTargetElevated := true
elevatedAdapter.isHubElevated := false
elevatedService := SnippetService(Map("single", "safe"), elevatedAdapter)
AssertThrows(() => elevatedService.Insert("single"), "blocks elevated targets from non-elevated hub")
AssertEqual("", elevatedAdapter.DirectText(), "does not type into rejected elevated target")

failingPasteAdapter := FakeInputAdapter("before")
failingPasteAdapter.failPaste := true
failingPasteService := SnippetService(Map("multi", "line 1`nline 2"), failingPasteAdapter)
AssertThrows(() => failingPasteService.Insert("multi"), "surfaces paste failure")
AssertEqual("before", failingPasteAdapter.ClipboardText(), "restores clipboard after paste failure")

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
