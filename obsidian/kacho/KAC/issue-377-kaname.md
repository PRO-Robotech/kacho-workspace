---
title: "kaname#377: волна второго фактора — влита в ветку эпика"
aliases:
  - issue-377-kaname
ticket_id: 377
category: kac
status: done
type: epic
repos:
  - kaname
areas:
  - internal/apps/kaname/api/humansession
  - internal/check
  - internal/passwordverify
  - docs/engineering/acceptance
  - docs/specs/reviews
prs:
  - https://github.com/PRO-Robotech/kaname/pull/409
issue_url: https://github.com/PRO-Robotech/kaname/issues/377
opened: 2026-09-23
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "PRO-Robotech/kaname: PR #409 влит 2026-09-24T14:09:51Z коммитом слияния dbf25d17e25cba5368856da789c2674705a2392f (родители d65f97e9e3e, dda965ecef3) = origin/357 на 2026-09-24; голова волны dda965ecef3 не предок origin/main (`git merge-base --is-ancestor`); ветка 377 с origin снята (`git ls-remote origin refs/heads/377` пусто). Прогоны головы — `gh run list --commit dda965ecef351b97c563a80b37e626bc05dc9ef2`. Закрытие: `gh issue view 377 -R PRO-Robotech/kaname --json state,closedAt` — CLOSED 2026-09-26T09:40:51Z; головы задач — перемерено мной 2026-09-26: `git merge-base --is-ancestor <голова> <origin/357>` — код 0, против origin/main — код 1; origin/357 = fc9f5aff19cfff9ec310f2ff35338b80f24379b1, origin/main = cbbac984b7b17f22bcc4a83f7533fff3494c809a (`git ls-remote origin`)"
---

# kaname#377: волна второго фактора — влита в ветку эпика

**Состояние на момент записи**: `test` — 2026-09-24. Задача волны была открыта с меткой
`status:test`; волна влита в ветку эпика `357` (координата, не живая ссылка) и в `main` **не**
доехала. Тогдашняя норма держала задачи волны открытыми до посадки эпика в ствол; её отменил
каскад закрытия 2026-09-26.

**Состояние на 2026-09-26**: `done`. Волна закрыта тем, что её запрос влит в ветку эпика
(`git-issues.md#gi-close-cascade`, решение владельца 2026-09-26), и тем же заходом закрыты её
задачи #287, #305, #378; #295 закрыта вместе со своей волной [[KAC/issue-358-kaname|#358]].
Закрывающая запись с коммитом слияния и числом закрытых — комментарий в задаче. Посадка эпика
#357 в `main` — предмет эпика, а не волны.

## Что и зачем

Полоса второго фактора, восстановление доступа через единственного писателя, записи ревью
редакции 11 и калибровка огибающей входа — одной волной в ветку эпика. Предмет каждой задачи —
в её записке.

## Вливание

| что | координата |
|---|---|
| запрос волны | PR #409 `377` → `357`, голова `dda965ecef351b97c563a80b37e626bc05dc9ef2` |
| коммит слияния в ветке эпика | `dbf25d17e25cba5368856da789c2674705a2392f` |
| база эпика в волне | `357` @ `d65f97e9e3e` влита в `377` коммитом `8ba158e4809` |
| вердикт головы | прогоны `workflow_dispatch` попытка 1: ci `36006719990`, образ службы `36006724769`, e2e-newman `36006729719`; 20 заданий — 17 `success`, 3 `skipped`, 0 упавших |

Прогоны на самом запросе не шли: ветка `377` ответвлена до правки триггера
[[KAC/issue-394-kaname|#394]], поэтому вердикт снят ручным запуском по голове.

## Задачи волны и их слияния в `377`

| задача | голова → слияние |
|---|---|
| [[KAC/issue-287-kaname\|#287]] | `7d0e12e4b05` → `ae0c77502e6`; `a71043da90e` → `253cf0446c3` |
| [[KAC/issue-305-kaname\|#305]] | `d22f5f4f5d2` → `4ed53c9b94a` |
| [[KAC/issue-378-kaname\|#378]] | `d060e6df67e` → `2209bce0b62`; `f4190035d7a` → `0ea18de483e` |
| [[KAC/issue-295-kaname\|#295]] | `c22aeb58d72` → `4edbb2821f0`; `5e7a46e90fe` → `83829f2d586`; `b80cdd0074b` → `7910f12528b`; `585749b7422` → `dda965ecef3` |

Последние головы задач (перечень тела PR #409) — предки origin/`357`, не предки origin/`main`
(на 2026-09-24 и перемерено 2026-09-26 @ `fc9f5aff19c`).
#295 — sub-issue волны [[KAC/issue-358-kaname|#358]], влита этой волной.

## Затронутые сущности vault

Поля «затронуто в vault» у задач волны нет; узкие записки не менялись.

- [[KAC/issue-287-kaname]] · [[KAC/issue-305-kaname]] · [[KAC/issue-378-kaname]] ·
  [[KAC/issue-295-kaname]] — задачи волны.

#kac #kacho-iam #epic
