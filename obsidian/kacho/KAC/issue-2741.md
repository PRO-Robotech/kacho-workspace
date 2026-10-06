---
title: "kacho#2741: один код ответа соседа несёт временный и постоянный диагнозы — разведены на обоих путях"
aliases:
  - issue-2741
ticket_id: 2741
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/clients
  - gateway/internal/streamrevocation
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3009
  - https://github.com/PRO-Robotech/kacho/pull/3016
issue_url: https://github.com/PRO-Robotech/kacho/issues/2741
opened: 2026-09-21
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@9b14ae7f01c (коммит слияния PR #3016, родители 656955b66b7 + be1d233cc8c; голова origin/1266 = этот коммит, 2026-10-04): состав — git log 656955b66b7..9b14ae7f01c --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям-доказательствам задачи; пробы и конвейер этой записью не перезапускались"
closed: 2026-10-04
---

# kacho#2741: один код ответа соседа несёт временный и постоянный диагнозы — разведены на обоих путях

> [!note] Состояние — `test`: задача ЗАКРЫТА вместе с волной-2, в `main` не влито
> Часть сделана волной-1 [[KAC/issue-2964]] (путь переходника, `753315ec39c`); остаток — путь перепроса
> открытых потоков — волной-2 [[KAC/issue-2965]], коммит `c037ddeb4ad`. Запрос [kacho#3016](https://github.com/PRO-Robotech/kacho/pull/3016) влит в `1266`
> коммитом слияния `9b14ae7f01c` 2026-10-04, задача стоит в нём строкой `Closes`. Запроса `1266` → `main` нет.

## Что и зачем

Ответ соседа «метода нет» приходит в двух положениях с противоположным действием: глагола нет у
сборки (окно раската, сходится само) и спрошен не тот слушатель (настройка, повтор не лечит).
Классификация их не различала. Наружу ответ одинаков и меняться не должен — предмет только
классификация внутри края и подсказка дежурному.

Сделано (коммит `753315ec39c`): на пути классификации отказа переходника диагнозы разведены на
две существующие корзины, ответ арендатору прежний. Остаток волны-1 — путь перепроса открытых потоков — доделан волной-2 (`c037ddeb4ad`): каждая полоса
перепроса (liveness, cutoff) различает «не тот слушатель» и «окно раската», поток жив в обоих случаях.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса KA1 → волна | ветка `2728-ka1` (координата, не живая ссылка) → ветка `2964` | — | bb8d2aa4e36 · догон d4645fee458 · харнесс 85da1906c85 | [kacho#3004](https://github.com/PRO-Robotech/kacho/pull/3004) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |
| полоса KA-2741 → волна-2 | остаток → ветка `2965` (координата, не живая ссылка) | c037ddeb4ad | 50b61a11f45 | — |
| волна-2 → эпик | ветка `2965` → ветка `1266` | be1d233cc8c | 9b14ae7f01c | [kacho#3016](https://github.com/PRO-Robotech/kacho/pull/3016) |

## Затронутые каталоги

Волна-1: `753315ec39c` — `gateway/internal/clients/session_revocations_client.go`. Волна-2: `c037ddeb4ad` —
`gateway/internal/streamrevocation/sweeper.go`, `gateway/internal/middleware/auth_session_cutoff.go`, проба
`gateway/internal/clients/sweeper_diagnosis_test.go`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено, причина в строке.

- [x] пп.1–3 — диагнозы разведены по двум корзинам с подсказкой дежурному на обоих путях:
  `TestSweeperTellsMisaddressedFromRolloutWindow` (путь потоков), `TestUnimplementedIsDiagnosedAsMisaddressedOrRolloutWindow`
  (путь запроса) — PASS на `be1d233cc8c`, `-race` ([доказательство](https://github.com/PRO-Robotech/kacho/issues/2741#issuecomment-5974823894));
- [x] п.4 — ответ арендатору одинаков при обоих диагнозах: `TestTenantAnswerIsTheSameForBothDiagnoses` — PASS (там же);
- [x] задача закрыта вливанием волны-2 (комментарий каскада 2026-10-04);
- [ ] в `main` — нет.

## Затронутые сущности vault

- [[packages/apigw-clients]] — переходник края к службе доступа: бюджет и диагнозы; путь перепроса потоков (History #2741, волны 1 и 2)

## Связанные задачи

- [[KAC/issue-2965]] — волна-2, где закрыта
- [[KAC/issue-2964]] — волна-1, где сделана часть
- [[KAC/issue-1266]] — эпик

#kac #kacho-api-gateway
