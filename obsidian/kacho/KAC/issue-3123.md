---
title: "kacho#3123: CI — сводный вердикт читает все страницы проверок"
aliases:
  - issue-3123
  - kacho#3123
ticket_id: 3123
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - .github/scripts
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3124
  - https://github.com/PRO-Robotech/kacho/pull/3122
issue_url: https://github.com/PRO-Robotech/kacho/issues/3123
opened: 2026-10-10
closed: 2026-10-10
tags:
  - kac
  - fix
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10); PR #3122 влит коммитом aba639bcea21, PR #3124 помечен влитым в 1266 — его голова e2ed8512a60f вошла через #3122 (gh pr view 2026-10-10); состояние задачи и DoD — gh api …/issues/3123/comments 2026-10-10; конвейер этой записью не перезапускался"
---

# kacho#3123: CI — сводный вердикт читает все страницы проверок

> [!note] Состояние — `test`: задача закрыта 2026-10-10, работа в ветке эпика `1266`, в `main` не влита
> Ветка задачи слита в ветку [[KAC/issue-3118]] и вошла в `1266` запросом
> [kacho#3122](https://github.com/PRO-Robotech/kacho/pull/3122), коммит слияния `aba639bcea21`.

## Что и зачем

Сводный вердикт запроса читал проверки головы одной страницей в 100. Когда набор вырос за этот порог,
страж «прочитано не целиком» честно останавливал вердикт на каждом запросе — недочитывал чтец, а не набор.
Теперь читаются все страницы; набор, сменившийся между страницами, опрашивается заново; страж для
оборванной страницы сохранён.

## Затронутые каталоги

`.github/scripts` (ожидание сводного вердикта), `internal/repohygiene` (проба на настоящем скрипте с
подставным клиентом) — PRO-Robotech/kacho.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] вердикт выносится на наборе в две страницы — [замер на голове #3122](https://github.com/PRO-Robotech/kacho/issues/3123#issuecomment-6092052708) (со слов комментария);
- [x] влито в ветку эпика `1266` — [DoD-proof @`aba639bcea21`](https://github.com/PRO-Robotech/kacho/issues/3123#issuecomment-6092525417);
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

—

## Связанные задачи

- [[KAC/issue-3118]] — запрос, которым влито
- [[KAC/issue-1266]] — эпик

#kac #fix
