# Lessons

사용자 교정에서 반복 가능한 작업 패턴을 기록한다.

- AutoHotkey v2 identifiers are case-insensitive; never name locals after classes, and test startup composition by executing it headlessly rather than relying on `/Validate` alone.
- User-visible commands need execution-level UI feedback tests, not only return-value or log assertions.
## 2026-08-13 - Treat reported line numbers as evidence, not identity

- A UI error ending in `[line 256]` did not identify the AutoHotkey source line 256. The adapter appends PowerShell `InvocationInfo.ScriptLineNumber`, and line 256 in that script was a strict-mode property lookup.
- Reproduce through the real process boundary and capture the original result before editing the line that happens to share the same number.
- Under PowerShell strict mode, do not read `$Object.PSObject.Properties.Name` when the property collection may be empty. Enumerate `PSPropertyInfo` objects and compare each `.Name` instead.
- Treat successful create responses as potentially asynchronous or
  schema-nested: extract handles only from semantically known terminal
  containers, then reconcile through an exact list selector before retrying or
  failing. Never treat generic repository/worktree/result IDs as terminal
  handles, and keep schema diagnostics to key names rather than values.
