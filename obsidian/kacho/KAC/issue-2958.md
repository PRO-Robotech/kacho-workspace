---
title: "kacho#2958: отказ 401 края одинаков для всех причин"
aliases:
  - issue-2958
ticket_id: 2958
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/authnrefusal
  - gateway/internal/middleware
  - gateway/internal/handler
  - ui-future
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3009
issue_url: https://github.com/PRO-Robotech/kacho/issues/2958
opened: 2026-10-01
closed: "2026-10-03"
tags:
  - kac
  - kacho-api-gateway
  - kacho-ui
verified_against: "kacho 1266@656955b66b7 (коммит слияния PR #3009, родители 108e7c32b90 + 25ba0c48664; голова origin/1266 = этот коммит, 2026-10-03): состав коммитов — git log по 108e7c32b90..25ba0c48664, предикаты DoD, названные в строках, — git grep -c на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kacho#2958: отказ 401 края одинаков для всех причин

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-10-03 каскадом волны-1 [[KAC/issue-2964]]: волна влита в ветку эпика `1266`
> запросом [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009), коммит слияния `656955b66b759d6c3c39ad0d94b383a5c89ae8af`.
> В `main` продукта код не влит — открытого запроса эпика `1266` → `main` нет
> (`gh pr list --base main --head 1266` → пусто, 2026-10-03), поэтому состояние записки `test`.
> Комментарий закрытия: local на голове `25ba0c48664` — 7 из 7 групп, код 0; сквозные прогоны на
> стенде и конвейер не проверялись.

## Что и зачем

Требуемое свойство: тело и детали отказа 401 на крае не зависят от причины отказа — так же, как на
пути отказа 403. Разбор находки не публикуется; адрес — дифф фикса, коммит `e00dfe9b196` в
[kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009).

Исход — приёмка KA1 ред. 7, Р2 и Р3: производитель отказа 401 **один** — пакет
`gateway/internal/authnrefusal`; ответ побайтово один на обеих поверхностях и несёт ровно одну деталь
`google.rpc.ErrorInfo` без `metadata`. Указание повысить уровень остаётся различимым — это не отказ, а
следующий шаг держателю годного удостоверения. Консоль разбирает отказ по канону того же пакета.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса KA1 → волна | ветка `2728-ka1` (координата, не живая ссылка) → ветка `2964` | — | bb8d2aa4e36 · догон d4645fee458 · харнесс 85da1906c85 | [kacho#3004](https://github.com/PRO-Robotech/kacho/pull/3004) |
| полоса KA1-ui → волна | ветка `2958-ka1-ui` (координата) → ветка `2964` | — | 6839b3153cd · 7a47d4b47d6 · 25ba0c48664 | [kacho#3008](https://github.com/PRO-Robotech/kacho/pull/3008) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |

Серверная часть пришла полосой KA1 (`e00dfe9b196` — основная сдача; `3fd5dfb766b`, `139e0521c48` — догон), консольная — полосой KA1-ui.

## Затронутые каталоги

Коммиты задачи: `e00dfe9b196`, `3fd5dfb766b`, `139e0521c48`, `98eaac3a6eb`, `f1d4ebae4e1`,
`588057ca24e`. Пути: `gateway/internal/authnrefusal/` (новый), `gateway/internal/middleware/`,
`gateway/internal/handler/`, `gateway/internal/subscriptionstream/`, `gateway/docs/`,
`gateway/tests/newman/` (`authn_edge`), `internal/repohygiene/edgeunauthproducer.go`,
`ui-future/shared/src/api/`, `ui-future/e2e/specs/`.

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] свойство на HTTP- и gRPC-поверхности держит перепись производителей: `TestEdgeUnauthenticatedHasOneProducer` в `internal` → база 0, слияние 2; вызовов `authnrefusal.` в `gateway` → база 0, слияние 37.
- [ ] проба на обе поверхности, красная до фикса — со слов коммита (KA1-10…16), этой записью не исполнялась.
- [x] страница края об отказе 401 согласована: `AUTHN_REQUIRED` в `gateway/docs` → база 0, слияние 1; построчно страница не сверялась.

## Затронутые сущности vault

- [[packages/apigw-authnrefusal]] — единственный производитель отказа 401 края (заведена этой записью)
- [[packages/apigw-middleware]] — цепочка края: что волна-1 в ней меняет (History #2958)

## Связанные задачи

- [[KAC/issue-2964]] — волна-1, родитель
- [[KAC/issue-1266]] — эпик

#kac #kacho-api-gateway #kacho-ui
