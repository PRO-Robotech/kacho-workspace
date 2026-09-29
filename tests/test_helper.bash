#!/usr/bin/env bash
# Helper для bats-тестов bootstrap.sh и sync-all.sh

# Подпись песочницы — её HOME со своим `.gitconfig`, в котором корневая учётная
# запись запускающего (ws#785): переопределение подписи в пробах не используется.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../scripts/lib/sandbox-git-home.sh
. "$BATS_TEST_DIRNAME/../scripts/lib/sandbox-git-home.sh"

setup_fake_workspace() {
  TMP_WS="$(mktemp -d)"
  export TMP_WS
  sandbox_git_home "$TMP_WS/home"
  cd "$TMP_WS"
}

teardown_fake_workspace() {
  if [ -n "${TMP_WS:-}" ]; then rm -rf "$TMP_WS"; fi
}

# Создаёт локальные bare-репо как фейковые remotes для тестов bootstrap.sh
#
# `kacho` (монорепо) стоит ПЕРВЫМ и раньше здесь отсутствовал — ровно как и в самом
# bootstrap.sh. Фикстура повторяла дефект продукта, поэтому тест «клонирует все репо»
# оставался зелёным, ни разу не создав `project/kacho` — каталог, ради которого bootstrap
# и запускают. `kacho-vpc-operator` убран: на GitHub такого репозитория нет (404).
setup_fake_remotes() {
  local remotes_dir="$TMP_WS/fake-remotes"
  mkdir -p "$remotes_dir"
  # Владелец в file://-URL — последний сегмент каталога remotes; предикат repos.sh
  # опознаёт цель по origin, поэтому тестам нужно назвать своего владельца явно.
  export KACHO_REPO_OWNER="fake-remotes"
  for r in kacho kacho-proto kacho-corelib kacho-api-gateway kacho-iam kacho-geo kacho-vpc kacho-compute kacho-nlb kacho-ui kacho-deploy; do
    git init --bare "$remotes_dir/$r.git" >/dev/null
    local work="$TMP_WS/work-$r"
    git clone "$remotes_dir/$r.git" "$work" >/dev/null 2>&1
    echo "# $r" > "$work/README.md"
    (cd "$work" && git add README.md && sandbox_git commit -m init >/dev/null && git push -u origin HEAD:main >/dev/null 2>&1)
    rm -rf "$work"
  done
  export FAKE_REMOTES_BASE="$remotes_dir"
}
