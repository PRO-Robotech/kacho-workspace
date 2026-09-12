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

# product_fixture_init <каталог> — пустое дерево продукта с одним кандидатом ствола.
#
# Подпись ставится В КОНФИГ ВЫБРОШЕННОГО дерева, а не через `-c`/`GIT_AUTHOR_*`:
# правило про подпись владельца связывает коммиты РЕПОЗИТОРИЯ, а это дерево живёт
# до конца пробы и на origin не попадает НИКОГДА. Без подписи `commit` отказывает
# (`empty ident name`) везде, где нет глобального конфига, — то есть на ранере, где
# выкладка подменяет HOME; локально проба при этом зеленела бы на подписи
# разработчика.
product_fixture_init() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.name  'product fixture'
    git -C "$dir" config user.email 'fixture@invalid'
    git -C "$dir" config commit.gpgsign false
    # Имя локальной ветви уводится из набора имён ствола: кандидатом обязана быть
    # ровно одна ссылка, иначе отбор зависит от `init.defaultBranch` чужой машины.
    git -C "$dir" symbolic-ref HEAD refs/heads/parked
}

# product_fixture_seal_trunk <каталог> — то, что сейчас в дереве, становится СТВОЛОМ.
product_fixture_seal_trunk() {
    local dir="$1"
    git -C "$dir" add -A -f >/dev/null 2>&1
    git -C "$dir" commit -q -m 'ствол' >/dev/null 2>&1
    git -C "$dir" update-ref refs/remotes/origin/main "$(git -C "$dir" rev-parse HEAD)"
}

# product_fixture_seal_parked <каталог> — то, что сейчас в дереве, становится
# ПРИПАРКОВАННОЙ вершиной: коммит поверх ствола, HEAD отсоединён. Ствол при этом
# остаётся там, где был, поэтому `ls-tree <ствол>` и `ls-files` отвечают РАЗНОЕ —
# ровно то различие, ради которого фикстура и заведена.
product_fixture_seal_parked() {
    local dir="$1"
    git -C "$dir" add -A -f >/dev/null 2>&1
    git -C "$dir" commit -q -m 'припаркованная вершина' >/dev/null 2>&1
    git -C "$dir" checkout -q --detach HEAD
}

# product_fixture_park_on_trunk <каталог> — копия ВОЗВРАЩЕНА на ствол.
# Однофактное отличие от припаркованной: положение HEAD, и только оно. Состав
# ствола не меняется, поэтому вердикт обязан совпасть — это и есть свойство,
# которое проба заводит.
product_fixture_park_on_trunk() {
    local dir="$1"
    git -C "$dir" checkout -q --detach refs/remotes/origin/main
    git -C "$dir" clean -qfd
}

# product_fixture_drop_trunk <каталог> — ствола не существует вовсе.
# Кандидатов не остаётся: ни ветки слежения, ни локальной с именем ствола. Читатель
# обязан ответить ТРЕТЬЕЙ КАТЕГОРИЕЙ, а не откатиться на индекс молча.
product_fixture_drop_trunk() {
    local dir="$1"
    git -C "$dir" update-ref -d refs/remotes/origin/main
}
