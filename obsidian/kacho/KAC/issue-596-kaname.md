---
title: "kaname#596: приёмка A7 — заведение пароля из живой сессии"
aliases:
  - issue-596-kaname
  - kaname#596
ticket_id: 596
category: kac
status: in-progress
type: docs
repos:
  - kaname
areas:
  - docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/597
issue_url: https://github.com/PRO-Robotech/kaname/issues/596
opened: 2026-10-04
tags:
  - kac
  - kacho-iam
  - iam
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#596: приёмка A7 — заведение пароля из живой сессии

> [!note] Состояние — `in-progress`: приёмка одобрена, запрос в ветку волны не влит
> Записи ревью: круг 1 — CHANGES_REQUESTED, круг 2 — APPROVED (ветка `596`); событие полномочия
> опубликовано в kaname#213. Запрос [kaname#597](https://github.com/PRO-Robotech/kaname/pull/597)
> (`596` → `537`) открыт, 2026-10-04.

## Что и зачем

Носитель приёмки A7 волны-3: заведение первого пароля из живой сессии
(`POST /iam/v1/auth/password/enroll`). Своя задача понадобилась потому, что ветка `213` занята приёмкой
Ф5 (kaname#593), а предмет #213 по §0.2 Ф13 входит в A5–A7.

## Затронутые каталоги

`docs/engineering/acceptance/first-password-from-a-live-session.md`, `docs/specs/reviews/`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] приёмка APPROVED, событие опубликовано — комментарий задачи 2026-10-04;
- [ ] запрос kaname#597 влит в `537` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-537-kaname]] — волна-3

#kac #kacho-iam #iam
