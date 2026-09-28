#!/usr/bin/env bash
# check-21 — хук коммита и хук отправки ОТКАЗЫВАЮТ трейлеру атрибуции (ws#861).
#
# Правило (`.claude/rules/git-issues.md`, gi-no-attribution-trailers) держалось
# вниманием, а среда подставляет трейлер в каждое задание. Механизм — два хука
# дерева с одним предикатом (scripts/hooks/attribution-rule.sh):
# scripts/hooks/commit-msg и страж отправки scripts/hooks/prepush-attribution.sh,
# которого scripts/hooks/pre-push зовёт первым.
#
# ЧТО ТРЕБУЕТСЯ (песочница: свой клон, провязанный штатной командой
# `bash scripts/hooks/install.sh install`, и голый удалённый; коммиты — настоящий
# `git commit`, отправки — настоящий `git push` с KACHO_SKIP_PREPUSH=1: обход
# снимает наборы, а страж идёт раньше него):
#
#   настоящий вход — сообщения трёх коммитов полосы kacho, записанных с
#       трейлерами (2840-trailered-b81c695; адрес сессии заменён) → хук коммита
#       отказывает и называет строку; близнец без блока трейлеров → записан;
#   по мутанту на ключ (Co-Authored-By с любым значением, Claude-Session:,
#       строка Generated with Claude Code, ссылка claude.ai/code) → отказ;
#       близнец — ключ в середине строки прозы → записан;
#   коммит мимо хука коммита (--no-verify, commit-tree) → отправка остановлена,
#       sha назван; близнец → доехал; опубликованный коммит с трейлером в истории
#       не судится; черновик `wip/*` не освобождён; обход стража не снимает;
#   судить нечем (пустое сообщение, нет файла, нет предиката или стража) →
#       отказ, а не молчание.
#
# Файлов правила в дереве нет — это НАХОДКА, а не VOID: предмет проверки и есть
# их существование. VOID — только когда проверять нечем (нет git).
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-21-attribution-hooks-refuse-the-trailer"
HK="$WS/scripts/hooks"

command -v git > /dev/null 2>&1 || { tooling_gate_void "$NAME" "нет git — проверять нечем"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS \
      GIT_CONFIG_COUNT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE \
      GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE GIT_EDITOR EDITOR VISUAL \
      KACHO_SKIP_PREPUSH KACHO_MONOREPO
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" GIT_CONFIG_NOSYSTEM=1 \
       GIT_TERMINAL_PROMPT=0
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
printf '[user]\n\tname = probe\n\temail = probe@example.invalid\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n[advice]\n\tdetachedHead = false\n' > "$HOME/.gitconfig"

probes=0
findings=0
bad() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }
okp() { probes=$((probes + 1)); }
badp() { probes=$((probes + 1)); bad "$1"; }

KIT=(commit-msg attribution-rule.sh prepush-attribution.sh pre-push install.sh)
missing=()
for f in "${KIT[@]}"; do
    [ -f "$HK/$f" ] || missing+=("scripts/hooks/$f")
done
if [ "${#missing[@]}" -gt 0 ]; then
    tooling_gate_fail "$NAME" "в дереве нет: ${missing[*]} — трейлер атрибуции механически не отказывается"
    tooling_gate_census "$NAME: файлов правила в дереве $(( ${#KIT[@]} - ${#missing[@]} )) из ${#KIT[@]}, проб 0"
    exit 1
fi

# ── НАСТОЯЩИЙ ВХОД ───────────────────────────────────────────────────────────
cat > "$TMP/real.all" <<'REAL'
#2840 deploy: проба порядка cert-manager исполняема в индексе

TestShebangScriptsAreExecutable на голове 82f0e455536: неисполняемых 1
(проба заведена с режимом 100644, в чистом клоне не запустится). После
git add --chmod=+x: неисполняемых 0 из 337 файлов с shebang.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01fixture
%%
#2840 deploy: состояние релиза cert-manager спрашивается без helm list -a

Живой stack-up на kind (helm v4.2.4) показал: у helm v4 флага -a нет,
и ветка «наш релиз» отказывала бы на каждом повторном подъёме. Проба
этого не видела: подставной helm принимал любой флаг.

Подставные kubectl и helm теперь сперва разбирают флаги настоящим
инструментом (<args> --help) и отказывают его текстом. До правки
рецепта: 10 из 10, находок 2 (Б2, Б3 — unknown shorthand flag 'a');
после: 10 из 10, находок 0.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01fixture
%%
#2840 deploy: stack-up ставит cert-manager тем же местом, что dev-up

Порядок «cert-manager отдельным релизом → его вебхук → продукт» жил
строками внутри dev-up; stack-up применял умбреллу с
cert-manager.enabled=false и релиза не ставил, поэтому на чистом
кластере цепочка упиралась в отсутствие CRD Certificate/Issuer.

Порядок вынесен в цель cert-manager-up (страж guard-declared-context),
её зовут оба пути подъёма раньше продукта. Исходы по владельцу CRD:
нет — ставит; наш той же версии — не переставляет; наш другой версии —
доводит; чужой (a8f60d) — не трогает; не прочитано — отказ.

Проба tests/helm/cert-manager-release-before-product-test.sh: до правки
10 из 10 исполнено, 9 находок; после — 10 из 10, находок 0.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01fixture
REAL

awk -v d="$TMP" '/^%%$/ { n++; next } { print > (d "/real-" (n + 1) ".msg") }' "$TMP/real.all"
real_n=0
for m in "$TMP"/real-*.msg; do
    [ -f "$m" ] || continue
    real_n=$((real_n + 1))
    sed '/^Co-Authored-By:/,$d' "$m" > "${m%.msg}.twin"
done
[ "$real_n" = 3 ] || { tooling_gate_void "$NAME" "настоящий вход не разобран ($real_n из 3)"; exit 2; }
real_trailer="Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"

# ── ПЕСОЧНИЦА ────────────────────────────────────────────────────────────────
F="$TMP/f"
mkdir -p "$F/scripts/hooks"
for f in "${KIT[@]}"; do cp "$HK/$f" "$F/scripts/hooks/"; done
chmod +x "$F/scripts/hooks/"*
if ! { git -C "$F" init -q && git -C "$F" add -A && git -C "$F" commit -q --no-verify -m "#1 оснастка" &&
    git -C "$F" commit -q --allow-empty --no-verify -m "#1 опубликовано до правила" -m "$real_trailer" &&
    git init -q --bare "$F.git" && git -C "$F" remote add origin "$F.git" &&
    git -C "$F" push -q --no-verify origin main 2> /dev/null; }; then
    tooling_gate_void "$NAME" "песочница не собрана"
    exit 2
fi
install_out="$(cd "$F" && bash scripts/hooks/install.sh install 2>&1)" || true
if [ -x "$F/.git/hooks/commit-msg" ] && [ -x "$F/.git/hooks/pre-push" ]; then okp
else badp "штатная провязка (install.sh install) не провязала commit-msg и pre-push: ${install_out//$'\n'/ | }"; fi

attempt() {
    local before after
    before="$(git -C "$F" rev-parse -q --verify HEAD)"
    out="$(cd "$F" && "$@" 2>&1 < /dev/null)"
    rc=$?
    after="$(git -C "$F" rev-parse -q --verify HEAD)"
    made=0
    [ "$before" = "$after" ] || made=1
}
has() { [[ "$out" == *"$1"* ]]; }
refused() { # <имя> <образец…>
    local name="$1" p miss=""
    shift
    for p in "$@"; do has "$p" || miss="$miss «$p»"; done
    if [ "$rc" -ne 0 ] && [ "$made" = 0 ] && [ -z "$miss" ]; then okp
    else badp "$name: код $rc, записан $made; нет в выводе:${miss:- —}"; fi
}
accepted() { # <имя>
    if [ "$rc" -eq 0 ] && [ "$made" = 1 ] && [ -z "$out" ]; then okp
    else badp "$1: код $rc, записан $made, вывод «${out//$'\n'/ | }»"; fi
}
on() { git -C "$F" checkout -q -f -B "$1" "${2:-main}" > /dev/null 2>&1; }
commit() { attempt git commit -q --allow-empty "$@"; }

# ── ХУК КОММИТА ──────────────────────────────────────────────────────────────
for i in 1 2 3; do
    on 2840; commit -F "$TMP/real-$i.msg"
    refused "настоящий вход $i — отказ с названной строкой" "commit-msg ОТКАЗ" "«$real_trailer»"
    on 2840; commit -F "$TMP/real-$i.twin"
    accepted "близнец настоящего входа $i без блока трейлеров"
done
while IFS='|' read -r label trailer; do
    [ -n "$label" ] || continue
    on 7; commit -m "#7 x" -m "тело" -m "$trailer"
    refused "мутант: $label" "«$trailer»"
done << 'FORMS'
Co-Authored-By с моделью|Co-Authored-By: Claude Opus <noreply@example.invalid>
Co-Authored-By соавтора-человека — запрещён ключ, а не значение|Co-authored-by: Иван Петров <ivan@example.org>
Claude-Session:|Claude-Session: https://example.invalid/session_x
строка Generated with Claude Code|🤖 Generated with [Claude Code](https://example.invalid)
ссылка claude.ai/code|https://claude.ai/code/session_x
FORMS
while IFS='|' read -r label trailer; do
    [ -n "$label" ] || continue
    on 7; commit -m "#7 x" -m "Снята строка шаблона $trailer — подставлялась"
    accepted "близнец: «$label» в середине строки прозы"
done << 'MENTIONS'
Co-Authored-By|Co-authored-by: Иван Петров <ivan@example.org>
Claude-Session:|Claude-Session: https://example.invalid/session_x
MENTIONS
: > "$TMP/empty.msg"
attempt bash scripts/hooks/commit-msg "$TMP/empty.msg"
refused "пустое сообщение" "сообщение пусто"
attempt bash scripts/hooks/commit-msg
refused "нет файла сообщения" "файла сообщения нет"
on 7; mv "$F/scripts/hooks/attribution-rule.sh" "$TMP/rule.away"
commit -m "#7 x"
refused "предиката нет рядом с хуком коммита" "предиката нет"
mv "$TMP/rule.away" "$F/scripts/hooks/attribution-rule.sh"

# ── ОТПРАВКА ─────────────────────────────────────────────────────────────────
remote_at() { git -C "$F" ls-remote origin "$1" | cut -f1; }
push() { attempt env KACHO_SKIP_PREPUSH=1 git push -q origin "$@"; }
delivered() { # <имя> <ссылка>
    if [ "$rc" -eq 0 ] && [ "$(remote_at "$2")" = "$(git -C "$F" rev-parse HEAD)" ] && has "нарушений нет"; then okp
    else badp "$1: код $rc, на удалённом «$(remote_at "$2")»"; fi
}
stopped() { # <имя> <ссылка> <образец…>
    local name="$1" ref="$2" p miss=""
    shift 2
    for p in "$@"; do has "$p" || miss="$miss «$p»"; done
    if [ "$rc" -ne 0 ] && [ -z "$(remote_at "$ref")" ] && [ -z "$miss" ]; then okp
    else badp "$name: код $rc, на удалённом «$(remote_at "$ref")»; нет в выводе:${miss:- —}"; fi
}
nv() { git -C "$F" commit -q --allow-empty --no-verify "$@"; }

on 101; nv -F "$TMP/real-1.msg"; s="$(git -C "$F" rev-parse --short=10 HEAD)"; push 101
stopped "настоящий вход мимо хука коммита" refs/heads/101 "$s атрибуция в сообщении: «$real_trailer»"
if has "пропущен по KACHO_SKIP_PREPUSH"; then badp "обход KACHO_SKIP_PREPUSH снял страж атрибуции"; else okp; fi
on 102; nv -F "$TMP/real-1.twin"; push 102
delivered "близнец настоящего входа без трейлеров" refs/heads/102
on 103
c="$(git -C "$F" commit-tree -p HEAD -m "#103 x" -m "Co-authored-by: Иван Петров <ivan@example.org>" "HEAD^{tree}")"
git -C "$F" update-ref refs/heads/103 "$c"; push 103
stopped "соавтор-человек через commit-tree" refs/heads/103 "${c:0:10} атрибуция в сообщении"
on 104; nv -m "#104 x" -m "Снята строка шаблона Co-Authored-By: Claude Opus — подставлялась"; push 104
delivered "близнец: ключ в середине строки прозы" refs/heads/104
on 105; nv -m "#105 x"; push 105
delivered "опубликованный коммит с трейлером в истории не судится" refs/heads/105
on wip/106; nv -m "#106 x" -m "$real_trailer"; push wip/106
stopped "черновик wip/* с трейлером" refs/heads/wip/106 "атрибуция в сообщении"
on 107; nv -m "#107 x"; mv "$F/scripts/hooks/prepush-attribution.sh" "$TMP/guard.away"
push 107
stopped "стража нет рядом с хуком отправки" refs/heads/107 "стража атрибуции нет"
mv "$TMP/guard.away" "$F/scripts/hooks/prepush-attribution.sh"

tooling_gate_census "$NAME: проб $probes, находок $findings; настоящий вход — $real_n сообщения, ключей под мутантами 4"
if [ "$findings" -gt 0 ]; then
    exit 1
fi
tooling_gate_pass "$NAME" "хук коммита и хук отправки отказывают трейлеру атрибуции, близнецы проходят"
exit 0
