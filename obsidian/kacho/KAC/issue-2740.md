---
title: "kacho#2740: отказы полосы предъявителя видны на приборе"
aliases:
  - issue-2740
ticket_id: 2740
category: kac
status: test
type: refactor
repos:
  - kacho
areas:
  - gateway/internal/middleware
  - gateway/internal/observability/metrics
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3009
issue_url: https://github.com/PRO-Robotech/kacho/issues/2740
opened: 2026-09-21
closed: "2026-10-03"
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@656955b66b7 (коммит слияния PR #3009, родители 108e7c32b90 + 25ba0c48664; голова origin/1266 = этот коммит, 2026-10-03): состав коммитов — git log по 108e7c32b90..25ba0c48664, предикаты DoD, названные в строках, — git grep -c на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kacho#2740: отказы полосы предъявителя видны на приборе

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-10-03 каскадом волны-1 [[KAC/issue-2964]]: волна влита в ветку эпика `1266`
> запросом [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009), коммит слияния `656955b66b759d6c3c39ad0d94b383a5c89ae8af`.
> В `main` продукта код не влит — открытого запроса эпика `1266` → `main` нет
> (`gh pr list --base main --head 1266` → пусто, 2026-10-03), поэтому состояние записки `test`.
> Комментарий закрытия: local на голове `25ba0c48664` — 7 из 7 групп, код 0; сквозные прогоны на
> стенде и конвейер не проверялись.

## Что и зачем

У полосы предъявителя не было ни одной клетки на приборе — дежурный видел причину отказа только
строкой журнала раз в интервал; обоснование «у процесса нет поверхности сбора» в шапке докладчика
устарело. Перепись накопителей этой разновидности не видела.

Исход: исходы полосы — клетками на приборе (`kacho_api_gateway_bearer_lane_revocation_total`), окна
доклада журнала — клеткой `kacho_api_gateway_log_window_events_total`; перепись накопителей
расширена на итог под замком.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса KA1 → волна | ветка `2728-ka1` (координата, не живая ссылка) → ветка `2964` | — | bb8d2aa4e36 · догон d4645fee458 · харнесс 85da1906c85 | [kacho#3004](https://github.com/PRO-Robotech/kacho/pull/3004) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |

## Затронутые каталоги

Коммиты задачи: `b7226ae2226`, `c683861ea2b`, `e81ac2506b4`. Пути:
`gateway/internal/observability/metrics/{bearer_lane,log_window}.go` (новые),
`gateway/internal/middleware/introspection_failure_report.go`, `internal/repohygiene/`.

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] п.1 — клетки полосы на приборе: `bearer_lane` в `gateway/internal/observability` → база 0, слияние 3.
- [ ] п.2 — устаревшее обоснование снято из шапки докладчика: этой записью не читалось.
- [x] п.3 — перепись расширена: `TestDeclaredAccumulatorsHaveANonTestReader` в `internal` → база 2, слияние 3; объём осмотренного до и после (1012 → 1013 файлов, накопителей 9 → 11) — со слов комментария задачи 2026-10-03.
- [ ] п.4 — инъекция в обе стороны (`accumulatorlockedtotal_injection_test.go`) — со слов комментария задачи, этой записью не исполнялась.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — цепочка края: что волна-1 в ней меняет (History #2740)

## Связанные задачи

- [[KAC/issue-2964]] — волна-1, родитель
- [[KAC/issue-1266]] — эпик

#kac #kacho-api-gateway
