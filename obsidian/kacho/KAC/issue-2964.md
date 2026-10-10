---
title: "kacho#2964: волна-1 identity-own — край: вердикт отзыва, бюджет вызовов, канон издателя, отказ 401"
aliases:
  - issue-2964
ticket_id: 2964
category: kac
status: test
type: epic
repos:
  - kacho
areas:
  - gateway
  - internal/repohygiene
  - ui-future
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3009
issue_url: https://github.com/PRO-Robotech/kacho/issues/2964
opened: 2026-10-01
closed: "2026-10-03"
tags:
  - kac
  - kacho-api-gateway
  - epic
verified_against: "kacho 1266@656955b66b7 (коммит слияния PR #3009, родители 108e7c32b90 + 25ba0c48664; голова origin/1266 = этот коммит, 2026-10-03): состав коммитов — git log по 108e7c32b90..25ba0c48664, предикаты DoD, названные в строках, — git grep -c на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kacho#2964: волна-1 identity-own — край: вердикт отзыва, бюджет вызовов, канон издателя, отказ 401

> [!note] Состояние — `test`: волна ЗАКРЫТА вливанием в ветку эпика
> Запрос [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) `2964` → `1266` влит 2026-10-03T18:38Z коммитом
> слияния `656955b66b759d6c3c39ad0d94b383a5c89ae8af` (родители `108e7c32b90`, `25ba0c48664`); голова
> `origin/1266` равна этому коммиту. Ветки волны и полос на origin сняты
> (`git ls-remote --heads origin 2964 2728-ka1 2958-ka1-ui 2961-ka10` → пусто). В `main` не влито.

## Что и зачем

Волна-1 эпика [[KAC/issue-1266]] со стороны края. Три полосы:

| полоса | ветка | задачи |
|---|---|---|
| KA1 | `2728-ka1` | [[KAC/issue-2728]] · [[KAC/issue-2713]] · [[KAC/issue-2738]] · [[KAC/issue-2740]] · [[KAC/issue-2742]] · [[KAC/issue-2758]] · [[KAC/issue-2760]] · [[KAC/issue-2741]] (частично) |
| KA1-ui | `2958-ka1-ui` | [[KAC/issue-2958]] |
| KA10 | `2961-ka10` | [[KAC/issue-2961]] · [[KAC/issue-2971]] |

kacho#2942 (граница доверия конвейера публикации) — в составе волны, но закрыта отдельно
2026-10-02 исправлением вне каскада (PR kacho#2962, решение R33); trail ей этой записью не заводится.

Приёмка KA1 ред. 7 (вход полосы KA1) — `docs/specs/sub-phase-KA1-edge-refusals-and-call-budgets-acceptance.md`
воркспейса, влита PR воркспейса #906 в ветку `897-identity-own-wave1` (`fabf7d1b114`), запись ревью на
отпечаток `e88968ad…` — `APPROVED`. В `main` воркспейса её нет.

Остаток: [[KAC/issue-2741]] — `Refs`, а не `Closes`; перенесена в волну-2 [kacho#2965](https://github.com/PRO-Robotech/kacho/issues/2965).

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса KA1 → волна | ветка `2728-ka1` (координата, не живая ссылка) → ветка `2964` | — | bb8d2aa4e36 · догон d4645fee458 · харнесс 85da1906c85 | [kacho#3004](https://github.com/PRO-Robotech/kacho/pull/3004) |
| полоса KA1-ui → волна | ветка `2958-ka1-ui` (координата) → ветка `2964` | — | 6839b3153cd · 7a47d4b47d6 · 25ba0c48664 | [kacho#3008](https://github.com/PRO-Robotech/kacho/pull/3008) |
| полоса KA10 → волна | ветка `2961-ka10` (координата) → ветка `2964` | — | 99410192c35 | — (локальное слияние) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |

Перед полосами — догон ветки эпика `0f33d90972e` (PR kacho#3006, `1266` → `2964`).

## Затронутые каталоги

Диф `108e7c32b90..656955b66b7`: 144 файла, +8210 / −689 (`git diff --stat`). Новые пакеты: `gateway/internal/authnrefusal`, `gateway/internal/issuercanon`; новые файлы в `gateway/internal/config` (`callbudget.go`), `gateway/internal/middleware` (`bearer_lane.go`, `credential_state_unknown.go`, `cutoff_subject.go`), `gateway/internal/observability/metrics`, `internal/repohygiene`.

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] запрос волны влит в ветку эпика: `gh pr view 3009` → `MERGED`, `mergeCommit` `656955b66b7`; `git ls-remote origin 1266` → тот же коммит.
- [x] задачи волны закрыты тем же заходом: sub-issue #2964 — 11, все `closed` (`gh api …/issues/2964/sub_issues`); #2741 снята из волны-1 и стоит в #2965.
- [ ] local на голове `25ba0c48664` — 7 из 7 групп, код 0 — со слов тела PR #3009; сквозные прогоны на стенде и конвейер не проверялись.
- [ ] эпик `1266` влит в `main` — нет, запроса `1266` → `main` нет.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — цепочка края: что волна-1 в ней меняет (History #2964)
- [[packages/apigw-clients]] — переходник края к службе доступа: бюджет и диагнозы (History #2964)
- [[packages/apigw-config]] — ручки бюджетов и запись приёма издателя (History #2964)
- [[packages/apigw-restmux]] — бюджет унарного вызова REST-моста (History #2964)
- [[packages/apigw-authnrefusal]] — единственный производитель отказа 401 края (заведена этой записью)
- [[packages/apigw-issuercanon]] — канон формы издателя (заведена этой записью)

## Связанные задачи

- [[KAC/issue-1266]] — эпик
- [kacho#2965](https://github.com/PRO-Robotech/kacho/issues/2965) — волна-2
- [[KAC/issue-535-kaname]] — волна-1 службы, та же линия

#kac #kacho-api-gateway #epic
