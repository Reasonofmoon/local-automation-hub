# Orca AI Development Workspace Design

## Goal

Add a Local Automation Hub command named `workspace.ai-development` that asks
the user to choose an existing Git checkout, opens or reuses that checkout as
an Orca workspace, and prepares Codex, Claude, Grok, and Gemini CLI terminals
without sending any prompts.

## Approved user flow

1. The user opens the hub with `CapsLock + Space`.
2. The user runs `workspace.ai-development`.
3. A native Windows folder picker opens on every run.
4. The selected folder must belong to a Git working tree. The resolved
   repository root, not an arbitrary nested folder, becomes the workspace path.
5. The existing checkout is used as-is. The automation does not create a Git
   branch, clone, or worktree.
6. Orca must be running with a `ready` and reachable runtime.
7. The repository is registered with Orca when necessary, and the existing
   checkout is opened or reused as its workspace.
8. Four Orca terminals are prepared, one for each installed CLI:
   `codex`, `claude`, `grok`, and `gemini`.
9. Each CLI is launched and left waiting for the user. No shared or generated
   prompt is sent.
10. A visible summary reports which terminals were created, reused, skipped,
    or failed.

Closing the folder picker is a normal cancellation and creates no Orca state.

## Architecture

AutoHotkey remains responsible for the command palette, the native folder
picker, cancellation checks, and user-visible results. A PowerShell adapter is
responsible for Git discovery, Orca JSON commands, workspace resolution,
terminal discovery, and terminal creation. This division keeps Windows GUI
behavior in the hub while using PowerShell for process execution, quoting,
structured JSON, timeouts, and partial-failure aggregation.

The command has three components:

- `OrcaWorkspaceService.ahk`: selects a folder, checks cancellation, calls the
  PowerShell adapter, and formats a visible result.
- `Open-OrcaAiWorkspace.ps1`: accepts one selected path, resolves the Git root,
  verifies Orca readiness, registers or locates the repository/workspace, and
  creates or reuses the four agent terminals.
- Focused tests: inject folder selection and process adapters into the AHK
  service, while PowerShell contract tests use a fake Orca executable and a
  temporary Git repository. No real agent CLI is launched during automated
  tests.

## Orca integration contract

The adapter uses the installed, version-matched Orca CLI surface and JSON
responses. It performs the following logical operations:

1. `orca status --json` and require `runtime.state=ready` and
   `runtime.reachable=true`.
2. Resolve the selected checkout using `git -C <path> rev-parse
   --show-toplevel`. Reject non-Git folders before any Orca mutation.
3. List registered repositories and add the resolved root only when it is not
   already registered.
4. Locate the Orca workspace representing that exact existing checkout. If
   Orca exposes it as a folder workspace, use that context; if it is a tracked
   repository worktree, use the full `<repoId>::<worktreePath>` identifier.
   Never call the command that creates a new Git worktree.
5. List terminals for the resolved workspace.
6. For each agent, reuse an existing live terminal whose normalized title and
   command identity match. Otherwise create one terminal with these titles and
   commands:

   | Title | Command |
   | --- | --- |
   | Codex | `codex` |
   | Claude | `claude` |
   | Grok | `grok` |
   | Gemini | `gemini` |

7. Wait for each newly created agent terminal to reach `tui-idle`, with a
   bounded timeout. Readiness failure is reported for that terminal and does
   not stop the remaining agents.

The implementation must use the exact selectors and fields returned by the
installed Orca version rather than reconstructing worktree IDs.

## Duplicate and partial-failure behavior

Repeated execution is idempotent at the terminal level. A live matching agent
terminal is reused. A closed or stale handle is not reused; terminal state is
listed again before creation. The summary contains arrays for `created`,
`reused`, `skipped`, and `failed`.

Missing agent executables do not abort the whole workspace. The adapter checks
command availability before terminal creation and records the missing CLI as
`skipped`. Orca or Git validation failures abort before any terminal is
created because they invalidate the target workspace itself.

## User-visible results

The result is shown in a dedicated message or read-only report window. Example:

```text
Orca AI workspace: C:\projects\lesson-platform

Created: Codex, Claude
Reused: Grok
Skipped: Gemini (command not found)
Failed: none
```

Errors are actionable and redacted. The report may include repository paths,
agent names, Orca error codes, and terminal titles. It must not include CLI
account tokens, environment variable values, terminal contents, prompts, or
credential material.

## Safety boundaries

- No new clone, branch, commit, or Git worktree.
- No modification of repository files or Git configuration.
- No automatic prompt transmission to any agent.
- No terminal closing, stopping, or replacement of an existing session.
- No reuse based only on a title when command/workspace identity cannot be
  confirmed.
- No fallback to Windows Terminal when Orca is unavailable.
- No shell command assembled from unescaped user input.
- Folder cancellation and non-Git selection leave no external state.
- Automated tests use fake Orca responses and temporary Git repositories only.

## Configuration and command registration

`workspace.ai-development` is a built-in medium-risk palette command. It does
not depend on the static `[Workspace.*]` launcher configuration and therefore
does not replace existing modes such as `workspace.development`. The existing
sample mode remains available for simple app/folder/URL bundles.

The Orca command and agent names are fixed for the first version. User-defined
agent lists, prompt broadcasting, new-worktree creation, layouts, and automatic
task assignment are outside this scope.

## Verification

Automated verification must prove:

- folder-picker cancellation performs no process call;
- a nested selected folder resolves to the Git root;
- non-Git folders fail before Orca mutation;
- unavailable Orca runtime produces an actionable error;
- existing matching terminals are reused;
- missing agent commands are skipped;
- failures are isolated per agent;
- no `terminal send`, Git branch/worktree creation, or prompt text occurs;
- result presentation is invoked once with the aggregate summary;
- all AutoHotkey files validate, PowerShell files parse, and existing tests
  remain green.

One user-owned manual QA scenario remains: select a disposable existing Git
checkout in the folder picker, confirm Orca opens/reuses it, and visually verify
that all four available CLIs are waiting for input in separate Orca terminals.
