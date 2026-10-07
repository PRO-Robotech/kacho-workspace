---
title: "kaname#201: iam: снять поле сессии passwordChangeRequired и его читателей (служба → край)"
aliases:
  - issue-201-kaname
  - kaname#201
ticket_id: 201
category: kac
status: test
type: refactor
repos:
  - kacho
  - kaname
areas:
  - proto
  - gateway
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kaname/issues/201
opened: 2026-09-17
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#201: iam: снять поле сессии passwordChangeRequired и его читателей (служба → край)

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Снято поле сессии `passwordChangeRequired` и его читатели — в службе и на краю; номер и имя поля в proto зарезервированы. Закрыта в волне платформы, потому что последний читатель жил на краю.

## Затронутые каталоги

`proto`, `gateway` (PRO-Robotech/kaname, PRO-Robotech/kacho).

Работа влита до волны-4; в волне — доказательство на дереве слияния.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/201#issuecomment-6012652077): (kacho `1266`; kaname `296` @ `2cf9c8528b1f`): `git grep -c PasswordChangeRequired origin/1266 -- '*.go' ':!*_test.go' | wc -l` (kacho) → 0; то же на kaname `origin/296` → 0; `git grep -n 'reserved' origin/296 -- proto/kaname/cloud/iam/v1/human_session_service.proto` → `reserved 8;` и `reserved "password_change_required";` (строки 107–108); `git grep -n 'PasswordChangeRequired: *true' origin/296 -- '*_test.go' | wc -l` → 0; сквозная Ф5-24 — зелёная (запись закрытия выше, прогон в PRO-Robotech/kacho#1269).
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-iam #kacho-api-gateway
