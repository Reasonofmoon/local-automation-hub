# Orca AI Development Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `workspace.ai-development`, which asks for an existing Git checkout and prepares Codex, Claude, Grok, and Gemini terminals in that checkout's Orca workspace without creating a Git worktree or sending prompts.

**Architecture:** AutoHotkey owns the palette command, native folder picker, cancellation checks, and visible summary. A PowerShell adapter owns Git-root resolution, Orca readiness and repository discovery, exact existing-checkout selection through `path:<root>`, live-terminal reuse, terminal creation, bounded readiness waits, and structured JSON output. Automated tests inject fake adapters and a fake Orca executable; they never launch a real AI CLI or mutate a real Orca workspace.

**Tech Stack:** AutoHotkey v2.0.26 64-bit, PowerShell 5.1, Git CLI, Orca CLI 1.4.180 JSON interface, Windows 11

## Global Constraints

- The command ID is exactly `workspace.ai-development` and risk is `medium`.
- A native folder picker appears on every invocation; cancellation creates no process or Orca state.
- Only existing Git checkouts are accepted. A nested selection resolves through `git -C <path> rev-parse --show-toplevel`.
- Use the selected existing checkout through Orca's `path:<absolute-root>` selector. Never call `orca worktree create`, `git worktree`, clone, branch, commit, or configuration mutation.
- Prepare exactly four agent definitions: `Codex/codex`, `Claude/claude`, `Grok/grok`, and `Gemini/gemini`.
- Launch the CLI only. Never call `orca terminal send` and never transmit a prompt.
- Reuse only a live terminal whose workspace, normalized title, and command identity can be confirmed. Never close, stop, or replace an existing session.
- Missing CLI executables are `skipped`; per-agent create/wait failures are isolated; Git or Orca target-validation failures abort before terminal creation.
- Orca must report `runtime.state=ready` and `runtime.reachable=true`.
- All external processes are timeout-bounded and arguments are passed as an array, never interpolated into a shell command.
- Tests use temporary Git repositories, fake Orca JSON, and fake CLI commands only. They do not touch real Orca state, user repositories, credentials, Kakao, or Startup.
- AutoHotkey identifiers are case-insensitive. Local variables must not reuse class or function names.
- `npx tsc --noEmit` is not applicable because this repository has no TypeScript project; use AutoHotkey `/Validate`, focused AHK tests, PowerShell parsing, and focused PowerShell contract tests.

---

## Planned File Structure

```text
src/modules/OrcaWorkspace.ahk          # folder selection, adapter invocation, result presentation
scripts/Open-OrcaAiWorkspace.ps1      # Git/Orca orchestration and JSON result
tests/orca-workspace-tests.ahk         # injected AHK service contracts
tests/Open-OrcaAiWorkspace.Tests.ps1  # fake Orca + temporary Git integration contracts
main.ahk                               # composition and command registration
tests/Run-Tests.ps1                    # focused AHK module/test routing
scripts/Validate-PowerShell.ps1        # parser plus adapter parameter contract
README.md                              # command usage and safety boundaries
docs/harness/manifest.md               # verification commands and feature record
```

## Shared Interfaces

```ahk
class OrcaWorkspaceService {
    __New(folderPicker, processAdapter, presenter, scriptPath, appContext)
    OpenAiDevelopment()
}

RegisterOrcaWorkspaceCommand(registry, service)
```

PowerShell adapter input and output:

```powershell
param(
    [Parameter(Mandatory)][string]$SelectedPath,
    [string]$OrcaCommand = 'orca',
    [string]$GitCommand = 'git',
    [int]$ReadyTimeoutMs = 60000
)
```

```json
{
  "success": true,
  "repositoryRoot": "C:\\projects\\lesson-platform",
  "created": ["Codex", "Claude"],
  "reused": ["Grok"],
  "skipped": [{"agent":"Gemini","reason":"command not found"}],
  "failed": []
}
```

### Task 1: PowerShell Git and Orca adapter

**Files:**
- Create: `scripts/Open-OrcaAiWorkspace.ps1`
- Create: `tests/Open-OrcaAiWorkspace.Tests.ps1`
- Modify: `scripts/Validate-PowerShell.ps1`

**Interfaces:**
- Consumes: selected filesystem path, `git`, version-matched `orca`, and four fixed agent definitions.
- Produces: one JSON object containing `success`, `repositoryRoot`, `created`, `reused`, `skipped`, and `failed`.

- [ ] **Step 1: Write the failing PowerShell contract test**

The test creates a temporary Git repository, a fake `orca.cmd`, and fake agent commands. The fake Orca records each argument array as JSON lines and returns deterministic responses for `status`, `repo list/add`, `terminal list/create/wait`.

```powershell
$result = & $scriptPath -SelectedPath $nestedPath -OrcaCommand $fakeOrca -GitCommand 'git' -ReadyTimeoutMs 1000 | ConvertFrom-Json
Assert-Equal $gitRoot $result.repositoryRoot 'nested selection resolves to Git root'
Assert-Equal 4 $result.created.Count 'creates four missing terminals'
$calls = Get-Content -LiteralPath $callLog | ForEach-Object { $_ | ConvertFrom-Json }
Assert-False ($calls.command -contains 'worktree create') 'never creates a worktree'
Assert-False ($calls.command -contains 'terminal send') 'never sends a prompt'
```

Add separate scenarios for non-Git rejection before any Orca call, runtime `starting` rejection, existing terminal reuse, missing CLI skip, one create failure with later agents continuing, and exact `path:<root>` selector use.

- [ ] **Step 2: Run the focused PowerShell test and confirm RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Open-OrcaAiWorkspace.Tests.ps1
```

Expected: exit non-zero because `scripts/Open-OrcaAiWorkspace.ps1` does not exist.

- [ ] **Step 3: Implement process and JSON boundaries**

Use `System.Diagnostics.ProcessStartInfo` with an argument-quoting helper, redirected output/error, and a timeout. Every invocation returns an object with `ExitCode`, `TimedOut`, `Output`, and `Error`; kill only the owned process on timeout.

```powershell
function Invoke-BoundedProcess {
    param([string]$FilePath, [string[]]$Arguments, [int]$TimeoutMs)
    # ProcessStartInfo, redirected async output, WaitForExit($TimeoutMs), owned-process Kill
}
```

Parse Orca envelopes strictly: require `ok=true` before consuming `result`. Require status `ready/reachable`, then resolve or add the repository. Target terminal operations with exactly `path:$repositoryRoot`; do not call `worktree create`.

For each fixed agent, first verify command availability with a bounded, noninteractive command lookup. List live terminals once and compare normalized title plus exposed command identity. Create missing terminals with:

```text
orca terminal create --worktree path:<root> --title <Title> --command <command> --json
```

Wait for each returned handle with:

```text
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms <ReadyTimeoutMs> --json
```

Emit only the final JSON object on stdout. Put diagnostics on stderr without tokens, environment values, or terminal contents.

- [ ] **Step 4: Add parser and public-parameter validation**

Extend `Validate-PowerShell.ps1` to require `Open-OrcaAiWorkspace.ps1` to expose `-SelectedPath`, `-OrcaCommand`, `-GitCommand`, and `-ReadyTimeoutMs`, then parse all PowerShell files.

- [ ] **Step 5: Run focused and parser verification**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Open-OrcaAiWorkspace.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
rg -n "worktree create|terminal send|git worktree|git clone|git checkout" scripts\Open-OrcaAiWorkspace.ps1
```

Expected: contract test prints `PASS: Orca AI workspace adapter`; parser passes; forbidden-command search has no matches.

- [ ] **Step 6: Commit the adapter**

```powershell
git add scripts/Open-OrcaAiWorkspace.ps1 scripts/Validate-PowerShell.ps1 tests/Open-OrcaAiWorkspace.Tests.ps1
git commit -m "feat: add Orca AI workspace adapter"
```

### Task 2: AutoHotkey service, folder picker, and palette command

**Files:**
- Create: `src/modules/OrcaWorkspace.ahk`
- Create: `tests/orca-workspace-tests.ahk`
- Modify: `main.ahk`
- Modify: `tests/main-startup-tests.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: `Open-OrcaAiWorkspace.ps1`, `AppContext.IsCancelled()`, `CommandRegistry.Register`, injected folder picker/process adapter/presenter.
- Produces: `OrcaWorkspaceService.OpenAiDevelopment()` and palette command `workspace.ai-development`.

- [ ] **Step 1: Write failing injected service tests**

```ahk
picker := FakeOrcaFolderPicker("C:\projects\lesson-platform")
processAdapter := FakeOrcaProcessAdapter(Map("success", true, "repositoryRoot", picker.path, "created", ["Codex"], "reused", [], "skipped", [], "failed", []))
presenter := FakeOrcaPresenter()
service := OrcaWorkspaceService(picker, processAdapter, presenter, "C:\hub\scripts\Open-OrcaAiWorkspace.ps1", FakeAppContext())
result := service.OpenAiDevelopment()
AssertEqual(1, processAdapter.callCount, "selected folder invokes adapter once")
AssertEqual(picker.path, processAdapter.selectedPath, "passes selected path as a separate argument")
AssertEqual(1, presenter.callCount, "shows aggregate result once")
```

Add cancellation-before-picker, picker-cancel-with-zero-process-calls, cancellation-after-picker, adapter failure presentation, and result-summary created/reused/skipped/failed cases.

- [ ] **Step 2: Run the focused AHK test and confirm RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only orca-workspace
```

Expected: validation/include failure because `OrcaWorkspaceService` does not exist.

- [ ] **Step 3: Implement the injected service and Win32 adapters**

The production folder picker uses `DirSelect("*" A_MyDocuments, 3, "Select an existing Git checkout")`. The process adapter launches PowerShell with a ProcessStartInfo argument array and parses the adapter's JSON object. It must not construct a single interpolated command string from the selected path.

```ahk
OpenAiDevelopment() {
    if this.appContext.IsCancelled()
        throw Error("Orca workspace creation cancelled")
    selectedPath := this.folderPicker.Select()
    if (selectedPath = "")
        return Map("success", false, "cancelled", true)
    if this.appContext.IsCancelled()
        throw Error("Orca workspace creation cancelled")
    result := this.processAdapter.Open(this.scriptPath, selectedPath)
    this.presenter.Show(FormatOrcaWorkspaceResult(result))
    return result
}
```

Production presentation uses a readable, non-secret `MsgBox` titled `Orca AI Development Workspace`.

- [ ] **Step 4: Register the command in the composition root**

Include the module in `main.ahk`, construct it inside `InitializeHub`, and register it independently of static `[Workspace.*]` modes:

```ahk
registry.Register(
    "workspace.ai-development",
    "Workspace: Orca AI development",
    ["workspace", "orca", "codex", "claude", "grok", "gemini"],
    "medium",
    (*) => orcaWorkspaceService.OpenAiDevelopment()
)
```

Avoid AHK case-insensitive collisions: the local must not be named `orcaWorkspaceService` if it conflicts with class `OrcaWorkspaceService`; use `aiWorkspaceLauncher`.

Update `main-startup-tests.ahk` to assert the new command is registered during headless composition without opening a picker.

- [ ] **Step 5: Add runner routing and execute focused/full tests**

Add `OrcaWorkspace.ahk` to module validation when `-Only orca-workspace` is requested.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only orca-workspace,main-startup
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

Expected: focused tests pass without visible UI or real Orca calls; full suite passes with no new AutoHotkey PID.

- [ ] **Step 6: Commit the hub integration**

```powershell
git add main.ahk src/modules/OrcaWorkspace.ahk tests/orca-workspace-tests.ahk tests/main-startup-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add Orca AI workspace command"
```

### Task 3: Documentation, real-readiness gate, and manual QA record

**Files:**
- Modify: `README.md`
- Modify: `docs/harness/manifest.md`
- Create: `docs/harness/runs/2026-08-13-orca-ai-development-workspace/verification.md`

**Interfaces:**
- Consumes: completed adapter/service and automated evidence.
- Produces: user instructions, exact verification record, and an honest manual-QA boundary.

- [ ] **Step 1: Document first use**

README must explain:

1. Start Orca and confirm `orca status --json` reports `ready/reachable`.
2. Open the hub with `CapsLock + Space`.
3. Run `workspace.ai-development` rather than sample `workspace.development`.
4. Select an existing Git checkout.
5. Confirm separate Codex, Claude, Grok, and Gemini terminals are waiting for input.
6. Explain created/reused/skipped/failed and that no prompt/worktree/branch is created.

Clearly label `workspace.development` as a configurable app/folder/URL sample so users do not expect it to open Orca.

- [ ] **Step 2: Run all automated gates**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Open-OrcaAiWorkspace.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
git diff --check
rg -n "worktree create|terminal send|git worktree|git clone|git checkout" scripts src main.ahk
```

Expected: all tests/parsers pass; whitespace is clean; forbidden-command search has no operational matches.

- [ ] **Step 3: Record automated evidence and safe real readiness**

Write exact timestamps, commands, exits, pass counts, PID audit, and redacted findings to `verification.md`. A real `orca status --json` is read-only and may be recorded. If the runtime is `starting` or unreachable, record the manual scenario as blocked by Orca readiness; do not create terminals speculatively.

- [ ] **Step 4: Perform one user-owned manual QA only when Orca is ready**

With the user present, select a disposable existing Git checkout and verify visually:

- Orca reuses the exact checkout;
- no new Git branch/worktree appears;
- four installed CLIs appear in separate terminals and wait for input;
- a second invocation reuses live matching terminals;
- no prompt is automatically sent.

If Orca is not `ready/reachable`, leave this unchecked and report the exact blocker. Automated success must not be presented as manual UI success.

- [ ] **Step 5: Commit documentation and verification**

```powershell
git add README.md docs/harness/manifest.md docs/harness/runs/2026-08-13-orca-ai-development-workspace/verification.md
git commit -m "docs: verify Orca AI workspace workflow"
```

## Final Definition of Done

- `workspace.ai-development` appears in the palette and always opens a folder picker.
- Non-Git selection and Orca-not-ready state fail before terminal mutation.
- The exact existing checkout is targeted with `path:<root>`; no new Git worktree or branch is created.
- Codex, Claude, Grok, and Gemini are created or safely reused without prompts.
- Missing/failing agents do not prevent other agents from being prepared.
- Visible output distinguishes created, reused, skipped, and failed agents.
- Focused AHK tests, fake-Orca PowerShell tests, full regression tests, parser validation, forbidden-command scan, PID audit, and `git diff --check` pass.
- Documentation distinguishes the new Orca workflow from the original Google-opening sample workspace.
- Real Orca UI success is claimed only after the user-visible manual scenario is performed.
