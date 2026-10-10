---
title: "kaname#176: iam: отсечка сессии уезжает на провод усечённой до секунды, край сравнивает неусечённый момент"
aliases:
  - issue-176-kaname
  - kaname#176
ticket_id: 176
category: kac
status: test
type: fix
repos:
  - kacho
  - kaname
areas:
  - internal/apps/kaname/api/session_revocations
  - gateway/internal/streamrevocation
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kaname/issues/176
opened: 2026-09-16
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#176: iam: отсечка сессии уезжает на провод усечённой до секунды, край сравнивает неусечённый момент

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Отсечка сессии больше не усекается до секунды на проводе, и край судит открытый поток моментом сессии, полученным при разрешении хранилищем.

## Затронутые каталоги

`internal/apps/kaname/api/session_revocations`, `gateway/internal/streamrevocation` (PRO-Robotech/kaname, PRO-Robotech/kacho).

Правка края `67c6accf0cf` влита до волны-4; в волне — доказательство на дереве слияния.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/176#issuecomment-6012654508): (kacho `1266`; kaname `296` @ `2cf9c8528b1f`): край: `git merge-base --is-ancestor 67c6accf0cf origin/1266` → 0; `git grep -c 'func TestOpenStreamIsJudgedByTheSessionMomentAtStorageResolution' origin/1266 -- gateway/internal/streamrevocation/` → 1; `go test -count=1 ./gateway/internal/streamrevocation/ -run TestOpenStreamIsJudgedByTheSessionMomentAtStorageResolution` на дереве слияния → код 0, PASS 1; служба: `git grep -n 'Truncate(time.Second)' origin/296 -- internal/apps/kaname/api/session_revocations/ ':!*_test.go' | wc -l` → 0.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-iam #kacho-api-gateway
