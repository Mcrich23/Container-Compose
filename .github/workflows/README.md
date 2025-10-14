# GitHub Actions Workflows

This directory contains GitHub Actions workflows for Container-Compose.

## Available Workflows

### Tests (`tests.yml`)

A required status check for pull requests that must be run manually before merging.

**How to run:**
1. Go to the "Actions" tab in the GitHub repository
2. Select "Tests" workflow from the left sidebar
3. Click "Run workflow" button
4. Select the branch (e.g., your PR branch)
5. Click "Run workflow" to start the tests

**Requirements:** macOS 15 runner (tests require macOS environment)

**Note:** Tests are configured as a required check but do NOT run automatically on each commit. This allows you to control when tests run (e.g., after you're done with a series of commits) while still enforcing that tests must pass before merging.

## Test Environment

All tests run on macOS 15 with Swift 6.0+ because:
- Container-Compose depends on `apple/container` package
- The upstream dependency requires macOS-specific `os` module
- Swift Package Manager dependencies are cached for faster builds

## Troubleshooting

If tests fail to run:
1. Check that the workflow was triggered on the correct branch
2. Verify Package.swift is valid
3. Check the Actions tab for detailed logs
4. Ensure macOS 15 runners are available
5. If the workflow doesn't appear as a status check, you may need to run it once first
