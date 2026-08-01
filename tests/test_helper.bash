#!/usr/bin/env bash
# Helper для bats-тестов bootstrap.sh и sync-all.sh

setup_fake_workspace() {
  TMP_WS="$(mktemp -d)"
  export TMP_WS
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
    (cd "$work" && git add README.md && git -c user.email=t@t -c user.name=t commit -m init >/dev/null && git push -u origin HEAD:main >/dev/null 2>&1)
    rm -rf "$work"
  done
  export FAKE_REMOTES_BASE="$remotes_dir"
}
