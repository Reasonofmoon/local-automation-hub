# Orca AI development workspace verification

Date: 2026-08-13 (Asia/Seoul)
Repository: `C:\Users\sound\Documents\ChatGPT\autohotkey`

## Scope and safety boundary

This record covers the Task 3 documentation, fake-Orca contract, headless
AutoHotkey validation, PowerShell parsing, forbidden-operation scan, whitespace
check, PID audit, and read-only Orca readiness check. No real Orca mutation,
terminal creation, terminal wait, prompt transmission, Git worktree/branch
operation, folder picker, AI CLI launch, UI picker, or user repository change
was performed. The user did not select a disposable existing checkout in this
turn, so the manual scenario remains user-owned and not performed.

## Automated evidence

All commands ran from the repository root. Timestamps are local ISO-8601 with
`+09:00` (Asia/Seoul).

| Timestamp | Command | Result |
| --- | --- | --- |
| 2026-08-13T12:24:57.2055905+09:00 → 2026-08-13T12:25:23.5806533+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Open-OrcaAiWorkspace.Tests.ps1` | Exit `0`; `PASS: Orca AI workspace adapter`. Temporary Git checkout, fake Orca, and fake agent commands only. |
| 2026-08-13T12:25:29.4291312+09:00 → 2026-08-13T12:25:32.0395722+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1` | Exit `0`; all module validations passed; all 8 AHK test files printed `PASS`; aggregate `PASS: 8 test file(s)`. AutoHotkey PID audit: before `9752,13532,37064`, after `9752,13532,37064`, new repository test PIDs `none`. |
| 2026-08-13T12:25:39.7626016+09:00 → 2026-08-13T12:25:40.0995041+09:00 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1` | Exit `0`; `PASS: 7 PowerShell file(s) parsed`. |
| 2026-08-13T12:25:45.1613570+09:00 → 2026-08-13T12:25:45.1955789+09:00 | `rg -n "worktree create|terminal send|git worktree|git clone|git checkout" scripts src main.ahk` | No matches. Raw `rg` exit `1` means no matches; the verification wrapper treated this expected result as success (`0`). |
| 2026-08-13T12:25:49.5022269+09:00 → 2026-08-13T12:25:49.5518231+09:00 | `git diff --check` | Exit `0`; no whitespace errors. Git emitted only normal LF→CRLF working-copy notices for the two edited Markdown files. |
| 2026-08-13T12:25:58.5488898+09:00 → 2026-08-13T12:25:58.8964476+09:00 | `orca status --json` (read-only) | Exit `0`, envelope `ok=true`; app running with PID `39284`, but `runtime.state=starting`, `runtime.reachable=false`, `runtimeId=null`, graph `starting`. This is not a ready runtime and no follow-up Orca operation was attempted. |

There is no TypeScript project in this repository, so `npx tsc --noEmit` is
not applicable. The plan's AutoHotkey `/Validate`, focused AHK tests, and
PowerShell contract/parser checks are the applicable gates.

## Manual QA gate

Manual QA is intentionally not represented as passing. It requires a user-owned
disposable existing Git checkout and a ready/reachable Orca runtime. Neither
precondition was available: no checkout was selected in this turn, and the
read-only status above reports `starting`/unreachable.

| Surface | Automated/read-only evidence | Manual status |
| --- | --- | --- |
| `workspace.ai-development` palette invocation and native picker | Injected service tests cover cancellation, picker cancellation, adapter invocation, aggregate presentation, exact command ID/risk, and headless startup registration. | **Not performed** in a visible UI. |
| Existing checkout reuse and exact `path:<root>` targeting | Fake-Orca contract proves nested Git-root resolution and exact path selector; forbidden scan has no operational matches. | **Not performed** against a real disposable checkout. |
| Codex/Claude/Grok/Gemini terminal creation/reuse and `tui-idle` wait | Fake-Orca contract covers four creates, live matching reuse, missing CLI skip, and isolated create/wait failures. | **Not performed**; Orca runtime is not ready. |
| No prompt/worktree/branch/terminal replacement | Fake call log and forbidden scan prove no `terminal send`/worktree operations in automated scenarios; no real mutation was attempted. | **Not performed** visually. |
| Second invocation idempotence | Existing-terminal fake scenario covers reuse without recreation. | **Not performed** against real Orca. |

## Changed files and boundaries

Task 3 versioned documentation files:

- `README.md` — first-use flow, `workspace.ai-development` safety/results,
  and explicit distinction from `[Workspace.development]` sample.
- `docs/harness/manifest.md` — Orca contract, verification record pointer,
  manual-QA boundary, and x64-only Minor.
- `docs/harness/runs/2026-08-13-orca-ai-development-workspace/verification.md`
  — this evidence record.

The `.superpowers/` directory is pre-existing/untracked and is excluded from
the documentation commit. Source and test files were not modified by Task 3.

## Limitations

- Real Orca UI success is not claimed. Runtime readiness must be rechecked and
  the user must select a disposable checkout before manual QA can run.
- The validation evidence is x64-only because the repository and runner use
  `AutoHotkey64.exe`; x86 AutoHotkey was not tested (Minor).

## Final-gate timeout and process-tree correction

The outer AutoHotkey timeout now budgets the PowerShell adapter's exact
worst-case sequence of 17 timeout-bounded external calls: Git root resolution,
Orca status, repository list, optional repository add, terminal list, four
executable lookups, four terminal creates, and four terminal waits. The default
is `17 * ReadyTimeoutMs + 5000ms`; the original per-call value is still passed
unchanged to PowerShell.

The native launcher now creates PowerShell suspended, assigns it to a Windows
Job Object configured with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, and only then
resumes its main thread. Timeout terminates the Job Object, so PowerShell and
its descendants share the same bounded lifetime. Normal completion closes the
job only after PowerShell exits.

Fresh evidence on 2026-08-13 (Asia/Seoul):

- RED: the strengthened focused AHK run exited `1`/timed out against the old
  four-wait budget and parent-only process termination implementation.
- GREEN: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only orca-workspace`
  exited `0`; the fake PowerShell child wrote its started marker, while neither
  the child nor parent wrote a late marker after timeout.
- Final automated run, `2026-08-13T12:46:44.7725470+09:00` to
  `2026-08-13T12:47:20.6607056+09:00`: fake-Orca PowerShell contracts passed;
  all 8 AHK test files passed; `main.ahk` validation exited `0`; 7 PowerShell
  files parsed; AutoHotkey PID set stayed exactly `9752,13532,37064` with no
  new PID.

No real Orca command, agent CLI, terminal, folder picker, or visible UI was
used for this correction. The manual QA status above remains unchanged.
