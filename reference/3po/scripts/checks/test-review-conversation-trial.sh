#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init review-conversation-trial
xcrun swiftc -D DEBUG -parse-as-library -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" \
  MissionControl/Development/Trials/ReviewConversationTrial.swift MissionControl/Development/Evaluations/EvaluationLaunchGuard.swift \
  Tests/Development/Trials/ReviewConversationTrialChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
