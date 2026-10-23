#!/bin/zsh
# Sourced by component checks. Each direct invocation gets a private work folder.
# MISSIONCONTROL_TEST_ROOT is a parent for artifacts, never personal app storage.
# The aggregate runner supplies its own root and serially shared module cache.
missioncontrol_test_init() {
  local suite="$1"
  local parent="${MISSIONCONTROL_TEST_ROOT:-${TMPDIR:-/private/tmp}}"
  mkdir -p "$parent"
  parent="$(cd "$parent" && pwd -P)"
  export MISSIONCONTROL_TEST_ROOT="$parent"
  MISSIONCONTROL_TEST_WORK_DIR="$(mktemp -d "$parent/$suite.XXXXXX")"
  MISSIONCONTROL_TEST_BIN="$MISSIONCONTROL_TEST_WORK_DIR/checks"
  MISSIONCONTROL_TEST_MODULE_CACHE="${MISSIONCONTROL_TEST_MODULE_CACHE:-$MISSIONCONTROL_TEST_WORK_DIR/modules}"
  mkdir -p "$MISSIONCONTROL_TEST_MODULE_CACHE" "$MISSIONCONTROL_TEST_WORK_DIR/tmp"
  export MISSIONCONTROL_TEST_MODULE_CACHE
  export TMPDIR="$MISSIONCONTROL_TEST_WORK_DIR/tmp/"
  # The integration checkpoint adds this shared repository. Older review bases
  # can still run; a missing required type remains a compiler failure.
  missioncontrol_storage_sources=()
  if [[ -f MissionControl/Infrastructure/Storage/LocalRecordRepository.swift ]]; then
    missioncontrol_storage_sources=(MissionControl/Infrastructure/Storage/LocalRecordRepository.swift)
  fi
  missioncontrol_learning_sources=()
  if [[ -f MissionControl/Memory/Learning/BackgroundLearningCoordinator.swift ]]; then
    missioncontrol_learning_sources=(MissionControl/Memory/Learning/BackgroundLearningCoordinator.swift)
  fi
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
}

missioncontrol_test_node() {
  MISSIONCONTROL_NODE="${MISSIONCONTROL_NODE:-$PWD/WhatsAppBridge/Runtime/node}"
  if [[ ! -x "$MISSIONCONTROL_NODE" ]]; then
    print -u2 -- "Required bundled Node runtime unavailable: $MISSIONCONTROL_NODE. Prepare runtime separately; checks never download it."
    return 1
  fi
}
