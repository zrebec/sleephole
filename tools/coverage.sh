#!/bin/sh
# SleepCore test coverage report (lines/functions per file). Usage: tools/coverage.sh
set -e
cd "$(dirname "$0")/../SleepCore"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --enable-code-coverage 2>&1 | grep -E "Test run|✘"
B=.build/out/Products/Debug
[ -d "$B" ] || B=$(swift build --show-bin-path)
xcrun llvm-cov report "$B/SleepCoreTests.xctest/Contents/MacOS/SleepCoreTests" \
  -instr-profile "$B/codecov/default.profdata" -ignore-filename-regex="Tests|\.build"
