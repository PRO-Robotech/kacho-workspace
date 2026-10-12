---
title: "corelib#110: principalwire: номер записи сессии читает фундамент (Ф11 §9 п.7)"
aliases:
  - issue-110-corelib
  - corelib#110
ticket_id: 110
category: kac
status: done
type: feature
repos:
  - corelib
areas:
  - principalwire
  - grpcsrv
prs:
  - https://github.com/PRO-Robotech/corelib/pull/111
issue_url: https://github.com/PRO-Robotech/corelib/issues/110
opened: 2026-10-11
closed: 2026-10-11
tags:
  - kac
  - feature
  - kacho-corelib
verified_against: "`gh` 2026-10-12: corelib PR #111 MERGED в `main` 2026-10-11T22:12Z коммитом слияния c64abe6857df; состояние задачи — `gh issue view` (CLOSED 2026-10-11); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# corelib#110: principalwire: номер записи сессии читает фундамент (Ф11 §9 п.7)

> [!note] Состояние — `done`: задача закрыта 2026-10-11, работа влита в `main` corelib

## Что и зачем

Одобренная приёмка Ф11 службы доступа (§9 п.7) требует, чтобы ключ номера записи сессии читался через фундамент. Ключ помечен фундаментным в каталоге `principalwire`, `grpcsrv` даёт чтение доверенного номера из контекста. Выпущено тегом v1.14.0.

## Затронутые каталоги

`principalwire`, `grpcsrv` (PRO-Robotech/corelib). Ветка задачи — `110-session-record-fundament` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [corelib#111](https://github.com/PRO-Robotech/corelib/pull/111) | `main` | `c64abe6857df` | 2026-10-11T22:12Z | запрос задачи; тег v1.14.0 на этом коммите |

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `main` — коммит слияния `c64abe6857df` (corelib#111);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/corelib/issues/110#issuecomment-6114332786): @9ad2added37d: каталог фундаментных ключей 5 → 6, пробы каталога и чтения;

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-711-kaname]] — потребитель в службе доступа

## History

- 2026-10-12 — trail заведён после вливания (corelib#111); статус `done` (ws#1035).

#kac #feature #kacho-corelib
