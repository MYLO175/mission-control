#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init workspace
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Dashboard/WorkspaceModels.swift MissionControl/Dashboard/WorkspaceGeometry.swift MissionControl/Dashboard/WorkspaceControls.swift Tests/Dashboard/WorkspaceChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
