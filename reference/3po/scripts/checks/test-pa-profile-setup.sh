#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init pa-profile-setup
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Infrastructure/Actions/ActionModels.swift MissionControl/Infrastructure/Usage/AIUsage.swift MissionControl/Assistant/Provider/ChatGPTStream.swift MissionControl/Assistant/Tools/PAToolProtocol.swift MissionControl/Projects/LifeWorkspace.swift MissionControl/Projects/LifeProjectPlacement.swift MissionControl/Projects/LifeWorkspaceQuery.swift MissionControl/Projects/LifeWorkspaceToolSchema.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Assistant/Conversation/Conversations.swift MissionControl/Assistant/Profile/PAProfileSetup.swift Tests/Assistant/PAProfileSetupChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
