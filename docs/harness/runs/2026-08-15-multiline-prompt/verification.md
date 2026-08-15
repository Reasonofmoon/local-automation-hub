# Multiline prompt snippet verification

Date: 2026-08-15 (Asia/Seoul)
Repository: `C:\Users\sound\Documents\ChatGPT\autohotkey`

## Scope and safety boundary

This report records the final automated gate for the fixed, configuration-driven
`snippet.multiline-prompt` flow. The implementation captures only the target
window/process/control metadata before the transient palette takes focus, then
restores and validates that same target before sending text or pasting. No
credential, field text, terminal content, user clipboard, production form, or
real UI target was used in this run.

Task 8 Kakao login automation remains unsupported and is outside this feature.
The existing capability record is [kakao-ui-capability.md](../2026-08-12-local-automation-hub/kakao-ui-capability.md).

## Implementation and focused evidence

The product implementation is at `86b59f7` (`test: cover snippet watcher
service cleanup`). The reviewed range after plan commit `057029c` contains
these 13 commits, in chronological order:

`bb617cd`, `3ce814b`, `3931e97`, `2f45d8e`, `6f11fc4`, `df5830e`, `f858767`,
`5f42050`, `c228c1c`, `c056c0d`, `08dfb71`, `497c73d`, `86b59f7`.

The last five commits (`c228c1c`, `c056c0d`, `08dfb71`, `497c73d`, and
`86b59f7`) are the review-driven cleanup, live-metadata/identity hardening,
watcher-lifetime correction, and regression-test additions made after the
earlier documentation checkpoint. The uncommitted `.superpowers/sdd/
multiline-task-*-report.md` files retain task-level RED, GREEN, review, and
remediation evidence.

Fresh focused headless evidence from `86b59f7`:

- `tests\Run-Tests.ps1 -Only snippets,core,main-startup` — PASS: 3 test files;
  palette capture/hide ordering, custom/standard target guards, clipboard
  handoff ordering, one shared adapter, and command registration.

The task reports also retain the expected RED runs before each production
change. The direct standalone palette `/Validate` command can remain resident
because `Palette.ahk` installs an `OnMessage` handler; the focused runner's
validation of the included file and `main.ahk /Validate` both completed without
that concern.

## Automated gate

All commands ran from the repository root. Timestamps are local ISO-8601 with
`+09:00` (Asia/Seoul).

| Timestamp | Command | Result |
| --- | --- | --- |
| 2026-08-15T10:50:10.2737689+09:00 → 2026-08-15T10:50:10.9653851+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets,core,main-startup` | Exit `0`; 3 selected AHK test files validated and printed `PASS`; aggregate `PASS: 3 test file(s)`. |
| 2026-08-15T10:51:36.5146880+09:00 → 2026-08-15T10:51:46.5185594+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1` | Exit `0`; seven AHK module validations and eight AHK test-file validations completed; all eight test files printed `PASS`; aggregate `PASS: 8 test file(s)`. |
| 2026-08-15T10:50:32.6389325+09:00 → 2026-08-15T10:50:32.9638386+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1` | Exit `0`; `PASS: 8 PowerShell file(s) parsed`. |
| 2026-08-15T10:51:01.7017967+09:00 → 2026-08-15T10:51:01.7692418+09:00 | `Start-Process AutoHotkey64.exe /ErrorStdOut=UTF-8 /Validate main.ahk -Wait -PassThru` | Exit `0`; no diagnostic output. |
| 2026-08-15T10:51:07.8434233+09:00 → 2026-08-15T10:51:07.8897613+09:00 | `git diff --check` (before documentation edits) | Exit `0`; no whitespace diagnostics. |

The full runner uses the repository's process-owned AutoHotkey runner and does
not open a palette or send input to a user window. The repository has no
TypeScript source or `tsconfig.json`; `npx tsc --noEmit` is not applicable.

## Forbidden-content scans

These read-only scans were limited to operational source, `main.ahk`, and the
public example configuration; test fixtures and documentation were not treated
as runtime secret storage.

| Timestamp | Command | Result |
| --- | --- | --- |
| 2026-08-15T10:51:18.2524623+09:00 → 2026-08-15T10:51:18.3210465+09:00 | `rg -n -i '(password|secret|credential)[[:space:]]*=[[:space:]]*[^;\r\n]+' src main.ahk config/settings.example.ini` | `rg` exit `1` (no matches); no operational secret assignment. |
| 2026-08-15T10:51:18.2524623+09:00 → 2026-08-15T10:51:18.3210465+09:00 | `rg -n -i 'ControlGetText|WinGetText|A_Clipboard.*(password|secret|credential)|SendText\(.*(password|secret|credential)' src main.ahk config/settings.example.ini` | `rg` exit `1` (no matches); no forbidden credential-content read/send pattern. |

The implementation does use the clipboard for a configured multiline body, but
does not store or log credentials, terminal content, or target field text.

## AutoHotkey process audit

The audit was read-only and filtered for this repository path when command-line
metadata was available. `Get-CimInstance Win32_Process` returned access denied,
so the documented fallback `Get-Process AutoHotkey*` was used. No unidentified
process was terminated and no pre-existing user process was touched.

| Phase | Timestamp | Method/result |
| --- | --- | --- |
| Before full gate | 2026-08-15T10:51:30.6020414+09:00 → 2026-08-15T10:51:30.7027926+09:00 | CIM unavailable (`액세스가 거부되었습니다.`); `Get-Process AutoHotkey*` fallback count `0`. |
| After full gate | 2026-08-15T10:51:54.8619791+09:00 → 2026-08-15T10:51:54.9564392+09:00 | CIM unavailable (`액세스가 거부되었습니다.`); fallback count `0`; no newly leaked test-owned process. |

## Manual UI QA

No real UI or user clipboard QA was performed in this delegated run. It would
require the user to place a harmless sentinel in the clipboard, focus disposable
inputs, and observe insertion without submitting a terminal or AI prompt. No
credential or production form was used.

| Surface | Result | Evidence |
| --- | --- | --- |
| Automated snippet target handoff | PASS | Focused core/snippet/startup suites above; full runner: eight test files PASS. |
| Notepad standard edit | not performed | No real GUI or clipboard interaction. |
| Browser textarea | not performed | No disposable browser field was used. |
| VS Code untitled editor | not performed | No real IDE target was used. |
| Windows Terminal | not performed | No terminal text was pasted or submitted. |
| Orca/AI CLI | not performed | No Orca/AI CLI input was touched. |
| Standard password control | not performed | No real password control was touched; automated fake/metadata guards passed in `snippets-tests.ahk`. |

## Remaining limitations

- Real target restoration and clipboard preservation remain user-owned manual QA;
  the automated coverage is headless and uses fake adapters.
- The standalone `src\core\Palette.ahk /Validate` persistence behavior noted in
  Task 1 remains a known validation quirk; the full runner and `main.ahk`
  validation passed, and the final process audit found no test-owned process.
- An independent whole-branch review is a parent-agent final gate and is not
  claimed by this document.
