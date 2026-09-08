#!/usr/bin/env bash
set -euo pipefail

# This runs actual production Swift without requiring signing or API credentials.
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$test_dir/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/nexus-runtime-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  "$repo_dir/ios-app/NexusAgentTypes.swift" \
  "$repo_dir/ios-app/NexusPlanning.swift" \
  "$repo_dir/ios-app/NexusVerifier.swift" \
  "$repo_dir/ios-app/NexusTooling.swift" \
  "$repo_dir/ios-app/NexusToolCalls.swift" \
  "$repo_dir/ios-app/NexusLocalTools.swift" \
  "$repo_dir/ios-app/NexusShellTool.swift" \
  "$repo_dir/ios-app/NexusExecutor.swift" \
  "$repo_dir/ios-app/NexusModelBridge.swift" \
  "$test_dir/ios_runtime_tests.swift" \
  "$test_dir/ios_agent_tests.swift" \
  -o "$build_dir/runtime-tests"
"$build_dir/runtime-tests"
