---
title: "kacho#3002: repohygiene: потолок привязок к снятому поставщику судит прирост"
aliases:
  - issue-3002
  - kacho#3002
ticket_id: 3002
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/3002
opened: 2026-10-03
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3002: repohygiene: потолок привязок к снятому поставщику судит прирост

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Потолок привязок к снятому поставщику личности судит добавленное дельтой, а не общий прирост.

## Затронутые каталоги

`internal/repohygiene` (PRO-Robotech/kacho).

Коммиты в составе волны: `c79c753702c`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3002#issuecomment-6012645212): `go test -count=1 -v ./internal/repohygiene/ -run 'RetiredVendor|RetiredIdentityVendor'` → код 0, PASS 100, FAIL 0 (четыре пробы предиката в их числе; красный до правки — комментарий от 2026-10-05, ревизия c79c7537). Конвейер: golangci-lint юниты internal — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-deploy
