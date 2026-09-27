#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-verified-inject.sh — доказательство того, что признак состоявшейся
# отправки СПОСОБЕН упасть и способен смолчать. Инъекция в обе стороны на
# синтетических репозиториях, которые скрипт заводит сам и сносит за собой.
#
# ЗАЧЕМ. Проверка, не падавшая ни разу, неотличима от проверки, которая падать не
# умеет. Предмет здесь — ПОСТУСЛОВИЕ операции, а не причина её провала: обёртка
# обязана краснеть везде, где ссылка на сервере не равна отправленной sha, чем бы
# ни объяснялся пришедший ноль, — и молчать на законной отправке, иначе её
# отключат первым же ложным срабатыванием.
#
# ПАРА, РАДИ КОТОРОЙ ЭТО НАПИСАНО (наблюдения 2026-09-22):
#   · обрыв: `exit code 0` у обёртки при настоящем 128 и пустом `git ls-remote`;
#   · уход в фон: тот же ложный ноль от ДРУГОЙ причины — хук гнал 25 проверок,
#     перешагнул порог харнесса в 120 с, команда ушла в фон и прислала «exit code
#     0». Настоящий код там оказался нулём — совпадение, а не доказательство;
#   · законный близнец: та же ветка, ушедшая со второй попытки за 86 секунд.
# Отсюда устройство проб: ложный ноль воспроизводится ТРЕМЯ разными путями,
# потому что путей к нему больше одного и будут ещё:
#   A — сервер ДОСТУПЕН, ссылки на нём нет, а команда отчиталась нулём;
#   B — транспорт отказал по-настоящему (`ssh` в закрытый порт, код 128);
#   H — код обёртки СЪЕДЕН посредником (фон, труба, харнесс): читателю остаётся
#       только печатный вердикт, и он обязан говорить об операции.
# Если бы обёртка судила по коду `git push`, пробы A и H прошли бы зелёными.
#
# ТРИ ИСХОДА: 0 — доказано в обе стороны; 1 — проба не дала ожидаемого; 2 — без
# предмета (нет обёртки, нет git, нет личности коммиттера — фикстуру не собрать).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/.." && pwd)"
SUBJECT="$WS/scripts/push-verified.sh"

[ -f "$SUBJECT" ] || { echo "[VOID] обёртки $SUBJECT в дереве нет — доказывать нечего" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "[VOID] git не найден" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0
failed=0

# fixture <имя> — печатает путь рабочей копии с одним коммитом и bare-«сервером»
# рядом (`<путь>.git`). Личность задаётся ВНУТРИ синтетического репозитория и
# заведомо недоставляемым адресом (`.invalid`): рабочей копии она не касается, а
# без неё коммит фикстуры не состоится на машине без глобальной личности — так
# же, как в `branch-audit-inject.sh`.
fixture() {
    local name="$1" dir="$TMP/$1" bare="$TMP/$1.git"
    git init -q --bare "$bare" >/dev/null 2>&1 || return 1
    git init -q "$dir" >/dev/null 2>&1 || return 1
    git -C "$dir" config user.email inject@example.invalid || return 1
    git -C "$dir" config user.name  inject || return 1
    git -C "$dir" checkout -q -b work >/dev/null 2>&1 || return 1
    printf 'существо полосы\n' > "$dir/file.txt"
    git -C "$dir" add -A >/dev/null 2>&1 || return 1
    git -C "$dir" commit -q -m "фикстура $name" >/dev/null 2>&1 || return 1
    git -C "$dir" remote add origin "$bare" >/dev/null 2>&1 || return 1
    printf '%s\n' "$dir"
}

# shim <каталог> — кладёт в <каталог>/bin «git», который на `push` отчитывается
# НУЛЁМ и не делает ничего, а всё прочее исполняет настоящим git. Это и есть
# наблюдавшийся дефект в чистом виде: обёртка вернула ноль, пакет не ушёл.
shim() {
    mkdir -p "$1/bin"
    cat > "$1/bin/git" <<EOF
#!/usr/bin/env bash
sub=""
for a in "\$@"; do case "\$a" in -*) continue ;; *) sub="\$a"; break ;; esac; done
if [ "\$sub" = push ]; then echo "Everything up-to-date"; exit 0; fi
exec $REAL_GIT "\$@"
EOF
    chmod +x "$1/bin/git"
}

# probe <ожидаемый код> <метка> <вывод> <код> [<обязательная подстрока>…]
probe() {
    local want="$1" label="$2" out="$3" rc="$4"; shift 4
    probes=$((probes + 1))
    local ok=1 needle
    [ "$rc" = "$want" ] || ok=0
    # Сравнением, а не трубой: `| grep -q` под `pipefail` роняет писателя
    # SIGPIPE'ом и объявляет найденное ненайденным.
    for needle in "$@"; do
        [[ "$out" == *"$needle"* ]] || ok=0
    done
    if [ "$ok" = 1 ]; then
        echo "[PASS] $label (код $rc)"
    else
        failed=$((failed + 1))
        echo "[FAIL] $label — ожидался код $want, получен $rc" >&2
        printf '%s\n' "$out" | sed 's/^/    | /' >&2
    fi
}

# ── A. ОБРЫВ: сервер доступен, команда вернула НОЛЬ, ссылки на сервере нет ────
d="$(fixture a)" || { echo "[VOID] фикстура не собралась — нет git или личности коммиттера" >&2; exit 2; }
sha="$(git -C "$d" rev-parse refs/heads/work)"
shim "$TMP/a"
out="$(cd "$d" && PATH="$TMP/a/bin:$PATH" bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 1 "A обрыв: команда отчиталась нулём, ссылки на сервере нет — краснеет и называет обе стороны" \
    "$out" "$rc" "ОТКАЗ" "$sha" "ссылки НЕТ"

# Контроль к A: сервер и правда пуст — краснота пришла от ссылки, а не от кода.
probes=$((probes + 1))
if git --git-dir="$TMP/a.git" rev-parse --verify -q refs/heads/work >/dev/null; then
    failed=$((failed + 1)); echo "[FAIL] A-контроль: шим всё-таки отправил — проба A недоказательна" >&2
else
    echo "[PASS] A-контроль: на сервере ссылки нет — краснота пришла ИМЕННО от неё"
fi

# ── B. ОБРЫВ НАСТОЯЩИЙ: транспорт отказал (ssh в закрытый порт, код 128) ──────
d="$(fixture b)" || { echo "[VOID] фикстура b не собралась" >&2; exit 2; }
git -C "$d" remote set-url origin "ssh://127.0.0.1:1/nowhere.git"
out="$(cd "$d" && GIT_SSH_COMMAND="ssh -o ServerAliveInterval=20 -o BatchMode=yes -o ConnectTimeout=5" \
    bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 2 "B обрыв транспорта: сервер не опрошен — «без предмета», НЕ успех" \
    "$out" "$rc" "БЕЗ ПРЕДМЕТА" "НЕ подтверждена"

# ── C. ЗАКОННЫЙ БЛИЗНЕЦ: настоящая отправка — молчит и называет sha ───────────
d="$(fixture c)" || { echo "[VOID] фикстура c не собралась" >&2; exit 2; }
sha="$(git -C "$d" rev-parse refs/heads/work)"
out="$(cd "$d" && bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 0 "C близнец: законная отправка — подтверждено сервером" \
    "$out" "$rc" "ПОДТВЕРЖДЕНО" "$sha"

probes=$((probes + 1))
if [ "$(git --git-dir="$TMP/c.git" rev-parse refs/heads/work 2>/dev/null)" = "$sha" ]; then
    echo "[PASS] C-контроль: сервер и правда несёт $sha — зелёное сказано о состоявшемся"
else
    failed=$((failed + 1)); echo "[FAIL] C-контроль: обёртка подтвердила отправку, которой на сервере нет" >&2
fi

# ── D. БЛИЗНЕЦ «нечего отправлять»: повтор той же sha — по-прежнему молчит ────
out="$(cd "$d" && bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 0 "D близнец: повторная отправка той же sha — подтверждено, не находка" \
    "$out" "$rc" "ПОДТВЕРЖДЕНО"

# ── E. ССЫЛКА ЕСТЬ, НО ДРУГАЯ: сервер отстал на коммит ───────────────────────
printf 'второй коммит полосы\n' >> "$d/file.txt"
git -C "$d" commit -q -am "второй коммит" >/dev/null 2>&1
new_sha="$(git -C "$d" rev-parse refs/heads/work)"
shim "$TMP/e"
out="$(cd "$d" && PATH="$TMP/e/bin:$PATH" bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 1 "E обрыв на дозаливке: ссылка ЕСТЬ, но старая — краснеет и называет обе sha" \
    "$out" "$rc" "ОТКАЗ" "$new_sha" "$sha"

# ── F. ПРЕДПОСЫЛКА: не рабочая копия — «без предмета», а не успех ─────────────
mkdir -p "$TMP/f"
out="$(cd "$TMP/f" && bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 2 "F предпосылка: каталог не репозиторий — без предмета" "$out" "$rc" "БЕЗ ПРЕДМЕТА"

# ── G. KEEPALIVE: свой выставляется, чужая команда НЕ перебивается ────────────
d="$(fixture g)" || { echo "[VOID] фикстура g не собралась" >&2; exit 2; }
out="$(cd "$d" && env -u GIT_SSH_COMMAND bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 0 "G keepalive: при пустом транспорте выставляется свой" \
    "$out" "$rc" "ServerAliveInterval=20"

d="$(fixture g2)" || { echo "[VOID] фикстура g2 не собралась" >&2; exit 2; }
out="$(cd "$d" && GIT_SSH_COMMAND="ssh -i /dev/null -p 2222" bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 0 "G2 близнец: чужой транспорт без keepalive — не перебит, состояние названо" \
    "$out" "$rc" "ВНИМАНИЕ" "ssh -i /dev/null -p 2222"

# G3: транспорт задан программой `GIT_SSH`. `core.sshCommand` и выставленный
# обёрткой `GIT_SSH_COMMAND` сильнее её, поэтому «выставить свой keepalive» значило
# бы молча выключить чужую программу (ключ, прокси). Отправка в этой песочнице
# локальная и транспорта не зовёт — проба судит РЕШЕНИЕ обёртки, а не соединение.
d="$(fixture g3)" || { echo "[VOID] фикстура g3 не собралась" >&2; exit 2; }
out="$(cd "$d" && env -u GIT_SSH_COMMAND GIT_SSH=/opt/inject/ssh-wrapper bash "$SUBJECT" origin work 2>&1)"; rc=$?
probe 0 "G3 близнец: транспорт — программа GIT_SSH — не перебит, состояние названо" \
    "$out" "$rc" "ВНИМАНИЕ" "/opt/inject/ssh-wrapper"
probes=$((probes + 1))
if [[ "$out" == *"keepalive выставлен этой отправке"* ]]; then
    failed=$((failed + 1)); echo "[FAIL] G3-контроль: обёртка выставила свой транспорт поверх GIT_SSH" >&2
else
    echo "[PASS] G3-контроль: свой транспорт поверх GIT_SSH не выставлен"
fi

# ── H. КОД СЪЕДЕН ПОСРЕДНИКОМ: вердикт обязан остаться в ПЕЧАТНОМ виде ───────
#
# Порог харнесса в 120 с этот хук перешагивает почти всегда, поэтому «код
# обёртки» будет приходить ВСЕГДА и почти всегда совпадать с истиной. Проба
# ставит ровно это: код потерян (посредник вернул 0), а вердикт об операции
# читается из вывода — и он отрицательный, потому что ссылки на сервере нет.
d="$(fixture h)" || { echo "[VOID] фикстура h не собралась" >&2; exit 2; }
sha="$(git -C "$d" rev-parse refs/heads/work)"
shim "$TMP/h"
out="$(cd "$d" && PATH="$TMP/h/bin:$PATH" bash -c "bash '$SUBJECT' origin work 2>&1; exit 0")"; rc=$?
probe 0 "H посредник съел код: ноль пришёл от него, а печатный вердикт называет ОТКАЗ" \
    "$out" "$rc" "ОТКАЗ" "$sha"
probes=$((probes + 1))
if [[ "$out" == *"ПОДТВЕРЖДЕНО"* ]]; then
    failed=$((failed + 1)); echo "[FAIL] H-контроль: в выводе есть и «ПОДТВЕРЖДЕНО» — вердикт неоднозначен" >&2
else
    echo "[PASS] H-контроль: слова «ПОДТВЕРЖДЕНО» в выводе НЕТ — читается однозначно"
fi

echo
echo "[CENSUS] push-verified-inject: проб исполнено $probes, провалов $failed; фикстур собрано 8, ложный ноль воспроизведён тремя путями (ноль команды, отказ транспорта, код съеден посредником)"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] признак не доказан: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] признак доказан в обе стороны: проб $probes, провалов 0"
