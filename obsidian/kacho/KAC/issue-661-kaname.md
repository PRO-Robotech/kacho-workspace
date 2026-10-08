---
title: "kaname#661: администраторы кластера через публичную службу (ADM-1)"
aliases:
  - issue-661-kaname
  - kaname#661
ticket_id: 661
category: kac
status: in-progress
type: feature
repos:
  - kaname
areas:
  - proto/kaname/cloud/iam/v1
  - cmd/kaname
  - internal/restfront
  - tests/newman
  - docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/666
  - https://github.com/PRO-Robotech/kaname/pull/668
  - https://github.com/PRO-Robotech/kaname/pull/674
issue_url: https://github.com/PRO-Robotech/kaname/issues/661
opened: 2026-10-07
tags:
  - kac
  - feature
  - kacho-iam
verified_against: "kaname 296@aa253fa9bcad (git ls-remote 2026-10-08): cluster_service.proto и регистрация на публичном слушателе и REST-фронте — git show / git grep; коммит службы 701512a5d в сборке 6b (PR #668 → 8b0379e2a9c5); приёмка cluster-admins-on-the-public-surface — PR #666 (28b7acb117cc) и #674 (aa253fa9bcad), gh pr view; состояние задачи — gh issue view 2026-10-08 (OPEN); DoD-proof у задачи нет (тело PR #668)"
---

# kaname#661: администраторы кластера через публичную службу (ADM-1)

> [!note] Состояние — `in-progress`: служба в ветке эпика, задача открыта
> Публичный близнец влит сборкой 6b ([kaname#668](https://github.com/PRO-Robotech/kaname/pull/668), `8b0379e2a9c5`)
> как `Refs`: S1 сделан, кроме расхождения сценариев CAP-20 и CAP-21 с приёмкой. Приёмка переутверждена
> после сборки ([kaname#674](https://github.com/PRO-Robotech/kaname/pull/674), запись ревью APPROVED); DoD-proof не выставлен.

## Что и зачем

Перечень, назначение и снятие администраторов кластера были только у внутреннего близнеца, поэтому на посадке
внешнего края системный администратор не мог ими воспользоваться. Предмет — публичная служба
[[rpc/iam-cluster-service]] с тем же правом и тем же порогом уверенности, что у внутреннего близнеца.

## Затронутые каталоги

`proto/kaname/cloud/iam/v1`, `cmd/kaname`, `internal/restfront`, `tests/newman`, `docs/engineering/acceptance` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] приёмка одобрена и в линии — PR kaname#666, переутверждение CAP-20/CAP-21 — PR kaname#674;
- [x] служба зарегистрирована на публичном слушателе и REST-фронте — `git grep` на `296`;
- [ ] интеграционные пробы по переутверждённым CAP-20/CAP-21 и DoD-proof — нет;
- [ ] пин службы на краю, регистрация и экраны консоли — kacho#3093, kacho#3094 (открыты).

## Затронутые сущности vault

- [[rpc/iam-cluster-service]] — новая записка
- [[rpc/iam-internal-cluster-service]] — ссылка на публичного близнеца (History 2026-10-08)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-2969]] — волна-6 платформы (kacho#3091…#3094)

#kac #feature #kacho-iam
