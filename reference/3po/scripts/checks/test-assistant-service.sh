#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
reference="${MISSIONCONTROL_ASSISTANT_DEPENDENCIES:-$PWD}"
source "$reference/scripts/lib/test-env.sh"
missioncontrol_test_init assistant-service
types=(Infrastructure/Storage/Cache Infrastructure/Storage/LocalRecordRepository Assistant/Conversation/ConversationRepository Infrastructure/Models/Models Memory/Records/PAMemory Memory/Notebook/LifeNotebook Memory/Notebook/LifeOrganisation Memory/Learning/MemoryLearning Assistant/Profile/PALearningQuestion Memory/Records/MemoryDependencies Review/Inbox/ReviewPolicyModels Review/Inbox/ReviewPolicy Background/Briefing/Briefing Memory/Records/PAMemoryStore Projects/LifeWorkspace Projects/LifeProjectPlacement Projects/LifeWorkspaceQuery Projects/LifeWorkspaceStore Projects/LifeWorkspaceToolSchema Memory/Notebook/LifeCanonicalNotebook Assistant/Conversation/Conversations Assistant/Conversation/ChatDraftStore Assistant/Conversation/PARequestQueue Assistant/Conversation/ChatImages Infrastructure/Actions/ActionModels Infrastructure/Actions/ActionReceiptStore Infrastructure/Actions/NativeCreation Infrastructure/Actions/NativeEditing Infrastructure/Usage/AIUsage Assistant/Provider/ChatGPTStream Assistant/Tools/PAToolProtocol Review/Actions/ReviewPlanTools Assistant/Conversation/PAConversationEngine Assistant/Profile/PAIdentity Assistant/Profile/PAProfileSetup Sources/Mail/MailLookupRules Sources/Email/EmailSummary Sources/Email/EmailResolution Review/Inbox/Proactive Sources/WhatsApp/WhatsAppModels Memory/Learning/SourceContextLearning Memory/Learning/NativeSourceLearning)
sources=()
for name in "${types[@]}"; do sources+=("$reference/MissionControl/$name.swift"); done
sources+=("$reference/MissionControl/Sources/Mail/MailService.swift" "$reference/MissionControl/Sources/Mail/MailBatching.swift")
# Deliberately excludes DashboardModel, its adapter, production connection,
# EventKitService, MailLookup and PAToolSession: this runs the actual core only.
sources+=(MissionControl/Assistant/Provider/PAInferenceConnection.swift MissionControl/Assistant/Conversation/AssistantRuntime.swift MissionControl/Assistant/Context/PAWorkingContext.swift MissionControl/Assistant/Conversation/AssistantService.swift Tests/Assistant/AssistantServiceChecks.swift)
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 "${sources[@]}" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
