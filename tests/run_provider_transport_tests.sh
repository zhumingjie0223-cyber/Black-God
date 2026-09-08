#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$test_dir/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/nexus-provider-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$build_dir/module-cache" \
  "$repo_dir/ios-app/NexusSSEParser.swift" \
  "$repo_dir/ios-app/NexusClient.swift" \
  "$test_dir/provider_transport_tests.swift" \
  -o "$build_dir/provider-tests"
"$build_dir/provider-tests" "$test_dir/provider_fixtures"
