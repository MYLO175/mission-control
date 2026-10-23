#!/bin/zsh
set -euo pipefail
runtime_fixture_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
# A review worktree may point at the integration checkout's current source files.
# Default after integration is this same checkout. The fixture stays local.
runtime_source_root="${MISSIONCONTROL_RUNTIME_SOURCE_ROOT:-$runtime_fixture_root}"
source "$runtime_source_root/scripts/lib/test-env.sh"
missioncontrol_test_init runtime-performance
case "${MISSIONCONTROL_PERFORMANCE_MODE:-debug}" in
  debug) runtime_flags=(-Onone) ;;
  release) runtime_flags=(-O) ;;
  *) print -u2 -- "MISSIONCONTROL_PERFORMANCE_MODE must be debug or release."; exit 2 ;;
esac
print -- "Runtime performance compile mode: ${MISSIONCONTROL_PERFORMANCE_MODE:-debug}"
runtime_names=(Infrastructure/Storage/Cache Infrastructure/Storage/LocalRecordRepository Memory/Records/PAMemory Memory/Notebook/LifeNotebook Memory/Notebook/LifeOrganisation Memory/Learning/MemoryLearning Assistant/Profile/PALearningQuestion Memory/Records/MemoryDependencies Infrastructure/Models/Models Review/Inbox/ReviewPolicyModels Background/Briefing/Briefing Memory/Records/PAMemoryStore Memory/Notebook/LifeCanonicalNotebook Projects/LifeWorkspace Projects/LifeProjectPlacement Projects/LifeWorkspaceQuery Assistant/Conversation/Conversations Assistant/Conversation/ConversationRepository)
runtime_sources=()
for runtime_name in "${runtime_names[@]}"; do
  runtime_sources+=("$runtime_source_root/MissionControl/$runtime_name.swift")
done
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 "${runtime_flags[@]}" "${runtime_sources[@]}" "$runtime_fixture_root/Tests/Performance/RuntimePerformanceChecks.swift" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
