#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
swift_binary=${SWIFT_BINARY:-}
if [[ -z "$swift_binary" ]]; then
    if command -v swift >/dev/null 2>&1; then
        swift_binary=$(command -v swift)
    elif [[ -x /workspace/.toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swift ]]; then
        swift_binary=/workspace/.toolchains/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin/swift
    else
        printf '%s\n' 'Swift not found. Set SWIFT_BINARY or run tools/intelligence/install-swift-linux.sh.' >&2
        exit 1
    fi
fi

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/black-god-intelligence.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT
mkdir -p "$scratch_dir/Sources" "$scratch_dir/Tests"
cp "$script_dir/Package.swift" "$scratch_dir/Package.swift"
cp -R "$script_dir/Support" "$scratch_dir/Support"

sources=(NexusIntent NexusIntentRegression NexusRecall NexusEvidenceAudit NexusReasoningEngine NexusExecutor
    NexusTooling NexusEvidence NexusAgentTypes NexusVerifier NexusNativeAgent
    NexusToolCalls NexusToolSchema NexusAdditionalProtocols NexusCognitiveTools
    NexusLocalTools NexusShellTool NexusStreamDecoder NexusToolCallAssembler
    NexusReadOnlyLookup NexusAgentCheckpoint NexusModelRouting NexusDataConsent
    NexusWorkspaceTransactions NexusTaskEpisodes NexusConversationStore NexusMemory
    NexusSkills NexusBuiltinSkills NexusSessionLibrary NexusDataVault NexusRecoveryPolicy
    NexusCognitiveControl NexusSelfContinuity NexusTaskService NexusSandboxTools NexusLinuxTool NexusWorkspaceIdentity NexusShuyu
    NexusLiveExecution NexusSkillPractice NexusEvaluation NexusPresence NexusRuntime
    NexusRecovery NexusAutonomy NexusPermissions NexusApproval NexusTaskContract NexusRunMetrics ChatViewModel)
for source in "${sources[@]}"; do
    cp "$repo_dir/ios-app/$source.swift" "$scratch_dir/Sources/$source.swift"
done
cp "$script_dir/Support/PlatformSupport.swift" "$scratch_dir/Sources/PlatformSupport.swift"

# Only imports are adapted. Production Swift source content is kept byte-for-byte.
test_files=(NexusIntentTests NexusRecallTests NexusEvidenceReviewTests
    NexusIntentExecutionTests NexusNativeAgentTests NexusToolBoundaryTests NexusReadOnlyLookupTests
    NexusModelRoutingTests NexusWorkspaceTransactionTests NexusIntelligenceTests NexusTaskEpisodeTests
    NexusSessionLibraryTests NexusDataVaultTests NexusTaskServiceIntentTests NexusRecoveryTests NexusChatRecoveryTests
    NexusRetrievalExecutionTests NexusAgentCheckpointTests NexusToolGovernanceIntegrationTests
    NexusIntentRecallPipelineTests NexusRetrievalEvidenceTests NexusCognitiveTests)
for test_file in "${test_files[@]}"; do
    source_test="$repo_dir/tests/ios/$test_file.swift"
    [[ -f "$source_test" ]] || { printf 'Required regression test missing: %s\n' "$source_test" >&2; exit 1; }
    sed 's/@testable import BlackGod$/@testable import BlackGodCore/' "$source_test" > "$scratch_dir/Tests/$test_file.swift"
done
for test_file in "$script_dir"/Tests/*.swift; do
    [[ -f "$test_file" ]] || continue
    cp "$test_file" "$scratch_dir/Tests/"
done
export BLACK_GOD_REPO_ROOT="$repo_dir"
export NEXUS_INTENT_FIXTURE_PATH="$repo_dir/tests/fixtures/nexus-intent-50.json"
[[ -f "$NEXUS_INTENT_FIXTURE_PATH" ]] || { printf '%s\n' 'Required 50-case intent fixture is missing.' >&2; exit 1; }
# Managed workers may have read-only user homes. Keep SwiftPM and Clang caches
# inside the same removable scratch directory without changing HOME.
export CLANG_MODULE_CACHE_PATH="$scratch_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$scratch_dir/module-cache"
"$swift_binary" --version
"$swift_binary" test --package-path "$scratch_dir" --jobs "${SWIFT_TEST_JOBS:-4}" \
    --cache-path "$scratch_dir/cache" --config-path "$scratch_dir/config" \
    --security-path "$scratch_dir/security" "$@"
