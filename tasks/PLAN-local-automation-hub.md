# Local Automation Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows 11에서 안전하게 실행되는 AutoHotkey v2 통합 단축키 허브와 다섯 자동화 모듈을 구현한다.

**Architecture:** `main.ahk`는 조립과 전역 단축키 등록만 담당하고, `src/core/`의 명령 레지스트리·설정·로그 계층이 `src/modules/`의 기능 모듈을 느슨하게 연결한다. 파일 변경과 자격 증명 입력은 각각 미리보기/확인과 대상 창 검증을 통과해야 하며, 자동 검증 가능한 로직은 부작용 없는 함수로 분리해 AutoHotkey 테스트 스크립트에서 실행한다.

**Tech Stack:** AutoHotkey v2.0.26 64-bit, Windows 11 API, PowerShell 5.1 보조 스크립트, UTF-8 INI 설정, Git

## Global Constraints

- Runtime은 AutoHotkey v2이며 모든 `.ahk` 파일은 `#Requires AutoHotkey v2.0`을 선언한다.
- 허브 호출 키는 `CapsLock + Space`, 긴급 정지는 `Ctrl + Alt + Esc`다.
- 비밀번호는 Windows Credential Manager에만 저장하며 소스·설정·로그·클립보드에 기록하지 않는다.
- 자격 증명 문자열의 런타임 메모리 존재를 완전히 제거한다고 주장하지 않는다. 대신 콜백 범위 밖으로 반환하지 않고, 네이티브 복사 버퍼를 즉시 0으로 덮으며, 파일·로그·클립보드·프로세스 인자에 남기지 않는다.
- 카카오톡 실행 파일과 로그인 창을 검증하지 못하면 자격 증명을 읽거나 입력하지 않는다.
- 파일 정리는 사용자가 탐색기에서 선택한 일반 파일만 미리보기와 명시적 확인 후 변경한다.
- 파일 대상 형식은 원래 폴더 아래 `YYYY\MM\YYYY-MM-DD_기존이름.ext`이고 충돌 시 `(2)`, `(3)`을 추가한다.
- TypeScript 소스가 없으므로 `npx tsc --noEmit` 대신 AutoHotkey `/Validate`, PowerShell 파서 검사, 관련 시나리오 테스트를 실행한다.
- 한 작업은 하나의 논리적 변경으로 커밋하며 Conventional Commits 형식을 사용한다.

---

## Planned File Structure

```text
main.ahk                         # composition root and global hotkeys
config/
  settings.example.ini          # safe, versioned configuration example
  settings.local.ini            # ignored, machine-specific paths and aliases
src/core/
  AppContext.ahk                 # shared paths, cancellation state, notifications
  CommandRegistry.ahk            # command contracts, search, invocation isolation
  Config.ahk                     # INI loading and validation
  Logger.ahk                     # redacted local diagnostics
  Palette.ahk                    # searchable command GUI
src/modules/
  Snippets.ahk                   # safe text insertion and clipboard restoration
  Workspaces.ahk                 # app/folder/URL launch aggregation
  WindowManager.ahk              # work-area placement and monitor movement
  FileOrganizer.ahk              # preview, confirmed move, collision, one-step undo
  CredentialStore.ahk            # CredReadW and secure buffer cleanup
  KakaoLogin.ahk                 # executable/window/focus gates and direct SendText
src/system/
  ExplorerSelection.ahk          # selected regular files from Explorer
scripts/
  Register-Credential.ps1        # CredWriteW helper with secure prompt
  Manage-Startup.ps1             # startup shortcut register/remove/status
  Validate-PowerShell.ps1        # parser check for project PowerShell files
tests/
  TestSupport.ahk                # assertion and exit-code helpers
  core-tests.ahk                 # config, registry, cancellation, redaction
  snippets-tests.ahk             # selection and clipboard restoration contracts
  workspaces-tests.ahk           # launch aggregation with injected runner
  windows-tests.ahk              # rectangle calculations
  file-organizer-tests.ahk       # temp-file preview/apply/collision/undo scenarios
  credential-tests.ahk           # missing-target and buffer-cleanup contracts
  kakao-login-tests.ahk          # mock-window gate and abort behavior
  Run-Tests.ps1                  # per-file AutoHotkey validation and test execution
.gitignore                       # local config, state, logs, temporary artifacts
README.md                        # setup, credential registration, use, recovery
docs/harness/manifest.md         # implemented verification commands and change log
```

## Shared Interfaces

The implementation must keep these names consistent across tasks:

```ahk
class AppContext {
    __New(rootDir, config, logger)
    Cancel(reason := "Emergency stop")
    ResetCancellation()
    IsCancelled()
    Notify(message, level := "info")
}

class CommandRegistry {
    Register(id, label, tags, risk, handler)
    Search(query)
    Invoke(id, appContext)
    All()
}

class HubConfig {
    static Load(path)
    static Validate(config)
}

class FileOrganizer {
    BuildPlan(paths, dateStamp)
    ApplyPlan(plan, confirmer)
    UndoLast(confirmer)
}

class CredentialStore {
    Read(targetName, consumer)
}

class KakaoLogin {
    Login(accountAlias, confirmer)
}
```

`CredentialStore.Read` must never return the password. It calls `consumer(secretText)` only inside the read scope, then wipes and frees native temporary buffers in `finally`. AutoHotkey가 생성한 문자열 복사본의 즉시 삭제는 보장할 수 없으므로 consumer는 값을 저장·반환·로그하지 않고 즉시 입력에만 사용한다.

### Task 1: Core harness, configuration, and command registry

**Files:**
- Create: `.gitignore`
- Create: `config/settings.example.ini`
- Create: `src/core/AppContext.ahk`
- Create: `src/core/CommandRegistry.ahk`
- Create: `src/core/Config.ahk`
- Create: `src/core/Logger.ahk`
- Create: `tests/TestSupport.ahk`
- Create: `tests/core-tests.ahk`
- Create: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: approved config fields `General`, `KakaoAccounts`, `Snippets`, and `Workspace.*`.
- Produces: `AppContext`, `CommandRegistry`, `HubConfig`, `SafeLogger`, and the common test runner used by every later task.

- [ ] **Step 1: Write failing core tests**

```ahk
#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\core\CommandRegistry.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Logger.ahk

registry := CommandRegistry()
registry.Register("window.left", "Move left", ["window", "layout"], "low", (*) => "ok")
AssertEqual(1, registry.Search("layout").Length, "searches tags")
AssertThrows(() => registry.Register("window.left", "Duplicate", [], "low", (*) => 0), "rejects duplicate ids")

safe := SafeLogger.Redact("password=secret clipboard=private")
AssertFalse(InStr(safe, "secret"), "redacts password value")
AssertFalse(InStr(safe, "private"), "redacts clipboard value")
ExitWithTestResult()
```

- [ ] **Step 2: Run the core test and confirm the expected failure**

Run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate tests\core-tests.ahk
```

Expected: non-zero exit with an include error because the core classes do not exist.

- [ ] **Step 3: Implement the minimum core contracts**

Implement `CommandRegistry` with a `Map` keyed by command ID, lowercase substring search across label and joined tags, risk validation limited to `low|medium|high`, and `try/catch` isolation in `Invoke`. Implement `HubConfig.Load` with `IniRead`, returning nested maps without credentials; `Validate` returns an array of actionable errors. Implement `SafeLogger.Redact` with case-insensitive removal of `password=`, `secret=`, `clipboard=`, and credential blob values, and ensure log files live under `var/logs/`.

The safe example config must use only placeholders:

```ini
[General]
KakaoPath=%LOCALAPPDATA%\Kakao\KakaoTalk\KakaoTalk.exe
LogLevel=info

[KakaoAccounts]
work=LocalAutomationHub/Kakao/work

[Snippets]
student-feedback=Great effort today.
multiline-prompt=First line\nSecond line

[Workspace.development]
Items=app|notepad.exe;folder|%USERPROFILE%\Documents;url|https://localhost/
```

`HubConfig.Load`는 일반 값에서 `%NAME%` 환경 변수를 확장하고, 문구 본문에서 `\n`을 AutoHotkey 줄바꿈 `` `n ``으로, `\\`를 리터럴 백슬래시로 디코딩한다. 알 수 없는 이스케이프는 설정 오류로 보고하며 암묵적으로 수정하지 않는다.

- [ ] **Step 4: Run core validation and tests**

Run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate tests\core-tests.ahk
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\core-tests.ahk
```

Expected: validation exit code `0`; tests print `PASS` and exit code `0`.

- [ ] **Step 5: Commit the core harness**

```powershell
git add .gitignore config/settings.example.ini src/core tests/TestSupport.ahk tests/core-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add automation hub core"
```

### Task 2: Command palette and composition root

**Files:**
- Create: `src/core/Palette.ahk`
- Create: `main.ahk`
- Modify: `tests/core-tests.ahk`

**Interfaces:**
- Consumes: `CommandRegistry.Search(query)`, `CommandRegistry.Invoke(id, appContext)`, `HubConfig.Load(path)`.
- Produces: `CommandPalette.Show()`, `CommandPalette.Hide()`, `RegisterBuiltInCommands(registry, appContext)`, and global hotkeys `CapsLock & Space` and `^!Esc`.

- [ ] **Step 1: Add failing palette state tests**

```ahk
palette := CommandPalette(registry, appContext)
palette.SetQuery("window")
AssertEqual("window.left", palette.VisibleCommandIds()[1], "filters palette")
palette.SelectIndex(1)
AssertEqual("ok", palette.ExecuteSelection(), "executes selected command")
appContext.Cancel()
AssertTrue(appContext.IsCancelled(), "emergency stop sets cancellation")
```

- [ ] **Step 2: Run the targeted test and confirm failure**

Run `& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\core-tests.ahk`.

Expected: failure because `CommandPalette` is undefined.

- [ ] **Step 3: Implement the palette and entry point**

Create a single-instance GUI with an edit control and list view. Refresh results on `Change`, execute the selected row on Enter or double-click, support numeric selection `1` through `9`, close on Escape, and display caught errors through `AppContext.Notify`. `main.ahk` must only load config, create context/registry/modules, register commands, and bind:

```ahk
CapsLock & Space::palette.Show()
^!Esc::appContext.Cancel("Emergency stop requested")
```

- [ ] **Step 4: Validate without launching the GUI and run core tests**

Run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate main.ahk
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\core-tests.ahk
```

Expected: both exit code `0`.

- [ ] **Step 5: Commit the command palette**

```powershell
git add main.ahk src/core/Palette.ahk tests/core-tests.ahk
git commit -m "feat: add command palette"
```

### Task 3: Snippets with guarded clipboard restoration

**Files:**
- Create: `src/modules/Snippets.ahk`
- Create: `tests/snippets-tests.ahk`
- Modify: `main.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: snippet maps from `HubConfig`, active-window metadata, `AppContext.IsCancelled()`.
- Produces: `SnippetService.Search(query)` and `SnippetService.Insert(id)`.

- [ ] **Step 1: Write failing snippet tests with injected adapters**

```ahk
adapter := FakeInputAdapter("before")
service := SnippetService(Map("multi", Map("title", "Multi", "tags", ["lesson"], "body", "line 1`nline 2")), adapter)
service.Insert("multi")
AssertEqual("before", adapter.ClipboardText(), "restores clipboard")
AssertEqual("line 1`nline 2", adapter.InsertedText(), "inserts configured body")
adapter.isPasswordControl := true
AssertThrows(() => service.Insert("multi"), "blocks password controls")
```

- [ ] **Step 2: Run the targeted test and confirm failure**

Run `& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\snippets-tests.ahk`.

Expected: failure because `SnippetService` and `FakeInputAdapter` contracts are not implemented.

- [ ] **Step 3: Implement safe insertion**

Use direct `SendText` for single-line content. Decode the config's explicit `\n` escape before deciding whether content is multiline. For multiline content, save `ClipboardAll()`, assign only the snippet body, paste, and restore the saved clipboard in `finally`. Reject elevated windows when the hub is not elevated and controls whose class/name indicates password input. Register one palette command per snippet with ID `snippet.<config-id>`.

- [ ] **Step 4: Run snippet validation and test**

Run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut=UTF-8 /Validate src\modules\Snippets.ahk
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\snippets-tests.ahk
```

Expected: exit code `0`, clipboard restoration assertions pass.

- [ ] **Step 5: Commit snippets**

```powershell
git add main.ahk src/modules/Snippets.ahk tests/snippets-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add safe snippet insertion"
```

### Task 4: Workspace launcher and window geometry

**Files:**
- Create: `src/modules/Workspaces.ahk`
- Create: `src/modules/WindowManager.ahk`
- Create: `tests/workspaces-tests.ahk`
- Create: `tests/windows-tests.ahk`
- Modify: `main.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: ordered workspace item arrays, injected `runner`/`activator`, monitor work areas.
- Produces: `WorkspaceService.RunMode(modeId)`, `WindowManager.MoveActive(position)`, and `WindowManager.MoveToMonitor(direction)`.

- [ ] **Step 1: Write failing aggregation and geometry tests**

```ahk
runner := FakeWorkspaceRunner(Map("bad.exe", false))
service := WorkspaceService(runner)
result := service.RunItems(["app|notepad.exe", "app|bad.exe", "url|https://localhost/"])
AssertEqual(2, result.succeeded.Length, "continues after a failed item")
AssertEqual(1, result.failed.Length, "reports failed item")

rect := WindowManager.CalculateRect(Map("left", 0, "top", 0, "right", 1920, "bottom", 1040), "left")
AssertEqual(960, rect.width, "uses half work area")
AssertEqual(1040, rect.height, "excludes taskbar")
```

- [ ] **Step 2: Run both tests and confirm failure**

Run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\workspaces-tests.ahk
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\windows-tests.ahk
```

Expected: undefined-class failures.

- [ ] **Step 3: Implement partial-failure launching and work-area placement**

Parse each item strictly as `app|value`, `folder|value`, or `url|value`. Activate an existing app process before calling `Run`, continue after individual errors, and return maps containing `succeeded`, `skipped`, and `failed`. Calculate left/right/full rectangles from `MonitorGetWorkArea`; preserve window size while moving between monitors and clamp it inside the destination work area.

- [ ] **Step 4: Validate modules and run their tests**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only workspaces,windows`.

Expected: all selected validations and tests pass.

- [ ] **Step 5: Commit both low-risk modules**

```powershell
git add main.ahk src/modules/Workspaces.ahk src/modules/WindowManager.ahk tests/workspaces-tests.ahk tests/windows-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add workspace and window commands"
```

### Task 5: Explorer selection and file organizer plan generation

**Files:**
- Create: `src/system/ExplorerSelection.ahk`
- Create: `src/modules/FileOrganizer.ahk`
- Create: `tests/file-organizer-tests.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: Explorer-selected paths, fixed `YYYY-MM-DD` date for deterministic tests.
- Produces: `ExplorerSelection.GetRegularFiles()` and `FileOrganizer.BuildPlan(paths, dateStamp)`; no filesystem mutation in this task.

- [ ] **Step 1: Write failing plan tests**

```ahk
root := CreateTempDirectory()
source := root "\report.txt"
FileAppend("content", source, "UTF-8")
organizer := FileOrganizer(root "\state.ini")
plan := organizer.BuildPlan([source], "2026-08-12")
AssertEqual(root "\2026\08\2026-08-12_report.txt", plan[1].destination, "builds dated destination")
FileAppend("occupied", plan[1].destination, "UTF-8")
collisionPlan := organizer.BuildPlan([source], "2026-08-12")
AssertEqual(root "\2026\08\2026-08-12_report (2).txt", collisionPlan[1].destination, "avoids overwrite")
```

- [ ] **Step 2: Run the file test and confirm failure**

Run `& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\file-organizer-tests.ahk`.

Expected: failure because `FileOrganizer` does not exist.

- [ ] **Step 3: Implement selection filters and pure plan construction**

Use the active Explorer window's `Document.SelectedItems` collection. Normalize each path with `GetFullPathName`, reject folders and files with hidden/system attributes, deduplicate case-insensitively, and reject empty selection. `BuildPlan` must return objects containing `source`, `destination`, `status := "pending"`; it must create no folders and move no files.

- [ ] **Step 4: Validate and run plan tests**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only file-organizer`.

Expected: selection filter unit cases and collision planning pass without changing source files.

- [ ] **Step 5: Commit plan-only file organization**

```powershell
git add src/system/ExplorerSelection.ahk src/modules/FileOrganizer.ahk tests/file-organizer-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add file organization planning"
```

### Task 6: Confirmed file moves and one-step undo

**Files:**
- Modify: `src/modules/FileOrganizer.ahk`
- Modify: `tests/file-organizer-tests.ahk`
- Modify: `main.ahk`

**Interfaces:**
- Consumes: immutable plan from `BuildPlan`, injected `confirmer(previewText)` callback.
- Produces: `ApplyPlan(plan, confirmer)` and `UndoLast(confirmer)` with state at `var/state/file-undo.ini`.

- [ ] **Step 1: Add failing deny/apply/partial-failure/undo tests**

```ahk
denied := organizer.ApplyPlan(plan, (*) => false)
AssertTrue(FileExist(source), "denial preserves source")
AssertEqual(0, denied.succeeded.Length, "denial performs no move")

applied := organizer.ApplyPlan(plan, (*) => true)
AssertTrue(FileExist(plan[1].destination), "confirmed plan moves file")
undone := organizer.UndoLast((*) => true)
AssertTrue(FileExist(source), "undo restores original path")
AssertFalse(FileExist(plan[1].destination), "undo removes moved path")
AssertThrows(() => organizer.UndoLast((*) => true), "undo state is single use")
```

- [ ] **Step 2: Run the targeted test and confirm failure**

Expected: missing `ApplyPlan` or `UndoLast` behavior.

- [ ] **Step 3: Implement preview, confirmation, state, and rollback boundaries**

Immediately before moving, re-check that every source still exists and every destination is still free; if drift exists, abort the full plan and require a new preview. After confirmation, create destination directories per item, continue across move failures, and persist only successful source/destination pairs. Undo must preview the reverse mapping, refuse if the original path is occupied, restore successful items, and delete state only after all stored items are restored.

- [ ] **Step 4: Run the complete temporary-file scenario**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only file-organizer`.

Expected: deny, apply, collision, partial failure, drift abort, and one-step undo cases pass using only a generated temp directory.

- [ ] **Step 5: Commit confirmed file operations**

```powershell
git add main.ahk src/modules/FileOrganizer.ahk tests/file-organizer-tests.ahk
git commit -m "feat: add confirmed file moves and undo"
```

### Task 7: Windows Credential Manager adapter

**Files:**
- Create: `src/modules/CredentialStore.ahk`
- Create: `scripts/Register-Credential.ps1`
- Create: `tests/credential-tests.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: a configured generic credential target such as `LocalAutomationHub/Kakao/work`.
- Produces: `CredentialStore.Read(targetName, consumer)` and an interactive registration helper that writes a Generic credential with `CredWriteW`.

- [ ] **Step 1: Write failing missing-target and consumer tests**

```ahk
store := CredentialStore()
AssertThrows(() => store.Read("LocalAutomationHub/Test/DefinitelyMissing", (*) => 0), "missing credential is actionable")
fake := FakeCredentialStore("example-secret")
seen := false
fake.Read("test", (secret) => seen := secret = "example-secret")
AssertTrue(seen, "secret is scoped to consumer callback")
AssertTrue(fake.WasWiped(), "temporary secret buffer is wiped")
```

- [ ] **Step 2: Run the credential test and confirm failure**

Run `& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\credential-tests.ahk`.

Expected: undefined credential adapter.

- [ ] **Step 3: Implement direct Win32 credential access**

Call `Advapi32\CredReadW` with `CRED_TYPE_GENERIC := 1`, validate `CredentialBlobSize` as even UTF-16 bytes, copy into an allocated buffer, invoke the consumer with `StrGet`, call `RtlSecureZeroMemory` on the copy, and call `CredFree` in `finally`. Never concatenate the secret into an error, command line, log message, or return value. The registration script must use `Read-Host -AsSecureString`, marshal only for `CredWriteW`, wipe the unmanaged string in `finally`, and print only the target name and success/failure.

- [ ] **Step 4: Parse PowerShell and run credential tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\credential-tests.ahk
rg -n -i "password\s*=|secret\s*=|CredentialBlob" . -g '!tasks/**' -g '!docs/**'
```

Expected: parser and tests pass; search shows API field names and redaction rules only, with no literal credential values.

- [ ] **Step 5: Commit credential integration**

```powershell
git add src/modules/CredentialStore.ahk scripts/Register-Credential.ps1 tests/credential-tests.ahk tests/Run-Tests.ps1
git commit -m "feat: add secure credential adapter"
```

### Task 8: Kakao UI capability gate and guarded login flow

**Files:**
- Create: `src/modules/KakaoLogin.ahk`
- Create: `scripts/Inspect-KakaoLogin.ahk`
- Create: `tests/kakao-login-tests.ahk`
- Create: `docs/harness/runs/2026-08-12-local-automation-hub/kakao-ui-capability.md`
- Modify: `main.ahk`
- Modify: `tests/Run-Tests.ps1`

**Interfaces:**
- Consumes: `CredentialStore.Read`, configured account alias/target, configured Kakao executable, a capability record produced from the installed Kakao login window, injected window adapter and confirmer.
- Produces: `KakaoUiCapability.Inspect()`, `KakaoLogin.Login(accountAlias, confirmer)`, and `KakaoLogin.SwitchAccount(accountAlias, confirmer)`. If no stable login-screen/password-control signal is observable, login commands remain disabled and credentials are never read.

- [ ] **Step 1: Write failing mock-window safety tests**

```ahk
window := FakeKakaoWindowAdapter()
credentials := FakeCredentialStore("example-secret")
login := KakaoLogin(config, credentials, window, appContext)
window.processPath := "C:\Windows\notepad.exe"
AssertThrows(() => login.Login("work", (*) => true), "rejects wrong executable")
AssertEqual(0, credentials.readCount, "does not read secret before window validation")
window.processPath := config.kakaoPath
window.isLoginScreen := false
AssertThrows(() => login.Login("work", (*) => true), "rejects non-login screen")
AssertEqual(0, credentials.readCount, "still does not read secret")
```

- [ ] **Step 2: Run the Kakao test and confirm failure**

Run `& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\kakao-login-tests.ahk`.

Expected: undefined `KakaoLogin`.

- [ ] **Step 3: Inspect the installed Kakao login UI without reading credentials**

`Inspect-KakaoLogin.ahk` must collect only non-secret evidence from the active Kakao window: resolved process path, executable name, window class/title, focused control class/name, and whether UI Automation exposes a password edit element. It must not type keys, read text values, access Credential Manager, click logout, or save screenshots. Run it with the Kakao login screen already open and write a redacted capability result to `kakao-ui-capability.md`.

Acceptance rule:

- `supported`: process path matches the configured executable and either an accessible password edit control or another stable non-text automation property uniquely identifies the login password target.
- `unsupported`: the target is identifiable only by coordinates, timing, selected-account assumptions, or blind Tab navigation. In this case register `kakao.diagnostics` only; do not register login or switch commands.

- [ ] **Step 4: Implement validation-first login for supported capability only**

Resolve and compare the active process path case-insensitively to the configured `KakaoTalk.exe`. Require the `supported` capability and its positively identified login-screen/password-target signal, focus the target, re-check process/control immediately before credential access, then call `CredentialStore.Read(target, (secret) => SendText(secret))`. The consumer must not assign `secret` to an object, global, closure retained after the call, log, return value, or clipboard. Check `AppContext.IsCancelled()` before every focus or send operation. `SwitchAccount` may navigate only when the capability inspection also proves a stable logout action; otherwise expose login-only mode and document manual logout. It must request confirmation after logout and before calling `Login`.

- [ ] **Step 5: Run mock-login and syntax validation**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 -Only kakao-login,credential`.

Expected: wrong executable, wrong screen, focus drift, cancellation, missing credential, and successful mock insertion cases pass; no real Kakao window is touched.

- [ ] **Step 6: Commit the capability gate and guarded Kakao automation**

```powershell
git add main.ahk src/modules/KakaoLogin.ahk scripts/Inspect-KakaoLogin.ahk tests/kakao-login-tests.ahk tests/Run-Tests.ps1 docs/harness/runs/2026-08-12-local-automation-hub/kakao-ui-capability.md
git commit -m "feat: add guarded Kakao login"
```

### Task 9: Startup management, diagnostics, and user documentation

**Files:**
- Create: `scripts/Manage-Startup.ps1`
- Create: `scripts/Validate-PowerShell.ps1`
- Create: `README.md`
- Modify: `main.ahk`
- Modify: `docs/harness/manifest.md`
- Modify: `config/settings.example.ini`

**Interfaces:**
- Consumes: repository root, AutoHotkey executable path, `main.ahk`, local configuration.
- Produces: `Manage-Startup.ps1 -Action Install|Remove|Status`, palette diagnostics command, complete setup/recovery documentation.

- [ ] **Step 1: Add a failing PowerShell contract check**

```powershell
$commands = Get-Command "$PSScriptRoot\..\scripts\Manage-Startup.ps1" -Syntax -ErrorAction Stop
if ($commands -notmatch '-Action') { throw 'Manage-Startup.ps1 must expose -Action' }
```

- [ ] **Step 2: Run the parser/contract check and confirm failure**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1`.

Expected: failure because startup management is absent.

- [ ] **Step 3: Implement idempotent startup and diagnostics**

Use `WScript.Shell.CreateShortcut` to create exactly one shortcut under `[Environment]::GetFolderPath('Startup')`, targeting `AutoHotkey64.exe` with `main.ahk` as the quoted argument and the repository as working directory. `Remove` deletes only that exact shortcut; `Status` performs no mutation. Add a `system.diagnostics` command that reports configuration errors, missing executables, duplicate command IDs/hotkeys, unwritable state/log directories, and credential target names without reading credentials.

- [ ] **Step 4: Document setup and validate dry-run behavior**

README must cover AutoHotkey 2.0.26+, copying `settings.example.ini` to ignored `settings.local.ini`, credential registration, hub keys, every module, emergency stop, startup status/install/remove, log/state locations, file undo limits, and the final manual Kakao test. Run `Manage-Startup.ps1 -Action Status`; do not install startup during automated verification.

- [ ] **Step 5: Commit operations and documentation**

```powershell
git add scripts README.md main.ahk docs/harness/manifest.md config/settings.example.ini
git commit -m "docs: add hub setup and diagnostics"
```

### Task 10: Integrated verification and manual QA gate

**Files:**
- Create: `docs/harness/runs/2026-08-12-local-automation-hub/verification.md`
- Modify: `tasks/PLAN-local-automation-hub.md`

**Interfaces:**
- Consumes: every prior module and test runner.
- Produces: artifact-backed final verification report and an explicit list of manual checks that remain user-owned.

- [ ] **Step 1: Run all automated validation**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
git diff --check
```

Expected: every `.ahk` file passes `/Validate`, all related tests exit `0`, every PowerShell file parses, and Git reports no whitespace errors.

- [ ] **Step 2: Run security and repository-boundary searches**

```powershell
rg -n -i "password\s*=\s*[^;\r\n]+|secret\s*=\s*[^;\r\n]+|A_Clipboard.*password|SendText\(.*password" . -g '!tasks/**' -g '!docs/**'
git status --short
```

Expected: no literal password or secret values; only expected uncommitted verification report/plan checkbox changes are present.

- [ ] **Step 3: Record automated evidence**

Write exact command, timestamp, exit code, pass/fail count, changed files, and redacted observations to `verification.md`. Do not claim actual Kakao login, multi-monitor placement, Explorer COM selection, or Startup-folder installation succeeded unless each was visibly performed.

- [ ] **Step 4: Perform user-visible manual QA with explicit confirmation**

Run the hub only after automated gates pass. Verify palette open/search/numeric execution, emergency stop, one single-line and one multiline snippet with clipboard restoration, partial-failure workspace summary, window left/right/full placement, temp-file preview/apply/undo, mock login, and finally one real credential registration/login with the user present. Multi-monitor movement is marked `not applicable` when only one monitor exists.

- [ ] **Step 5: Commit verification artifacts**

```powershell
git add docs/harness/runs/2026-08-12-local-automation-hub/verification.md tasks/PLAN-local-automation-hub.md
git commit -m "test: verify local automation hub"
```

## Final Definition of Done

- All five modules are reachable through the command palette and failures stay isolated.
- AutoHotkey `/Validate`, module tests, PowerShell parsing, security search, and `git diff --check` pass.
- No credential value appears in versioned files, logs, process arguments, or clipboard; native temporary buffers are wiped after callback use.
- File mutation is impossible without fresh preview and confirmation, and the latest successful mapping can be undone once.
- The verification report distinguishes automated evidence from manual or not-applicable checks.
- Startup registration and real Kakao login are performed only with explicit user participation after automated gates pass. Kakao login is enabled only when the installed UI exposes a stable, positively verified password target; otherwise diagnostics remain available and the module fails closed.
