---
title: "kacho#2713: у вызовов края к службе доступа о сессии свой предел"
aliases:
  - issue-2713
ticket_id: 2713
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/clients
  - gateway/internal/restmux
  - gateway/internal/config
  - gateway/deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3009
issue_url: https://github.com/PRO-Robotech/kacho/issues/2713
opened: 2026-09-18
closed: "2026-10-03"
tags:
  - kac
  - kacho-api-gateway
  - config
verified_against: "kacho 1266@656955b66b7 (коммит слияния PR #3009, родители 108e7c32b90 + 25ba0c48664; голова origin/1266 = этот коммит, 2026-10-03): состав коммитов — git log по 108e7c32b90..25ba0c48664, предикаты DoD, названные в строках, — git grep -c на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kacho#2713: у вызовов края к службе доступа о сессии свой предел

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-10-03 каскадом волны-1 [[KAC/issue-2964]]: волна влита в ветку эпика `1266`
> запросом [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009), коммит слияния `656955b66b759d6c3c39ad0d94b383a5c89ae8af`.
> В `main` продукта код не влит — открытого запроса эпика `1266` → `main` нет
> (`gh pr list --base main --head 1266` → пусто, 2026-10-03), поэтому состояние записки `test`.
> Комментарий закрытия: local на голове `25ba0c48664` — 7 из 7 групп, код 0; сквозные прогоны на
> стенде и конвейер не проверялись.

## Что и зачем

Вызовы края к внутреннему слушателю службы доступа на пути запроса (вопрос о сессии, об отсечке) и
унарные вызовы REST-моста к бэкендам шли без собственного предела: контекст вызывающего пределом
не является, а сервер края ограничивает только чтение запроса.

Исход — приёмка KA1 ред. 7, Р4: два бюджета объявлены ручками без умолчания
(`KACHO_API_GATEWAY_IDENTITY_CALL_BUDGET`, `KACHO_API_GATEWAY_BACKEND_CALL_BUDGET`), судятся
стражем старта и стоят на **каждом** глаголе переходника и на каждом унарном вызове моста; чарт
края объявляет обе ручки. Подробности — в [[packages/apigw-config]] и [[packages/apigw-clients]].

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса KA1 → волна | ветка `2728-ka1` (координата, не живая ссылка) → ветка `2964` | — | bb8d2aa4e36 · догон d4645fee458 · харнесс 85da1906c85 | [kacho#3004](https://github.com/PRO-Robotech/kacho/pull/3004) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |

## Затронутые каталоги

Коммиты задачи: `7f3fccc50d6` (общий с [[KAC/issue-2738]]: ручки, страж, перепись
`TestEveryIdentityAdapterVerbIsBounded`), `bf39c0376ef` (харнесс KA1 для сборки П10). Пути:
`gateway/internal/config/callbudget.go` (новый), `gateway/internal/clients/`,
`gateway/internal/restmux/`, `gateway/deploy/`, `internal/repohygiene/identityadapterbudget.go`.

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] у каждого вызова переходника к службе — предел: перепись `TestEveryIdentityAdapterVerbIsBounded` в дереве (`git grep -c` по `internal` → база 0, слияние 2); исполнение пробы — со слов коммита.
- [x] у REST-моста — предел: `BackendCallBudget` в `gateway/internal/restmux` и `gateway/cmd` → база 0, слияние 3.
- [ ] проба с медленным сервером и законным близнецом — названа в коммите (KA1-22…26, пакет `gateway/internal/e2e/ka1budget`), этой записью не исполнялась.

## Затронутые сущности vault

- [[packages/apigw-clients]] — переходник края к службе доступа: бюджет и диагнозы (History #2713)
- [[packages/apigw-config]] — ручки бюджетов и запись приёма издателя (History #2713)
- [[packages/apigw-restmux]] — бюджет унарного вызова REST-моста (History #2713)

## Связанные задачи

- [[KAC/issue-2964]] — волна-1, родитель
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-2738]] — тот же бюджет со стороны источника отзыва
- [[KAC/issue-1269]] — Ф3

#kac #kacho-api-gateway #config
