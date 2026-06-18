---
title: "100% tuple↔resource-create guarantee (sub-phase 1.4)"
aliases:
  - sub-phase-1.4-tuple-resource-guarantee
  - tuple-resource-guarantee
ticket_id: "(none — sub-phase acceptance doc)"
category: kac
status: done
type: feature
repos:
  - kacho-corelib
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
tags:
  - kac
  - feature
  - kacho-corelib
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - race-fix
---

# 100% tuple↔resource-create guarantee (sub-phase 1.4)

> [!note] Трек без KAC-номера
> Acceptance-док `docs/specs/sub-phase-1.4-*-acceptance.md`; YouTrack-тикет не заводился.

**Status**: ✅ done — merged на `main` + live `fe3455` (helm rev13, 2026-06-18).
**Type**: feature (at-least-once hardening)
**Repos / PRs**: kacho-corelib [#25](https://github.com/PRO-Robotech/kacho-corelib/pull/25) (S0), [#26](https://github.com/PRO-Robotech/kacho-corelib/pull/26) (starvation fix); kacho-iam [#161](https://github.com/PRO-Robotech/kacho-iam/pull/161) (S2); kacho-vpc [#158](https://github.com/PRO-Robotech/kacho-vpc/pull/158), kacho-compute [#57](https://github.com/PRO-Robotech/kacho-compute/pull/57), kacho-nlb [#32](https://github.com/PRO-Robotech/kacho-nlb/pull/32) (S3 backstop).

## Что и зачем

Ядро-требование заказчика: **owner-access tuple НИКОГДА не должен теряться при создании ресурса**. Раньше iam писал owner/hierarchy-tuple для своих ресурсов best-effort POST-COMMIT (терялся при крэше между commit'ом ресурса и tuple-write); под длительным outage transient-сбои отравляли intent → нарушение at-least-once.

## Сделано

- **corelib #25 (S0)** — at-least-once hardening: `markTransientFailure` кэпит `attempt_count` на `MaxAttempts-1` (transient НЕ poison'ит сам по себе); reconciler (`RedrivePoisoned`/`BackfillFromState`/`GCOrphans`); метрики; fail-closed bootgate.
- **corelib #26** — claim `ORDER BY attempt_count, id` (был `ORDER BY id`) — INCIDENT A07 fix (ниже).
- **iam #161 (S2)** — owner/hierarchy-tuple собственных ресурсов (Account/Project/Group/SA/Role + bootstrap `UpsertFromIdentity`) перенесён из best-effort POST-COMMIT `relationhook.WriteHierarchyTuple` ВНУТРЬ writer-tx (`Writer.EmitFGARelationWrite`/`EmitFGARelationDelete` → co-commit в `kacho_iam.fga_outbox`; in-process drainer доставляет, idempotent FGA-409→success). **Без новой миграции** (fga_outbox в `0001`). AccessBinding.Create + seed bootstrap уже были атомарны.
- **vpc #158 / compute #57 / nlb #32 (S3 backstop)** — additive `account_id`-миграции (vpc `0009` / compute `0012` / nlb `0003`) на собственных operations-таблицах (закрывают 42703).

## Инциденты

### A07 — head-of-line starvation (corelib #26)

> [!warning] Регрессия at-least-once от S0
> S0-кэп (`attempt_count` транзиента застывает высоким, но НЕ poison) + старый claim `ORDER BY id` →
> starvation: backlog transient-застрявших **low-id** строк навсегда затенял свежие **higher-id**
> intent'ы → под outage новый intent НЕ доставлялся → at-least-once нарушен. Поймано red-тестом
> `kacho-iam/TestRegisterResource_A07_FGADownIntentPersistsAcrossRestart` на main. Фикс: claim
> `ORDER BY attempt_count, id`. Гард: `Test_1_4_24_TransientBacklog_DoesNotStarveFreshIntent`.

### 42703 — operations account_id merge-order

corelib #24 (sub-phase 1.2) дал безусловный `account_id`-INSERT раньше consumer-миграций → `42703` fleet-wide. Закрыто S3-миграциями + iam 0016. Подробно — [[sub-phase-1.2-iam-operations]].

## Затронутые сущности vault

[[../packages/corelib-outbox-drainer]] [[../packages/iam-pg-fga-outbox]] [[../packages/corelib-operations]] [[../edges/iam-to-openfga-grant-write]] [[../resources/operation]]

## DoD

- [x] corelib #25 (S0): transient-no-poison + reconciler + bootgate + metrics
- [x] corelib #26: claim `ORDER BY attempt_count, id` + гард-тест (RED→GREEN)
- [x] iam #161 (S2): own-resource owner-tuple co-commit в fga_outbox (no new migration)
- [x] vpc #158 / compute #57 / nlb #32 (S3): account_id-миграции (42703 backstop)
- [x] всё на `main` + live `fe3455` rev13
- [x] vault обновлён

## Связанные тикеты

- [[sub-phase-1.2-iam-operations]] — operations visibility (источник 42703)
- [[sub-phase-1.3-subject-privileges]] — привилегии-таб
- [[KAC-163]] — W1.5 fga_outbox для AccessBinding/JIT/BreakGlass (предшественник)
- [[KAC-137]] — W1.1 drainer foundation

#kac #feature #kacho-corelib #kacho-iam #race-fix
