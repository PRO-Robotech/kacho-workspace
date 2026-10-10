---
title: "kaname#139: гейт материала: результат объявленного потребителя считается не несущим предмет"
aliases:
  - issue-139-kaname
  - kaname#139
ticket_id: 139
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/check
prs:
  - https://github.com/PRO-Robotech/kaname/pull/658
issue_url: https://github.com/PRO-Robotech/kaname/issues/139
opened: 2026-09-16
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #658 = b729affb6a80 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @933406a898b7; пробы и конвейер этой записью не перезапускались"
---

# kaname#139: гейт материала: результат объявленного потребителя считается не несущим предмет

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kaname#658](https://github.com/PRO-Robotech/kaname/pull/658) (вторая сборка волны-6) влит в ветку эпика `296` коммитом слияния `b729affb6a80` 2026-10-07.

## Что и зачем

Гейт материала считал результат объявленного потребителя не несущим предмет. Результат преобразующего потребителя ведётся дальше; многозначный вызов и замыкание аргументом судятся по позициям.

## Затронутые каталоги

`internal/check` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `b729affb6a80` (kaname#658);
- [x] DoD-proof @`933406a898b7` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/139#issuecomment-6042848318): go test ./internal/check/ -count=1 -v → ok, PASS 2067 · FAIL 0 (TMPDIR вне репозиториев, слот MemoryMax=10G)
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
