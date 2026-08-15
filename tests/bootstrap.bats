#!/usr/bin/env bats

load 'test_helper'

setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

# bootstrap.sh клонирует репо в $SCRIPT_DIR/project/<repo> (layout: kacho-workspace/project/*).
#
# Прежняя редакция этого файла утверждала «клонирует все 11 sibling-репо» и перечисляла в
# том числе `kacho-vpc-operator`, которого на GitHub нет вовсе (404), — и НЕ упоминала
# `kacho`, монорепо, в котором ведётся вся разработка. То есть тест закреплял дефект:
# он был зелёным ровно тогда, когда bootstrap не создавал `project/kacho` — каталог, на
# который смотрит dev-стенд, в который раскатывается оснастка и который CI отдельно
# доклонирует, чтобы job `doc-commands` было что проверять.

@test "A1: bootstrap клонирует МОНОРЕПО — то, ради чего его запускают" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh

  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]

  [ -d "kacho-workspace/project/kacho/.git" ]
}

@test "A1b: предшествующие полирепо по умолчанию НЕ клонируются, по флагу — клонируются" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  # Отрицание в паре с положительным: «по умолчанию нет» само по себе зеленело бы и в том
  # случае, если бы флаг вообще не работал.
  ./kacho-workspace/bootstrap.sh
  [ ! -d "kacho-workspace/project/kacho-vpc/.git" ]

  KACHO_CLONE_LEGACY_POLYREPOS=1 ./kacho-workspace/bootstrap.sh
  [ -d "kacho-workspace/project/kacho-vpc/.git" ]
  [ -d "kacho-workspace/project/kacho-geo/.git" ]
  [ -d "kacho-workspace/project/kacho/.git" ]
}

@test "A2: bootstrap идемпотентен, локальный коммит переживает повтор" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  ./kacho-workspace/bootstrap.sh

  cd kacho-workspace/project/kacho
  echo "local change" > local.txt
  git -c user.email=t@t -c user.name=t add local.txt
  git -c user.email=t@t -c user.name=t commit -m "local-only"
  cd "$TMP_WS"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already cloned"* ]] || [[ "$output" == *"skip"* ]]

  cd kacho-workspace/project/kacho
  git log --oneline | grep -q "local-only"
}

@test "A3: недостижимое репо — отказ с координатой, уже склонированное сохраняется" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh

  rm -rf "$FAKE_REMOTES_BASE/kacho-compute.git"
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"
  export KACHO_CLONE_LEGACY_POLYREPOS=1

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"failed"* ]]
  [[ "$output" == *"compute"* ]]

  [ -d "kacho-workspace/project/kacho/.git" ]
  [ -d "kacho-workspace/project/kacho-vpc/.git" ]
}
