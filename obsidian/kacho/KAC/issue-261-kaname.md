---
title: "kaname#261: контракт: отказ 405 на двух HTTP-поверхностях службы даёт разный gRPC-код"
aliases:
  - issue-261-kaname
  - kaname#261
ticket_id: 261
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/restfront
  - internal/handler/loginlanehttp
  - docs/content
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/261
opened: 2026-09-17
closed: 2026-10-08
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #668 = 8b0379e2a9c5 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @5d0de82c0d74; пробы и конвейер этой записью не перезапускались"
---

# kaname#261: контракт: отказ 405 на двух HTTP-поверхностях службы даёт разный gRPC-код

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) (сборка 6b волны-6) влит в ветку эпика `296` коммитом слияния `8b0379e2a9c5` 2026-10-08.

## Что и зачем

Отказ 405 на двух HTTP-поверхностях службы давал разный gRPC-код. Одна форма отказа на неверный метод у полосы входа и REST-фронта (код, сообщение, `Allow`). Остаток — kaname#524 (ещё две формы).

## Затронутые каталоги

`internal/restfront`, `internal/handler/loginlanehttp`, `docs/content`, `tests/newman` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `8b0379e2a9c5` (kaname#668);
- [x] DoD-proof @`5d0de82c0d74` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/261#issuecomment-6048893145): go test -race -count=1 ./internal/restfront/... ./internal/handler/loginlanehttp/... -run '_261_' → ok (обе поверхности: 405, {"code":12,"message":"method not allowed","details":[]}, Allow; законный близнец зелёный)
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- [[rpc/iam-login-lane]]

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
