---
title: "kacho#3037: край: ретрансляция двух глаголов входа ключом доступа (Ф13)"
aliases:
  - issue-3037
  - kacho#3037
ticket_id: 3037
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - gateway/internal/middleware
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3055
issue_url: https://github.com/PRO-Robotech/kacho/issues/3037
opened: 2026-10-05
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
  - kacho-iam
verified_against: "kacho 1266@0ae22f8f8c67 (коммит слияния PR #3055, родители 680d1794b6b8 + 926f8d323162; голова origin/1266 = этот коммит, git ls-remote 2026-10-07): состав — тело PR #3055 и git merge-base --is-ancestor; состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3037: край: ретрансляция двух глаголов входа ключом доступа (Ф13)

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2968]] влита в `1266` коммитом слияния `0ae22f8f8c67` ([kacho#3055](https://github.com/PRO-Robotech/kacho/pull/3055)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Половина Ф13 в доме платформы: служба несёт два глагола полосы формы для входа ключом доступа (запрос и подтверждение), а перечень путей полосы входа на крае их не знал — оба отвечали краем «не найдено». Две записи в перечне края тем же объявлением, что глаголы Ф3/Ф4/Ф5/Ф12; ветка полосы сессии — как у входа паролем.

## Затронутые каталоги

`gateway/internal/middleware` (PRO-Robotech/kacho). Полоса K-PIN волны-5.

Коммит в составе волны: `18180823b5e`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — `git merge-base --is-ancestor d7dc08983a38 0ae22f8f8c67` → 0;
- [x] DoD-proof @`d7dc08983a38` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3037#issuecomment-6019801496): в перечне полосы входа путей ключа доступа 2 (`git grep -c`); `go test -count=1 ./gateway/internal/middleware/` → код 0, исполнено 6262, отказов 0; пин службы на голове несёт оба глагола.
- [ ] сквозная проба Ф13-28 через край на стенде — в волне-6 (#1282), не предъявлена.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[edges/api-gateway-to-kaname-login-lane]] — два глагола входа ключом в перечне ретрансляции (History 2026-10-07)
- [[packages/apigw-middleware]] (History 2026-10-07)

## Связанные задачи

- [[KAC/issue-2968]] — волна-5
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-613-kaname]] — Ф13 в службе
- [[KAC/issue-2718]]

#kac #kacho-api-gateway #kacho-iam
