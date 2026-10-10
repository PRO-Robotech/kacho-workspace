---
title: "kacho#3118: зависимости — toolchain go1.26.9 и x/net v0.60.0, govulncheck на линии 1266"
aliases:
  - issue-3118
  - kacho#3118
ticket_id: 3118
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - go.mod
  - gateway/cmd/api-gateway
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3122
issue_url: https://github.com/PRO-Robotech/kacho/issues/3118
opened: 2026-10-09
closed: 2026-10-10
tags:
  - kac
  - fix
  - kacho-api-gateway
  - dependencies
  - go
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10): go.mod — toolchain go1.26.9, golang.org/x/net v0.60.0 (git show …:go.mod); коммит слияния PR #3122 = aba639bcea21 (gh pr view → MERGED 2026-10-10T02:06Z); состояние задачи и DoD — gh issue view / gh api …/issues/3118/comments 2026-10-10; govulncheck этой записью не перезапускался"
---

# kacho#3118: зависимости — toolchain go1.26.9 и x/net v0.60.0, govulncheck на линии 1266

> [!note] Состояние — `test`: задача закрыта 2026-10-10, работа в ветке эпика `1266`, в `main` не влита
> Запрос [kacho#3122](https://github.com/PRO-Robotech/kacho/pull/3122) влит в ветку эпика `1266`
> коммитом слияния `aba639bcea21` 2026-10-10. Первый запрос этой задачи (kacho#3120) закрыт без
> вливания, работа перенесена в #3122.

## Что и зачем

`govulncheck` на голове `1266` стал красным без правки дерева: бюллетени вышли позже. Исправления — в
toolchain go1.26.9 и в `golang.org/x/net` v0.60.0; сопутствующие модули `golang.org/x/*` подняты по
требованию x/net. Вызов настройки HTTP/2 края, объявленный в v0.60 устаревшим, снят: TLS-слушатель края
отдаёт соединения через мультиплексор, и вызов был инертен. Разбор находок — в бюллетенях, адрес фикса —
дифф #3122.

В тот же запрос влита ветка [[KAC/issue-3123]] (сводный вердикт читает все страницы проверок): без неё
вердикт запроса был красным при зелёных проверках.

## Затронутые каталоги

`go.mod`, `go.sum`, `gateway/cmd/api-gateway` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] `govulncheck` — 0 находок: [DoD-proof @`0e1e6a1c0e2d`](https://github.com/PRO-Robotech/kacho/issues/3118#issuecomment-6090209550) и [после вливания @`aba639bcea21`](https://github.com/PRO-Robotech/kacho/issues/3118#issuecomment-6092524874) (со слов комментариев);
- [x] влито в ветку эпика `1266` — `aba639bcea21` (kacho#3122);
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

— (записки края о слушателе HTTP/2 нет; см. [[KAC/issue-3125]])

## Связанные задачи

- [[KAC/issue-3123]] — влита тем же запросом
- [[KAC/issue-1266]] — эпик

#kac #fix #kacho-api-gateway #dependencies #go
