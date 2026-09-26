---
title: "kaname#334: своя причина снятия сессии при административном выходе"
aliases:
  - issue-334-kaname
ticket_id: 334
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - internal/apps
  - docs/specs
  - internal/migrations
  - internal/passwordverify
  - cmd/kaname
  - internal/check
prs:
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/334
opened: 2026-09-21
closed: 2026-09-26
tags:
  - kac
  - refactor
  - kacho-iam
verified_against: "PRO-Robotech/kaname: голова задачи 92b9b1b97eb — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:38:27Z, меток status:* нет (`gh issue view`); коммит слияния волны fc9f5aff19c — в origin/357, не в origin/main (`gh api compare`)"
---

# kaname#334: своя причина снятия сессии при административном выходе

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:38:27Z вместе с волной [[KAC/issue-358-kaname|#358]]: запрос волны PR #422 влит в ветку эпика `357` (координата, не живая ссылка), коммит закрытия — слияние волны `fc9f5aff19c`; метка `status:test` снята, метки сейчас: `P2`, `size:L`, `area:iam`, `tech-debt`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #357 в ствол.

## Что и зачем

Словарь причин снятия сессии не отличал административный выход от прочих. Новая миграция добавляет свою причину в ограничение `ended_reason`, а запись события принудительного выхода называет её. Сюда же перенесена калибровка огибающей входа, ушедшая затем в [[KAC/issue-295-kaname|#295]].

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `92b9b1b97eb` → слияние в ветку волны `358` `d6d8170ff57` — «#358 merge #334: своя причина снятия сессии при административном выходе» |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- миграция НОВАЯ, применённая не правится (ban #5);
- падающая проба до миграции (ban #12);
- приёмка Given-When-Then APPROVED до первой строки (ban #1).

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `fc9f5aff19c` в ветку эпика `357`;
- [ ] предмет в стволе: `main` — посадкой эпика #357.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: ресурс human_sessions (ограничение ended_reason); rpc InternalIAMService.ForceLogout; пакеты internal_iam, humansession, domain, migrations, passwordverify.

- [[KAC/issue-358-kaname]] — волна.
- [[resources/iam-human-session]]
- [[rpc/iam-internal-iam-service]]

#kac #refactor #kacho-iam
