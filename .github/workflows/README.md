# GitHub Actions Workflows

This directory contains GitHub Actions workflows for Container-Compose.

## Available Workflows

### 1. Run Tests (`tests.yml`)

Automatically runs on:
- Pull requests targeting `main` branch
- Changes to `Sources/`, `Tests/`, `Package.swift`, or workflow files

Can also be triggered manually via the GitHub Actions UI.

**Requirements:** macOS 15 runner (tests require macOS environment)

### 2. PR Comment Tests (`pr-comment-tests.yml`)

Runs tests when requested via a comment on a pull request.

**How to use:**
1. Comment `/test` on any pull request
2. The workflow will:
   - React with a 🚀 emoji to acknowledge
   - Check out the PR branch
   - Run the test suite on macOS
   - Post results back as a comment

**Example:**
```
@copilot /test
```

or simply:
```
/test
```

**Requirements:** 
- macOS 15 runner
- Permissions to comment on PRs

## Test Environment

All tests run on macOS 15 with Swift 6.0+ because:
- Container-Compose depends on `apple/container` package
- The upstream dependency requires macOS-specific `os` module
- Swift Package Manager dependencies are cached for faster builds

## Troubleshooting

If tests fail to run:
1. Check that the PR has no merge conflicts
2. Verify Package.swift is valid
3. Check the Actions tab for detailed logs
4. Ensure macOS 15 runners are available
