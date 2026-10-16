#!/usr/bin/env bash
# ЕДИНЫЙ ВХОД доказательств набора: все сиблинги `inject-<N>.sh`, выведенные из
# каталога. Конвейер зовёт этот файл (`scripts/lib/run-suites.sh --proofs --job`,
# задание `vault-gate`), и только его.
#
# Доказательство того, что гейт СПОСОБЕН упасть — и способен смолчать: рядом с
# внесённым дефектом стоит ЗАКОННЫЙ БЛИЗНЕЦ той же формы (`gate-authoring`
# §Инъекция настоящим входом с законным близнецом).
#
# С 2026-10-16 набор судит только ведомые `lessons/` и `runbooks/` плюс
# учётные данные во всём хранилище (check-01); прежние check-01 (ребро называет снятый механизм) и
# check-04/05 (указатель) сняты вместе с заморозкой архива — их доказательства
# здесь жили и сняты тем же изменением.
#
# Перечень ВЫВОДИТСЯ из каталога, а не выписывается: рукописный разошёлся бы с
# деревом молча. Ноль найденных — ОТКАЗ, а не успех (`scripts/lib/proofs.sh`).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$SCRIPT_DIR/../lib/proofs.sh"
proof_parts "$SCRIPT_DIR"
[ $? -eq 2 ] && exit 1

echo
echo "inject: доказательств рассмотрено $PROOF_PARTS; провалено $PROOF_PARTS_BAD"

[ "$PROOF_PARTS_BAD" -eq 0 ]
