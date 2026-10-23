#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init performance
# Measurements have no timing pass threshold. Debug matches the default build;
# release is a separately labelled comparison, not the installed app's mode.
case "${MISSIONCONTROL_PERFORMANCE_MODE:-debug}" in
  debug) performance_flags=(-Onone) ;;
  release) performance_flags=(-O) ;;
  *) print -u2 -- "MISSIONCONTROL_PERFORMANCE_MODE must be debug or release."; exit 2 ;;
esac
print -- "Performance compile mode: ${MISSIONCONTROL_PERFORMANCE_MODE:-debug}"
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" "${performance_flags[@]}" MissionControl/Infrastructure/Storage/Cache.swift MissionControl/Infrastructure/Storage/LocalRecordRepository.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeCanonicalNotebook.swift MissionControl/Projects/LifeWorkspace.swift MissionControl/Projects/LifeProjectPlacement.swift MissionControl/Projects/LifeWorkspaceQuery.swift MissionControl/Assistant/Conversation/Conversations.swift Tests/Performance/PerformanceChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
