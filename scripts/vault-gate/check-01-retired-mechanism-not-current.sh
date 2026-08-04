#!/usr/bin/env bash
# Записка-ребро не вправе называть СВОИМ предметом механизм, который дерево
# запретило потребителю, не объявив при этом, что описывает прошлое.
#
# Почему именно рёбра. Запрет адресован ПОТРЕБИТЕЛЮ: «перечисли всё, что субъекту
# можно» из сервиса-вызывающего. Сам RPC на стороне владельца прав жив и
# обслуживается, поэтому записка в rpc/, описывающая его как метод, — верна, и
# предметом этой проверки не является. Спутать эти две вещи значит получить гейт,
# который краснеет на правде.
#
# Что считается находкой: ЗАГОЛОВОК записки называет запрещённый механизм, а
# объявленное состояние не признаёт прошлое. Тело, объясняющее «почему этот
# механизм снят», находкой не является и обязано существовать — иначе следующий
# читатель вернёт снятое.
#
# Исход: 0 — чисто; 1 — находки; 2 — предпосылки нет (VOID).

set -uo pipefail

# shellcheck source=scripts/vault-gate/_lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

CHECK="записка-ребро не выдаёт снятый механизм за текущий"

ws="$(vault_gate_workspace_root)"

repo="$(vault_gate_monorepo "$ws")" || {
    vault_gate_void "$CHECK" "монорепо не найдено (ни KACHO_MONOREPO, ни project/kacho) — запрет вывести не из чего"
    exit 2
}

mapfile -t banned < <(vault_gate_banned_consumer_mechanisms "$repo")
mapfile -t declaring < <(vault_gate_ban_declaring_files "$repo")

if [ "${#banned[@]}" -eq 0 ] || [ "${#declaring[@]}" -eq 0 ]; then
    vault_gate_void "$CHECK" \
        "в дереве $(git -C "$repo" rev-parse --short HEAD) ни один анализатор сужения не объявляет запрещённых имён — предмет запрета исчез, судить не по чему"
    exit 2
fi

mapfile -t notes < <(vault_gate_edge_files "$ws")
if [ "${#notes[@]}" -eq 0 ]; then
    vault_gate_void "$CHECK" "в индексе нет ни одной записки-ребра"
    exit 2
fi

findings=0
titled=0
for f in "${notes[@]}"; do
    title="$(vault_gate_note_title "$ws/$f")"
    [ -n "$title" ] || continue
    for m in "${banned[@]}"; do
        case "$title" in
            *"$m"*) ;;
            *) continue ;;
        esac
        titled=$((titled + 1))
        st="$(vault_gate_note_status "$ws/$f")"
        if vault_gate_status_is_retired "$st"; then
            continue
        fi
        findings=$((findings + 1))
        vault_gate_fail "$CHECK" \
            "$f — заголовок называет «$m», дерево запретило его потребителю, а состояние записки «${st:-не объявлено}» выдаёт её за текущую"
    done
done

# Объём осмотренного — ОТДЕЛЬНОЕ утверждение: «находок ноль» обязано быть отличимо
# от «прочитано ноль» (`testing.md` §Гейт на класс п.3).
echo "vault-gate[01]: дерево $(git -C "$repo" rev-parse --short HEAD), запрещённых имён ${#banned[@]} из ${#declaring[@]} анализатор(ов); прочитано ${#notes[@]} записок-рёбер, из них называют запрещённое в заголовке $titled"

if [ "$findings" -gt 0 ]; then
    vault_gate_fail "$CHECK" "находок $findings"
    exit 1
fi

vault_gate_pass "$CHECK" "находок 0 при $titled записках, называющих снятый механизм в заголовке"
exit 0
