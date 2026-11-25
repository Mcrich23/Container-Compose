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
