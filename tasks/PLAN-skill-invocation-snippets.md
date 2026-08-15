# Skill Invocation Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two local general-purpose snippets with eighteen fixed slash-command snippets for frequently used content and Superpowers skills.

**Architecture:** Change only the user-local `[Snippets]` section in `config/settings.local.ini`. Preserve every other INI section and rely on the existing config loader, command registry, target handoff, and safe paste implementation without production-code changes.

**Tech Stack:** AutoHotkey v2, INI configuration, PowerShell 7 verification

## Global Constraints

- Only `config/settings.local.ini` changes at runtime; it remains untracked.
- Remove `student-feedback` and `multiline-prompt`.
- Register exactly the eighteen approved slash commands.
- Paste commands without automatically pressing Enter.
- Preserve `[General]`, `[KakaoAccounts]`, `[Workspace.development]`, and their values.
- Do not add credentials, paths, clipboard contents, prompt history, arguments, variables, or templates.
- Do not exercise a real UI or the user's clipboard during automated verification.

---

### Task 1: Replace and verify the local Snippets section

**Files:**
- Modify: `config/settings.local.ini`
- Verify: `tests/snippets-tests.ahk`
- Verify: `tests/main-startup-tests.ahk`

**Interfaces:**
- Consumes: existing INI `[Snippets]` key/value loader and `RegisterSnippetCommands(registry, service)`.
- Produces: eighteen palette command IDs in the form `snippet.skill-<name>` whose bodies are slash commands.

- [x] **Step 1: Capture the non-Snippets sections and write a failing local contract check**

Run this read-only PowerShell check before editing:

```powershell
$path = 'config\settings.local.ini'
$raw = Get-Content -LiteralPath $path -Raw
$expected = @(
  'skill-blog=/blog',
  'skill-k-blog=/k-blog',
  'skill-k-book=/k-book',
  'skill-k-news=/k-news',
  'skill-k-youtube=/k-youtube',
  'skill-research=/research',
  'skill-harness=/harness',
  'skill-notebooklm=/notebooklm',
  'skill-ocr=/ocr',
  'skill-humanizer=/humanizer',
  'skill-brainstorming=/brainstorming',
  'skill-writing-plans=/writing-plans',
  'skill-executing-plans=/executing-plans',
  'skill-subagent-development=/subagent-driven-development',
  'skill-systematic-debugging=/systematic-debugging',
  'skill-tdd=/test-driven-development',
  'skill-verification=/verification-before-completion',
  'skill-using-superpowers=/using-superpowers'
)
$actual = [regex]::Match($raw, '(?ms)^\[Snippets\]\r?\n(.*?)(?=^\[|\z)').Groups[1].Value.Trim() -split '\r?\n'
if (@(Compare-Object $expected $actual).Count -ne 0) { throw 'RED: local skill snippets do not match the approved set' }
```

Expected: FAIL with `RED: local skill snippets do not match the approved set` because the old two entries still exist.

- [x] **Step 2: Replace only the `[Snippets]` section**

Set the section to exactly:

```ini
[Snippets]
skill-blog=/blog
skill-k-blog=/k-blog
skill-k-book=/k-book
skill-k-news=/k-news
skill-k-youtube=/k-youtube
skill-research=/research
skill-harness=/harness
skill-notebooklm=/notebooklm
skill-ocr=/ocr
skill-humanizer=/humanizer
skill-brainstorming=/brainstorming
skill-writing-plans=/writing-plans
skill-executing-plans=/executing-plans
skill-subagent-development=/subagent-driven-development
skill-systematic-debugging=/systematic-debugging
skill-tdd=/test-driven-development
skill-verification=/verification-before-completion
skill-using-superpowers=/using-superpowers
```

Use `apply_patch` so the remaining local configuration is preserved verbatim.

- [x] **Step 3: Run the local contract check again**

Run the exact PowerShell check from Step 1.

Expected: exit `0`, with exactly eighteen entries and no `student-feedback` or `multiline-prompt` difference.

- [x] **Step 4: Run focused product regressions**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only snippets,main-startup
```

Expected: `PASS: 2 test file(s)` with every validation and test process exiting `0` without timeout.

- [x] **Step 5: Verify the hub entry point and local diff boundary**

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate '.\main.ahk'
git diff --check
git status --short --branch
```

Expected: `main.ahk` validates, tracked diff is clean, and `config/settings.local.ini` remains untracked/ignored rather than entering a commit.

- [x] **Step 6: Record completion without committing the local configuration**

Update this plan's checkboxes and report the exact local entries, focused-test result, and restart instruction. Do not commit `config/settings.local.ini`; the design and plan commits are the only tracked artifacts.
