#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init life-workspace
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Projects/LifeWorkspace.swift MissionControl/Projects/LifeProjectPlacement.swift MissionControl/Projects/LifeWorkspaceQuery.swift MissionControl/Projects/LifeWorkspaceStore.swift Tests/Projects/LifeWorkspaceChecks.swift Tests/Projects/LifeWorkspaceIndexChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
