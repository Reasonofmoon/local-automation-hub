# Multiline target identity hardening report

Date: 2026-08-15 (Asia/Seoul)
Repository: `C:\Users\sound\Documents\ChatGPT\autohotkey`

## Scope

This remediation stayed within the delegated product/test files:

- `src/modules/Snippets.ahk`
- `tests/snippets-tests.ahk`

The report is untracked SDD evidence. No `main.ahk`, palette, configuration,
documentation, real desktop target, or user clipboard was changed or used.

## RED evidence

Tests were extended first for exact custom HWND capture, unavailable live
metadata, same-metadata standard-control recreation, and watcher replacement.
Before the production watcher and Win32 identity implementation existed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets
```

The existing module validation passed, while the snippets test validation
timed out because the new `SnippetTargetWatcher` seam was not yet present.
This was the expected test-first failure; no production changes were used to
make the RED run pass.

## Implemented hardening

### Exact custom target identity

- `CaptureBeforePalette()` now rejects an unavailable target process or exact
  focused HWND.
- `ControlGetFocus`/`ControlGetHwnd` is supplemented by `GetGUIThreadInfo`.
- The captured HWND must belong to the captured top-level window; the code
  never falls back to a newly active window.
- Live class and style are queried from that exact HWND with
  `GetClassNameW` and `GetWindowLongPtrW`/`GetWindowLongW`.
- A missing live class/style fails closed for both standard and custom
  controls. Custom controls remain allowed when they have a valid focused
  HWND and readable live metadata.
- Focus is checked against the exact captured HWND immediately before input.
- Known password/credential classes and `ES_PASSWORD` transitions remain
  blocked for custom controls as well as standard controls.

### Same-HWND destruction/recreation

- `SnippetTargetWatcher` installs a one-shot `EVENT_OBJECT_DESTROY` WinEvent
  hook filtered to the captured process and exact top-level/control HWNDs.
- Each replacement receives a monotonically increasing capture generation.
  Stale callbacks from an older registration cannot invalidate a newer
  capture even when HWND/class/style values are identical.
- The watcher is released on target replacement, capture/restore failure,
  final pre-input confirmation, and successful/failing insertion cleanup.
  A 30-second one-shot expiry also bounds a palette that is cancelled without
  invoking a command. Cleanup failures are recorded and replacement fails
  closed.
- The watcher stores only local handles, process/generation metadata, and
  callback state; it stores no snippet text, clipboard content, credentials,
  or terminal content.

## TDD and validation evidence

Focused cross-module run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets,core,main-startup
```

Result: exit `0`; all 3 selected test files passed.

Full automated run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

Result: exit `0`; all 8 AHK test files passed and all selected modules
validated.

PowerShell parser:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
```

Result: exit `0`; 8 PowerShell files parsed.

Main validation used a bounded `System.Diagnostics.Process` wrapper so a
validation process could not linger:

```text
MAIN_VALIDATE_EXIT=0
REMAINING_AHK=
```

The final full test/Powershell run had no AutoHotkey process before or after
the run. `git diff --check` reported no whitespace errors; Git emitted only
its normal LF-to-CRLF working-tree notices.

## Test coverage added

- Custom controls use a nonzero focused HWND.
- Custom focus drift is blocked.
- Custom live metadata lookup failure is blocked and clipboard/text state is
  safe.
- Custom snapshots with `controlHandle=0` are rejected.
- A standard target with identical HWND/class/style after recreation is still
  invalidated by its destroy event.
- Old callbacks are ignored after watcher replacement.
- One-shot watcher cleanup is asserted for both the original and replacement
  generations.
- A cancelled-palette expiry releases its watcher and makes the old generation
  unusable.

## Boundary and uncertainty

No real browser, IDE, terminal, password field, WinEvent callback, or user
clipboard was exercised in this delegated headless run. The WinEvent lifecycle
and callback signature are covered through an injected fake API; bounded manual
UI QA remains the parent task's `not performed` boundary.
