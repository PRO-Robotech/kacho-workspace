---
title: "kaname#678: identity-own · kaname#296 · волна-7 — перенесённые задачи для фиксации состава волны 6"
aliases:
  - issue-678-kaname
  - kaname#678
ticket_id: 678
category: kac
status: done
type: epic
repos:
  - kaname
areas:
  - internal/handler
  - internal/apps
  - internal/check
  - internal/errors
  - tests/newman
  - docs/content
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kaname/pull/702
  - https://github.com/PRO-Robotech/kaname/pull/704
  - https://github.com/PRO-Robotech/kaname/pull/714
issue_url: https://github.com/PRO-Robotech/kaname/issues/678
opened: 2026-10-08
closed: 2026-10-14
tags:
  - kac
  - epic
  - kacho-iam
verified_against: "kaname main@9ccdc8d86275 (коммит слияния PR #714, ветка эпика 296 → main, gh pr view 714 → MERGED 2026-10-14); запросы волны — gh pr view 702 / 704 → MERGED в 296, коммиты слияния 8a13a6a4b7bb и d33a3b866abc; состояние задачи и sub-issue — gh issue view 678 (CLOSED COMPLETED) и gh api …/issues/678/sub_issues (19 из 19 closed) 2026-10-14; DoD — комментарий DoD-proof @278ac4c0 и комментарий закрытия; пробы и конвейер этой записью не перезапускались"
---

# kaname#678: identity-own · kaname#296 · волна-7 — перенесённые задачи для фиксации состава волны 6

> [!note] Состояние — `done`: волна ЗАКРЫТА каскадом 2026-10-14
> Оба запроса волны влиты в ветку эпика `296`, ветка эпика посажена в `main` службы
> (PR [kaname#714](https://github.com/PRO-Robotech/kaname/pull/714), коммит слияния `9ccdc8d86275`).
> Комментарий закрытия — [kaname#678](https://github.com/PRO-Robotech/kaname/issues/678#issuecomment-6164796066).

## Что и зачем

Волна-7 эпика [[KAC/issue-296-kaname]]: задачи, перенесённые из волны-6 ([[KAC/issue-540-kaname]]),
чтобы состав волны-6 был зафиксирован, и задачи, добавленные по ходу работ. Прежняя волна-7
kaname#541 снята 2026-10-06 (NOT_PLANNED) — номер волны унаследован этой задачей.

| запрос | коммит слияния в `296` | что |
|---|---|---|
| [kaname#702](https://github.com/PRO-Robotech/kaname/pull/702) | `8a13a6a4b7bb` 2026-10-11 | партия 1 |
| [kaname#704](https://github.com/PRO-Robotech/kaname/pull/704) | `d33a3b866abc` 2026-10-11 | партия 2 |

Вне запросов волны в `296` влиты запросы по одной задаче: kaname#706 и #713 ([[KAC/issue-458-kaname]]),
#709 ([[KAC/issue-664-kaname]]), #712 ([[KAC/issue-711-kaname]]), #715 ([[KAC/issue-710-kaname]]).
Имена веток — координаты на момент вливания, не живые ссылки.

## Задачи волны (по трекеру, 19 sub-issue, все закрыты)

- перенесённые из волны-6: kaname#133, #213, #387, [[KAC/issue-458-kaname]], #608, #614, #635, [[KAC/issue-664-kaname]];
- находки ревью о наблюдаемости полосы входа: kaname#691, #692, #693;
- добавленные по ходу работ: kaname#677, #680, #681, #685, #699, #700, [[KAC/issue-710-kaname]], [[KAC/issue-711-kaname]].

Остаток: kaname#468 не выполнила предикат и **переведена** в эпик продолжения kaname#746 —
[комментарий перевода](https://github.com/PRO-Robotech/kaname/issues/468#issuecomment-6162258440); задача открыта.

## Затронутые каталоги

`internal/{handler,apps,check,errors}`, `tests/newman`, `docs/content`, `.github/scripts`, `INSTALL.md` —
по полю «Затронуто» тела задачи.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`.

- [x] запросы волны влиты в `296` коммитами слияния — `8a13a6a4b7bb`, `d33a3b866abc`;
- [x] задачи волны закрыты либо переведены: 19 из 19 sub-issue закрыты, kaname#468 переведена в kaname#746;
- [x] DoD-proof волны — [@278ac4c0](https://github.com/PRO-Robotech/kaname/issues/678#issuecomment-6162263805);
- [x] волна закрыта каскадом вместе с посадкой эпика в `main` — PR kaname#714, `9ccdc8d86275`.

## Затронутые сущности vault

Перечня узких записок вход этой записи не нёс; trail задач — по ссылкам выше.

## History

- 2026-10-14 — записка заведена при закрытии волны каскадом посадки эпика в `main` (ws#1077).

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-540-kaname]] — волна-6

#kac #epic #kacho-iam
