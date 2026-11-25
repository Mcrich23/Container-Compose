Container dependency 1.7.1 (official latest release: https://github.com/apple/container/releases/tag/1.7.1), containerization 0.54.0. Installed runtime: container CLI 1.5.0. Base: 505e2f190ab19f8ec55cff8668b7d94eae1d08b2.

Commands:
- `swift package resolve`: passed.
- `container system start`: passed.
- `swift build`: passed after replacing removed Application.BuildCommand API with installed container build invocation.
- `swift test --filter Container_Compose_StaticTests`: 315 passed, 0 failed, 0 skipped.
- `swift test --filter Container_Compose_DynamicTests`: 23 passed, 1 failed, 0 skipped (24 tests, 5 suites).
- `git diff --check`: passed.

The dynamic failure is testRelativeBindMountUsesComposeFileDirectory: its YAML healthcheck contains unescaped nested quotes after Swift string decoding. The identical fixture exists on origin/main; parsing fails before container execution. No baseline suite rerun was performed, so baseline attribution is based on unchanged fixture and parser, rather than a separate baseline run.

Disk started at 24 GiB free and remained above 13 GiB. Existing caches were reused. Test-prefixed containers and volumes were removed. Images were retained because no initial image inventory was captured, so ownership cannot be established safely. A test UUID container and buildkit remain; runtime remains started. Cleanup of all listed containers was rejected by automatic approval review; selective test-prefix cleanup succeeded. No blanket prune was used.

Logs are included alongside this report. README unchanged.

Follow-up validation:
- Original unchanged isolated bind-mount test: 0 passed, 1 failed, 0 skipped, reproducing the exact YAML parser error before container execution (cc-original-isolated.log).
- Quoting correction alone exposed a project-name mismatch: Compose uses deploy, while the assertion expects the temporary project name (cc-quoting-only-isolated.log).
- Fixture now uses a YAML single-quoted shell command and an explicit temporary project name. Shell command and assertions are preserved. Corrected isolated test: 1 passed, 0 failed, 0 skipped (cc-fixed-isolated.log).
- Full dynamic rerun: 23 passed, 1 failed, 0 skipped. Bind-mount test passed; WordPress bootstrap failed with Address already in use (errno 48), a different runtime failure (cc-dynamic-final.log).
- No baseline execution on main was performed.
- Removed prior stopped UUID container B0E73BD8-79FE-483F-818C-A97124BA725A, whose exact ID appears in the committed original dynamic log. Buildkit, images and runtime retained because ownership/initial state is not established. Runtime inventory includes other test IDs absent from this run, so broad cleanup or runtime shutdown would risk unrelated testing.

- Isolated WordPress rerun: 1 passed, 0 failed, 0 skipped (cc-wordpress-isolated.log).

- Second full dynamic run: 23 passed, 1 failed, 0 skipped (cc-dynamic-retry.log). WordPress up and corrected bind-mount test passed; two-container down test failed during WordPress bootstrap with Address already in use (errno 48). This is consistent with runtime contention, but its cause is not proven. PR remains draft because neither full rerun passed.
- Selective stopped-container cleanup is recorded in cleanup-followup.log. Running resources were retained to avoid disrupting concurrent testing. Disk remained above 8 GiB free.
