---
title: "corelib#47: выданная область — scope-token по RFC 6749 §3.3"
aliases:
  - issue-47-corelib
ticket_id: 47
category: kac
status: test
type: fix
repos:
  - corelib
areas:
  - oauthceremony
prs:
  - https://github.com/PRO-Robotech/corelib/pull/66
  - https://github.com/PRO-Robotech/corelib/pull/69
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/47
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - fix
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи 70f6144d7e1 — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:39:03Z, меток status:* нет (`gh issue view`); коммит слияния волны 227ed2b77b4 — в origin/26, не в origin/main (`gh api compare`)"
---

# corelib#47: выданная область — scope-token по RFC 6749 §3.3

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:39:03Z вместе с волной [[KAC/issue-32-corelib|#32]]: запрос волны PR #62 влит в ветку эпика `26` (координата, не живая ссылка), коммит закрытия — слияние волны `227ed2b77b4`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:iam`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #26 в ствол.

## Что и зачем

Область с пробелом или табуляцией внутри выдавалась как есть. Теперь такая область отвергается без записи гранта. Приехала веткой `42`.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `70f6144d7e1` → слияние в ветку сборки `68` `6db323bb139` — «#68 merge #42: способ интроспекции, scope-token, снят id_token» |
| запрос задачи | PR #66 — отмечен влитым вместе со сборкой |
| запрос сборки | PR #69 `68` → `32`, голова `c6d8b1b37b5`, коммит слияния `372daa9094a`; прогоны головы — 2 прогона, оба `success` |
| запрос волны | PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`; прогоны головы — 2 прогона, оба `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- падающая проба ДО кода; у каждого отказа — положительный близнец;
- `go test ./oauthceremony/... -count=1` на ветке задачи — код 0, исполненных проб больше нуля;
- предикат снятия выполнен командами из этого тела, вывод — комментарием при сдаче.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `227ed2b77b4` в ветку эпика `26`;
- [ ] предмет в стволе: `main` — посадкой эпика #26.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: пакет oauthceremony.

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]
- [[KAC/issue-42-corelib]]

#kac #fix #kacho-corelib
