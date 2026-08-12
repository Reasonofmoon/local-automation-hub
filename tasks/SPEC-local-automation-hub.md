# SPEC: Local Automation Hub

## 목표

AutoHotkey v2 기반 통합 단축키 허브로 다섯 가지 로컬 업무 자동화를 안전하고 확장 가능하게 제공한다.

## 승인된 요구사항

- 호출: `CapsLock + Space` 명령 팔레트와 직접 단축키
- 모듈: 카카오톡 보안 로그인, 문구 입력, 업무 모드, 창 정렬, 파일 정리
- 비밀번호: Windows 자격 증명 저장소만 사용
- 파일 정리: 선택 파일만 미리보기 후 확인, `YYYY-MM-DD_` 접두사, `YYYY\MM` 분류, 충돌 시 번호 추가, 1회 되돌리기
- 긴급 정지: `Ctrl + Alt + Esc`
- 시작 프로그램 등록·해제와 진단 제공

## 기술 설계

- Runtime: AutoHotkey v2
- Architecture: 모듈형 Generate-Verify 하네스
- Configuration: 비밀정보가 없는 로컬 설정
- Secret storage: Windows 자격 증명 저장소
- Supporting scripts: 필요한 최소 PowerShell 도우미
- Detailed design: `docs/superpowers/specs/2026-08-12-local-automation-hub-design.md`

## 품질 게이트

- 비밀번호 평문 검색 결과 0건
- 모든 `.ahk` 파일의 v2 구문 검사 통과
- 설정·단축키 충돌 검사 통과
- 임시 파일 기반 파일 정리 및 되돌리기 테스트 통과
- 실제 계정 테스트 전 모의 로그인 테스트 통과
- 관련 검사만 실행하고 결과를 기록

## 단계 경계

본 명세 승인 후 상세 구현 계획을 작성한다. 구현 계획 승인 전 `.ahk` 코드, 자격 증명, 시작 프로그램 등록을 변경하지 않는다.

