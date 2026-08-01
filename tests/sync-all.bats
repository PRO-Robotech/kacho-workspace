#!/usr/bin/env bats
load 'test_helper'
setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

# sync-all.sh больше не носит собственный список репозиториев: он обходит то, что реально
# склонировано (repos.sh). Прежняя копия списка здесь уже разошлась с двумя другими — в ней
# не хватало kacho-geo, то есть репозиторий, который bootstrap клонировал, sync-all молча
# не обновлял, и заметить это было нечем.

@test "A5: sync-all обходит склонированное и делает ff-pull" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" "$BATS_TEST_DIRNAME/../sync-all.sh" \
     "$BATS_TEST_DIRNAME/../repos.sh" kacho-workspace/
  chmod +x kacho-workspace/*.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"
  export KACHO_CLONE_LEGACY_POLYREPOS=1
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

  [ -f "kacho-workspace/project/kacho-vpc/upstream.txt" ]
}

@test "A5b: sync-all обходит ВСЁ склонированное, включая kacho-geo" {
  # Именно этого имени не было в рукописном списке sync-all.sh. Проверка адресная:
  # утверждение «обходит всё» без названного пропущенного зеленело и с дефектом.
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" "$BATS_TEST_DIRNAME/../sync-all.sh" \
     "$BATS_TEST_DIRNAME/../repos.sh" kacho-workspace/
  chmod +x kacho-workspace/*.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"
  export KACHO_CLONE_LEGACY_POLYREPOS=1
  ./kacho-workspace/bootstrap.sh

  local work="$TMP_WS/work-geo"
  git clone "$FAKE_REMOTES_BASE/kacho-geo.git" "$work" >/dev/null 2>&1
  echo "geo-upstream" > "$work/geo.txt"
  (cd "$work" && git add geo.txt && git -c user.email=t@t -c user.name=t commit -m geo && git push)
  rm -rf "$work"

  run ./kacho-workspace/sync-all.sh
  [ "$status" -eq 0 ]
  [ -f "kacho-workspace/project/kacho-geo/geo.txt" ]
  [[ "$output" == *"kacho-geo"* ]]
}

@test "A5c: ноль рабочих копий — отказ, а не «всё актуально»" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace/project
  cp "$BATS_TEST_DIRNAME/../sync-all.sh" "$BATS_TEST_DIRNAME/../repos.sh" kacho-workspace/
  chmod +x kacho-workspace/*.sh

  run ./kacho-workspace/sync-all.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ОТКАЗ"* ]]
}
