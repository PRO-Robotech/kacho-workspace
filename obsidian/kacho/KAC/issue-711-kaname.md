---
title: "kaname#711: edgecredential: номер записи сессии читается через фундамент (corelib v1.14.0)"
aliases:
  - issue-711-kaname
  - kaname#711
ticket_id: 711
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - internal/edgecredential
  - go.mod
prs:
  - https://github.com/PRO-Robotech/kaname/pull/712
issue_url: https://github.com/PRO-Robotech/kaname/issues/711
opened: 2026-10-11
closed: 2026-10-12
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-corelib
verified_against: "`gh` 2026-10-12: kaname PR #712 MERGED в `296` 2026-10-12T01:58Z коммитом слияния 2952ea7f3874; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kaname#711: edgecredential: номер записи сессии читается через фундамент (corelib v1.14.0)

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `296`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Служба доступа читала номер записи сессии из метаданных запроса сама, мимо фундамента. С corelib v1.14.0 ([[KAC/issue-110-corelib]]) номер берётся из решения фундамента о доверии; пин corelib поднят с v1.13.0. Приёмка Ф11 §9 п.7.

## Затронутые каталоги

`internal/edgecredential`, `go.mod` (PRO-Robotech/kaname). Ветка задачи — `711` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kaname#712](https://github.com/PRO-Robotech/kaname/pull/712) | `296` | `2952ea7f3874` | 2026-10-12T01:58Z | запрос задачи |

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `296` — коммит слияния `2952ea7f3874` (kaname#712);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/711#issuecomment-6114686838): @57d31a2b8fc7: красный до кода (два кейса FAIL, близнец PASS), зелёный после правки;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик службы доступа
- [[KAC/issue-110-corelib]] — сторона фундамента
- kacho#1280 — подъём пинов corelib и kaname в `1266` (PR kacho#3157)

## History

- 2026-10-12 — trail заведён после вливания (kaname#712); статус `test` (ws#1035).

#kac #feature #kacho-iam #kacho-corelib
