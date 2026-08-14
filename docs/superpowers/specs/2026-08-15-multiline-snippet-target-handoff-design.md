# Multiline Snippet Target Handoff Design

**Date:** 2026-08-15  
**Status:** approved design, awaiting written-spec review

## 1. Goal

Make the configured `snippet.multiline-prompt` command paste its fixed multiline
body into the window that was active immediately before the command palette
opened. Support standard Windows text controls as well as browser, IDE, Orca,
and AI CLI custom input surfaces.

The feature remains configuration-driven. It does not open an editor, generate
prompt text, or send text to remote services by itself.

## 2. User flow

1. The user focuses the intended input surface.
2. The user opens the hub with `CapsLock + Space`.
3. The palette captures a target snapshot before taking focus.
4. The user selects `snippet.multiline-prompt`.
5. The palette hides before command invocation.
6. The hub restores and validates the captured window.
7. The configured multiline body is pasted once.
8. The original clipboard content is restored after a bounded handoff delay.

The same target handoff applies to single-line snippets so a snippet is never
typed into the palette's own search box.

## 3. Configuration contract

The fixed body continues to come from the local INI file:

```ini
[Snippets]
multiline-prompt=First line\nSecond line
```

`\n` is decoded to a real newline by the existing configuration/snippet
normalization path. No new prompt file format or template language is added.

## 4. Architecture

### 4.1 Target handoff capability

The palette receives an optional target-handoff dependency. The production
implementation is shared with `SnippetService`; tests use a fake.

The capability exposes two operations:

- capture the active target immediately before the palette is shown;
- restore and validate the captured target immediately before insertion.

The snapshot contains only local window metadata needed for validation:
window handle, process ID, focused-control handle/class/style when available,
and whether the original target exposed a standard control. It contains no
text, clipboard data, credentials, or terminal contents.

### 4.2 Palette behavior

`CommandPalette.Show()` captures the target before creating/focusing the
palette UI. `ExecuteSelection()` hides the palette before invoking the selected
command. If invocation fails, it reports the existing safe error through
`AppContext`; it does not paste into a fallback window.

Headless palette tests retain an optional no-op target dependency so existing
non-UI command tests remain isolated.

### 4.3 Snippet insertion

`SnippetService.Insert(id)` obtains only the previously captured target. It
must never treat the currently active palette window as a new insertion target.

- Single-line content uses direct text input after restoration.
- Multiline content uses the clipboard transaction because browser, IDE, and
  terminal custom controls handle paste more reliably than simulated typing.
- Clipboard restoration occurs in `finally`, including paste and focus errors.
- A short bounded delay after the paste chord gives asynchronous consumers time
  to read the temporary clipboard value before restoration.

## 5. Target validation and safety

The user selected broad custom-control support. The following boundaries remain
mandatory:

- reject a missing or destroyed captured window;
- reject a window whose current process ID differs from the captured process;
- reject an elevated target when the hub is not elevated;
- reject known standard password/credential controls;
- reject focus drift to a different standard control when an exact control was
  captured;
- never fall back to the newly active window when restoration fails;
- never insert into the hub palette itself;
- allow a custom surface when the captured general window still exists and its
  process identity matches.

Custom browser/IDE/terminal controls often do not expose password semantics.
Under the explicitly selected broad policy, those unknown controls are allowed.
The documentation must state that the user is responsible for focusing a
non-sensitive field before opening the palette.

## 6. Failure handling

Target capture, activation, validation, clipboard assignment, paste, and
clipboard restoration failures are returned through the existing command result
boundary. Error text is redacted by the existing safe error path.

No retry targets a different window. A failed activation or identity check
aborts without sending keystrokes. The clipboard backup is released after
restoration so it is not retained in service state.

## 7. Testing strategy

Use test-first changes with injected fakes.

Required focused tests:

- palette captures the original target before showing;
- palette hides before invoking a snippet command;
- multiline body decodes `\n` and pastes exactly once;
- browser/IDE/terminal-like custom controls are accepted;
- standard password controls remain blocked;
- elevated targets remain blocked;
- destroyed windows, process replacement, and standard-control focus drift are
  blocked without input;
- a failed paste still restores the original clipboard;
- delayed clipboard restoration occurs after the paste operation;
- single-line snippets use the captured target rather than the palette edit;
- repeated palette sessions replace stale snapshots instead of reusing them.

Run the focused snippet/core tests first, then the existing full AutoHotkey and
PowerShell validation gates. Manual QA uses disposable text in Notepad, one
browser textarea, VS Code, Windows Terminal, and an Orca AI CLI terminal. It
must also verify clipboard restoration and a blocked known password field.

## 8. Scope exclusions

- No OCR, accessibility-tree inspection, or browser extension.
- No automatic detection of custom password fields.
- No per-application allow list in this iteration.
- No prompt editor, prompt variables, history, cloud sync, or prompt sending.
- No changes to Orca workspace creation or AI-agent orchestration.

## 9. Acceptance criteria

- `snippet.multiline-prompt` inserts the configured two-or-more-line body into
  the window active before the palette opened.
- Notepad, browser text input, VS Code, Windows Terminal, Orca, and AI CLI custom
  input surfaces are supported under the broad general-window policy.
- The palette never receives the snippet text.
- Known password controls, unsafe elevation boundaries, destroyed/replaced
  windows, and verifiable focus drift fail closed.
- Clipboard contents are restored on both success and failure.
- Automated focused and regression gates pass before manual QA.
