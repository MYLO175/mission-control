#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init conversations
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Assistant/Conversation/Conversations.swift MissionControl/Assistant/Conversation/AssistantTranscriptProjection.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift Tests/Assistant/ConversationChecks.swift Tests/Assistant/AssistantTranscriptProjectionChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
