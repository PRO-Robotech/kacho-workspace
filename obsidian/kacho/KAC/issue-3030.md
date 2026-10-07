---
title: "kacho#3030: консоль: служебная точка живости фронта не отдаётся на внешнем входе"
aliases:
  - issue-3030
  - kacho#3030
ticket_id: 3030
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - ui-future/deploy
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3055
issue_url: https://github.com/PRO-Robotech/kacho/issues/3030
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
  - kacho-ui
verified_against: "kacho 1266@0ae22f8f8c67 (коммит слияния PR #3055, родители 680d1794b6b8 + 926f8d323162; голова origin/1266 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #3055 и git merge-base --is-ancestor; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3030: консоль: служебная точка живости фронта не отдаётся на внешнем входе

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2968]] влита в `1266` коммитом слияния `0ae22f8f8c67` ([kacho#3055](https://github.com/PRO-Robotech/kacho/pull/3055)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Класс «служебная поверхность на внешнем входе»: точка живости фронта консоли и точки модулей отвечали снаружи. После правки внешний вход их не отдаёт, внутренняя проба живости работает. Разбор — в диффе фикса (`fa44ad9d`), здесь не пересказывается.

## Затронутые каталоги

чарт фронта консоли (`ui-future/deploy`), пробы рендера в `deploy/` (PRO-Robotech/kacho). Полоса K-CHART волны-5.

Коммит в составе волны: `fa44ad9d5c8`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — `git merge-base --is-ancestor fa44ad9d5c84 0ae22f8f8c67` → 0;
- [x] DoD-proof @`fa44ad9d5c84` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3030#issuecomment-6022460054): проба по объявлению шаблона — красная до кода, зелёная на голове с инъекциями на настоящем шаблоне; поднятая раздача из рендера: на прежнем шаблоне FAIL, на голове исполнено 2, отказов 0; `go test ./deploy/ ./ui-future/deploy/` — 903 / 0.
- [ ] проба на стенде — отдельной подзадачей в kacho#2969 (волна-6), этот DoD-proof её не обещает.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — правило рендера фронта консоли (History 2026-10-07)

## Связанные задачи

- [[KAC/issue-2968]] — волна-5
- [[KAC/issue-1266]] — эпик

#kac #kacho-deploy #kacho-ui
