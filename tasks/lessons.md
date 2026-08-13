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

## 2026-08-13 - Treat CLI JSON as a framed protocol

- A successful CLI can write a harmless notice before its machine-readable response; parsing all stdout as one JSON document couples the adapter to incidental framing.
- Extract only bounded line-delimited candidates, then require exactly one top-level protocol envelope with `id`, Boolean `ok`, and the matching `result` or `error` member. Nested JSON-shaped log lines are not responses.
- Framing errors must identify the operation and report only safe structure metadata such as nonempty line count, candidate count, and single/multi-line shape. Never echo stdout, tokens, terminal contents, or envelope values.

## 2026-08-13 - Bound Orca JSON by payload size, not line formatting

- Pretty-printed Orca envelopes may legitimately contain thousands of nonempty lines; a fixed line cap rejects valid output solely because of formatting.
- Keep the UTF-8/character payload bound and report line count only as safe diagnostic metadata. The balanced top-level scanner and exact-one-envelope validation remain the framing protections.

## 2026-08-13 - Mirror installed CLI response schemas in contract tests

- Orca `terminal wait --json` returns readiness under `result.wait.satisfied`; its `status` can remain `running` even when the requested `tui-idle` condition is satisfied.
- A fake response shaped as a convenient root-level `state` created a false-green test and made every real terminal look failed.
- Treat a valid unsatisfied wait as a created terminal that may need first-run user input. Reserve `failed` for create, transport, or malformed-response errors, and preserve only bounded error code/message fields.
