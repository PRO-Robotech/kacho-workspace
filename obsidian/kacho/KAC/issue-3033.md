---
title: "kacho#3033: край: аутентификация не читает список публичных методов"
aliases:
  - issue-3033
  - kacho#3033
ticket_id: 3033
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/middleware
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3055
issue_url: https://github.com/PRO-Robotech/kacho/issues/3033
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@0ae22f8f8c67 (коммит слияния PR #3055, родители 680d1794b6b8 + 926f8d323162; голова origin/1266 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #3055 и git merge-base --is-ancestor; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3033: край: аутентификация не читает список публичных методов

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2968]] влита в `1266` коммитом слияния `0ae22f8f8c67` ([kacho#3055](https://github.com/PRO-Robotech/kacho/pull/3055)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Список публичных методов края объявлял, что для проверки здоровья снимаются и аутентификация, и проверка прав, но читала его только проверка прав. Источник был один, а читателя у него — один из двух. После правки аутентификация читает тот же список: метод, добавленный в список, проходит обе ступени.

## Затронутые каталоги

`gateway/internal/middleware` (PRO-Robotech/kacho). Полоса K-PIN волны-5.

Коммит в составе волны: `539c0c765d3`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — `git merge-base --is-ancestor d7dc08983a38 0ae22f8f8c67` → 0;
- [x] DoD-proof @`d7dc08983a38` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3033#issuecomment-6019799958): `go test -count=1 ./gateway/internal/middleware/ ./gateway/internal/allowlist/` (в прогоне пяти пакетов) → код 0, тестов исполнено 6262, отказов 0; коммит задачи — предок доказанной головы.
- [ ] число строк о неготовности домена операций на стенде за час — шаг после выкатки, не измерено.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — один список публичных методов, два читателя (History 2026-10-07)

## Связанные задачи

- [[KAC/issue-2968]] — волна-5
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-3032]]

#kac #kacho-api-gateway
