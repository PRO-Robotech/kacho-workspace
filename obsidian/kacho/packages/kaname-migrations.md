---
title: "kaname internal/migrations"
aliases:
  - kaname schema
  - kaname-migrations
category: packages
path: internal/migrations
repo: kacho-iam
layer: migrations
status: stable
related_tickets:
  - "[[KAC/issue-334-kaname]]"
  - "[[KAC/issue-335-kaname]]"
  - "[[KAC/issue-336-kaname]]"
tags:
  - packages
  - kacho-iam
  - migrations
verified_against: "перепись файлов каталога на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21): 102 файла, из них 43 непробных; построчно прочитаны только объявления таблиц и функций, названные ниже"
---

# kaname `internal/migrations`

Схема продукта Kaname: `0001_initial.sql` плюс датированные миграции goose. Применённая
миграция не правится — правка идёт новой (запрет #5).

## Что схема держит сама, а не писатель

| предмет | чем |
|---|---|
| согласие контекста церемонии | составной UNIQUE на семействе, на который ссылаются составные FK кода и обновляющего токена |
| одноинструкционное гашение кода и ротация токена | условие на прежнее состояние + `RETURNING`; пары «прочитать, затем записать» нет |
| «признак активности» и «отметка снятия» — одно состояние | парные `CHECK`; писатель их согласовать не обязан |
| непустой решивший у второй записи отсечки | `CHECK` на длину: отсечка без принявшего неоспорима |
| закрытые словари причин | `CHECK … = ANY(ARRAY[…])` без корзины «прочее» |

## Здесь живут схемные писатели отсечки

`kaname.minted_cutoff_on_client_removal()` и `kaname.minted_cutoff_on_owner_deactivation()`,
четыре триггера. Они переписывают причину и актора **безусловно**, тогда как Go-дверь после
`kn-313` — только вместе с принятым моментом: [[KAC/issue-335-kaname]],
[[edges/kaname-cutoff-door-vs-schema-writers]].

## Открытые предметы схемы

- четвёртое значение в словаре причин завершения сессии — [[KAC/issue-334-kaname]];
- триггер-зеркало между двумя записями отсечки — [[KAC/issue-336-kaname]].

## See also

[[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
[[resources/iam-refresh-token]] · [[resources/iam-user-token-revocation]] ·
[[resources/iam-minted-token-revocation]] · [[resources/iam-human-session]]

#packages #kacho-iam #migrations
