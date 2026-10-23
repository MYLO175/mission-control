#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init conversation-repository
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Infrastructure/Storage/Cache.swift MissionControl/Infrastructure/Storage/LocalRecordRepository.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Assistant/Conversation/Conversations.swift MissionControl/Assistant/Conversation/ConversationRepository.swift Tests/Assistant/ConversationRepositoryChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
