---
title: "kaname#540: identity-own · kaname#296 · волна-6 — полоса формы и формы отказов, ведомость долга, гейт материала, свои сессии, смена адреса, публичная служба администраторов кластера"
aliases:
  - issue-540-kaname
  - kaname#540
ticket_id: 540
category: kac
status: in-progress
type: epic
repos:
  - kaname
areas:
  - internal/handler
  - internal/restfront
  - internal/apps
  - internal/check
  - internal/repo
  - proto
  - tests/newman
  - docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/640
  - https://github.com/PRO-Robotech/kaname/pull/658
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/540
opened: 2026-10-01
tags:
  - kac
  - epic
  - kacho-iam
verified_against: "kaname 296@aa253fa9bcad (голова origin/296, git ls-remote 2026-10-08; сверх сборок волны — PR #663, #666, #672, #674); сборки — коммиты слияния PR #640 = 76ca2c8aa6e0, #658 = b729affb6a80, #668 = 8b0379e2a9c5 (gh pr view → MERGED); состав — тела этих PR; состояние задачи и sub-issue — gh issue view / gh api …/issues/540/sub_issues 2026-10-08; DoD задач — комментарии DoD-proof и закрытия; пробы и конвейер этой записью не перезапускались"
---

# kaname#540: identity-own · kaname#296 · волна-6 — полоса формы и формы отказов, ведомость долга, гейт материала, свои сессии, смена адреса, публичная служба администраторов кластера

> [!note] Состояние — `in-progress`: волна ОТКРЫТА, влиты три сборки
> Ветка эпика `296` на origin @`aa253fa9bcad` (2026-10-08). Открыт запрос полосы REF (kaname#675, `211` → `296`,
> редакции пяти приёмок волны).

## Что и зачем

Волна-6 эпика [[KAC/issue-296-kaname]] в доме службы доступа; шла парой с волной платформы [[KAC/issue-2969]].

| сборка | запрос | коммит слияния в `296` | полосы |
|---|---|---|---|
| первая | [kaname#640](https://github.com/PRO-Robotech/kaname/pull/640) | `76ca2c8aa6e0` 2026-10-07 | N-PII #631, NA6 #261 (с #280), N-MAIL #630, N-E2E #614 (с #633), N-CLOCK #589 |
| вторая | [kaname#658](https://github.com/PRO-Robotech/kaname/pull/658) | `b729affb6a80` 2026-10-07 | #635 смена адреса почты, #634 свои сессии, #139 гейт материала |
| 6b | [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) | `8b0379e2a9c5` 2026-10-08 | ADM #661 (публичный близнец `ClusterService`), SEC #641 и #642, FGA #665, 405 #261, LEDGER #643 |

Имена веток — координаты на момент сборки, не живые ссылки. Вне сборок в `296` за то же время влиты запросы
приёмок и правок по одной задаче: #663 (#660), #666 и #674 (приёмка [[KAC/issue-661-kaname]]), #672
(приёмка [[KAC/issue-638-kaname]], редакция 5).

## Закрыты вливаниями (по трекеру, 15)

| задача | основание |
|---|---|
| [[KAC/issue-589-kaname]], [[KAC/issue-630-kaname]], [[KAC/issue-631-kaname]], [[KAC/issue-280-kaname]], [[KAC/issue-633-kaname]] | первая сборка, DoD-proof |
| [[KAC/issue-139-kaname]] | вторая сборка, DoD-proof |
| [[KAC/issue-261-kaname]], [[KAC/issue-641-kaname]], [[KAC/issue-642-kaname]], [[KAC/issue-643-kaname]], [[KAC/issue-665-kaname]] | сборка 6b, DoD-proof |
| [[KAC/issue-526-kaname]] | DoD-proof @`8f96e120` (первая сборка); держатель EV-14 перенесён на kacho#3069 (сборка 6b) |
| [[KAC/issue-637-kaname]] | правка уже в `296` (коммит `e1c4946cc`), DoD-proof без запроса |
| [[KAC/issue-467-kaname]] | **передачей** держателю kacho#1269, не доказательством |
| [[KAC/issue-924-ws]] | запрос воркспейса ws#927 в `main`, DoD-proof |

## Открыты (по трекеру, 22 из 37 sub-issue)

- влиты сборкой, но не закрыты (`Refs`): kaname#634, kaname#635 (браузерная и стендовая части впереди),
  [[KAC/issue-661-kaname]] (S1 в дереве; CAP-20/CAP-21 переутверждены приёмкой после сборки);
- приёмка переделывается: [[KAC/issue-638-kaname]];
- формы отказов и шаги: kaname#211 (запрос #675 открыт), kaname#520, kaname#511, kaname#524;
- прочие: kaname#258, kaname#133, kaname#387, kaname#614, kaname#458, kaname#198, [[KAC/issue-475-kaname]],
  kaname#609, kaname#610, kaname#608, kaname#213, kacho#2702, kaname#468, kaname#664.

## Затронутые каталоги

`proto/kaname/cloud/iam/v1`, `cmd/kaname`, `internal/{handler,restfront,apps,check,repo,clients,mailaddr,revocationpolicy}`,
`tests/newman`, `.github/scripts`, `docs/engineering/acceptance`, `docs/specs/reviews`, `docs/content`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] три сборки влиты в `296` merge-коммитами — `76ca2c8aa6e0`, `b729affb6a80`, `8b0379e2a9c5`;
- [x] 15 задач закрыты; у 14 есть DoD-proof, kaname#467 закрыта передачей (комментарий закрытия);
- [ ] 22 sub-issue открыты (список выше);
- [ ] выкатка на стенд — не сделана: на стенде `296` @`d9e233f4` (ревизия 5, со слов диспетчера);
- [ ] волна закрыта — нет, задача открыта.

## Затронутые сущности vault

- [[rpc/iam-cluster-service]] — публичный близнец службы администраторов кластера (новая записка)
- [[rpc/iam-internal-cluster-service]] — внутренний близнец: координата контракта и ссылка на публичный (History 2026-10-08)
## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-539-kaname]] — волна-5
- [[KAC/issue-2969]] — волна-6 платформы

#kac #epic #kacho-iam
