# Multiline Prompt Snippet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `snippet.multiline-prompt` insert its configured fixed multiline body into the browser, IDE, Orca, Windows Terminal, AI CLI, or standard text window that was focused before the command palette opened.

**Architecture:** A single `Win32InputAdapter` instance becomes the target-handoff boundary shared by `CommandPalette` and `SnippetService`. The palette captures the pre-palette window and hides before invocation; the snippet service consumes that snapshot, restores and validates the exact window/process, then uses direct text for single-line content or a bounded clipboard transaction for multiline content.

**Tech Stack:** AutoHotkey v2.0 on Windows 11, INI configuration, existing headless AHK test runner, PowerShell validation scripts.

## Global Constraints

- Keep `multiline-prompt` configuration-driven through `[Snippets]`; do not add an editor or template language.
- Allow general custom controls without an application allow list, as explicitly selected by the user.
- Continue blocking known standard password controls and non-elevated-hub to elevated-target input.
- Never fall back to the currently active window when the captured target is unavailable or replaced.
- Store only window/process/control metadata; never store field text, credentials, or terminal content.
- Restore the original clipboard on success and failure.
- Use AutoHotkey v2 syntax and avoid identifiers that differ from class names only by case.
- Read every owned file immediately before editing it; do not revert unrelated user changes or `.superpowers/` artifacts.
- Use Conventional Commit messages and one logical commit per task.

## File map

- Modify `src/core/Palette.ahk`: accept the optional target-handoff capability, capture before display, and hide before command invocation.
- Modify `src/modules/Snippets.ahk`: store/consume target snapshots, restore/validate standard and custom targets, and delay clipboard restoration until paste handoff.
- Modify `main.ahk`: construct one `Win32InputAdapter` and share it between palette and snippet service.
- Modify `tests/core-tests.ahk`: verify capture and hide-before-invoke ordering without real input.
- Modify `tests/snippets-tests.ahk`: verify custom surfaces, stale/replaced targets, exact standard controls, paste ordering, and clipboard restoration.
- Modify `tests/main-startup-tests.ahk`: verify headless composition still registers snippet commands with the new shared dependency.
- Modify `config/settings.example.ini`: document the fixed multiline value and literal `\n` convention.
- Modify `README.md`: document the command, supported target classes, and the broad custom-field risk.
- Modify `docs/harness/manifest.md`: record the target-handoff contract and fail-closed boundaries.
- Add `docs/harness/runs/2026-08-15-multiline-prompt/verification.md`: record automated evidence and the bounded manual QA result.

---

### Task 1: Palette target capture and hide-before-invoke

**Files:**
- Modify: `src/core/Palette.ahk`
- Modify: `tests/core-tests.ahk`

**Interfaces:**
- Consumes: optional object with `CaptureBeforePalette()`.
- Produces: `CommandPalette(registry, context, targetHandoff := unset)`, `CommandPalette.CaptureTargetBeforeShow()`, and the guarantee that `isVisible=false` before `registry.Invoke(...)` starts.

- [x] **Step 1: Read the current palette and focused core tests**

```powershell
Get-Content -Raw src\core\Palette.ahk
Get-Content tests\core-tests.ahk | Select-Object -Skip 35 -First 100
git status --short
```

Expected: no product changes beyond work explicitly owned by this task; `.superpowers/` may remain untracked.

- [x] **Step 2: Add RED tests for capture and invocation ordering**

Add a fake target capability and an invocation probe to `tests/core-tests.ahk`:

```ahk
class FakePaletteTargetHandoff {
    __New(events) {
        this.events := events
        this.captureCount := 0
    }

    CaptureBeforePalette() {
        this.captureCount += 1
        this.events.Push("capture")
        return Map("windowHandle", 100)
    }
}

TrackPaletteVisibility(palette, events, *) {
    events.Push(palette.IsOpen() ? "invoke-visible" : "invoke-hidden")
    return "ok"
}
```

Exercise the wished-for API without displaying a real GUI:

```ahk
paletteEvents := []
paletteTarget := FakePaletteTargetHandoff(paletteEvents)
targetRegistry := CommandRegistry()
targetPalette := CommandPalette(targetRegistry, context, paletteTarget)
targetRegistry.Register(
    "snippet.target-test",
    "Snippet target test",
    ["snippet"],
    "low",
    TrackPaletteVisibility.Bind(targetPalette, paletteEvents)
)

targetPalette.CaptureTargetBeforeShow()
AssertEqual(1, paletteTarget.captureCount, "captures the target before palette display")
targetPalette.SetQuery("target")
targetPalette.isVisible := true
targetPalette.ExecuteSelection()
AssertEqual("capture", paletteEvents[1], "captures before invocation")
AssertEqual("invoke-hidden", paletteEvents[2], "hides palette before command invocation")
```

- [x] **Step 3: Run the focused RED test**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only core
```

Expected: FAIL because the third `CommandPalette` constructor argument and `CaptureTargetBeforeShow()` do not exist, or because invocation observes `invoke-visible`.

- [x] **Step 4: Implement the minimal palette boundary**

Update the constructor and add the capture method:

```ahk
class CommandPalette {
    __New(registry, context, targetHandoff := unset) {
        this.registry := registry
        this.context := context
        this.targetHandoff := IsSet(targetHandoff) ? targetHandoff : ""
        if IsObject(this.targetHandoff) && !HasMethod(this.targetHandoff, "CaptureBeforePalette")
            throw TypeError("Palette target handoff must provide CaptureBeforePalette")
        this.query := ""
        this.results := []
        this.selectedIndex := 0
        this.isVisible := false
        this.gui := false
        this.editControl := false
        this.listView := false
        this.keyHandler := ObjBindMethod(this, "HandleKeyDown")
        this.SetQuery("")
    }

    CaptureTargetBeforeShow() {
        if IsObject(this.targetHandoff) {
            try return this.targetHandoff.CaptureBeforePalette()
            catch as caughtError {
                this.context.Notify(SafeErrorMessage(caughtError), "warn")
            }
        }
        return ""
    }
}
```

Call it as the first action of `Show()`:

```ahk
Show() {
    this.CaptureTargetBeforeShow()
    this.EnsureGui()
    this.SetQuery("")
    this.editControl.Value := ""
    this.RenderResults()
    this.gui.Show()
    this.editControl.Focus()
    this.isVisible := true
    return true
}
```

Hide before invocation and do not fall through to a second hide:

```ahk
command := this.results[this.selectedIndex]
this.Hide()
try result := this.registry.Invoke(command["id"], this.context)
catch as caughtError {
    this.context.Notify(SafeErrorMessage(caughtError), "error")
    return Map("success", false, "error", SafeErrorMessage(caughtError))
}

if IsObject(result) && result is Map && result.Has("success") && !result["success"]
    this.context.Notify(result.Has("error") ? result["error"] : "Command failed", "error")
return result
```

- [ ] **Step 5: Run GREEN and syntax validation**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only core
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate src\core\Palette.ahk
```

Expected: focused runner PASS and validation exit 0 with no modal error.

Evidence note: the focused core runner passed, but the Task 1 report records
that standalone `src\core\Palette.ahk /Validate` remained resident because of
the file's `OnMessage()` handler and had to be terminated. This step therefore
remains unchecked; the concern is not treated as a validation PASS.

- [x] **Step 6: Review and commit Task 1**

```powershell
git diff --check
git diff -- src/core/Palette.ahk tests/core-tests.ahk
git add src/core/Palette.ahk tests/core-tests.ahk
git commit -m "fix: preserve palette invocation target"
```

Expected: one commit containing only the palette boundary and focused tests.

---

### Task 2: Captured target restoration for standard and custom controls

**Files:**
- Modify: `src/modules/Snippets.ahk`
- Modify: `tests/snippets-tests.ahk`

**Interfaces:**
- Consumes: `CommandPalette` calls `Win32InputAdapter.CaptureBeforePalette()`.
- Produces: `Win32InputAdapter.CaptureBeforePalette()`, `Win32InputAdapter.EnsureSafeTarget()`, and target snapshot keys `windowHandle`, `processId`, `controlHandle`, `controlClass`, `controlStyle`, `isStandardControl`.
- Preserves: `SnippetService.Insert(id)`, `SendText(targetSnapshot, text)`, `Paste(targetSnapshot)`, and clipboard capture/restore contracts.

- [x] **Step 1: Read the current snippet service and tests immediately before editing**

```powershell
Get-Content -Raw src\modules\Snippets.ahk
Get-Content -Raw tests\snippets-tests.ahk
git status --short
```

- [x] **Step 2: Extend the fake adapter with capture, custom-target, identity, and operation-order state**

Replace the fake's implicit always-safe target with an explicit captured target:

```ahk
class FakeInputAdapter {
    __New(clipboardText := "") {
        this._clipboardText := clipboardText
        this._insertedText := ""
        this._directText := ""
        this._pasteCount := 0
        this._captureCount := 0
        this._captured := false
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
        if !IsObject(targetSnapshot)
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
}
```

Update the existing fake paste/restore methods to expose ordering:

```ahk
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

EventSummary() {
    result := ""
    for index, eventName in this._events
        result .= (index = 1 ? "" : ",") eventName
    return result
}
```

- [x] **Step 3: Add RED tests for custom controls and fail-closed identity checks**

Before every direct `Insert(...)` in the focused tests, call `adapter.CaptureBeforePalette()`.

Add these cases:

```ahk
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
```

Add an event-order assertion:

```ahk
AssertEqual("paste,wait,restore", adapter.EventSummary(), "waits for paste handoff before clipboard restoration")
```

Use this repeated-session regression to prove that the second capture replaces the first snapshot and an insertion consumes it once:

```ahk
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
```

- [x] **Step 4: Run focused RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets
```

Expected: FAIL because production lacks `CaptureBeforePalette()`, custom controls are rejected, or clipboard restoration occurs without `WaitForPasteHandoff()`.

- [x] **Step 5: Implement target snapshot capture in `Win32InputAdapter`**

Add state and capture without requiring a standard focused control:

```ahk
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
        focusedControl := ControlGetFocus("ahk_id " windowHandle)
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
            "isStandardControl", controlHandle && IsStandardTextControl(controlClass)
        )
        return this.capturedTarget
    }
}
```

- [x] **Step 6: Implement one-shot restore and validation**

Replace the old recapture-at-insert behavior:

```ahk
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

    if targetSnapshot["isStandardControl"]
        this.ValidateTargetSnapshot(targetSnapshot)

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
```

Do not call the old `CaptureTargetSnapshot()` during insertion and do not accept a different active window as a fallback.

Replace `ConfirmSafeTarget(targetSnapshot)` so the final check immediately before `SendText` or paste validates the already restored target without consuming another snapshot:

```ahk
ConfirmSafeTarget(targetSnapshot) {
    if !IsObject(targetSnapshot)
        throw Error("Snippet insertion target snapshot is invalid")
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

    if targetSnapshot["isStandardControl"] {
        this.ValidateTargetSnapshot(targetSnapshot)
        currentControl := ControlGetFocus("ahk_id " windowHandle)
        currentControlHandle := currentControl = "" ? 0 : ControlGetHwnd(currentControl, "ahk_id " windowHandle)
        if currentControlHandle != targetSnapshot["controlHandle"]
            throw Error("Snippet insertion is blocked because focus changed before input")
    }
    return true
}
```

- [x] **Step 7: Add bounded clipboard handoff before restoration**

In `SnippetService.Insert(id)`, change the multiline transaction to:

```ahk
savedClipboard := this.inputAdapter.CaptureClipboard()
try {
    this.inputAdapter.SetClipboardText(body)
    this.inputAdapter.Paste(targetSnapshot)
    this.inputAdapter.WaitForPasteHandoff()
} finally {
    this.inputAdapter.RestoreClipboard(savedClipboard)
    savedClipboard := ""
}
```

Add the production method:

```ahk
WaitForPasteHandoff() {
    if this.postPasteDelayMs > 0
        Sleep(this.postPasteDelayMs)
    return true
}
```

- [x] **Step 8: Run GREEN and module validation**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate src\modules\Snippets.ahk
```

Expected: focused runner PASS; module validation exit 0; no new AutoHotkey test process remains.

- [x] **Step 9: Review and commit Task 2**

```powershell
git diff --check
git diff -- src/modules/Snippets.ahk tests/snippets-tests.ahk
git add src/modules/Snippets.ahk tests/snippets-tests.ahk
git commit -m "feat: support custom snippet targets"
```

---

### Task 3: Shared production wiring and startup regression

**Files:**
- Modify: `main.ahk`
- Modify: `tests/main-startup-tests.ahk`

**Interfaces:**
- Consumes: `CommandPalette(registry, context, targetHandoff)` and `SnippetService(snippets, inputAdapter, context)`.
- Produces: exactly one `Win32InputAdapter` instance shared by the palette and snippet service during `InitializeHub(...)`.

- [x] **Step 1: Read composition and startup tests**

```powershell
Get-Content -Raw main.ahk
Get-Content -Raw tests\main-startup-tests.ahk
git status --short
```

- [x] **Step 2: Add RED composition assertions**

Expose the shared adapter in the returned headless hub map so the test can assert identity without invoking Windows input:

```ahk
hub := InitializeHub(A_ScriptDir "\..", false)
AssertTrue(hub.Has("inputAdapter"), "headless composition exposes the shared input adapter")
AssertTrue(hub["palette"].targetHandoff = hub["inputAdapter"], "palette shares the snippet input adapter")
AssertTrue(hub["registry"].Search("multiline-prompt").Length = 1, "registers multiline prompt snippet")
```

- [x] **Step 3: Run startup RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only main-startup
```

Expected: FAIL because the hub map lacks `inputAdapter` and the palette has no shared target handoff.

- [x] **Step 4: Wire one adapter instance**

In `InitializeHub(...)`:

```ahk
inputAdapter := Win32InputAdapter()
if (configLoadError = "") {
    RegisterBuiltInCommands(registry, context)
    snippets := SnippetService(config["Snippets"], inputAdapter, context)
    RegisterSnippetCommands(registry, snippets)
}
; Preserve Orca command registration.
palette := CommandPalette(registry, context, inputAdapter)
```

Return it for headless contract inspection:

```ahk
return Map(
    "context", context,
    "registry", registry,
    "palette", palette,
    "inputAdapter", inputAdapter
)
```

The diagnostics-only path still creates the inert adapter but registers no configured snippet commands.

- [x] **Step 5: Run GREEN, main validation, and focused cross-module tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only main-startup,core,snippets
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate main.ahk
```

Expected: three focused test files PASS and main validation exit 0.

- [x] **Step 6: Review and commit Task 3**

```powershell
git diff --check
git diff -- main.ahk tests/main-startup-tests.ahk
git add main.ahk tests/main-startup-tests.ahk
git commit -m "fix: wire snippet target handoff"
```

---

### Task 4: Documentation, automated gate, and manual QA boundary

**Files:**
- Modify: `config/settings.example.ini`
- Modify: `README.md`
- Modify: `docs/harness/manifest.md`
- Add: `docs/harness/runs/2026-08-15-multiline-prompt/verification.md`
- Modify: `tasks/PLAN-multiline-prompt.md`

**Interfaces:**
- Consumes: completed palette/snippet/main behavior from Tasks 1-3.
- Produces: user-facing usage/risk documentation and final verification evidence.

- [x] **Step 1: Document first use and the fixed configuration boundary**

The example config and README describe `snippet.multiline-prompt`, the
`CapsLock + Space` palette flow, the literal `\n` line-break convention, and
clipboard restoration.

- [x] **Step 2: Record the target-handoff correction pattern**

The harness manifest records capture-before-palette, hide-before-invoke,
identity restoration, broad custom-control policy, and fail-closed behavior.

- [x] **Step 3: Run the complete automated gate with fresh evidence**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate main.ahk
git diff --check
```

Expected: all AHK test files PASS, all PowerShell files parse, main validation exit 0, and diff check has no errors. Record exact counts and timestamps in the verification document.

- [x] **Step 4: Audit test-owned AutoHotkey processes**

Before and after the full gate, list only AutoHotkey processes whose command line contains this repository path when available. When WMI/CIM access is denied, use `Get-Process AutoHotkey*` as a documented fallback and never terminate an unidentified process.

Expected: no newly leaked test-owned process. Do not terminate pre-existing user AutoHotkey processes.

- [x] **Step 5: Record bounded manual QA status**

With the user present, place a harmless two-line prompt such as `alpha\nbeta` in the local config, restart the hub, and verify one insertion in each available surface:

1. Notepad standard edit.
2. Browser textarea on a disposable local/blank test page.
3. VS Code untitled editor.
4. Windows Terminal prompt without pressing Enter after paste.
5. Orca or another AI CLI input without submitting the prompt.
6. A known standard password control, which must be blocked.

After every multiline insertion, verify the clipboard still contains its pre-test sentinel. Do not paste credentials, do not press Enter in terminal/AI inputs, and do not use production forms.

This delegated headless run did not use real UI or the user clipboard, so the
insertion checks were not performed. Every surface is recorded as `not
performed` rather than claimed as passing; the user can run this bounded QA
later with disposable text and a clipboard sentinel.

- [x] **Step 6: Update verification evidence**

Record:

```markdown
| Surface | Result | Evidence |
| --- | --- | --- |
| Automated snippet target handoff | PASS/FAIL | focused/full command and count |
| Notepad | PASS/FAIL/not performed | two lines inserted; clipboard restored |
| Browser textarea | PASS/FAIL/not performed | disposable field only |
| VS Code | PASS/FAIL/not performed | untitled editor only |
| Windows Terminal | PASS/FAIL/not performed | pasted, not submitted |
| Orca/AI CLI | PASS/FAIL/not performed | pasted, not submitted |
| Standard password control | PASS/FAIL/not performed | insertion blocked |
```

- [x] **Step 7: Commit documentation and verification**

```powershell
git add config/settings.example.ini README.md docs/harness/manifest.md docs/harness/runs/2026-08-15-multiline-prompt/verification.md tasks/PLAN-multiline-prompt.md
git commit -m "docs: explain multiline snippet targets"
```

- [x] **Step 8: Final range and worktree audit**

```powershell
git log --oneline --decorate 5deb5cd..HEAD
git diff --check 5deb5cd..HEAD
git status --short --branch
```

Expected: the final branch range contains fifteen commits after the spec
commit `5deb5cd`: the planning commit `057029c`, thirteen implementation,
documentation, and review-driven hardening commits through product HEAD
`86b59f7`, and this final verification-doc commit. The thirteen commits after
`057029c` are retained as separate logical changes because the later review
passes corrected cleanup errors, live target metadata/identity, watcher
lifetime, and regression coverage. The committed-range diff is clean, and
only the intentional untracked `.superpowers/` reports remain.

## Completion gate

The feature is complete only when:

- the focused tests demonstrate RED before production changes and GREEN after;
- the pre-palette window/process identity is restored without fallback;
- custom browser/IDE/terminal surfaces are allowed under the approved broad policy;
- standard password and unsafe elevation boundaries still fail closed;
- clipboard restoration ordering is proven in tests;
- main composition shares exactly one target-handoff adapter;
- full automated gates pass with fresh output;
- manual surfaces are truthfully recorded as PASS, FAIL, or not performed;
- an independent review finds no Critical or Important issue.
