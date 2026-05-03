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
setup_fake_remotes() {
  local remotes_dir="$TMP_WS/fake-remotes"
  mkdir -p "$remotes_dir"
  for r in kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
    git init --bare "$remotes_dir/$r.git" >/dev/null
    local work="$TMP_WS/work-$r"
    git clone "$remotes_dir/$r.git" "$work" >/dev/null 2>&1
    echo "# $r" > "$work/README.md"
    (cd "$work" && git add README.md && git -c user.email=t@t -c user.name=t commit -m init >/dev/null && git push -u origin HEAD:main >/dev/null 2>&1)
    rm -rf "$work"
  done
  export FAKE_REMOTES_BASE="$remotes_dir"
}
