---
title: audit-hardening-r5-8-2026-07-08
category: kac
tags:
  - kac
  - fix
  - batch
  - security
  - race-fix
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - kacho-api-gateway
  - kacho-registry
  - kacho-corelib
status: done
type: fix
---

# Массированный аудит-рефакторинг — раунды 5-9 (2026-07-08/09)

**Status**: DONE — сошлось на раунде 9 (0 confirmed) → «хватит и 100% выполнено»
**Type**: batch fix (security/leak/structure/readability/LEAN/concurrency)
**Repos**: corelib, iam, vpc, compute, geo, nlb, api-gateway, registry

## Что и зачем

Стойкая цель: полный массированный рефакторинг (безопасность/структурность/читаемость/
утечки/LEAN) до «100% чисто и безопасно», итеративно — **на каждой итерации аудит
заново, пока не сойдётся**. Метод (ultracode/workflow): per-repo deep-finder × 5-6
дименсий → **adversarial verify** (refute-пасс) → подтверждённые находки → TDD-фикс
(падающий regression-тест → фикс → verify build+test-race+lint) → PR → CI → merge → re-check.

## Сходимость (confirmed findings по раундам)

| Раунд | Candidates | Confirmed | HIGH | Чистых репо |
|---|---|---|---|---|
| r5 | 15 | 10 | 0 | — |
| r6 | 5 | 5 | 0 | 4/8 |
| r7 | 3 | 2 | **1** | 5/8 |
| r8 | 2 | 1 | 0 | 6/8 |
| r9 | 1 | **0** | 0 | 8/8 |

Тренд 10→5→2→1→**0** — монотонная сходимость до нуля. r7 вскрыл 1 HIGH (deep BOLA) —
подтверждает ценность «проверяешь заново». **r9 = 0 confirmed** (единственный кандидат
опровергнут adversarial-verify) → цикл СОШЁЛСЯ: ноль actionable HIGH/MEDIUM defects по
всем 6 дименсиям × 8 code-heavy репо. Решение: **хватит, 100% выполнено** (practical
convergence — не осталось находок, переживающих adversarial-verify на максимальной планке).

## Классы находок и фиксы (все merged кроме r8)

- **SECURITY**:
  - r7 **HIGH BOLA** — nlb `GetTargetStates` возвращал targets чужого project-TG без
    object-scoped authz → same-project + FGA `viewer` на `lb_target_group` (helper `tg_authz.go`, дедуп с Attach). PR nlb#70.
  - r5 — api-gateway authz-cache key без device_attestation/amr_claims (cache-poisoning replay) → в key. PR#127.
  - r5 — vpc internal admin-gate блокировал object-scoped IPAM RPC до FGA-Check (nlb→vpc edge) → `IsObjectScopedInternalMethod` из PermissionMap. PR#43.
  - r5 — compute `InternalWatchService/Watch` unmapped→fail-closed в prod → PermissionMap Public:true. PR#91.
  - r5 — corelib `operations.NewFromContext` игнорировал WithoutPrincipal scrub (forged principal) → PrincipalFromContextOK. PR#45.
  - r8 (fixing) — registry `ListRegistryOperations` existence-oracle (namespace v_list → имена чужих под-репо/тегов через DeleteTag-op metadata) → scope-filter по per-repo v_list.
- **LEAK / per-call-deadline** (systemic класс, **зачищен во ВСЕХ peer-клиентах**):
  - r5 iam openfga writeOrDelete; nlb check_client; registry IAMCheckClient.
  - r6 **sweep** — compute geo/iam clients; nlb vpc(address/subnet/nic/internal_address)/iam-project/geo-zone (~6); registry iam ProjectExists — все получили `context.WithTimeout` + Unavailable/DeadlineExceeded→ErrUnavailable + hanging-peer regression-тесты. PRs iam#306/compute#92/nlb#69/registry#18.
- **READABILITY / doc-truthfulness** (misleading-security-comment trap):
  - r5 iam access_binding Update/Delete: все Get-ошибки → PermissionDenied (коммент врал) → только ErrNotFound; прочие → MapRepoErr (retriable). PR#305.
  - r6 iam `iamhooks/hook_auth.go`: коммент про dev-mode-no-auth/401, код — fail-closed 500 → коммент под реальность. PR#306.
  - r5 compute `Instance.Fqdn` суффикс `.ru-central1.internal` (чужой-облако, **ban #2**) на публичной поверхности → Kachō-native. PR#91.
- **CONCURRENCY/EFFICIENCY**:
  - r7 corelib `listObjectsCache` O(N²) insertion-sort под write-lock на hot-path → O(N) (incremental count + expired-sweep + arbitrary eviction, zeркалит `authz.Cache.evictLocked`); regression `LinearNotQuadratic` 19.7s→0.12s. PR#46.
- **STDLIB SECURITY** (побочно вскрыт govulncheck при go1.26.5-DB):
  - GO-2026-5856 (crypto/tls) + GO-2026-4970 (os) в go1.26.4 → bump `go 1.26.5` + x/crypto v0.54.0 (iam/vpc/api-gateway). GO-2026-5932 (x/crypto/openpgp, depends-only/unfixable, `go mod why`=not-needed) → documented suppression в iam govulncheck-wrapper.

## Затронутые сущности vault
- [[../packages/vpc-apps-kacho-api-address]] (nested-conn race-fix — предыдущий батч)
- (peer-client deadline hardening — все `internal/clients/**`; authz object-scoping — nlb loadbalancer, registry public)

## DoD
- [x] r5/r6/r7 находки merged (TDD + CI-green, 7+4+2 PR)
- [x] per-call-deadline класс зачищен во всех peer-клиентах всех репо
- [x] stdlib go1.26.5 security-bump
- [x] r8 registry existence-oracle merged (fix/audit-r8)
- [x] r9 convergence-check → **0 confirmed** → «хватит и 100% выполнено»

## Связанные
- [[KAC-newman-100pct-batch]] (newman-e2e стек bring-up, Session 16)

#kac #fix #batch #security #race-fix
