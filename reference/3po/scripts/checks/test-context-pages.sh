#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init context-pages
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" \
  MissionControl/Infrastructure/Storage/Cache.swift \
  MissionControl/Infrastructure/Storage/LocalRecordRepository.swift \
  MissionControl/Memory/Context/ContextPages.swift \
  MissionControl/Memory/Context/ContextPageStore.swift \
  Tests/Memory/ContextPageChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
