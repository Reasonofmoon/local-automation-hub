# Fix Orca large JSON envelope

1. Add process-boundary regressions for a >3716-line, sub-1MiB pretty repository-list envelope and an over-1MiB envelope. Verify the former is currently rejected because of the line cap.
2. Remove only the arbitrary nonempty-line rejection while preserving the 1MiB output bound and existing balanced-object/exact-one-envelope checks. Verify the focused adapter test passes.
3. Run the focused PowerShell test, full AutoHotkey test suite, parser validation, forbidden-pattern scan, and inspect the diff before committing the scoped change.
