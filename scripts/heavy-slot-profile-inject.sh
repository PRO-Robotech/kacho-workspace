#!/usr/bin/env bash
# Registry resource-profile causal probes; no cluster or payload is executed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
. "$HERE/lib/sandbox-git-home.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
sandbox_git_home "$W/ghome" || exit 2
pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then printf 'PASS %s\n' "$3"; pass=$((pass+1));
    else printf 'FAIL %s expected=%s actual=%s\n' "$3" "$1" "$2"; fail=$((fail+1)); fi
}
route() {
    (cd "$1" && shift && bash "$SLOT" --route "$@" > "$W/out" 2> "$W/err")
    printf '0 %s\n' "$(cut -f2 "$W/out" | head -n1)"
}
# ws#1375: select the existing resource profile without forging GitHub identity.
RG="$W/rclone-native-registry"; git init -q -b 1375-profile "$RG"
printf 'module github.com/PRO-Robotech/registry-operator\n\ngo 1.26.10\n' > "$RG/go.mod"
git -C "$RG" add go.mod; sandbox_git -C "$RG" commit -q -m module
git -C "$RG" remote add origin https://forge.example/group/registry-operator.git
for remote in https://forge.example/group/controllers/registry-operator.git ssh://git@forge.example:2222/group/registry-operator git@forge.example:group/registry-operator.git; do
    git -C "$RG" remote set-url origin "$remote"
    assert "0 external" "$(route "$RG" go-unit -- go test ./...)" "native Registry lawful remote: $remote"
    assert "0 none" "$(route "$RG" lint -- go vet ./...)" "native Registry unsupported class: $remote"
done
for remote in http://forge.example/group/registry-operator.git https://user:password@forge.example/group/registry-operator.git file:///group/registry-operator.git /group/registry-operator.git https://forge.example/group/registry-operator-extra.git ssh://root@forge.example/group/registry-operator.git; do
    git -C "$RG" remote set-url origin "$remote"
    assert "0 none" "$(route "$RG" go-unit -- go test ./...)" "native Registry malformed or foreign remote: $remote"
done
git -C "$RG" remote set-url origin https://forge.example/group/registry-operator.git
printf 'module example.org/other\n' > "$RG/go.mod"
git -C "$RG" add go.mod; sandbox_git -C "$RG" commit -q -m foreign
assert "0 none" "$(route "$RG" go-unit -- go test ./...)" "native Registry wrong committed module"
printf 'module github.com/PRO-Robotech/registry-operator\n' > "$RG/go.mod"
assert "0 none" "$(route "$RG" go-unit -- go test ./...)" "native Registry dirty module cannot spoof HEAD"
git -C "$RG" rm -q -f go.mod; sandbox_git -C "$RG" commit -q -m absent
assert "0 none" "$(route "$RG" go-unit -- go test ./...)" "native Registry missing module"

for op in vault-operator kaname-iam-operator registry-operator; do
    git -C "$RG" remote set-url origin "https://github.com/PRO-Robotech/$op.git"
    assert "0 external" "$(route "$RG" go-unit -- go test ./...)" "existing GitHub profile $op preserved"
done
printf 'PROFILE_CENSUS pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" = 0 ] && [ "$pass" = 18 ]
