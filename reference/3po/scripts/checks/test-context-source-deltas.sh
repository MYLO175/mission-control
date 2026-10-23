#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init context-source-deltas
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" \
  MissionControl/Infrastructure/Models/Models.swift \
  MissionControl/Memory/Records/PAMemory.swift \
  MissionControl/Memory/Notebook/LifeNotebook.swift \
  MissionControl/Memory/Notebook/LifeOrganisation.swift \
  MissionControl/Memory/Learning/MemoryLearning.swift \
  MissionControl/Assistant/Profile/PALearningQuestion.swift \
  MissionControl/Memory/Records/MemoryDependencies.swift \
  MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Background/Briefing/Briefing.swift \
  MissionControl/Sources/WhatsApp/WhatsAppModels.swift \
  MissionControl/Memory/Learning/NativeSourceLearning.swift \
  MissionControl/Memory/Learning/SourceContextLearning.swift \
  Tests/Memory/ContextSourceDeltaChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
