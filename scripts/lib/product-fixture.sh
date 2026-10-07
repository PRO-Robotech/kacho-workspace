#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Синтетическое дерево ПРОДУКТА для проб полосы ствола. Source-only.
#
# ЗАЧЕМ ЭТОТ ФАЙЛ СУЩЕСТВУЕТ. Проба полосы ствола обязана различать два состояния
# чужого дерева — «копия стоит на стволе» и «копия припаркована в стороне», — и
# вход для этого она ПРОИЗВОДИТ САМА, а не берёт у лежащей рядом копии продукта.
# Иначе её вход зависит от того, куда эту копию сегодня переставили: полоса
# доказывалась бы ровно до дня, когда копию вернут на ствол, а потом молча
# перестала бы что-либо утверждать — то есть разделила бы судьбу дефекта, который
# ловит (`testing.md` §«Гейт на класс», п. 5 — исключение живёт, пока у него есть
# предмет).
#
# Дерево крохотное и целиком под контролем пробы: на стволе лежит одно, в
# припаркованной вершине — другое, и различие ОДНОФАКТНОЕ по каждой оси. Кандидат
# ствола ровно один (локальная ветвь переименована в `parked`), поэтому отбор не
# зависит от имени ветки по умолчанию в чужом `git config`.
#
# Читатели (предикат: `git grep -l product-fixture.sh -- scripts`):
#   * `scripts/docs-gate/inject.sh`
#   * `scripts/skills-gate/inject.sh`

# ── СТРАЖ: функция фикстуры НЕ ДЕЙСТВУЕТ НА НАСТОЯЩЕЕ ДЕРЕВО ──────────────────
#
# ЗАЧЕМ. Половина функций ниже разрушительна: `checkout --detach`, `clean -qfd`.
# Путь к фикстуре приходит аргументом, а `git -C ""` МОЛЧА берёт ТЕКУЩИЙ каталог —
# то есть при пустом аргументе разрушительная операция исполняется в общей рабочей
# копии. Пустым аргумент становится легко: производитель каталога умер под `set -u`
# на необъявленной переменной и вернул пустую строку, а вызывающий этого не увидел.
#
# ЦЕНА ИЗМЕРЕНА, А НЕ ПРЕДПОЛОЖЕНА (ws#622): ровно так и вышло — `mkprod_lane`
# ссылался на счётчик, снятый в стволе, отдал пустой путь, и
# `product_fixture_park_on_trunk ""` выполнил в общей рабочей копии
# `checkout --detach refs/remotes/origin/main` и `clean -qfd`. Снесло ВОСЕМЬ
# неотслеживаемых файлов соседней сессии; спасли их байт-копии, снятые заранее.
#
# ПОЧЕМУ МАРКЕР, А НЕ ПРОВЕРКА ИМЕНИ. «Не равен корню воркспейса» — предикат по
# списку известных мест, и он стареет: завтра появится второй корень, о котором
# страж не знает. Маркер утверждает ПРОИСХОЖДЕНИЕ: каталог сделан этой фикстурой,
# и только такой она вправе разрушать. Лежит он в `.git/`, поэтому `git add -A`
# его не подхватывает и состав фикстуры не меняется.
_PRODUCT_FIXTURE_MARK=".git/product-fixture"

# Подпись фикстуры — её собственный HOME со своим `.gitconfig` внутри `.git/`
# (`git add -A` его не видит), в котором корневая учётная запись вызывающего.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=sandbox-git-home.sh
. "$(dirname "${BASH_SOURCE[0]}")/sandbox-git-home.sh"
_PRODUCT_FIXTURE_HOME=".git/sandbox-home"

# _product_fixture_git <каталог> <аргументы git…> — git фикстуры под её HOME.
_product_fixture_git() {
    local dir="$1"; shift
    SANDBOX_GIT_HOME="$dir/$_PRODUCT_FIXTURE_HOME" sandbox_git -C "$dir" "$@"
}

# _product_fixture_assert_own <каталог> — иначе отказ с кодом 2 и внятным текстом.
_product_fixture_assert_own() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        echo "product-fixture: пустой путь фикстуры — производитель каталога умер и вернул пустую строку. Разрушительная операция в ТЕКУЩЕМ каталоге отменена" >&2
        return 2
    fi
    if [ ! -e "$dir/$_PRODUCT_FIXTURE_MARK" ]; then
        echo "product-fixture: '$dir' не создан product_fixture_init (нет $_PRODUCT_FIXTURE_MARK) — отказываюсь трогать чужое дерево" >&2
        return 2
    fi
    return 0
}

# ── СТРАЖ: каталог фикстуры лежит ВНЕ рабочей копии git (ws#924) ─────────────
#
# ЗАЧЕМ. Фикстура — целый репозиторий. Внутри чужой рабочей копии она становится
# её неотслеживаемым каталогом: `git status` общего клона перестаёт быть признаком
# чистоты, гейты состава дерева дают находку на исправном дереве, соседняя полоса
# судит чужой файл. Каталог задаёт `mktemp -p`, то есть `TMPDIR` вызывающего, и
# свойство держалось его вниманием. Измерено: в общем клоне kaname лежали три
# каталога `h.XXXXXX` с коммитом «ствол» этой фикстуры (бывшая kaname#350). А если
# путём оказался корень самой копии, `init` перевёл бы её HEAD на `parked`.
#
# ПРИЗНАК — ответ git, а не перечень известных мест: от ближайшего существующего
# предка пути git ищет репозиторий вверх, и любой найденный — отказ, в том числе
# игнорируемый подкаталог (форма `tmp/` воркспейса): фикстура пишет только во
# временный каталог. Указатели окружения, подменяющие поиск (`GIT_DIR`,
# `GIT_WORK_TREE`, `GIT_CEILING_DIRECTORIES`), снимаются, а граница файловой
# системы поиск не обрывает — оба послабления дали бы «вне копии» молча.
#
# Доказательство — `scripts/docs-gate/inject-10.sh`.

# product_fixture_outside_worktree <путь> — 0, если путь вне любой рабочей копии
# и вне любого репозитория; иначе 1 и строка, называющая найденную копию.
product_fixture_outside_worktree() {
    local path="${1:-}" probe found
    [ -n "$path" ] || { echo "product-fixture: пустой путь — место фикстуры не определено" >&2; return 1; }
    probe="$path"
    while [ ! -d "$probe" ]; do
        probe="$(dirname "$probe")"
    done
    if found="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
            GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
            git -C "$probe" rev-parse --path-format=absolute --git-dir 2>/dev/null)"; then
        local top
        top="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
            GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
            git -C "$probe" rev-parse --show-toplevel 2>/dev/null)" || top="$found"
        echo "product-fixture: '$path' лежит внутри рабочей копии git '${top:-$found}' — фикстура пишет только во временный каталог вне копий (TMPDIR вызывающего указывает в дерево?)" >&2
        return 1
    fi
    return 0
}

# product_fixture_root_census <корень> — перепись места фикстур для вывода
# доказательства: 0 и строка с путём, если корень вне копий; иначе 2 и `[VOID]`.
product_fixture_root_census() {
    local root="${1:-}"
    # Пустой корень — это умерший производитель каталога (`mktemp` вызывающего
    # отказал), а не «корень в дереве»: причина называется своя, иначе вывод
    # отправляет читать TMPDIR, когда сломан сам временный каталог.
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        echo "[VOID] фикстуры продукта: корня нет ('${root}') — временный каталог не создан (mktemp вызывающего отказал?), место фикстур не определено" >&2
        return 2
    fi
    if product_fixture_outside_worktree "$root"; then
        echo "фикстуры продукта: под $root — вне рабочей копии git"
        return 0
    fi
    echo "[VOID] фикстуры продукта: корень $root внутри рабочей копии git — синтетические деревья встали бы в чужое дерево" >&2
    return 2
}

# product_fixture_init <каталог> — пустое дерево продукта с одним кандидатом ствола.
#
# Подпись — HOME фикстуры со своим `.gitconfig`, а не конфиг выброшенного дерева:
# правило подписи действует и на дерево, которое на origin не попадает никогда
# (ws#785). Без подписи `commit` отказывает (`empty ident name`) везде, где нет
# корневого конфига; нет его у вызывающего — init отказывает кодом 2.
product_fixture_init() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        echo "product-fixture: product_fixture_init вызван с пустым путём" >&2
        return 2
    fi
    product_fixture_outside_worktree "$dir" || return 2
    mkdir -p "$dir"
    git -C "$dir" init -q
    # HOME вызывающего (`SANDBOX_GIT_HOME`) фикстура не перенимает и не сбивает:
    # локальная переменная — область, куда `sandbox_git_home` пишет путь.
    # shellcheck disable=SC2034
    local SANDBOX_GIT_HOME=""
    sandbox_git_home "$dir/$_PRODUCT_FIXTURE_HOME" || return 2
    git -C "$dir" config commit.gpgsign false
    # Маркер происхождения — его требуют все функции ниже (см. страж выше).
    : > "$dir/$_PRODUCT_FIXTURE_MARK"
    # Имя локальной ветви уводится из набора имён ствола: кандидатом обязана быть
    # ровно одна ссылка, иначе отбор зависит от `init.defaultBranch` чужой машины.
    git -C "$dir" symbolic-ref HEAD refs/heads/parked
}

# product_fixture_seal_trunk <каталог> — то, что сейчас в дереве, становится СТВОЛОМ.
product_fixture_seal_trunk() {
    local dir="${1:-}"
    _product_fixture_assert_own "$dir" || return 2
    git -C "$dir" add -A -f >/dev/null 2>&1
    _product_fixture_git "$dir" commit -q -m 'ствол' >/dev/null 2>&1
    git -C "$dir" update-ref refs/remotes/origin/main "$(git -C "$dir" rev-parse HEAD)"
}

# product_fixture_seal_parked <каталог> — то, что сейчас в дереве, становится
# ПРИПАРКОВАННОЙ вершиной: коммит поверх ствола, HEAD отсоединён. Ствол при этом
# остаётся там, где был, поэтому `ls-tree <ствол>` и `ls-files` отвечают РАЗНОЕ —
# ровно то различие, ради которого фикстура и заведена.
product_fixture_seal_parked() {
    local dir="${1:-}"
    _product_fixture_assert_own "$dir" || return 2
    git -C "$dir" add -A -f >/dev/null 2>&1
    _product_fixture_git "$dir" commit -q -m 'припаркованная вершина' >/dev/null 2>&1
    git -C "$dir" checkout -q --detach HEAD
}

# product_fixture_park_on_trunk <каталог> — копия ВОЗВРАЩЕНА на ствол.
# Однофактное отличие от припаркованной: положение HEAD, и только оно. Состав
# ствола не меняется, поэтому вердикт обязан совпасть — это и есть свойство,
# которое проба заводит.
product_fixture_park_on_trunk() {
    local dir="${1:-}"
    _product_fixture_assert_own "$dir" || return 2
    git -C "$dir" checkout -q --detach refs/remotes/origin/main
    git -C "$dir" clean -qfd
}

# product_fixture_drop_trunk <каталог> — ствола не существует вовсе.
# Кандидатов не остаётся: ни ветки слежения, ни локальной с именем ствола. Читатель
# обязан ответить ТРЕТЬЕЙ КАТЕГОРИЕЙ, а не откатиться на индекс молча.
product_fixture_drop_trunk() {
    local dir="${1:-}"
    _product_fixture_assert_own "$dir" || return 2
    git -C "$dir" update-ref -d refs/remotes/origin/main
}

# product_fixture_set_identity <каталог> <owner/name> — объявить ИДЕНТИЧНОСТЬ дерева.
#
# ЗАЧЕМ. Координата приёмки вправе назвать свой ДОМ — репозиторий предмета
# (`e2e-flow.md` §7а), — и читатель резолвит дом по идентичности рабочей копии
# (`owner/name` в `origin`), а не по имени каталога: имя каталога — произвольная
# метка, и опознание по ней было бы адресацией по мутабельному имени. Значит
# фикстура, изображающая названный дом, обязана эту идентичность НЕСТИ; без неё
# она изображает дерево без origin, то есть другой случай.
#
# Пробе нужен и этот другой случай — дерево, чья идентичность НЕ та, что назвали, —
# поэтому имя передаётся аргументом, а не выводится из каталога.
product_fixture_set_identity() {
    local dir="${1:-}" id="${2:-}"
    _product_fixture_assert_own "$dir" || return 2
    if [ -z "$id" ]; then
        echo "product-fixture: product_fixture_set_identity вызван без owner/name" >&2
        return 2
    fi
    git -C "$dir" remote remove origin >/dev/null 2>&1
    git -C "$dir" remote add origin "git@github.com:$id.git"
}
