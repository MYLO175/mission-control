#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init mail-reader
missioncontrol_test_node
"$MISSIONCONTROL_NODE" --test Tests/Sources/Mail/MailReaderChecks.mjs
