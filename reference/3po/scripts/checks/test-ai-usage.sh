#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init ai-usage
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Infrastructure/Usage/AIUsage.swift MissionControl/Infrastructure/Usage/AIUsageStore.swift Tests/Infrastructure/Usage/AIUsageChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
