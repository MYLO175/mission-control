#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init chat-images
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Assistant/Conversation/Conversations.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Assistant/Conversation/ChatDraftStore.swift MissionControl/Assistant/Conversation/PARequestQueue.swift MissionControl/Assistant/Conversation/ChatImages.swift Tests/Assistant/ChatImageChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
