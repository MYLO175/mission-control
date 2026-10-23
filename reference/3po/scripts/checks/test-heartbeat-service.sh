#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
reference="${MISSIONCONTROL_HEARTBEAT_DEPENDENCIES:-$PWD}"
source "$reference/scripts/lib/test-env.sh"
missioncontrol_test_init heartbeat-service
types=(Infrastructure/Storage/Cache Infrastructure/Storage/LocalRecordRepository Infrastructure/Models/Models Memory/Records/PAMemory Memory/Notebook/LifeNotebook Memory/Notebook/LifeOrganisation Memory/Learning/MemoryLearning Assistant/Profile/PALearningQuestion Memory/Records/MemoryDependencies Review/Inbox/ReviewPolicyModels Review/Inbox/ReviewPolicy Background/Briefing/Briefing Projects/LifeWorkspace Projects/LifeProjectPlacement Projects/LifeWorkspaceQuery Projects/LifeWorkspaceToolSchema Memory/Notebook/LifeCanonicalNotebook Assistant/Conversation/Conversations Assistant/Conversation/PARequestQueue Infrastructure/Actions/ActionModels Infrastructure/Actions/NativeCreation Infrastructure/Actions/NativeEditing Infrastructure/Usage/AIUsage Assistant/Provider/ChatGPTStream Assistant/Tools/PAToolProtocol Assistant/Profile/PAIdentity Assistant/Profile/PAProfileSetup Sources/Mail/MailLookupRules Sources/Email/EmailSummary Sources/Email/EmailResolution Review/Inbox/Proactive Sources/WhatsApp/WhatsAppModels Memory/Learning/SourceContextLearning Memory/Learning/NativeSourceLearning Background/Heartbeat/Heartbeat Background/Heartbeat/HeartbeatPower)
sources=()
for name in "${types[@]}"; do sources+=("$reference/MissionControl/$name.swift"); done
sources+=("$reference/MissionControl/Sources/Mail/MailService.swift" "$reference/MissionControl/Sources/Mail/MailBatching.swift")
# Actual scheduler, rules and repository; no DashboardModel, desktop adapter,
# live connection, EventKitService or real child services are compiled or started.
sources+=(MissionControl/Background/Heartbeat/HeartbeatRuntime.swift MissionControl/Background/Heartbeat/HeartbeatService.swift Tests/Background/HeartbeatServiceChecks.swift)
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 "${sources[@]}" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
