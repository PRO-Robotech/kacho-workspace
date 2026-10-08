---
title: "ws#897: identity-own · ws#896 · волна-1 — приёмка экранов консоли S3 и S4"
aliases:
  - issue-897-ws
  - ws#897
ticket_id: 897
category: kac
status: in-progress
type: docs
repos:
  - kacho-workspace
areas:
  - docs/specs
  - docs/specs/reviews
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/980
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/897
opened: 2026-10-01
tags:
  - kac
  - docs
  - kacho-ui
verified_against: "kacho-workspace main@ce873ef3691a (коммит слияния PR #980, gh pr view → MERGED 2026-10-08T04:23Z; git log origin/main); файлы — gh pr view --json files; состояние задачи — gh issue view 2026-10-08 (OPEN); запись ревью — по телу PR #980, файл записи этой записью не перечитывался"
---

# ws#897: identity-own · ws#896 · волна-1 — приёмка экранов консоли S3 и S4

> [!note] Состояние — `in-progress`: задача открыта
> Редакция 4 приёмки F8-S4 влита в `main` воркспейса запросом [ws#980](https://github.com/PRO-Robotech/kacho-workspace/pull/980)
> (`ce873ef3691a`, 2026-10-08, `Refs`).

## Что и зачем

Приёмка экранов консоли S3 (восстановление доступа) и S4 (вход ключом) — сценарии Given-When-Then до кода.
Записка заведена при вливании редакции 4 F8-S4; прежние редакции здесь не пересказываются.

**Редакция 4 F8-S4** (`docs/specs/sub-phase-F8-S4-console-access-key-login-screen-acceptance.md`): сценарий
F8S4-03 переутверждён наблюдаемым исходом браузера — отказ и следующий шаг; уровень «2» ключа без проверки
пользователя остаётся за пробой службы (Ф13-10). Прочие сценарии не тронуты. Запись ревью — APPROVED на
отпечаток `624996ea…`, событие — комментарий в kacho#2969 (со слов тела PR). Проба на платформе —
[[KAC/issue-3059]].

## Затронутые каталоги

`docs/specs`, `docs/specs/reviews` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] редакция 4 F8-S4 одобрена и влита в `main` — `ce873ef3691a` (ws#980);
- [ ] задача закрыта — нет, открыта.

## Затронутые сущности vault

- [[resources/kaname-access-key]] — ключ доступа, вход которым описывает F8-S4 (History 2026-10-08)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6 платформы, где экраны S3 и S4 сделаны
- [[KAC/issue-1266]] — эпик платформы

#kac #docs #kacho-ui
