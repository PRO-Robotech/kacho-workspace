---
title: iam authzmap
repo: kacho-iam
layer: internal
category: packages
path: internal/authzmap
related_tickets:
  - "[[../KAC/issue-254-kaname]]"
  - "[[../KAC/issue-1281-kaname]]"
tags:
  - packages
  - kacho-iam
  - internal
  - go
status: stable
verified_against: "kaname origin/main: `git ls-tree -r --name-only origin/main internal/authzmap/` прочитан (8 прод-файлов + гейты модели); `governing_the_identity_is_not_an_account_right_test.go` и `catalog_seed_parity.go` ([[iam-check]]) прочитаны построчно в шапке; отношения per-RPC построчно не пересматривались"
---

# `internal/authzmap/` (kaname)

Дом **канонической модели прав** службы: типы и отношения FGA, посев каталога прав и его
свойства. Каталог прав генерируется **из proto** и является единственным источником per-RPC
решения края — здесь он посеян, скомпилирован в отношения и охраняется гейтами класса.

## Прод-файлы (по предмету)

| Файл | Предмет |
|---|---|
| `fga_types.go` · `type_dictionaries.go` | типы модели и их словари |
| `catalog_seed.go` · `catalog_resource_spelling.go` | посев каталога прав, канон написания ресурса |
| `permissions_to_relations.go` · `role_verbs.go` | отображение «право → отношение», глаголы ролей |
| `expand_acceptance.go` | развёртка отношения из канонической модели (для гейтов и приёмок) |
| `tables_gen.go` | генерат таблиц модели |

## Гейты класса (не литерал, а каталог)

Пробы утверждают **свойства модели**, компилируя отношение из канонической модели и спрашивая
его у каталога, а не сверяясь с литералом имени (литерал превратил бы гейт в проверку
написания). Среди них — дрейф канонической модели и модели FGA, круговой обход каталога,
«материализованное отношение имеет читателя», «условное отношение имеет производителя», и
классы распоряжения:

- **`governing_the_identity_is_not_an_account_right`** ([[../KAC/issue-254-kaname]]) —
  распоряжаться строкой личности не вправе распорядитель аккаунта: человек глобален (одна
  `iam_user` на все аккаунты), поэтому такое действие переходит границу аккаунта. Гейт
  проверяет с обеих сторон, что у отношения нет источников уровня аккаунта и нет прямого списка
  субъектов, а держатель (администратор облака) есть. Читатель — `UserService/ResetSecondFactor`
  ([[../rpc/iam-user-service]]).
- **`excluding_from_an_account_is_an_account_right`** — зеркальный: исключение из аккаунта,
  наоборот, **есть** право аккаунта (круг вводящих = круг выводящих).

## See also

[[iam-authzguard]] · [[iam-check]] · [[../rpc/iam-user-service]] · [[../KAC/issue-254-kaname]]

#packages #kacho-iam #internal #go
