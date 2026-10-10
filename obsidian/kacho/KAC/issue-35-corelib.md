---
title: "corelib#35: ID гранта чеканит крючок службы Config.NewGrantID"
aliases:
  - issue-35-corelib
ticket_id: 35
category: kac
status: done
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
  - ids
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/35
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи e90d570cd41 — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:38:08Z, меток status:* нет (`gh issue view`); коммит слияния волны 227ed2b77b4 — в origin/26, не в origin/main (`gh api compare`)"
---

# corelib#35: ID гранта чеканит крючок службы Config.NewGrantID

**Состояние на момент записи**: `done` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:38:08Z вместе с волной [[KAC/issue-32-corelib|#32]]: запрос волны PR #62 влит в ветку эпика `26` (координата, не живая ссылка), коммит закрытия — слияние волны `227ed2b77b4`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:iam`, `release:identity-own`. В `main` работа **не** доехала: посадка эпика #26 в ствол — предмет эпика, а не задачи; закрытая каскадом задача — `done` (`git-issues.md#gi-close-cascade`, решение владельца 2026-09-26).

**Состояние на 2026-10-03**: `done`, работа в `main`. Задача закрыта на трекере 2026-09-26 (`completed`); эпик corelib#26 влит в `main` запросом corelib#28 2026-10-02 коммитом слияния `2a8f797aa8c` — предок `origin/main` (`git merge-base --is-ancestor`, 2026-10-03); зонтичный эпик kacho#2564 закрыт 2026-10-03 — [[KAC/issue-2564|#2564]].

## Что и зачем

ID гранта чеканил uuid движка. Теперь его чеканит крючок службы `Config.NewGrantID`, а `New` без крючка отказывает.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `e90d570cd41` → слияние в ветку волны `32` `d5342ca501f` — «#32 merge #35: ID гранта чеканит крючок службы Config.NewGrantID» |
| запрос волны | PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`; прогоны головы — 2 прогона, оба `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- падающая проба ДО кода; у каждого отказа — положительный близнец;
- `go test ./oauthceremony/... -count=1` на ветке задачи — код 0, исполненных проб больше нуля;
- предикат снятия выполнен командами из этого тела, вывод — комментарием при сдаче.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `227ed2b77b4` в ветку эпика `26`;
- посадка в `main` — DoD эпика #26, а не задачи (`git-issues.md#gi-close-cascade`).

## History

- 2026-09-27 (#846) — состояние приведено к каскаду закрытия: задача закрыта вместе с волной, `test` → `done`; посадка в `main` — DoD эпика, а не задачи.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: пакеты oauthceremony (Config.NewGrantID, GrantRecord.GrantID), ids (PrefixTokenFamilyHyphen).

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]
- [[packages/corelib-ids]]

#kac #refactor #kacho-corelib
