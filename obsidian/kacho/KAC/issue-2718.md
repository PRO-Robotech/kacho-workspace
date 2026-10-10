---
title: "kacho#2718: край несёт ключи доступа Ф7; пин службы поднят"
aliases:
  - issue-2718
  - kacho#2718
ticket_id: 2718
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - gateway
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3055
issue_url: https://github.com/PRO-Robotech/kacho/issues/2718
opened: 2026-09-18
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
  - kacho-iam
verified_against: "kacho 1266@0ae22f8f8c67 (коммит слияния PR #3055, родители 680d1794b6b8 + 926f8d323162; голова origin/1266 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #3055 и git merge-base --is-ancestor; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2718: край несёт ключи доступа Ф7; пин службы поднят

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2968]] влита в `1266` коммитом слияния `0ae22f8f8c67` ([kacho#3055](https://github.com/PRO-Robotech/kacho/pull/3055)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Подъём пина службы доступа приносил на сервер службу ключей доступа (Ф7), которую край не маршрутизировал: гейты каталога прав и маршрутизируемости публичных методов краснели. Край регистрирует уже одобренный контракт (новая приёмка не нужна); пин заведения назван запросом, а не ревизией. Сторона службы не заводилась — ведомость ожидающих записей каталога у пина пуста.

## Затронутые каталоги

`gateway/`, `deploy/` (PRO-Robotech/kacho). Ветка полосы KA4b `2718` @`fb56a8635b91` влита в полосу K-PIN коммитом слияния `da5c4e221` (координаты, не живые ссылки).

Коммит в составе волны: `fb56a8635b9`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — `git merge-base --is-ancestor d7dc08983a38 0ae22f8f8c67` → 0;
- [x] DoD-proof @`d7dc08983a38` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2718#issuecomment-6019800898): при поднятом пине `go test -count=1 ./gateway/internal/middleware/ ./gateway/internal/allowlist/ ./internal/repohygiene/ ./deploy/` → код 0, исполнено 6262, отказов 0; старый пин в `go.mod` и `deploy/` не встречается.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[rpc/iam-access-key-service]] — край маршрутизирует службу ключей доступа (не правилась этой записью: предмет — регистрация на крае)

## Связанные задачи

- [[KAC/issue-2968]] — волна-5
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-1273]] — Ф7, дом предмета
- [[KAC/issue-3037]]

#kac #kacho-api-gateway #kacho-iam
