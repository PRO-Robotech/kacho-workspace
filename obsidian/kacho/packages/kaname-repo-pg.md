---
title: "kaname internal/repo/kaname/pg"
aliases:
  - kaname repo pg
  - kaname-repo-pg
category: packages
path: internal/repo/kaname/pg
repo: kacho-iam
layer: repo
status: stable
related_tickets:
  - "[[KAC/issue-335-kaname]]"
  - "[[KAC/issue-336-kaname]]"
  - "[[KAC/issue-339-kaname]]"
tags:
  - packages
  - kacho-iam
  - repo
  - go
verified_against: "перепись файлов каталога на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21): 498 файлов, из них 114 непробных; названные ниже адаптеры прочитаны построчно, остальные — нет"
---

# kaname `internal/repo/kaname/pg`

pg-адаптер репозиториев продукта Kaname: pgx + рукописное отображение, без ORM
(запрет #3). Дом писателей отсечки субъекта, записей церемонии и записи сессии человека.

> [!important] Этот пакет — не `services/iam/internal/repo/kacho/pg`
> Одноимённого слоя в монорепо Kachō ([[packages/iam-repo-kacho-pg]]) он не продолжает и не
> заменяет: Kaname — отдельный продукт, и деревья у них разные.

## Двери, у которых писатель обязан быть один

| дверь | что кладёт | почему одна |
|---|---|---|
| `upsertSubjectCutoff` | **обе** записи отсечки субъекта | путь снятия доступа, дошедший до одной записи и не дошедший до второй, есть контроль, исполненный наполовину и выглядящий исполненным целиком |
| `endSessionsOfSQL` | снятие живых записей сессии личности | исполнителей два — транзакция полосы входа и пул административного выхода; две копии оператора разошлись бы молча |
| `upsertMintedCutoffSQL` | вторую запись отсечки | тот же оператор зовут обе двери; расхождение означало бы «по одной записи отозван, по другой нет» |

## Границы, названные прямо

- Непредставимость пары записей отсечки достигнута **в пределах пакета**, не схемы:
  [[KAC/issue-336-kaname]].
- Схемные писатели второй записи живут в [[packages/kaname-migrations]] и расходятся с
  дверью в двух свойствах: [[edges/kaname-cutoff-door-vs-schema-writers]].
- Причины отзыва семейства, у которых писателя в этом пакете нет:
  [[KAC/issue-339-kaname]].

## See also

[[resources/iam-user-token-revocation]] · [[resources/iam-minted-token-revocation]] ·
[[resources/iam-token-family]] · [[resources/iam-human-session]] · [[packages/kaname-migrations]]

#packages #kacho-iam #repo #go
