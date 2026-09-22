#!/usr/bin/env bash
# check-10 — ВЕРДИКТ ОБ ОТПРАВКЕ БЕРЁТСЯ У СЕРВЕРА, А НЕ У КОДА ВОЗВРАТА.
#
# ПРЕДМЕТ — класс «код обёртки прочитан как исход операции». Между командой и её
# исходом всегда стоит посредник, и его код говорит О ПОСРЕДНИКЕ:
#   · 2026-09-22, путь первый: отправка отчиталась `exit code 0`, настоящий код
#     был 128 (`send-pack: unexpected disconnect`) — соединение молчало 831 с,
#     пока работал хук, и его оборвали по простою; пакет не ушёл;
#   · 2026-09-22, путь второй: хук перешагнул порог харнесса в 120 с (25 групп
#     проверок), команда ушла в фон и прислала «exit code 0». Настоящий код там
#     оказался нулём — СОВПАДЕНИЕ, а не доказательство.
# Путей будет больше, поэтому проверка спрашивает не причину, а ПОСТУСЛОВИЕ:
# ссылка на сервере равна отправленной sha, спрошенная отдельной командой ПОСЛЕ.
#
# ЧТО ТРЕБУЕТСЯ ОТ ОБЁРТКИ `scripts/push-verified.sh` — три утверждения:
#   ложный ноль   → код 1 и в выводе НЕТ слова подтверждения: команда вернула 0,
#                   ссылки на сервере нет, вердикт отрицательный;
#   законная      → код 0, слово подтверждения и та самая sha, причём сервер
#   отправка        и правда её несёт (спрошено НЕЗАВИСИМО от обёртки);
#   ПОЛОЖИТЕЛЬНЫЙ  → если законная отправка в песочнице не проходит вовсе,
#   КОНТРОЛЬ         остальные пробы недоказательны: это VOID, а не находка.
#
# ПОЧЕМУ ПОВЕДЕНЧЕСКАЯ, А НЕ ТЕКСТОВАЯ. Искать в исходнике `git ls-remote` значит
# закреплять запись: автор волен спросить сервер иначе (`--heads`, `rev-parse
# --remotes`, `gh api`). Спрашивается исход: рядом с обёрткой строится
# синтетический «сервер» (bare-репозиторий), и читается то, что обёртка вернула
# и напечатала.
#
# ПОЧЕМУ ЗДЕСЬ, А НЕ В `push-verified-inject.sh`. Тот доказывает признак в обе
# стороны двенадцатью пробами и запускается руками. Этот — узкая и быстрая
# половина того же вопроса, и он исполняется НА КАЖДОЙ ОТПРАВКЕ, потому что
# набор зовёт хук: обёртка, переставшая спрашивать сервер, обязана быть найдена
# в тот же день, а не на следующем ручном прогоне.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-10-push-verdict-comes-from-the-remote"
WRAPPER="scripts/push-verified.sh"
CONFIRM="ПОДТВЕРЖДЕНО"

mapfile -t FOUND < <(tooling_gate_files "$WS" "$WRAPPER")
if [ "${#FOUND[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "обёртки $WRAPPER в дереве нет — судить нечего"
    exit 2
fi

REAL_GIT="$(command -v git)" || { tooling_gate_void "$NAME" "git не найден"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Песочница: рабочая копия с одним коммитом и bare-«сервером» рядом. Личность
# задаётся ВНУТРИ неё недоставляемым адресом — рабочей копии это не касается.
fixture() {
    local dir="$TMP/$1" bare="$TMP/$1.git"
    git init -q --bare "$bare" >/dev/null 2>&1 || return 1
    git init -q "$dir" >/dev/null 2>&1 || return 1
    git -C "$dir" config user.email gate@example.invalid || return 1
    git -C "$dir" config user.name  gate || return 1
    git -C "$dir" checkout -q -b work >/dev/null 2>&1 || return 1
    echo "фикстура" > "$dir/file.txt"
    git -C "$dir" add -A >/dev/null 2>&1 || return 1
    git -C "$dir" commit -q -m "фикстура" >/dev/null 2>&1 || return 1
    git -C "$dir" remote add origin "$bare" >/dev/null 2>&1 || return 1
    printf '%s\n' "$dir"
}

# Шим: «git», который на `push` отчитывается нулём и не отправляет ничего.
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

findings=0
examined=0

for rel in "${FOUND[@]}"; do
    subject="$WS/$rel"

    # ── положительный контроль: законная отправка обязана проходить ───────────
    green_dir="$(fixture "green.$examined")" || {
        tooling_gate_void "$NAME" "песочницу не собрать (нет git либо коммит не состоялся) — пробы недоказательны"
        exit 2
    }
    green_sha="$(git -C "$green_dir" rev-parse refs/heads/work)"
    set +e
    green_out="$(cd "$green_dir" && bash "$subject" origin work 2>&1)"
    green_rc=$?
    set -e
    if [ "$green_rc" -ne 0 ]; then
        tooling_gate_void "$NAME" \
            "$rel — законная отправка в песочнице дала $green_rc; остальные пробы на ней недоказательны"
        exit 2
    fi
    examined=$((examined + 1))

    if ! printf '%s' "$green_out" | grep -qF "$CONFIRM"; then
        tooling_gate_fail "$NAME" "$rel — состоявшаяся отправка не названа словом «$CONFIRM»: читателю нечего отличать от отказа"
        findings=$((findings + 1))
    fi
    # sha ищется В СТРОКЕ ПОДТВЕРЖДЕНИЯ, а не где-нибудь в выводе: обёртка
    # называет её и до отправки («отправляю …»), и поиск по всему выводу был бы
    # зелёным у обёртки, которая подтверждает НЕИЗВЕСТНО ЧТО.
    if ! printf '%s' "$green_out" | grep -F "$CONFIRM" | grep -qF "$green_sha"; then
        tooling_gate_fail "$NAME" "$rel — строка подтверждения не называет sha $green_sha: подтверждено НЕИЗВЕСТНО ЧТО"
        findings=$((findings + 1))
    fi
    if [ "$(git --git-dir="$TMP/green.$((examined - 1)).git" rev-parse refs/heads/work 2>/dev/null)" != "$green_sha" ]; then
        tooling_gate_fail "$NAME" "$rel — обёртка подтвердила отправку, которой на сервере НЕТ"
        findings=$((findings + 1))
    fi

    # ── ложный ноль: команда вернула 0, пакет не ушёл ─────────────────────────
    red_dir="$(fixture "red.$examined")" || {
        tooling_gate_void "$NAME" "вторую песочницу не собрать — проба ложного нуля не исполнена"
        exit 2
    }
    shim "$TMP/shim.$examined"
    set +e
    red_out="$(cd "$red_dir" && PATH="$TMP/shim.$examined/bin:$PATH" bash "$subject" origin work 2>&1)"
    red_rc=$?
    set -e
    if [ "$red_rc" -eq 0 ]; then
        tooling_gate_fail "$NAME" \
            "$rel — команда отчиталась нулём, ссылки на сервере нет, а обёртка вышла 0: код посредника принят за исход операции"
        findings=$((findings + 1))
    fi
    if printf '%s' "$red_out" | grep -qF "$CONFIRM"; then
        tooling_gate_fail "$NAME" \
            "$rel — в выводе несостоявшейся отправки стоит «$CONFIRM»: при съеденном коде читатель прочтёт её как успех"
        findings=$((findings + 1))
    fi
done

tooling_gate_census "$NAME: обёрток осмотрено $examined (по две песочницы на каждую — законная отправка и ложный ноль; сервер спрошен независимо)"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "находок $findings"
    exit 1
fi

tooling_gate_pass "$NAME" "вердикт об отправке приходит от сервера: ложный ноль краснеет и не называется подтверждённым, состоявшаяся отправка названа sha"
