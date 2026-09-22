#!/usr/bin/env bash
# check-17 — СТРАЖИ ПРАВИЛА GIT отказывают на одно-фактном дефекте и молчат на
# законном близнеце.
#
# ПРЕДМЕТ. Решение владельца 2026-09-22 (`.claude/rules/git-issues.md` §«Git /
# коммиты», §«Дерево задач, ветки, слияния») держат два хука воркспейса:
# `scripts/hooks/commit-msg` (создаваемый коммит) и `scripts/hooks/pre-push`
# (отправляемые ссылки), с распознавателями в `scripts/hooks/git-rule.sh`. Хук,
# который пропускает всё, внешне неотличим от хука, которому нечего отвергать:
# оба молчат. Отличает их только опыт.
#
# ОПЫТ — НАСТОЯЩИЙ, А НЕ ВЫЗОВ ФУНКЦИИ. В песочнице заводится репозиторий и
# «удалённый» голый репозиторий, хуки провязываются тем же `install.sh`, что и в
# клоне, и судятся настоящие `git commit` и `git push`. Так доказывается и
# провязка (переходник зовёт хук, stdin ссылок доходит до стража), а не только
# распознаватели.
#
# У КАЖДОГО ОТКАЗА — ЗАКОННЫЙ БЛИЗНЕЦ, отличающийся одним фактом: номер ветки ⇄
# имя не номер; дата после T0 ⇄ до T0; соавтор-ассистент ⇄ соавтор-человек;
# новая ветка ⇄ обновление ветки до правила; чужой коммит только в стволе ⇄ в
# отправляемом. Отказ засчитывается, только если хук НАЗВАЛ причину («ОТКАЗ —»):
# коммит, упавший по посторонней причине, отказом стража не является.
#
# ПОДПИСЬ ПЕСОЧНИЦЫ — HOME ПЕСОЧНИЦЫ СО СВОИМ `.gitconfig`, а не переопределение
# (#785): корневая подпись пробы — это корневой gitconfig её HOME. Чужой автор
# получается сменой HOME, дата — флагом `--date`. Переопределение встречается
# ровно там, где оно — вносимый дефект (`-c user.email`, `git config --local`).
#
# ПРЕДПОСЫЛКА (VOID, код 2): в дереве есть оба хука, их распознаватели и
# `install.sh`, песочница строится и провязывается. Иначе опыт не о чем ставить.
#
# Коды: 0 — все пробы сошлись; 1 — хотя бы одна нет (названа); 2 — предмета нет.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-17-git-rule-guards-refuse-and-pass"
NEED=(scripts/hooks/commit-msg scripts/hooks/pre-push scripts/hooks/git-rule.sh scripts/hooks/install.sh)

for f in "${NEED[@]}"; do
    if [ ! -f "$WS/$f" ]; then
        tooling_gate_void "$NAME" "в дереве нет $f — опыт над стражами правила git ставить не на чем"
        exit 2
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Окружение git вызывающего сильнее каталога песочницы и увело бы запись в ЧУЖОЙ
# репозиторий; переменные подписи и настроек — вход, который задаёт только проба.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
      GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE \
      GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE \
      GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT KACHO_SKIP_PREPUSH KACHO_MONOREPO
export GIT_CONFIG_NOSYSTEM=1 GIT_EDITOR=true GIT_TERMINAL_PROMPT=0

mkhome() {
    mkdir -p "$1/.config"
    printf '[user]\n\tname = %s\n\temail = %s\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
        "$2" "$3" > "$1/.gitconfig"
}
ROOT_HOME="$TMP/home-root"
FOREIGN_HOME="$TMP/home-foreign"
mkhome "$ROOT_HOME" probe probe@example.invalid
mkhome "$FOREIGN_HOME" stranger stranger@example.invalid
export HOME="$ROOT_HOME" XDG_CONFIG_HOME="$ROOT_HOME/.config"

BOX="$TMP/box"
ORIGIN="$TMP/origin.git"
# Строки атрибуции собираются из частей: литерал в исходнике проверки нашёлся
# бы любым будущим обходом дерева на атрибуцию и сделал бы его ложным.
AI="Cl""aude"
TRAILER_AI="Co-Authored-By: $AI <noreply@anthrop""ic.com>"
TRAILER_SESSION="$AI-Session: 0000"
TRAILER_HUMAN="Co-Authored-By: Human Person <human@example.invalid>"
BEFORE_T0="2026-01-01T00:00:00+0000"
AT_T0="2026-06-01T00:00:00+0000"
AFTER_T0="2026-07-01T00:00:00+0000"

g() { git -C "$BOX" "$@"; }
gf() { HOME="$FOREIGN_HOME" XDG_CONFIG_HOME="$FOREIGN_HOME/.config" git -C "$BOX" "$@"; }
touchf() { printf '%s\n' "$1" > "$BOX/$1"; g add -- "$1"; }

build() {
    git init -q --bare "$ORIGIN" &&
    git init -q -b main "$BOX" &&
    g remote add origin "$ORIGIN" &&
    mkdir -p "$BOX/scripts/hooks" "$BOX/scripts/stub" &&
    # История до правила: другая подпись, заголовок без номера, трейлер ассистента.
    touchf legacy.txt &&
    gf commit -q --date="$BEFORE_T0" -m "старая работа" -m "$TRAILER_AI" &&
    cp "$WS/scripts/hooks/commit-msg" "$WS/scripts/hooks/pre-push" \
       "$WS/scripts/hooks/git-rule.sh" "$WS/scripts/hooks/install.sh" "$BOX/scripts/hooks/" &&
    printf '#!/usr/bin/env bash\nexit 0\n' > "$BOX/scripts/stub/run-all.sh" &&
    chmod +x "$BOX/scripts/hooks/commit-msg" "$BOX/scripts/hooks/pre-push" "$BOX/scripts/stub/run-all.sh" &&
    g add -- scripts/hooks/commit-msg scripts/hooks/pre-push scripts/hooks/git-rule.sh \
             scripts/hooks/install.sh scripts/stub/run-all.sh &&
    g commit -q --date="$AT_T0" -m "#900 правило git" &&
    g tag t0 &&
    # Ветка, заведённая до правила и уже лежащая на origin.
    g branch lane/old t0 &&
    # Ствол ушёл вперёд чужой подписью — так выглядит серверное слияние.
    touchf trunk-moved.txt &&
    gf commit -q --date="$AFTER_T0" -m "Merge pull request #1 from somewhere" &&
    g push -q origin main lane/old 2>/dev/null &&

    # Ветки для проб отправки — ДО провязки: коммит-страж их не судит.
    mkbranch p-ok       "$AFTER_T0"  root "#901 работа" &&
    mkbranch p-nonum    "$AFTER_T0"  root "работа без номера" &&
    mkbranch p-attr     "$AFTER_T0"  root "#903 работа" "$TRAILER_AI" &&
    mkbranch p-human    "$AFTER_T0"  root "#905 работа" "$TRAILER_HUMAN" &&
    mkbranch p-foreign  "$AFTER_T0"  foreign "#904 работа" &&
    mkbranch p-legacy   "$BEFORE_T0" root "работа без номера" &&
    mkbranch p-mergemain "$AFTER_T0" root "#908 работа" &&
    g checkout -q p-mergemain &&
    g merge -q --no-ff --no-edit -m "#908 merge main: догон" main &&
    g checkout -q -B lane/old refs/remotes/origin/lane/old &&
    touchf lane-old-next.txt &&
    g commit -q --date="$AFTER_T0" -m "#907 продолжение ветки до правила" &&
    g checkout -q --detach t0 &&
    ( cd "$BOX" && bash scripts/hooks/install.sh install >/dev/null )
}

# mkbranch <имя> <дата> <root|foreign> <заголовок> [тело]
mkbranch() {
    local b="$1" d="$2" who="$3" s="$4" body="${5:-}"
    local args=(-q --date="$d" -m "$s")
    [ -n "$body" ] && args+=(-m "$body")
    g checkout -q -B "$b" t0 &&
    touchf "$b.txt" &&
    if [ "$who" = foreign ]; then gf commit "${args[@]}"; else g commit "${args[@]}"; fi
}

if ! build >"$TMP/build.log" 2>&1; then
    tooling_gate_void "$NAME" "песочница не построилась: $(tail -3 "$TMP/build.log" | tr '\n' ' ')"
    exit 2
fi
if [ ! -x "$BOX/.git/hooks/commit-msg" ] || [ ! -x "$BOX/.git/hooks/pre-push" ]; then
    tooling_gate_void "$NAME" "install.sh не провязал commit-msg и pre-push в песочнице — опыт ставить не на чем"
    exit 2
fi

probes=0; bad=0; refusals=0; silences=0
verdict() { # <ожидали 0|1> <код> <вывод> <имя> <какой хук>
    local want="$1" rc="$2" out="$3" name="$4" hook="$5"
    probes=$((probes + 1))
    if [ "$want" = 1 ]; then
        refusals=$((refusals + 1))
        if [ "$rc" -ne 0 ] && grep -q "$hook: ОТКАЗ" <<<"$out"; then return 0; fi
        tooling_gate_fail "$NAME" "$name — ждали отказ «$hook: ОТКАЗ», получили код $rc: $(tail -2 <<<"$out" | tr '\n' ' ')"
    else
        silences=$((silences + 1))
        if [ "$rc" -eq 0 ]; then return 0; fi
        tooling_gate_fail "$NAME" "$name — законный близнец отвергнут (код $rc): $(grep -m2 'ОТКАЗ' <<<"$out" | tr '\n' ' ')"
    fi
    bad=$((bad + 1))
}

# pc <ожидали> <имя> <ветка> <дата> <заголовок> [тело] [-- аргументы git перед commit]
pc() {
    local want="$1" name="$2" br="$3" d="$4" subj="$5" body="${6:-}" rc out
    shift 6 2>/dev/null || shift $#
    local pre=("$@")
    local args=(-q --date="$d" -m "$subj")
    [ -n "$body" ] && args+=(-m "$body")
    g checkout -q -B "$br" t0
    touchf "c$probes.txt"
    set +e
    out="$(g ${pre[@]+"${pre[@]}"} commit "${args[@]}" 2>&1)"; rc=$?
    set -e
    g reset -q --hard
    verdict "$want" "$rc" "$out" "commit-msg: $name" commit-msg
}

# pp <ожидали> <имя> <refspec>
pp() {
    local want="$1" name="$2" spec="$3" rc out
    set +e
    out="$(g push origin "$spec" 2>&1)"; rc=$?
    set -e
    verdict "$want" "$rc" "$out" "pre-push: $name" pre-push
}

# ── коммит-страж ──────────────────────────────────────────────────────────
pc 0 "ветка-номер, «#911 …», корневая подпись" 911 "$AFTER_T0" "#911 правка"
pc 1 "заголовок без номера" 911 "$AFTER_T0" "правка"
pc 1 "номер чужой задачи на ветке-номере" 911 "$AFTER_T0" "#912 правка"
pc 0 "близнец: тот же «#912 …» на ветке до правила" lane/x "$AFTER_T0" "#912 правка"
pc 1 "трейлер соавторства ассистента" 911 "$AFTER_T0" "#911 правка" "$TRAILER_AI"
pc 1 "трейлер сеанса ассистента" 911 "$AFTER_T0" "#911 правка" "$TRAILER_SESSION"
pc 0 "близнец: соавтор-человек" 911 "$AFTER_T0" "#911 правка" "$TRAILER_HUMAN"
pc 0 "близнец: имя ассистента в прозе, не трейлер" 911 "$AFTER_T0" "#911 правка ${AI^^}.md"
pc 1 "подпись переопределена -c user.email" 911 "$AFTER_T0" "#911 правка" "" -c user.email=other@example.invalid
g config --local user.email probe@example.invalid
pc 1 "подпись переопределена настройкой копии (значение совпадает)" 911 "$AFTER_T0" "#911 правка"
g config --local --unset user.email
pc 1 "строка-комментарий git: собрано в редакторе" 911 "$AFTER_T0" "#911 правка" "# Please enter the commit message"
pc 0 "близнец: строка тела начинается с номера задачи" 911 "$AFTER_T0" "#911 правка" "#912 упомянута"
pc 0 "близнец: перепись сообщения истории (дата до T0) без номера" 911 "$BEFORE_T0" "старый заголовок"
pc 1 "перепись сообщения истории, а атрибуция осталась" 911 "$BEFORE_T0" "старый заголовок" "$TRAILER_AI"

# ── страж отправки ───────────────────────────────────────────────────────
pp 0 "новая ветка-номер, коммиты по правилу" p-ok:refs/heads/901
pp 1 "новая ветка не номер (те же коммиты)" p-ok:refs/heads/issue-901
pp 0 "близнец: обновление ветки до правила" lane/old:refs/heads/lane/old
pp 1 "коммит после T0 без номера" p-nonum:refs/heads/902
pp 0 "близнец: тот же коммит с датой до T0" p-legacy:refs/heads/906
pp 1 "коммит после T0 с атрибуцией" p-attr:refs/heads/903
pp 0 "близнец: соавтор-человек" p-human:refs/heads/905
pp 1 "коммит после T0 чужой подписью" p-foreign:refs/heads/904
pp 0 "близнец: чужая подпись только в стволе, влитом в ветку" p-mergemain:refs/heads/908
pp 0 "удаление ветки" :refs/heads/901

# Отказанная отправка не должна была ничего создать на origin.
for b in issue-901 902 903 904; do
    if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$b" >/dev/null; then
        tooling_gate_fail "$NAME" "ветка $b появилась на origin, хотя отправка отвергнута"
        bad=$((bad + 1))
    fi
done

tooling_gate_census "$NAME: проб $probes (отказов ожидалось $refusals, молчаний $silences) — настоящие git commit и git push в песочнице, хуки провязаны install.sh"
if [ "$bad" -gt 0 ]; then
    tooling_gate_fail "$NAME" "не сошлось проб: $bad из $probes"
    exit 1
fi
tooling_gate_pass "$NAME" "стражи отказывают на $refusals одно-фактных дефектах с названной причиной и молчат на $silences законных близнецах"
