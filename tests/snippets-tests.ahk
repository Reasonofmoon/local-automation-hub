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
        this.isCustomControl := false
        this.captureControlClass := ""
        this.captureControlStyle := 0
        this.captureControlHandle := 0
        this.currentControlClass := ""
        this.currentControlStyle := 0
        this.currentControlHandle := 0
        this.isTargetElevated := false
        this.isHubElevated := false
        this.targetDestroyed := false
        this.processReplaced := false
        this.failCapture := false
        this.liveMetadataUnavailable := false
        this.failPaste := false
        this.failWait := false
        this.failRestore := false
        this.hasFocusDrift := false
    }

    CaptureBeforePalette() {
        this._captureCount += 1
        this._captured := false
        this._snapshot := ""
        if this.failCapture
            throw Error("Target capture failed")
        this._captured := true
        controlClass := this.captureControlClass
        if (controlClass = "")
            controlClass := this.isCustomControl ? "Chrome_RenderWidgetHostHWND1" : "Edit1"
        controlHandle := this.captureControlHandle
        if !controlHandle
            controlHandle := this.isCustomControl ? 400 : 300
        this.lastCapturedHandle := controlHandle
        this._snapshot := Map(
            "windowHandle", 100,
            "processId", 200,
            "controlHandle", controlHandle,
            "controlClass", controlClass,
            "controlStyle", this.captureControlStyle,
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
        if !targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because the focused control handle is unavailable")
        if IsPasswordControl(targetSnapshot["controlClass"], targetSnapshot["controlStyle"])
            throw Error("Snippet insertion is blocked for password controls")
        if this.isTargetElevated && !this.isHubElevated
            throw Error("Snippet insertion is blocked for elevated targets")
        if this.hasFocusDrift && !this.isCustomControl
            throw Error("Snippet insertion is blocked because focus changed before input")
        currentMetadata := this.ReadCurrentControlMetadata(targetSnapshot["windowHandle"], targetSnapshot["controlHandle"], targetSnapshot["controlClass"])
        ValidateCurrentControlMetadata(
            targetSnapshot,
            currentMetadata["controlClass"],
            currentMetadata["controlStyle"],
            currentMetadata["styleAvailable"]
        )
        currentHandle := this.currentControlHandle ? this.currentControlHandle : targetSnapshot["controlHandle"]
        if currentHandle != targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because focus changed before input")
        return targetSnapshot
    }

    ReadCurrentControlMetadata(windowHandle, controlHandle, fallbackClass := "") {
        if this.liveMetadataUnavailable
            throw Error("Snippet insertion target live metadata is unavailable")
        currentControlClass := this.currentControlClass = "" ? fallbackClass : this.currentControlClass
        return Map(
            "controlClass", currentControlClass,
            "controlStyle", this.currentControlStyle,
            "styleAvailable", true
        )
    }

    ConfirmSafeTarget(targetSnapshot) {
        if !IsObject(targetSnapshot) || !targetSnapshot.Has("windowHandle")
            throw Error("Snippet insertion target snapshot is invalid")
        if this.targetDestroyed
            throw Error("Snippet insertion target no longer exists")
        if this.processReplaced
            throw Error("Snippet insertion target process changed")
        if IsPasswordControl(targetSnapshot["controlClass"], targetSnapshot["controlStyle"])
            throw Error("Snippet insertion is blocked for password controls")
        if this.isTargetElevated && !this.isHubElevated
            throw Error("Snippet insertion is blocked for elevated targets")
        if this.hasFocusDrift && !this.isCustomControl
            throw Error("Snippet insertion is blocked because focus changed before input")
        currentMetadata := this.ReadCurrentControlMetadata(targetSnapshot["windowHandle"], targetSnapshot["controlHandle"], targetSnapshot["controlClass"])
        ValidateCurrentControlMetadata(
            targetSnapshot,
            currentMetadata["controlClass"],
            currentMetadata["controlStyle"],
            currentMetadata["styleAvailable"]
        )
        currentHandle := this.currentControlHandle ? this.currentControlHandle : targetSnapshot["controlHandle"]
        if currentHandle != targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because focus changed before input")
        return true
    }

    WaitForPasteHandoff() {
        this._events.Push("wait")
        if this.failWait
            throw Error("Wait failed")
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
        if this.failRestore
            throw Error("Restore failed")
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

class FakeWinEventApi {
    __New() {
        this._nextHook := 1000
        this._registrations := []
        this.installCount := 0
        this.uninstallCount := 0
        this.uninstallAttempts := 0
        this.failUninstall := false
    }

    Install(windowHandle, processId, controlHandle, callback) {
        this.installCount += 1
        registration := Map(
            "hook", this._nextHook,
            "windowHandle", windowHandle,
            "processId", processId,
            "controlHandle", controlHandle,
            "callback", callback,
            "uninstalled", false,
            "callbackFreed", false
        )
        this._nextHook += 1
        this._registrations.Push(registration)
        return registration
    }

    Uninstall(registration) {
        this.uninstallAttempts += 1
        if this.failUninstall
            throw Error("Uninstall failed")
        this.uninstallCount += 1
        registration["uninstalled"] := true
        registration["callbackFreed"] := true
        return true
    }

    RaiseDestroy(registration, destroyedHandle, objectId := 0, childId := 0, event := 0x8001) {
        registration["callback"](
            registration["hook"],
            event,
            destroyedHandle,
            objectId,
            childId,
            0,
            0
        )
    }
}

class FakeWin32InputBoundary {
    __New() {
        this.adapter := ""
        this._activeWindow := 100
        this._processId := 200
        this._controlHandle := 300
        this._controlClass := "Edit"
        this._controlStyle := 0
        this.sendTextCount := 0
        this.pasteCount := 0
        this.sendTextWhileWatched := false
        this.pasteWhileWatched := false
        this.failSendText := false
    }

    ActiveWindow() {
        return this._activeWindow
    }

    WindowExists(windowHandle) {
        return windowHandle = this._activeWindow
    }

    ProcessId(windowHandle) {
        return windowHandle = this._activeWindow ? this._processId : 0
    }

    GetFocusedControlHandle(windowHandle) {
        return windowHandle = this._activeWindow ? this._controlHandle : 0
    }

    IsDescendantOfWindow(controlHandle, windowHandle) {
        return controlHandle = this._controlHandle && windowHandle = this._activeWindow
    }

    GetWindowClassName(controlHandle) {
        return controlHandle = this._controlHandle ? this._controlClass : ""
    }

    GetWindowStyle(controlHandle) {
        return controlHandle = this._controlHandle ? this._controlStyle : 0
    }

    Activate(windowHandle) {
        this._activeWindow := windowHandle
    }

    WaitActive(windowHandle, timeoutSeconds := 1) {
        return windowHandle = this._activeWindow
    }

    Focus(controlHandle, windowHandle) {
        this._controlHandle := controlHandle
        this._activeWindow := windowHandle
    }

    TargetProcessIsElevated(processId) {
        return false
    }

    CurrentProcessIsElevated() {
        return false
    }

    SendTextToTarget(text) {
        this.sendTextCount += 1
        this.sendTextWhileWatched := IsObject(this.adapter)
            && IsObject(this.adapter.destroyWatcher.registration)
        this.lastText := String(text)
        if this.failSendText
            throw Error("Input failed")
    }

    PasteToTarget() {
        this.pasteCount += 1
        this.pasteWhileWatched := IsObject(this.adapter)
            && IsObject(this.adapter.destroyWatcher.registration)
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

adapter.captureControlStyle := 0x20
adapter.CaptureBeforePalette()
AssertThrows(() => service.Insert("multi"), "blocks password controls")
AssertEqual("before", adapter.ClipboardText(), "does not alter clipboard for password controls")

livePasswordAdapter := FakeInputAdapter("before")
livePasswordAdapter.captureControlClass := "Edit1"
livePasswordAdapter.captureControlStyle := 0
livePasswordAdapter.CaptureBeforePalette()
livePasswordAdapter.currentControlClass := "Edit1"
livePasswordAdapter.currentControlStyle := 0x20
livePasswordService := SnippetService(Map("multi", "line 1`nline 2"), livePasswordAdapter)
AssertThrows(() => livePasswordService.Insert("multi"), "blocks a captured standard control that becomes password-protected")
AssertEqual(0, livePasswordAdapter.PasteCount(), "does not paste into a live password metadata drift")
AssertEqual("", livePasswordAdapter.InsertedText(), "does not leak snippet text after live password metadata drift")
AssertEqual("before", livePasswordAdapter.ClipboardText(), "restores clipboard after live password metadata drift")

classDriftAdapter := FakeInputAdapter("before")
classDriftAdapter.captureControlClass := "Edit1"
classDriftAdapter.CaptureBeforePalette()
classDriftAdapter.currentControlClass := "Button1"
classDriftService := SnippetService(Map("multi", "line 1`nline 2"), classDriftAdapter)
AssertThrows(() => classDriftService.Insert("multi"), "blocks standard control handle reuse with class drift")
AssertEqual(0, classDriftAdapter.PasteCount(), "does not paste after standard class metadata drift")
AssertEqual("", classDriftAdapter.InsertedText(), "does not leak snippet text after standard class metadata drift")
AssertEqual("before", classDriftAdapter.ClipboardText(), "restores clipboard after standard class metadata drift")

styleDriftAdapter := FakeInputAdapter("before")
styleDriftAdapter.captureControlClass := "Edit1"
styleDriftAdapter.captureControlStyle := 0
styleDriftAdapter.CaptureBeforePalette()
styleDriftAdapter.currentControlClass := "Edit1"
styleDriftAdapter.currentControlStyle := 0x40
styleDriftService := SnippetService(Map("multi", "line 1`nline 2"), styleDriftAdapter)
AssertThrows(() => styleDriftService.Insert("multi"), "blocks standard control handle reuse with style drift")
AssertEqual(0, styleDriftAdapter.PasteCount(), "does not paste after standard style metadata drift")
AssertEqual("", styleDriftAdapter.InsertedText(), "does not leak snippet text after standard style metadata drift")
AssertEqual("before", styleDriftAdapter.ClipboardText(), "restores clipboard after standard style metadata drift")

customAdapter := FakeInputAdapter("before")
customAdapter.isCustomControl := true
customAdapter.CaptureBeforePalette()
customService := SnippetService(Map("multi", "line 1\nline 2"), customAdapter)
customService.Insert("multi")
AssertEqual("line 1`nline 2", customAdapter.InsertedText(), "pastes multiline text into custom controls")
AssertEqual(400, customAdapter.lastCapturedHandle, "captures an exact focused HWND for custom controls")

customFocusDriftAdapter := FakeInputAdapter("before")
customFocusDriftAdapter.isCustomControl := true
customFocusDriftAdapter.CaptureBeforePalette()
customFocusDriftAdapter.currentControlHandle := 401
customFocusDriftService := SnippetService(Map("multi", "line 1`nline 2"), customFocusDriftAdapter)
AssertThrows(() => customFocusDriftService.Insert("multi"), "blocks focus drift for custom controls")
AssertEqual(0, customFocusDriftAdapter.PasteCount(), "does not paste after custom focus drift")

customMetadataFailureAdapter := FakeInputAdapter("before")
customMetadataFailureAdapter.isCustomControl := true
customMetadataFailureAdapter.CaptureBeforePalette()
customMetadataFailureAdapter.liveMetadataUnavailable := true
customMetadataFailureService := SnippetService(Map("multi", "line 1`nline 2"), customMetadataFailureAdapter)
AssertThrows(() => customMetadataFailureService.Insert("multi"), "fails closed when custom live metadata is unavailable")
AssertEqual(0, customMetadataFailureAdapter.PasteCount(), "does not paste without custom live metadata")
AssertEqual("", customMetadataFailureAdapter.InsertedText(), "does not leak text when custom metadata is unavailable")
AssertEqual("before", customMetadataFailureAdapter.ClipboardText(), "restores clipboard after custom metadata failure")

liveCredentialCustomAdapter := FakeInputAdapter("before")
liveCredentialCustomAdapter.isCustomControl := true
liveCredentialCustomAdapter.CaptureBeforePalette()
liveCredentialCustomAdapter.currentControlClass := "CredentialInput"
liveCredentialCustomService := SnippetService(Map("multi", "line 1`nline 2"), liveCredentialCustomAdapter)
AssertThrows(() => liveCredentialCustomService.Insert("multi"), "blocks a custom control that becomes credential-like")
AssertEqual(0, liveCredentialCustomAdapter.PasteCount(), "does not paste into a live credential-like custom control")
AssertEqual("", liveCredentialCustomAdapter.InsertedText(), "does not leak snippet text after live custom credential metadata drift")
AssertEqual("before", liveCredentialCustomAdapter.ClipboardText(), "restores clipboard after live custom credential metadata drift")

metadataAdapter := Win32InputAdapter()
safeCustomSnapshot := Map(
    "windowHandle", 100,
    "processId", 200,
    "controlHandle", 400,
    "controlClass", "Chrome_RenderWidgetHostHWND1",
    "controlStyle", 0,
    "isStandardControl", false
)
metadataAdapter.ValidateTargetSnapshot(safeCustomSnapshot, true)
missingCustomHandleSnapshot := Map(
    "windowHandle", 100,
    "processId", 200,
    "controlHandle", 0,
    "controlClass", "Chrome_RenderWidgetHostHWND1",
    "controlStyle", 0,
    "isStandardControl", false
)
AssertThrows(() => metadataAdapter.ValidateTargetSnapshot(missingCustomHandleSnapshot, true), "blocks custom snapshots without an exact focused HWND")
credentialCustomSnapshot := Map(
    "windowHandle", 100,
    "processId", 200,
    "controlHandle", 400,
    "controlClass", "CredentialInput",
    "controlStyle", 0,
    "isStandardControl", false
)
AssertThrows(() => metadataAdapter.ValidateTargetSnapshot(credentialCustomSnapshot, true), "blocks credential-like custom controls from snapshot metadata")
passwordStyleCustomSnapshot := Map(
    "windowHandle", 100,
    "processId", 200,
    "controlHandle", 400,
    "controlClass", "Chrome_RenderWidgetHostHWND1",
    "controlStyle", 0x20,
    "isStandardControl", false
)
AssertThrows(() => metadataAdapter.ValidateTargetSnapshot(passwordStyleCustomSnapshot, true), "blocks password-style custom controls from snapshot metadata")

watchApi := FakeWinEventApi()
targetWatcher := SnippetTargetWatcher(watchApi)
firstGeneration := targetWatcher.Replace(100, 200, 300)
firstRegistration := watchApi._registrations[1]
firstStandardSnapshot := Map("windowHandle", 100, "controlHandle", 300, "controlClass", "Edit", "controlStyle", 0)
recreatedStandardSnapshot := Map("windowHandle", 100, "controlHandle", 300, "controlClass", "Edit", "controlStyle", 0)
AssertTrue(SameSnippetTarget(firstStandardSnapshot, recreatedStandardSnapshot), "models identical metadata after standard target recreation")
watchApi.RaiseDestroy(firstRegistration, 300)
AssertTrue(targetWatcher.IsInvalidated(firstGeneration), "invalidates a standard target destroyed and recreated with identical metadata")
targetWatcher.Release(firstGeneration)
AssertEqual(1, watchApi.uninstallCount, "cleans up the one-shot destroy watcher after target consumption")

secondGeneration := targetWatcher.Replace(100, 200, 300)
secondRegistration := watchApi._registrations[2]
watchApi.RaiseDestroy(firstRegistration, 300)
AssertFalse(targetWatcher.IsInvalidated(secondGeneration), "ignores stale destroy callbacks after watcher replacement")
watchApi.RaiseDestroy(secondRegistration, 300)
AssertTrue(targetWatcher.IsInvalidated(secondGeneration), "tracks destruction for the replacement target generation")
targetWatcher.Release(secondGeneration)
AssertEqual(2, watchApi.uninstallCount, "cleans up the replacement watcher")

subobjectWatcher := SnippetTargetWatcher(watchApi)
subobjectGeneration := subobjectWatcher.Replace(100, 200, 300)
subobjectRegistration := watchApi._registrations[3]
watchApi.RaiseDestroy(subobjectRegistration, 100, 1, 0)
AssertFalse(subobjectWatcher.IsInvalidated(subobjectGeneration), "ignores non-window accessibility object destruction")
watchApi.RaiseDestroy(subobjectRegistration, 100, 0, 1)
AssertFalse(subobjectWatcher.IsInvalidated(subobjectGeneration), "ignores child accessibility object destruction")
watchApi.RaiseDestroy(subobjectRegistration, 100, 0, 0, 0x8000)
AssertFalse(subobjectWatcher.IsInvalidated(subobjectGeneration), "ignores non-destroy accessibility events")
watchApi.RaiseDestroy(subobjectRegistration, 100, 0, 0)
AssertTrue(subobjectWatcher.IsInvalidated(subobjectGeneration), "accepts exact top-level window destruction")
subobjectWatcher.Release(subobjectGeneration)
AssertEqual(3, watchApi.uninstallCount, "cleans up the object-filtered watcher")

failedReleaseApi := FakeWinEventApi()
failedReleaseWatcher := SnippetTargetWatcher(failedReleaseApi)
failedReleaseGeneration := failedReleaseWatcher.Replace(100, 200, 300)
failedReleaseRegistration := failedReleaseApi._registrations[1]
failedReleaseApi.failUninstall := true
AssertFalse(failedReleaseWatcher.Release(failedReleaseGeneration), "reports a watcher uninstall failure")
AssertTrue(IsObject(failedReleaseWatcher.registration), "retains registration after uninstall failure")
AssertFalse(failedReleaseRegistration["uninstalled"], "does not discard the hook after uninstall failure")
AssertFalse(failedReleaseRegistration["callbackFreed"], "does not free the callback after unhook failure")
failedReleaseApi.failUninstall := false
AssertTrue(failedReleaseWatcher.Release(failedReleaseGeneration), "retries watcher cleanup deterministically")
AssertEqual(2, failedReleaseApi.uninstallAttempts, "retries the retained watcher registration")
AssertTrue(failedReleaseRegistration["callbackFreed"], "frees the callback only after successful unhook")

productionWatchApi := FakeWinEventApi()
productionBoundary := FakeWin32InputBoundary()
productionAdapter := Win32InputAdapter(0, productionWatchApi, productionBoundary)
productionBoundary.adapter := productionAdapter
productionSnapshot := productionAdapter.CaptureBeforePalette()
productionAdapter.EnsureSafeTarget()
AssertTrue(IsObject(productionAdapter.destroyWatcher.registration), "keeps production watcher through target restoration")
productionAdapter.SendText(productionSnapshot, "safe")
AssertTrue(productionBoundary.sendTextWhileWatched, "keeps production watcher through final confirmation and direct input")
productionAdapter.CompleteTarget(productionSnapshot)
AssertFalse(IsObject(productionAdapter.destroyWatcher.registration), "releases production watcher after direct input attempt")

productionPasteWatchApi := FakeWinEventApi()
productionPasteBoundary := FakeWin32InputBoundary()
productionPasteAdapter := Win32InputAdapter(0, productionPasteWatchApi, productionPasteBoundary)
productionPasteBoundary.adapter := productionPasteAdapter
productionPasteSnapshot := productionPasteAdapter.CaptureBeforePalette()
productionPasteAdapter.EnsureSafeTarget()
productionPasteAdapter.Paste(productionPasteSnapshot)
AssertTrue(productionPasteBoundary.pasteWhileWatched, "keeps production watcher through final confirmation and paste input")
productionPasteAdapter.CompleteTarget(productionPasteSnapshot)
AssertFalse(IsObject(productionPasteAdapter.destroyWatcher.registration), "releases production watcher after paste input attempt")

cleanupPrecedenceWatchApi := FakeWinEventApi()
cleanupPrecedenceBoundary := FakeWin32InputBoundary()
cleanupPrecedenceAdapter := Win32InputAdapter(0, cleanupPrecedenceWatchApi, cleanupPrecedenceBoundary)
cleanupPrecedenceBoundary.adapter := cleanupPrecedenceAdapter
cleanupPrecedenceAdapter.CaptureBeforePalette()
cleanupPrecedenceBoundary.failSendText := true
cleanupPrecedenceWatchApi.failUninstall := true
cleanupPrecedenceService := SnippetService(Map("single", "safe"), cleanupPrecedenceAdapter)
AssertThrowsWithMessage(
    () => cleanupPrecedenceService.Insert("single"),
    "Input failed",
    "preserves the primary input error when watcher cleanup also fails"
)
AssertTrue(IsObject(cleanupPrecedenceAdapter.destroyWatcher.registration), "retains the watcher after cleanup failure during input")
cleanupPrecedenceWatchApi.failUninstall := false
cleanupPrecedenceBoundary.failSendText := false
AssertTrue(cleanupPrecedenceAdapter.destroyWatcher.Release(), "allows watcher cleanup retry after the primary error")

boundedWatcher := SnippetTargetWatcher(watchApi, 30000)
boundedGeneration := boundedWatcher.Replace(100, 200, 300)
boundedWatcher.Expire(boundedGeneration)
AssertThrows(() => boundedWatcher.IsInvalidated(boundedGeneration), "expires a watcher that outlives a cancelled palette")
AssertEqual(4, watchApi.uninstallCount, "cleans up an expired watcher")

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

primaryCleanupAdapter := FakeInputAdapter("before")
primaryCleanupAdapter.failPaste := true
primaryCleanupAdapter.failWait := true
primaryCleanupAdapter.failRestore := true
primaryCleanupAdapter.CaptureBeforePalette()
primaryCleanupService := SnippetService(Map("multi", "line 1`nline 2"), primaryCleanupAdapter)
AssertThrowsWithMessage(
    () => primaryCleanupService.Insert("multi"),
    "Paste failed",
    "preserves the primary paste failure when both cleanup steps fail"
)
AssertEqual("wait,restore", primaryCleanupAdapter.EventSummary(), "attempts wait then restore after a paste failure")
AssertEqual("before", primaryCleanupAdapter.ClipboardText(), "does not leak snippet content when cleanup reports failure")

waitCleanupAdapter := FakeInputAdapter("before")
waitCleanupAdapter.failWait := true
waitCleanupAdapter.failRestore := true
waitCleanupAdapter.CaptureBeforePalette()
waitCleanupService := SnippetService(Map("multi", "line 1`nline 2"), waitCleanupAdapter)
AssertThrowsWithMessage(
    () => waitCleanupService.Insert("multi"),
    "Wait failed",
    "uses wait failure as deterministic cleanup precedence"
)
AssertEqual("paste,wait,restore", waitCleanupAdapter.EventSummary(), "attempts restore even when wait fails")
AssertEqual("before", waitCleanupAdapter.ClipboardText(), "restores clipboard when cleanup errors are surfaced")

restoreCleanupAdapter := FakeInputAdapter("before")
restoreCleanupAdapter.failRestore := true
restoreCleanupAdapter.CaptureBeforePalette()
restoreCleanupService := SnippetService(Map("multi", "line 1`nline 2"), restoreCleanupAdapter)
AssertThrowsWithMessage(
    () => restoreCleanupService.Insert("multi"),
    "Restore failed",
    "surfaces restore failure when wait succeeds"
)
AssertEqual("paste,wait,restore", restoreCleanupAdapter.EventSummary(), "waits before attempting clipboard restoration")
AssertEqual("before", restoreCleanupAdapter.ClipboardText(), "does not leave snippet content after restore failure")

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

AssertThrowsWithMessage(callback, expectedMessage, message) {
    global TestFailures
    threw := false
    caughtMessage := ""
    try {
        callback()
    } catch as caughtError {
        threw := true
        caughtMessage := caughtError.Message
    }
    if !threw {
        TestFailures += 1
        FileAppend("FAIL: " message " (no exception)`n", "*")
        return
    }
    AssertEqual(expectedMessage, caughtMessage, message)
}
