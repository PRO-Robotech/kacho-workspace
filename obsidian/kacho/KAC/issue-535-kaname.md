---
title: "kaname#535: волна-1 identity-own — приёмки, модель прав, ключи доступа, проза"
aliases:
  - issue-535-kaname
ticket_id: 535
category: kac
status: test
type: epic
repos:
  - kaname
areas:
  - docs/engineering/acceptance
  - docs/specs/reviews
  - docs/content
  - proto/kaname/cloud/iam/v1
  - tests/newman
  - internal
prs:
  - https://github.com/PRO-Robotech/kaname/pull/582
issue_url: https://github.com/PRO-Robotech/kaname/issues/535
opened: 2026-10-01
closed: "2026-10-03"
tags:
  - kac
  - kacho-iam
  - iam
  - epic
verified_against: "kaname 296@d2f6f182 (коммит слияния PR #582, родители 9bac42bdcbc + ed95e66f1; голова origin/296 = этот коммит, 2026-10-03): состав коммитов — git log по 9bac42bdcbc..ed95e66f1, предикаты DoD, названные в строках, — git grep -c / sha256sum на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kaname#535: волна-1 identity-own — приёмки, модель прав, ключи доступа, проза

> [!note] Состояние — `test`: волна ЗАКРЫТА вливанием в ветку эпика
> Запрос [kaname#582](https://github.com/PRO-Robotech/kaname/pull/582) `535` → `296` влит 2026-10-03T13:37Z коммитом слияния
> `d2f6f182fab9d9727a7fab35a82a798005eb0d89` (родители `9bac42bdcbc`, `ed95e66f1`); голова `origin/296` равна
> этому коммиту. Ветки волны и полос на origin сняты (`git ls-remote --heads origin 535 269 254 268 472 530` → пусто).
> В `main` службы не влито.

## Что и зачем

Волна-1 эпика [[KAC/issue-296-kaname]]. Полосы — локальные слияния `--no-ff` в ветку волны:

| полоса | ветка | слияние | задачи |
|---|---|---|---|
| NA3a | `269` | `ae5f0df0b`, `ed95e66f1` | [[KAC/issue-269-kaname]] · [[KAC/issue-177-kaname]] · [[KAC/issue-237-kaname]] · [[KAC/issue-274-kaname]] · [[KAC/issue-345-kaname]] · [[KAC/issue-346-kaname]] · [[KAC/issue-347-kaname]] · [[KAC/issue-2703]] |
| NA1 | `254` | `9a91a0a80` | [[KAC/issue-254-kaname]] |
| NA13 | `268` | `5c1f7e8b4` | [[KAC/issue-268-kaname]] |
| NA18 | `472` | `6fb7b39e0` | [[KAC/issue-472-kaname]] · [[KAC/issue-342-kaname]] |
| NA17 | `530` | `f95bc6012` | [[KAC/issue-530-kaname]] · [[KAC/issue-517-kaname]] · [[KAC/issue-519-kaname]] · [[KAC/issue-521-kaname]] · [[KAC/issue-529-kaname]] · [[KAC/issue-531-kaname]] |
| NA16 | — | — | [[KAC/issue-303-kaname]] (только чтение) |

Перед полосами — догон ветки эпика `79b3e1825` (PR kaname#576).

> [!warning] Расхождение каскада, найденное этой записью
> В sub-issue закрытой волны **открытыми** остаются kacho#2688 и kaname#133
> (`gh api repos/PRO-Robotech/kaname/issues/535/sub_issues` → `2688 open`, `133 open`, 2026-10-03), а в
> комментарии закрытия волны они не названы. kaname#344, о которой сказано «перенесена в волну 2», в
> sub-issue волны-1 не стоит и стоит в волне-4 kaname#538 (`gh api graphql … issue(number:344){parent}` → 538).

## Затронутые каталоги

Диф `9bac42bdcbc..d2f6f182`: 64 файла, +29480 / −1258 (`git diff --stat`). Коммитов без слияний — 28 (`git log --no-merges 9bac42bdcbc..ed95e66f1`).

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] запрос волны влит в ветку эпика: `gh pr view 582` → `MERGED`, `mergeCommit` `d2f6f182`; `git ls-remote origin 296` → тот же коммит.
- [x] задачи волны с трекером: закрыты 21 из 23 sub-issue (`gh api …/issues/535/sub_issues`); открыты kacho#2688 и kaname#133 — см. врезку.
- [ ] хук отправки 6 из 6 групп на `ed95e66f1` и на слиянии — со слов тела PR и комментария закрытия.
- [ ] эпик `296` влит в `main` службы — нет, запроса нет.

## Затронутые сущности vault

- [[rpc/iam-user-service]] — `ResetSecondFactor`: кто вправе (History kaname#535)
- [[resources/kaname-access-key]] — ключ доступа: Ф7 на ветке эпика (History kaname#535)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-2964]] — волна-1 платформы, та же линия
- [[KAC/issue-1266]] — эпик платформы

#kac #kacho-iam #iam #epic
