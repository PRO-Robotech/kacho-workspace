---
title: "kaname#536: identity-own · #296 · волна-2 — отсечка, авторитет отзыва, рукоятка ключа, гейты, почта"
aliases:
  - issue-536-kaname
  - kaname#536
ticket_id: 536
category: kac
status: test
type: epic
repos:
  - kaname
areas:
  - internal
  - internal/migrations
  - proto
  - docs
  - deploy
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
  - https://github.com/PRO-Robotech/kaname/pull/591
issue_url: https://github.com/PRO-Robotech/kaname/issues/536
opened: 2026-10-01
closed: 2026-10-04
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#536: identity-own · #296 · волна-2 — отсечка, авторитет отзыва, рукоятка ключа, гейты, почта

> [!note] Состояние — `test`: волна ЗАКРЫТА вливанием в ветку эпика, в `main` службы не влито
> Запрос [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (`536` → `296`) влит коммитом слияния `77dae639` 2026-10-04 (родители `d2f6f182` + `594af5af`,
> дерево равно `refs/pull/599/merge`). Локальный прогон в форме конвейера — 13 из 13; хук отправки — 6 групп
> из 6, отказов 0; подпись pointpu — 36 из 36 коммитов (со слов тела запроса).

## Что и зачем

Семь полос и починка ak03, сведённые в ветку волны локальными слияниями `--no-ff`.

| полоса | задача | голова |
|---|---|---|
| ak03 (PR kaname#591) | [[KAC/issue-590-kaname]] | 335b9571 |
| NA24 | [[KAC/issue-522-kaname]] (+#525, #547) | 55c2bf7d |
| NA2 | [[KAC/issue-336-kaname]] (+#335, #231) | 037daf93 |
| NA4 | [[KAC/issue-171-kaname]] (+#388, #390, #547) | 57d165b0 |
| NA5 | [[KAC/issue-351-kaname]] (+#523) | 35eb7dfd |
| NM1 | [[KAC/issue-246-kaname]] (+#475, #175) | 4bc81e43 |
| #586 | [[KAC/issue-586-kaname]] | efdd229b |
| NA9a | [[KAC/issue-162-kaname]] (+#172, #174, #247, #223) | 340139ed |

**Закрыты** (Closes): #590, #522, #336, #171, #586, #162. **Перенесены в волну-3**
[[KAC/issue-537-kaname]] (Refs — работа в `296` есть, исход предиката в запросе не предъявлен): #351,
#246, #547, #525, #335, #231, #388, #390, #523, #475, #175, #172, #174, #247, #223.
**Заведены по ходу:** [[KAC/issue-589-kaname]], [[KAC/issue-587-kaname]], [[KAC/issue-596-kaname]].

## Затронутые каталоги

Ветка эпика `296`; дифф `d2f6f182..77dae639` — 178 файлов.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] запрос волны влит в ветку эпика — `git merge-base --is-ancestor 77dae639 origin/296` → 0;
- [x] закрыты 6 задач с Closes;
- [ ] 15 задач перенесены в #537 — но в sub-issue по-прежнему висят на закрытой #536, в #537 их нет (`gh api …/issues/537/sub_issues`, 2026-10-04) — расхождение трекера;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- [[edges/kaname-cutoff-door-vs-schema-writers]] · [[resources/iam-user-token-revocation]] · [[resources/iam-minted-token-revocation]] — схема отсечки
- [[packages/kaname-access-keys]] · [[resources/kaname-access-key]] — ключи доступа
- [[resources/iam-recovery-code]] — окно писем
- [[packages/kaname-internal-check]] — гейты дерева

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-535-kaname]] — волна-1
- [[KAC/issue-537-kaname]] — волна-3
- [[KAC/issue-2965]] — волна-2 платформы

#kac #kacho-iam #epic
