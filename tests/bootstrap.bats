#!/usr/bin/env bats

load 'test_helper'

setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

@test "A1: bootstrap clones all 8 sibling repos" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh

  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]

  for r in kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
    [ -d "$r/.git" ] || { echo "missing $r"; false; }
  done
}

@test "A2: bootstrap is idempotent on re-run" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  ./kacho-workspace/bootstrap.sh

  # Создаём локальный коммит в одном из репо
  cd kacho-proto
  echo "local change" > local.txt
  git -c user.email=t@t -c user.name=t add local.txt
  git -c user.email=t@t -c user.name=t commit -m "local-only"
  cd ..

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already cloned"* ]] || [[ "$output" == *"skip"* ]]

  # Локальный коммит сохранился
  cd kacho-proto
  git log --oneline | grep -q "local-only"
}

@test "A3: bootstrap fails gracefully when one repo is unreachable" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh

  rm -rf "$FAKE_REMOTES_BASE/kacho-loadbalancer.git"
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"failed"* ]]
  [[ "$output" == *"loadbalancer"* ]]

  # Другие репо клонировались
  [ -d "kacho-proto/.git" ]
  [ -d "kacho-vpc/.git" ]
}
