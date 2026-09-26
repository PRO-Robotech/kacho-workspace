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
verified_against: "перепись файлов каталога на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21): 102 файла, из них 43 непробных; построчно прочитаны только объявления таблиц и функций, названные ниже. 2026-09-26: строки таблицы о церемонии и раздел открытых предметов пересверены на ветке эпика 357 (fc9f5aff) по миграциям `20260920175117`, `20260923160455`; перепись файлов каталога на 357 не повторялась"
---

# kaname `internal/migrations`

Схема продукта Kaname: `0001_initial.sql` плюс датированные миграции goose. Применённая
миграция не правится — правка идёт новой (запрет #5).

## Что схема держит сама, а не писатель

| предмет | чем |
|---|---|
| согласие контекста церемонии | составной UNIQUE на семействе, на который ссылаются составные FK кода и обновляющего токена, без каскада на обновлении |
| живость семейства у выданного | ключ живости семейства и FK выданного на него с каскадом на обновлении — [[edges/kaname-family-revoke-vs-token-issue]] |
| одноинструкционное гашение кода и ротация токена | условие на прежнее состояние + `RETURNING`; пары «прочитать, затем записать» нет |
| «признак активности» выданного и его основания — одно состояние | у кода и токена `active` — вычисляемая колонка из отметки снятия и живости семейства; у семейства живость и отметку отзыва сводит парный `CHECK` |
| непустой решивший у второй записи отсечки | `CHECK` на длину: отсечка без принявшего неоспорима |
| закрытые словари причин | `CHECK … = ANY(ARRAY[…])` без корзины «прочее» |

## Здесь живут схемные писатели отсечки

`kaname.minted_cutoff_on_client_removal()` и `kaname.minted_cutoff_on_owner_deactivation()`,
четыре триггера. Они переписывают причину и актора **безусловно**, тогда как Go-дверь после
`kn-313` — только вместе с принятым моментом: [[KAC/issue-335-kaname]],
[[edges/kaname-cutoff-door-vs-schema-writers]].

## Открытые предметы схемы

- триггер-зеркало между двумя записями отсечки — [[KAC/issue-336-kaname]].

Снятые с этого перечня: четвёртое значение словаря причин завершения сессии,
`admin-force-logout`, заведено миграцией
`20260923160455_human_session_end_reason_names_the_forced_exit.sql` на ветке эпика `357`
(коммит `925fb778a`, [[KAC/issue-334-kaname]]); в `main` его пока нет.

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`.
- 2026-09-26 (#778) — строки о церемонии приведены к ветке эпика `357` (ключ живости
  семейства, вычисляемый признак активности), #334 перенесена из открытых в снятые.

## See also

[[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
[[resources/iam-refresh-token]] · [[resources/iam-user-token-revocation]] ·
[[resources/iam-minted-token-revocation]] · [[resources/iam-human-session]]

#packages #kacho-iam #migrations
