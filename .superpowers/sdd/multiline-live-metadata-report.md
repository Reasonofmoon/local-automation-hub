# Multiline live target metadata remediation

Date: 2026-08-15 (Asia/Seoul)
Repository: `C:\Users\sound\Documents\ChatGPT\autohotkey`

## Scope

This remediation is limited to the exact captured-control metadata check:

- `src/modules/Snippets.ahk`
- `tests/snippets-tests.ahk`

The report is untracked SDD evidence. No main wiring, configuration,
documentation, real UI, or user clipboard was changed or exercised.

## RED evidence

After adding the live password, class-drift, and style-drift cases to the fake
adapter, before adding the production helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets
```

Result: exit `1`; the snippets test process timed out because the new fake
called the not-yet-defined `ValidateCurrentControlMetadata` production seam.
This was the expected test-first failure.

## Implementation

`Win32InputAdapter.ConfirmSafeTarget()` now queries `ControlGetClassNN()` and
`ControlGetStyle()` using the captured exact control HWND (`ahk_id <control>`)
and the captured window (`ahk_id <window>`). It does not recapture the active
window. The existing window handle, process ID, active-window, elevation, and
standard-control focus checks remain in force.

`ValidateCurrentControlMetadata()` now:

- blocks current class names containing `password` or `credential`;
- blocks the current `ES_PASSWORD` style bit;
- for captured standard controls, requires the current class to remain a
  standard Edit/RichEdit class and requires exact captured class/style equality;
- allows ordinary custom controls when their current metadata is not
  detectable as credential/password metadata;
- fails closed for a standard control when current style metadata cannot be
  read, while preserving the approved broad custom-control policy.

The fake adapter now models current metadata separately from capture metadata.
Tests cover a safe standard Edit becoming password-protected, class drift,
style drift/handle reuse, and a custom control becoming credential-like. Each
case asserts zero paste count, no inserted snippet text, and clipboard
restoration.

## Validation evidence

Focused cross-module run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets,main-startup,core
```

Result: exit `0`; `3 test file(s)` passed.

Full AutoHotkey run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

Result: exit `0`; `8 test file(s)` passed.

Syntax and parser checks:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate src\modules\Snippets.ahk
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate main.ahk
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
git diff --check
```

Results: both AHK validations exit `0`; PowerShell parser reports `8
PowerShell file(s) parsed`; diff check reports no whitespace errors. The
post-run `Get-Process -Name 'AutoHotkey*'` audit returned no process.

## Remaining boundary

No real desktop control or user clipboard was touched. Manual insertion QA
remains the parent task's documented `not performed` boundary.
