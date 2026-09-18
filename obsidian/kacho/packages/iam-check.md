---
title: iam check
repo: kacho-iam
layer: internal
category: packages
path: internal/check
related_tickets:
  - "[[../KAC/issue-278-kaname]]"
tags:
  - packages
  - kacho-iam
  - internal
  - go
status: stable
verified_against: "kaname origin/main: `git ls-tree -r --name-only origin/main internal/check/ | grep '\\.go$'` → 309 файлов, из них 84 не-тестовых; шапки `catalog_seed_parity.go` и (переехавшего) `internal/repo/kaname/pg/catalog_key_form_test.go` прочитаны; полный перечень гейтов построчно не пересматривался"
---

# `internal/check/` (kaname)

Пакет внутренних гейтов службы — инварианты дерева, судимые в прогоне (аналог
`internal/repohygiene` монорепо, но **в службе**, потому что гейт обязан сверяться с
**литералом** каталога прав ([[iam-authzmap]]), а корневой пакет импортировать его не может по
правилу внутренних пакетов Go). Каждый гейт печатает объём осмотренного, падает на пустом обходе
и доказан инъекцией (рядом с каждым — `*_injection_test.go`). Замер origin/main: 309 `.go`, из них
84 не-тестовых.

## Гейты парности каталога (предмет [[../KAC/issue-278-kaname]])

- `catalog_seed_parity.go` — ядро гейтов посева каталога модуля, **намеренно** отделённое от
  корня дерева, чтобы инъекция гоняла его на синтетическом входе, а не на этом дереве. Сверяется
  с литералом из [[iam-authzmap]], не с текстом чужого исходника.
- `catalog_copy_parity.go` — парность копии каталога.

## Гейт формы ключей УЕХАЛ отсюда (kaname#278)

Гейт `catalog_key_form` **переехал** из этого пакета в ярус репозитория
(`internal/repo/kaname/pg/catalog_key_form_test.go`), потому что сменил предмет: он больше не
читает текст **одной** базовой миграции, а судит **действующую** схему через `pg_catalog` (накат
всех миграций на живую базу) и распознаёт снятие ключа/индекса через `DROP COLUMN`. Разбор
слепоты прежнего яруса — в трейле [[../KAC/issue-278-kaname]].

## See also

[[iam-authzmap]] · [[../KAC/issue-278-kaname]] · [[../resources/iam-human-session]]

#packages #kacho-iam #internal #go
