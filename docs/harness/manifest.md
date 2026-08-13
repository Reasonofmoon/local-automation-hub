# Local Automation Hub Harness

## 목적과 트리거

AutoHotkey 기반 로컬 자동화를 새로 추가하거나 수정·검증·재실행할 때 사용한다. 단순 설명 요청이나 AutoHotkey와 무관한 웹 애플리케이션 작업에는 사용하지 않는다.

## 아키텍처

Primary pattern: Generate-Verify

```text
orchestrator → builder → qa-reviewer → orchestrator
```

## 단계

1. **Context**: 명세, 현재 설정, 기존 모듈, 작업 트리를 읽는다.
2. **Contract**: 입력, 출력, 위험 수준, 실패 동작, 검증 명령을 확정한다.
3. **Build**: 한 번에 하나의 논리적 모듈만 구현한다.
4. **Verify**: 구문, 보안 경계, 관련 동작, 회귀를 검사한다.
5. **Integrate**: 허브에 명령을 등록하고 충돌 검사를 실행한다.
6. **Report**: 변경 파일, 실행 명령, 결과, 남은 수동 검증을 기록한다.

## 입력 계약

- 승인된 설계 또는 구현 계획
- 수정 범위와 제외 범위
- 실제 파일·창·앱 상태에 관한 확인된 근거

## 출력 계약

- 범위 내 코드·설정·문서
- 실행한 관련 검증 명령과 실제 결과
- 비밀정보를 제거한 진단 기록
- 수동 확인이 필요한 항목

## 실패와 폴백

- 대상 창을 검증할 수 없으면 키 입력을 중단한다.
- 자격 증명을 읽을 수 없으면 등록 안내만 표시한다.
- 파일 미리보기와 실제 대상이 달라지면 작업을 중단하고 다시 미리보기한다.
- 일부 업무 모드 항목이 실패하면 나머지를 실행하고 결과를 합산한다.
- 검증 실패 시 허브 통합과 자동 시작 등록을 진행하지 않는다.

## 공개·비공개 경계

- 비밀번호, 클립보드 내용, 개인 메시지, 자격 증명 값은 저장·로그·커밋하지 않는다.
- 계정 별칭과 자격 증명 대상 이름만 설정에 둘 수 있다.
- 로컬 절대 경로는 사용자 전용 설정으로 분리하고 공개 예제에는 자리표시자를 사용한다.

## 검증 명령 계약

구현 계획에서 실제 설치 경로와 지원 옵션을 확인한 명령만 사용한다. 최소 검증은 AutoHotkey v2 구문 검사, PowerShell 파서 검사, 설정 충돌 검사, 임시 파일 시나리오다. TypeScript 소스가 추가되는 경우에만 `npx tsc --noEmit`을 실행한다.

## Orca AI development workspace 기록

`workspace.ai-development`는 중간 위험도(`medium`)의 독립 팔레트 명령이다.
매 실행마다 네이티브 폴더 선택기를 열고, 선택한 기존 Git checkout을
`git -C <path> rev-parse --show-toplevel`로 확인한 뒤 `path:<root>` selector로
Orca에 전달한다. `runtime.state=ready`와 `runtime.reachable=true`가 모두
확인되지 않으면 repository 등록이나 터미널 생성 없이 중단한다.

준비 대상은 고정된 네 가지다: `Codex/codex`, `Claude/claude`, `Grok/grok`,
`Gemini/gemini`. workspace·제목·명령 identity가 확인된 live 터미널만
재사용하며, 그 외에는 CLI를 실행하고 `tui-idle`까지 bounded wait를 한다.
결과는 `created`, `reused`, `skipped`, `failed`로 집계한다. CLI 누락이나 한
터미널의 create/wait 실패는 해당 항목에 격리한다.

이 경로는 clone, branch, Git worktree, prompt 전송, 기존 터미널 종료/교체를
수행하지 않는다. `[Workspace.development]`는 기존의 설정 가능한
app/folder/URL 샘플이고 Orca workflow가 아니므로 두 명령을 문서와 QA에서
구분한다. 자동 검증은 임시 Git repository와 fake Orca/CLI만 사용한다.

Task 3의 통합 검증 산출물은
[`runs/2026-08-13-orca-ai-development-workspace/verification.md`](runs/2026-08-13-orca-ai-development-workspace/verification.md)에
기록한다. 해당 보고서는 명령별 현지 ISO-8601 timestamp, exit code, pass 수,
whitespace/금지 명령 검색, AutoHotkey PID audit, read-only Orca readiness,
그리고 실제 Orca UI를 수행하지 않은 이유를 분리해 적는다. 사용자가 이번
턴에 disposable checkout을 선택하지 않았으므로 수동 QA는 사용자 소유로
남긴다.

Minor: 이 저장소의 지원 실행 파일과 이번 자동 검증은
`AutoHotkey64.exe`(x64) 기준이다. x86 AutoHotkey runtime은 별도로 검증하지
않았다.

## 변경 이력

| 날짜 | 대상 | 변경 | 이유 |
| --- | --- | --- | --- |
| 2026-08-12 | 전체 | 초기 하네스 설계 | 통합 단축키 허브 신설 |
| 2026-08-13 | `workspace.ai-development` | Orca AI workspace 계약·자동 검증·수동 QA 경계 기록 | 기존 checkout 재사용과 무프롬프트 안전 경계 명시 |

## Task 9 운영 표면

`scripts/Manage-Startup.ps1`은 `-Action Install|Remove|Status`를 제공합니다. `Install`은 Windows Startup 폴더에 `Local Automation Hub.lnk` 정확히 하나를 만들고 AutoHotkey v2 실행 파일, `main.ahk` 인수, 저장소 working directory를 기록합니다. `Remove`는 그 정확한 경로만 삭제하며, `Status`는 shortcut 속성만 읽고 변이하지 않습니다. 자동 검증에서는 `Status`만 실행합니다.

`system.diagnostics` 팔레트 명령은 설정 오류, 누락 실행 파일, 중복 command ID/hotkey, `var/logs`·`var/state` 상태, Credential Manager target 이름을 보고합니다. credential 값이나 Credential Manager blob은 읽지 않습니다. Kakao 로그인 자동화는 Task 8에서 unsupported로 폐기되어 현재 runtime/module/login command가 없습니다. capability 근거는 `docs/harness/runs/2026-08-12-local-automation-hub/kakao-ui-capability.md`이며, 등록 helper는 target 이름만 받아 Credential Manager에 등록합니다.

검증:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Validate-PowerShell.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Manage-Startup.ps1 -Action Status
git diff --check
```

AutoHotkey는 `tests/Run-Tests.ps1`의 process-owned runner와 `/Validate`로 검증합니다. TypeScript 소스가 없으므로 `npx tsc --noEmit`은 적용 대상이 아닙니다. Startup `Install`/`Remove`와 real Kakao UI는 사용자 명시적 수동 확인 범위입니다.
