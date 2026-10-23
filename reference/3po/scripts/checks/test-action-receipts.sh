#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init action-receipts
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Infrastructure/Models/Models.swift MissionControl/Infrastructure/Actions/ActionModels.swift MissionControl/Infrastructure/Actions/NativeCreation.swift MissionControl/Infrastructure/Actions/NativeEditing.swift MissionControl/Infrastructure/Actions/NativeActionRuntime.swift MissionControl/Infrastructure/Usage/AIUsage.swift MissionControl/Assistant/Provider/ChatGPTStream.swift MissionControl/Assistant/Tools/PAToolProtocol.swift MissionControl/Projects/LifeWorkspace.swift MissionControl/Projects/LifeProjectPlacement.swift MissionControl/Projects/LifeWorkspaceQuery.swift MissionControl/Projects/LifeWorkspaceToolSchema.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Infrastructure/Storage/Cache.swift MissionControl/Infrastructure/Storage/LocalRecordRepository.swift MissionControl/Infrastructure/Actions/ActionReceiptStore.swift MissionControl/Assistant/Conversation/AssistantActions.swift Tests/Infrastructure/Actions/ActionReceiptChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
