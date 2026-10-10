---
title: "kacho#3069: край — текст отказа подтверждения адреса по kaname#526, переутверждение F6b"
aliases:
  - issue-3069
  - kacho#3069
ticket_id: 3069
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/middleware
  - ui-future/e2e/specs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3104
issue_url: https://github.com/PRO-Robotech/kacho/issues/3069
opened: 2026-10-07
tags:
  - kac
  - fix
  - kacho-api-gateway
  - kacho-ui
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10); коммит слияния PR #3104 = ad74c3ea01b5 (gh pr view → MERGED 2026-10-08T17:01Z, тело — состав третьей сборки волны-6); состояние задачи — gh issue view / gh api …/comments 2026-10-10 (OPEN, status:test); текст отказа построчно этой записью не сверялся"
---

# kacho#3069: край — текст отказа подтверждения адреса по kaname#526, переутверждение F6b

> [!note] Состояние — `test`: код влит в ветку эпика, задача открыта и ждёт DoD-proof
> Полоса вошла в третью сборку волны-6 — запрос [kacho#3104](https://github.com/PRO-Robotech/kacho/pull/3104),
> коммит слияния `ad74c3ea01b5` в `1266` 2026-10-08 (через полосы #3093 и #3094; запрос несёт `Refs`, а не `Closes`).
> Блокеры закрыты, метка `blocked` снята 2026-10-10.

## Что и зачем

Служба доступа ([[KAC/issue-526-kaname]]) сменила текст отказа положения подтверждения адреса: он называет
следующий шаг. Край повторяет этот отказ, а сценарии приёмки F6b и проба консоли сверяют его текст — край
приведён к тексту службы дословно, проба консоли сверяет полный текст, а не часть. Пин службы из этой полосы
при сведении перекрыт новым пином [[KAC/issue-3093]].

## Затронутые каталоги

`gateway/internal/middleware` (отказ адреса), `ui-future/e2e/specs` (проба консоли) — PRO-Robotech/kacho;
приёмка F6b — в воркспейсе.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] код влит в ветку эпика `1266` — `ad74c3ea01b5` (kacho#3104);
- [ ] DoD-proof — нет (комментарии задачи на 2026-10-10: перемер DoD ожидается);
- [ ] влито в `main` — нет.

## Затронутые сущности vault

— (записки края об отказе адреса нет)

## Связанные задачи

- [[KAC/issue-526-kaname]] — сторона службы
- [[KAC/issue-3093]] — пин службы, перекрывший пин этой полосы
- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик

#kac #fix #kacho-api-gateway #kacho-ui
