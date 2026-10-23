#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init life-notebook
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Assistant/Context/LifeFocus.swift Tests/Memory/LifeNotebookChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
