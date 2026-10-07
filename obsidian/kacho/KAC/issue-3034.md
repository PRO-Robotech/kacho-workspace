---
title: "kacho#3034: край: готовность пишет в журнал смену состояния, а не каждую пробу"
aliases:
  - issue-3034
  - kacho#3034
ticket_id: 3034
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/health
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3055
issue_url: https://github.com/PRO-Robotech/kacho/issues/3034
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@0ae22f8f8c67 (коммит слияния PR #3055, родители 680d1794b6b8 + 926f8d323162; голова origin/1266 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #3055 и git merge-base --is-ancestor; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3034: край: готовность пишет в журнал смену состояния, а не каждую пробу

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2968]] влита в `1266` коммитом слияния `0ae22f8f8c67` ([kacho#3055](https://github.com/PRO-Robotech/kacho/pull/3055)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Готовность края писала предупреждение о неготовом бэкенде на каждую пробу, и смена состояния терялась в одинаковых строках. Теперь строка пишется при переходе состояния домена; пока состояние держится — раз в окно напоминание со счётчиком.

## Затронутые каталоги

`gateway/internal/health` (PRO-Robotech/kacho). Полоса K-PIN волны-5.

Коммит в составе волны: `06656b91aa2`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — `git merge-base --is-ancestor d7dc08983a38 0ae22f8f8c67` → 0;
- [x] DoD-proof @`d7dc08983a38` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3034#issuecomment-6019800413): `go test -count=1 ./gateway/internal/health/` (в прогоне пяти пакетов) → код 0; всего исполнено 6262, отказов 0.
- [ ] число строк на домен за час в устойчивом состоянии на стенде — шаг после выкатки, не измерено.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/apigw-health]] — журнал готовности по смене состояния (History 2026-10-07)

## Связанные задачи

- [[KAC/issue-2968]] — волна-5
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-3032]]

#kac #kacho-api-gateway
