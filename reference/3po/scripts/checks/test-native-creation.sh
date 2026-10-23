#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init native-creation
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Infrastructure/Models/Models.swift MissionControl/Infrastructure/Actions/ActionModels.swift MissionControl/Infrastructure/Actions/NativeEditing.swift MissionControl/Infrastructure/Actions/NativeCreation.swift MissionControl/Infrastructure/Actions/NativeCreationStore.swift Tests/Infrastructure/Actions/NativeCreationChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
