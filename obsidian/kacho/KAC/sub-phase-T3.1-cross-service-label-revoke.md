---
title: "Cross-service ARM_LABELS revoke on label change (T3.1 / #113)"
aliases:
  - sub-phase-T3.1-cross-service-label-revoke
  - "#113 label-revoke"
ticket_id: "GH PRO-Robotech/kacho-workspace#113"
category: kac
status: in-progress
type: fix
repos:
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - kacho-iam
tags:
  - kac
  - fix
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - kacho-iam
  - cross-service
  - security
---

# Cross-service ARM_LABELS revoke on label change (T3.1 / #113)

> [!note] Трек
> GitHub issue `PRO-Robotech/kacho-workspace#113` (bug). Закрытие долга эпика T3-D4 «Resource-scoped AccessBinding selectors». Acceptance ✅ APPROVED (`acceptance-reviewer` раунд 2, 2026-06-23): `docs/specs/sub-phase-T3.1-cross-service-label-revoke-acceptance.md`. Найдено живым прогоном на fe3455.

**Status**: 🔧 in-progress — **T3.1 4 PR замержены в main** (vpc `47d707d`, compute `4a0b010`, nlb `3cf783e`, iam `3ecf7ec`); параллельно #211 замержен (iam `299bbbb`). Остаётся: kacho-deploy newman e2e (в работе), #212-фикс (в работе), deploy fe3455, vault post-merge trail.
**Type**: fix (cross-repo)

## Что и зачем

Consumer-сервисы (vpc/compute/nlb) эмитят `InternalIAMService.RegisterResource` (mirror.upsert) в iam **только на CREATE**, не на label-UPDATE → iam `resource_mirror` протухает → rsab reconciler не ревокает ARM_LABELS-грант при снятии/смене метки. Same-service (iam.account/project) ре-эволюционируют на своём Update-пути → разрыв ТОЛЬКО cross-service.

## Gap-матрица (баг шире issue — найдено acceptance-author + ревьюером, код-сверено)

- **vpc.network** — Update не эмитит.
- **vpc.securityGroup** — ДВОЙНОЙ баг: Create эмитит bare-tuple БЕЗ labels (`securitygroup/create.go:195`) + Update не эмитит.
- **compute.disk/image/snapshot** — Update не эмитит (instance — корректен).
- **nlb.listener** — ДВОЙНОЙ баг: Create без labels (`listener/create.go:488 listenerRegisterIntent`) + Update не эмитит (LB/TG — корректны).
- **iam** — прод-кода НЕ требует (rsab `applyDiff` fell-out-loop уже ревокает на mirror.upsert); обязательный новый confirmation-тест T3.1-IAM-01.
- **proto / схема БД** — без изменений.
- Эталон фикса: `subnet/update.go` (`labelsInMask`-gate + `ProjectHierarchyItem(... labels)`); compute `instance_repo.go`; nlb LB/TG.

## Ключевые решения (G-1..G-8)

- G-2: эмит только при labels-в-маске (gated); empty-mask full-PATCH ⇒ эмитить.
- G-3: полное снятие меток → **upsert с пустым labels, НЕ UnregisterResource** (ресурс жив; owner-tuple/containment на той же mirror-строке).
- G-4: intent в той же writer-tx (SEC-D, no dual-write).
- G-8: assignability by-design (account/project/system scope-tier, нет hierarchy-down; bind мис-скоупа → FAILED_PRECONDITION code 9). Причина переписать #211-сюит.

## Затронутые сущности vault

[[../resources/iam-resource-mirror]] [[../edges/vpc-to-iam-fgaproxy]] [[../edges/compute-to-iam-fgaproxy]] [[../edges/nlb-to-iam-fga-register]] [[../resources/vpc-network]] [[../resources/vpc-securitygroup]] [[../resources/nlb-listener]]

## DoD

- [x] acceptance APPROVED (раунд 2)
- [x] KAC-trail
- [x] kacho-vpc: network Update + SG Create+Update emit + integration RED→GREEN (PR [kacho-vpc#164](https://github.com/PRO-Robotech/kacho-vpc/pull/164); CI green кроме non-blocking trivy; **db-architect ✅**) — *awaiting merge*
- [x] kacho-compute: disk/image/snapshot Update emit + integration (PR [kacho-compute#62](https://github.com/PRO-Robotech/kacho-compute/pull/62), RED→GREEN; Create-эмит уже нёс labels — bare-create-бага у compute нет; by-design §9.1; **db-architect ✅**) — *awaiting merge*
- [x] kacho-nlb: listener Create+Update emit + integration (PR [kacho-nlb#39](https://github.com/PRO-Robotech/kacho-nlb/pull/39); double-bug закрыт; **db-architect ✅**) — *awaiting merge*
- [x] kacho-iam: T3.1-IAM-01 + G3-01 confirmation tests (test-only PR [kacho-iam#213](https://github.com/PRO-Robotech/kacho-iam/pull/213), GREEN — подтверждает G-6, iam revoke корректен) — *awaiting merge*
- [x] newman e2e label-revoke-{vpc,compute} + invite-coupled — PR [kacho-iam#214] merged (iam main `c7bb0605`), **GREEN в umbrella-CI**; nlb known-RED ([kacho-iam#217] — e2e блокирован umbrella nlb external-address provisioning; механика покрыта `TestListenerRepo_T31Revoke04`)
- [x] deploy реального main-образа на fe3455 (rev27/28; helm rev44; vpc/compute/nlb/iam/ui на исправленных main)
- [x] остаточный gap route/address/gateway/NIC → GitHub Issue [kacho-vpc#165](https://github.com/PRO-Robotech/kacho-vpc/issues/165)
- [ ] vault trail после merge (edges History + resource-mirror lifecycle)

## Сопутствующее (всплыло на live-прогоне fe3455)

- **grant-форма subjects[] 400** — UI слал `subjects[].type:"user"` (lowercase) при enum-поле → gateway ронял в UNSPECIFIED → `subject_type ""`. Фикс UI (enum-имя `SUBJECT_TYPE_USER`) — kacho-ui#113 merged + deployed (ui `27791bb`, rev28). Бэкенд/proto корректны.
- **«over-grant по меткам»** (binding `acb4bfp6pvs392sf799y`) — **НЕ баг, by-design**: ARM_LABELS эмитит строго per-object (доказано: FGA ListObjects 2/2/2, foreign→DENY, admin→DENY). «Видит всё» = subject — owner отдельного account'а → owner→viewer каскад показывает его собственные ресурсы. Опц.: UI-разделение «binding-grant vs own-resources».
- **#212 project-scoped role** — proto [kacho-proto#81] merged (`project_id`); iam [#216] backend готов, НО (a) C22 integration-регрессия чинится; (b) публичный путь требует gateway scope_extractor — follow-up [kacho-api-gateway#96]. T-E4 остаётся known-RED до #96.

**Review-gate (2026-06-23):** 3 db-architect-reviewer ✅ (vpc/compute/nlb tx-emit G-2/G-3/G-4 + source_version-монотонность); iam test-only. CI зелёный кроме `trivy` (строчный) — pre-existing CVE общей зависимости на ВСЕХ 4 PR, branch-protection не требует чеков → не блокирует. Все 4 PR merge-ready, держатся до go-ahead владельца.

## Связанные

- [[sub-phase-1.5-assignable-roles]] — assignability-предикат (G-8 база)
- #211 (iam invite/grant FGA) — newman-rework отдельным test-only KAC; kacho-iam#212 (project-scoped role unreachable)

#kac #fix #cross-service #kacho-vpc #kacho-compute #kacho-nlb #kacho-iam
