# SPEC: Multiline Prompt Snippet

## Goal

Activate `snippet.multiline-prompt` for the window that was focused before the
command palette opened, including browser, IDE, Orca, Windows Terminal, and AI
CLI custom controls.

The complete approved design is
[`../docs/superpowers/specs/2026-08-15-multiline-snippet-target-handoff-design.md`](../docs/superpowers/specs/2026-08-15-multiline-snippet-target-handoff-design.md).

## Requirements

- Read the fixed body from `[Snippets] multiline-prompt` in the local INI.
- Capture the intended window before the palette takes focus.
- Hide the palette before command invocation and restore the captured window.
- Paste multiline content once, then restore the previous clipboard.
- Support general custom input controls without an application allow list.
- Continue blocking known password controls and unsafe elevation boundaries.
- Abort when the captured window is destroyed, replaced, or cannot be safely
  restored; never fall back to whichever window becomes active.
- Apply the same target handoff to single-line snippets so the palette search
  field never receives snippet content.

## Technical design

- Add an injected target-handoff capability shared by `CommandPalette` and
  `SnippetService`.
- Store window/process/control metadata only; never store field text.
- Treat an exact standard control as a strict identity boundary. For custom
  controls, validate the captured window and process identity.
- Keep multiline insertion as a clipboard transaction with a bounded post-paste
  handoff delay and unconditional restoration in `finally`.
- Preserve optional injected fakes for headless tests.

## Test plan

- RED first: palette capture/hide order and captured-target insertion.
- Verify custom controls succeed and standard password/elevation checks fail.
- Verify destroyed/replaced windows and standard-control drift send no input.
- Verify multiline paste ordering and clipboard restoration on success/failure.
- Verify single-line snippets use the pre-palette target.
- Run focused `core` and `snippets` tests, then the full AutoHotkey suite and
  PowerShell parser.
- Perform manual QA in disposable fields only: Notepad, browser textarea,
  VS Code, Windows Terminal, Orca/AI CLI, and one known password field.

## Out of scope

- Custom password-field detection, application allow lists, prompt editing,
  variables, history, sync, and automatic prompt submission.
