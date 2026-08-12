# Local Automation Hub

Local Automation Hub는 Windows 11에서 AutoHotkey v2 명령을 한 곳에서 실행하는 작은 로컬 허브입니다. 모든 기능은 로컬 프로세스와 로컬 파일만 사용하며, 실패한 명령은 다른 명령을 중단시키지 않습니다.

## 요구 사항과 설치

- Windows 11
- AutoHotkey v2.0.26 이상 64-bit (`C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`)
- PowerShell 5.1 이상

1. 저장소를 원하는 로컬 폴더에 둡니다.
2. `config/settings.example.ini`를 `config/settings.local.ini`로 복사합니다. `settings.local.ini`는 `.gitignore`에 포함되어 있으므로 컴퓨터별 경로만 저장하세요.
3. `settings.local.ini`의 `General.KakaoPath`, 스니펫, workspace 항목을 필요에 맞게 바꿉니다. Kakao 계정 값에는 비밀번호가 아니라 Credential Manager target 이름만 적습니다.
4. `main.ahk`를 AutoHotkey로 실행합니다.

Credential Manager에 target을 등록하려면 다음을 실행하고 프롬프트에 값을 입력합니다. 값은 SecureString으로 입력되며, 파일·로그·명령줄에는 저장되지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Register-Credential.ps1 -TargetName LocalAutomationHub/Kakao/work
```

등록 helper는 target 이름만 출력합니다. 허브 자체는 자격 증명 값을 설정 파일, 로그, 클립보드 또는 프로세스 인수에 기록하지 않습니다.

## 기본 키와 명령

- `CapsLock + Space`: 명령 팔레트를 열고 label/tag를 검색합니다. `Enter`, 더블클릭 또는 `1`~`9`로 선택한 명령을 실행합니다.
- `Ctrl + Alt + Esc`: emergency stop. 진행 중인 명령이 취소 상태를 확인하면 이후 작업을 중단합니다.
- `system.diagnostics`: 설정 오류, 존재하지 않는 실행 파일, 명령 ID/핫키 중복, log/state 디렉터리 상태, Credential Manager target 이름만 보고합니다. Credential Manager를 읽지 않습니다.
- `snippet.<id>`: 설정된 단문/복문 스니펫을 입력합니다. 다중 행 입력은 기존 클립보드를 복원합니다.
- `workspace.<mode>`: app/folder/url 항목을 순서대로 시작하고 실패 항목을 요약합니다.
- `window.left`, `window.right`, `window.full`: 현재 창을 모니터 작업 영역에 배치합니다.
- `window.monitor-left`, `window.monitor-right`: 창을 다음 모니터로 이동합니다. 모니터가 하나면 아무 작업도 하지 않습니다.
- `files.organize-selected`: Explorer에서 선택한 일반 파일을 미리 보고 확인한 뒤 `YYYY\MM\YYYY-MM-DD_name.ext`로 이동합니다.
- `files.undo-last-organize`: 마지막으로 성공한 파일 이동 매핑만 한 번 되돌립니다. 원래 위치가 사용 중이면 중단합니다.

## 시작프로그램 등록과 복구

자동 검증은 항상 조회만 수행합니다.

```powershell
# 현재 등록 상태만 조회하며 Startup 폴더를 변경하지 않습니다.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage-Startup.ps1 -Action Status

# 사용자가 명시적으로 요청한 경우에만 정확히 하나의 바로가기를 생성합니다.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage-Startup.ps1 -Action Install

# 허브가 만든 정확한 바로가기 하나만 제거합니다.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manage-Startup.ps1 -Action Remove
```

바로가기는 Windows Startup 폴더의 `Local Automation Hub.lnk` 하나이며, `AutoHotkey64.exe`를 대상으로 하고 저장소의 `main.ahk`를 인수로 사용합니다. `Status`는 설치/삭제를 하지 않습니다.

## 로그와 상태

- 로그: `var/logs/hub.log` (민감한 key/value는 `[REDACTED]` 처리)
- 파일 undo 상태: `var/state/file-undo.ini`

파일 정리는 항상 새 미리보기와 확인 이후에만 수행됩니다. 마지막 성공 매핑 하나만 저장하므로 여러 번의 이동 이력이나 임의 파일 복구에는 사용할 수 없습니다. 원본/목적지 상태가 미리보기와 달라지면 전체 작업을 중단하고 새 미리보기를 요구합니다.

## Kakao 자동화 상태

실제 Kakao 로그인/계정 전환 자동화는 현재 지원하지 않으며 런타임 모듈과 로그인 명령을 등록하지 않습니다. 설치된 Kakao UI에서 안정적인 로그인/password control 신호를 관찰하지 못해 Task 8을 unsupported로 종료했습니다. 근거는 [kakao-ui-capability.md](docs/harness/runs/2026-08-12-local-automation-hub/kakao-ui-capability.md)에서 확인할 수 있습니다.

따라서 Credential Manager target 등록 helper는 존재하지만 실제 Kakao 로그인 UI에 값을 입력하지 않습니다. 최종 수동 Kakao 테스트는 사용자가 직접 UI를 확인하고 명시적으로 진행해야 하며, 자동 검증은 Kakao 창을 열거나 자격 증명을 읽지 않습니다.

## 검증

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate-PowerShell.ps1
git diff --check
```

이 프로젝트는 AutoHotkey/PowerShell만 포함하므로 TypeScript가 없고 `npx tsc --noEmit`은 적용 대상이 아닙니다. AutoHotkey `/Validate`와 프로세스 기반 테스트 runner가 관련 검증을 대신합니다.
