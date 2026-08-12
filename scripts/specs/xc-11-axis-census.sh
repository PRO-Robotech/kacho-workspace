#!/usr/bin/env bash
# xc-11-axis-census.sh — §1.1 приёмки XC-11 в КЛЕТОЧНОЙ форме: 14 осей × 7 сервисов.
#
# Зачем инструмент, а не таблица от руки. Прозаическая ячейка утверждает
# РАСПРЕДЕЛЕНИЕ по семи сервисам, а записана одной строкой; автор берёт координату
# у одного сервиса и выдаёт её за распределение. В первой редакции §1.1 это
# случилось дважды на четырнадцати ячейках — и оба раза у автора, который в том же
# документе объяснял, почему так делать нельзя. Лечится это ФОРМОЙ: клетка на
# сервис, у каждой координата либо «не применимо, потому что». Форму держит
# инструмент, а не старание.
#
# Каждая ось печатает СВОЙ предикат — строкой, которую можно выполнить отдельно.
# Клетка — либо путь из индекса git, либо `—` (пусто у этого сервиса). Пустая
# клетка сама по себе не находка: у части осей пустота законна и объявлена
# (лист-домен без соседей, сервис вне контура носителя). Разбор пустоты —
# в приёмке, здесь только измерение.
#
# Перепись печатается всегда: «осей 14, сервисов 7, клеток 98». Ноль прочитанных
# файлов обязан быть отличим от «расхождений не найдено».
#
# Прогон:  KACHO_MONOREPO=<путь> ./scripts/specs/xc-11-axis-census.sh
# Исходы:  0 — перепись напечатана; 2 — монорепо не найдено (проверять нечего).
set -uo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${KACHO_MONOREPO:-$WS/project/kacho}"

if [ ! -d "$REPO/.git" ]; then
    echo "[VOID] xc-11-axis-census — монорепо не найдено (ни KACHO_MONOREPO, ни project/kacho): мерить нечего" >&2
    exit 2
fi

REV="$(git -C "$REPO" rev-parse --short HEAD)"
SERVICES="compute geo iam nlb registry storage vpc"
axes=0
cells=0

# cell <сервис> <pathspec-глоб> — пути индекса сервиса, отфильтрованные от тестов.
cell() {
    local svc="$1" pat="$2" out
    out="$(git -C "$REPO" ls-files "services/$svc" | grep -E "$pat" | grep -v '_test\.go$' | tr '\n' ' ')"
    printf '%s' "${out:-—}"
}


# dash <строка> — пустая клетка печатается знаком, а не пустотой: пустая клетка и
# необойдённая клетка иначе выглядят одинаково.
dash() { printf '%s' "${1:-—}"; }

axis() {
    axes=$((axes + 1))
    echo
    echo "## ось $axes — $1"
    echo "предикат: $2"
}

row() {
    cells=$((cells + 1))
    printf '  %-9s %s\n' "$1" "$2"
}

echo "# XC-11 §1.1 — клеточная перепись осей участия"
echo "дерево продукта: $REV   ·   сервисов: $(echo "$SERVICES" | wc -w)"

# codegrep <pathspec> <ERE> — вхождения ERE в .go ВНЕ строчного комментария.
#
# Отбрасывание комментариев здесь не украшение: имена пары извлечения личности
# стоят в комментариях СЕМИ сервисов и НИ РАЗУ в их коде. Текстовый предикат дал
# бы «пару провязывают четверо» — ровно наоборот по смыслу, и это было бы третьей
# ошибкой того же класса в этом же разделе.
codegrep() {
    git -C "$REPO" grep -nE "$2" -- "$1" 2>/dev/null \
        | grep -E '\.go:' | grep -v '_test\.go:' \
        | awk -F: '{ l=$0; sub(/^[^:]*:[^:]*:/, "", l); if (l !~ /^[[:space:]]*(\/\/|\*)/) print }'
}

axis "пара извлечения личности — вызовы в коде сервиса (комментарии отброшены)" \
     "git grep -nE 'UnaryCertIdentityExtract|UnaryTrustedPrincipalExtract' -- services/<svc> | awk «строка не начинается с //»"
for s in $SERVICES; do
    row "$s" "$(dash "$(codegrep "services/$s" 'UnaryCertIdentityExtract|UnaryTrustedPrincipalExtract' | tr '\n' ' ')")"
done
# Контроль предпосылки: «ноль у всех семи» обязано быть отличимо от «предикат
# ничего не читает». Единственная сборка пары лежит в общем фундаменте — если её
# не видно и здесь, предикат сломан, а не дерево чисто.
echo "  контроль: сборок пары в pkg/ — $(codegrep pkg 'UnaryCertIdentityExtract\(\)' | wc -l) (ожидается ≥1)"

axis "вызов носителя контура (подъём слушателей)" \
     "codegrep services/<svc> 'servicehost\\.Serve\\('"
for s in $SERVICES; do
    row "$s" "$(dash "$(codegrep "services/$s" 'servicehost\.Serve\(' | cut -d: -f1 | sort -u | tr '\n' ' ')")"
done

axis "дескриптор процесса — где собирается" \
     "codegrep services/<svc> 'servicecontract\\.New'"
for s in $SERVICES; do
    row "$s" "$(dash "$(codegrep "services/$s" 'servicecontract\.New' | cut -d: -f1 | sort -u | tr '\n' ' ')")"
done

axis "загрузочный страж посадки — метод Config.Validate" \
     "git grep -l 'func (c Config) Validate' -- services/<svc> (кроме apps/migrator)"
for s in $SERVICES; do
    row "$s" "$(dash "$(git -C "$REPO" grep -lE 'func \(c \*?Config\) Validate\(' -- "services/$s" 2>/dev/null \
        | grep -v 'apps/migrator' | grep -v '_test\.go$' | tr '\n' ' ')")"
done

axis "зернистость стража — число именованных методов Config.Validate*" \
     "git grep -nE 'func \\(c Config\\) Validate[A-Za-z]*\\(' -- services/<svc> (кроме apps/migrator)"
for s in $SERVICES; do
    n="$(git -C "$REPO" grep -nE 'func \(c \*?Config\) Validate[A-Za-z]*\(' -- "services/$s" 2>/dev/null \
        | grep -v 'apps/migrator' | grep -vc '_test\.go:')"
    row "$s" "$n"
done

axis "самоотчёт посадки процесса" \
     "git ls-files services/<svc> | grep bootposture"
for s in $SERVICES; do row "$s" "$(cell "$s" 'bootposture')"; done

axis "дом клиента к владельцу модели прав" \
     "git ls-files services/<svc>/internal/clients | grep -i iam"
for s in $SERVICES; do
    row "$s" "$(dash "$(git -C "$REPO" ls-files "services/$s/internal/clients" 2>/dev/null \
        | grep -i iam | grep -v '_test\.go$' | tr '\n' ' ')")"
done

axis "рукописная карта прав" \
     "git ls-files services/<svc> | grep 'permission_map.go\$'"
for s in $SERVICES; do row "$s" "$(cell "$s" 'permission_map\.go$')"; done

axis "рукописная сверка карты с порождённым каталогом" \
     "git ls-files services/<svc> | grep 'catalog_parity_test.go\$'"
for s in $SERVICES; do
    row "$s" "$(dash "$(git -C "$REPO" ls-files "services/$s" | grep 'catalog_parity_test\.go$' | tr '\n' ' ')")"
done

axis "пакет эмиссии намерения регистрации" \
     "git ls-files services/<svc> | grep -E 'fgaintent|fga_intent|fgaregister'"
for s in $SERVICES; do row "$s" "$(cell "$s" 'fgaintent|fga_intent|fgaregister')"; done

axis "загрузочный гейт очереди намерений" \
     "git ls-files services/<svc> | grep fgaboot"
for s in $SERVICES; do row "$s" "$(cell "$s" 'fgaboot')"; done

axis "раскладка сужения списка (свой пакет)" \
     "git ls-files services/<svc> | grep -E 'authzfilter|listauthz'"
for s in $SERVICES; do row "$s" "$(cell "$s" 'authzfilter|listauthz')"; done

axis "общий носитель сужения списка — число не-тестовых импортов" \
     "git grep -l 'pkg/listnarrow' -- services/<svc> | grep -vc _test.go"
for s in $SERVICES; do
    n="$(git -C "$REPO" grep -l 'pkg/listnarrow' -- "services/$s" 2>/dev/null | grep -v '_test\.go$' | wc -l)"
    row "$s" "$n"
done

axis "машинный токен полосы отказа — общий носитель pkg/peer" \
     "git grep -l 'kacho/pkg/peer\"' -- services/<svc> | grep -vc _test.go"
for s in $SERVICES; do
    n="$(git -C "$REPO" grep -l '"github.com/PRO-Robotech/kacho/pkg/peer"' -- "services/$s" 2>/dev/null \
        | grep -v '_test\.go$' | wc -l)"
    row "$s" "$n"
done

echo
echo "[CENSUS] xc-11-axis-census: дерево $REV; осей $axes, сервисов $(echo "$SERVICES" | wc -w), клеток $cells"
if [ "$cells" -eq 0 ]; then
    echo "[VOID] xc-11-axis-census — ни одной клетки не заполнено: перепись не состоялась" >&2
    exit 2
fi
