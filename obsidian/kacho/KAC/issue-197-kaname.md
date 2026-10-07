---
title: "kaname#197: окно темпа заведения не сбрасывается сменой адреса"
aliases:
  - issue-197-kaname
  - kaname#197
ticket_id: 197
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/migrations
  - internal/repo/kaname/pg
prs:
  - https://github.com/PRO-Robotech/kaname/pull/629
issue_url: https://github.com/PRO-Robotech/kaname/issues/197
opened: 2026-09-16
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - migrations
verified_against: "kaname 296@d9e233f42051 (коммит слияния PR #629, родители 2cf9c8528b1f + 88c4e475f579; голова origin/296 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #629; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#197: окно темпа заведения не сбрасывается сменой адреса

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` службы не влито
> Волна [[KAC/issue-539-kaname]] влита в `296` коммитом слияния `d9e233f42051` ([kaname#629](https://github.com/PRO-Robotech/kaname/pull/629)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main` службы.

## Что и зачем

Ключ окна темпа заведения у людей нашей полосы был изменяемым атрибутом человека. Теперь носитель ключа закрепляется при чеканке личности и сменой адреса не меняется (приёмка A197, APPROVED). Разбор — в диффе фикса (`855b5dc5e`), здесь не пересказывается.

## Затронутые каталоги

`internal/migrations/` (миграция `20261006152443`), `internal/repo/kaname/pg/` (PRO-Robotech/kaname). Полоса N-ADDR волны-5, ветка `526` (координата, не живая ссылка).

Коммиты: `855b5dc5e`, `27af79a8e` (пересъёмка отчётов вердикта).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — `git merge-base --is-ancestor 27af79a8e d9e233f42` → 0;
- [x] DoD-proof @`27af79a8e` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/197#issuecomment-6021452624): пробы A197 написаны до миграции и красные, после — 0 отказов; миграция старше последней применённой; `go test ./... -count=1 -p 2` — 136 пакетов, исполнено 12210; `make lint` — 0;
- [ ] детектор гонок локально не гонялся (со слов закрывающего комментария) — вердикт за конвейером запроса;
- [ ] эпик влит в `main` службы — нет.

## Затронутые сущности vault

- [[packages/kaname-migrations]] — миграция `20261006152443` (History 2026-10-07)

## Связанные задачи

- [[KAC/issue-539-kaname]] — волна-5
- [[KAC/issue-296-kaname]] — эпик
- kaname#526 — полоса-носитель

#kac #kacho-iam #migrations
