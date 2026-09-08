#!/usr/bin/env bash
set -euo pipefail
storage_app_dir="$(cd "$(dirname "$0")/.." && pwd)"
storage_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/nexus-storage-build.XXXXXX")"
trap 'rm -rf "$storage_test_dir"' EXIT
xcrun swiftc -swift-version 5 -D NEXUS_STORAGE_TESTS \
  -module-cache-path "$storage_test_dir/modules" \
  "$storage_app_dir/NexusMemory.swift" \
  "$storage_app_dir/NexusEvaluation.swift" \
  "$storage_app_dir/NexusTaskHistory.swift" \
  "$storage_app_dir/NexusDataReset.swift" \
  "$storage_app_dir/NexusAgentTypes.swift" \
  "$storage_app_dir/StorageTests/StorageTests.swift" \
  -o "$storage_test_dir/storage-tests"
"$storage_test_dir/storage-tests"
