---
title: "kaname#171: граница отсечки — одна у правила токенов, хука и края"
aliases:
  - issue-171-kaname
  - kaname#171
ticket_id: 171
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/tokenrevocation
  - internal/revocationpolicy
  - internal/apps/kaname/api/user_tokens
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
issue_url: https://github.com/PRO-Robotech/kaname/issues/171
opened: 2026-09-16
closed: 2026-10-04
tags:
  - kac
  - kacho-iam
  - iam
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#171: граница отсечки — одна у правила токенов, хука и края

> [!note] Состояние — `test`: задача ЗАКРЫТА вместе с волной-2, в `main` службы не влито
> Волна [[KAC/issue-536-kaname]] влита в ветку эпика `296` запросом [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (коммит слияния `77dae639`,
> 2026-10-04); задача стоит в запросе строкой `Closes` и закрыта каскадом. Запроса `296` → `main` нет —
> до него состояние `test`, и на `origin/main` службы прежнее поведение.

## Что и зачем

Три читателя одной отсечки субъекта судили границу по-разному: правило токенов — строго, хук и
край — включающе. Граница у правила отзыва токенов сделана включающей, как у остальных: полномочие,
возникшее не позже отсечки, запрещено. Правило — одно на все полосы (`internal/revocationpolicy`).

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса NA4 → волна | ветка полосы (снята; слияние в волну названо «merge #171») → ветка `536` | 57d165b0 | — | — |
| волна → эпик | ветка `536` (координата, не живая ссылка) → ветка `296` | 594af5af | 77dae639 | [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) |

Коммиты задачи: `d91581770` (граница); в той же полосе — `1a2592502` (#547), `cde3dbb4c` (#390), `57d165b0f` (#388).

## Затронутые каталоги

`internal/tokenrevocation/rule.go`, `internal/revocationpolicy/revocationpolicy.go`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] закрыта вливанием волны — комментарий каскада 2026-10-04: локальный прогон в форме конвейера 13 из 13 на голове 594af5af, хук отправки 6 групп из 6, сверка волны приняла DoD;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- [[resources/iam-user-token-revocation]] — граница отсечки включающая (History #171)

## Связанные задачи

- [[KAC/issue-388-kaname]] · [[KAC/issue-390-kaname]] · [[KAC/issue-547-kaname]] — та же полоса, перенесены
- [[KAC/issue-589-kaname]] — остаток #388: один источник времени на все реплики
- [[KAC/issue-536-kaname]] — волна-2
- [[KAC/issue-296-kaname]] — эпик

#kac #kacho-iam #iam
