---
title: "kaname#467: newman: Ф3 и ID-PW-1 — 30 позиций уровня E без кейса набора"
aliases:
  - issue-467-kaname
  - kaname#467
ticket_id: 467
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - tests/newman
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/467
opened: 2026-09-28
closed: 2026-10-08
tags:
  - kac
  - fix
  - kacho-iam
  - kacho-test
verified_against: "kaname 296: коммит слияния PR #668 = 8b0379e2a9c5 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#467: newman: Ф3 и ID-PW-1 — 30 позиций уровня E без кейса набора

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) (сборка 6b волны-6) влит в ветку эпика `296` коммитом слияния `8b0379e2a9c5` 2026-10-08.

## Что и зачем

30 позиций уровня E приёмок Ф3 и ID-PW-1 без кейса набора. Задача закрыта **передачей**, а не доказательством: позиции переданы держателю kacho#1269 полосой LEDGER; остаток работы ведёт [[KAC/issue-1269]].

## Затронутые каталоги

`tests/newman`, `.github/scripts` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `8b0379e2a9c5` (kaname#668);
- [ ] DoD-proof — нет: задача закрыта передачей держателю (комментарий закрытия), доказательства предиката у неё нет;
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam #kacho-test
