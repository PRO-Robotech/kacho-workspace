#!/usr/bin/env bats
load 'test_helper'
setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

@test "A5: sync-all.sh fetches and ff-pulls each repo" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" "$BATS_TEST_DIRNAME/../sync-all.sh" kacho-workspace/
  chmod +x kacho-workspace/*.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"
  ./kacho-workspace/bootstrap.sh

  # Push новый коммит в один из remotes
  local work="$TMP_WS/work-vpc"
  git clone "$FAKE_REMOTES_BASE/kacho-vpc.git" "$work" >/dev/null 2>&1
  echo "upstream" > "$work/upstream.txt"
  (cd "$work" && git add upstream.txt && git -c user.email=t@t -c user.name=t commit -m up && git push)
  rm -rf "$work"

  run ./kacho-workspace/sync-all.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]] || [[ "$output" == *"up-to-date"* ]]

  [ -f "kacho-vpc/upstream.txt" ]
}
