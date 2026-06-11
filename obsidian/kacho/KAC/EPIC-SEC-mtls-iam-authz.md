---
title: "[EPIC] SEC — mTLS + IAM-fronted authz + least-privilege identities"
ticket_id: EPIC-SEC
status: in-progress
type: epic
repos:
  - kacho-proto
  - kacho-corelib
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - kacho-api-gateway
  - kacho-deploy
  - kacho-vpc-operator
opened: 2026-06-11
tags:
  - kac
  - epic
  - kacho-iam
  - kacho-corelib
  - architecture
  - security
---

# [EPIC] SEC — mTLS + IAM-fronted authz + least-privilege identities

> YouTrack-номер присвоить (MCP youtrack). Пока trail-ID `EPIC-SEC`.

## Что и зачем

Заказчик (2026-06-11): (1) mTLS на все компоненты как opt-in; (2) PKI через cert-manager
(k8s); (3) каждый внешний запрос аутентифицируется (JWT) + авторизуется (IAM), внутренние
компоненты — напрямую, но под mTLS; (4) персональные service-identity с least-privilege
ролями; (5) собрать стенд (сервисы + операторы + kube-ovn) на mTLS, два раздельных
сертификата — client и server; (6) модули не ходят в FGA напрямую — только через IAM,
FGA закрыт ролёвкой; (7) JWT сохраняется; (8) контракты не меняются, кроме работы с FGA.

Дизайн-документ: `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`.

## Точка отсчёта (разведка)

- JWT (#7) и `InternalIAMService.Check` (#3) — уже есть (api-gateway + corelib authz).
- Прямой FGA (нарушение #6): `kacho-vpc`/`kacho-compute` `clients/openfga_write_client.go`
  + `fgawrite.Emit` (best-effort после commit — dual-write баг, N5).
- mTLS — нет (corelib insecure); cert-manager-config subchart готов (server+client usages).

## Декомпозиция (топосортировка)

- **SEC-A** kacho-proto — Internal IAM FGA-proxy RPC (Register/UnregisterResource).
- **SEC-B** kacho-corelib — mTLS creds grpcsrv/grpcclient + config + cert→identity.
- **SEC-C** kacho-iam — FGA-proxy через fga_outbox+drainer + least-priv SA-роли + cert→SA.
- **SEC-D** kacho-vpc/compute/nlb — убрать прямой FGA → outbox-intent→IAM + mTLS.
- **SEC-E** kacho-api-gateway — mTLS backend-dial, JWT сохранить.
- **SEC-F** kacho-deploy — cert-manager internal CA + per-svc Certificate ×2 + SA + NetworkPolicy.
- **SEC-G** kacho-vpc-operator + deploy — operator/OVN на mTLS, least-priv SA оператора.

## Ключевые решения (design-review 2026-06-11, CHANGES REQUESTED → внесено)

- **FGA dual-write → transactional-outbox (Вариант A)**: intent в writer-tx ресурса,
  drainer→`IAM.RegisterResource` (идемпотентно, eventual, не теряется). Образец — IAM
  `fga_outbox`+drainer.
- principal-metadata (пользователь) ⟂ mTLS client-cert (модуль) — ортогональны; доверять
  principal ⟺ peer mTLS-verified.
- restart-on-rotate для MVP (Operations персистентны, Watch нет).
- SPIFFE-like SAN-строка сейчас, SPIRE позже.
- per-edge feature-flag (rollback granular); fail-closed Unavailable.
- Ацикличность подтверждена (iam — leaf; vpc⇄compute не семантический цикл).

## Затронутые сущности vault

[[edges/compute-to-vpc-nic-ipam]] · [[edges/vpc-to-compute-zone]] · `* → kacho-iam`
(ProjectService.Get + InternalIAMService.Check + новые fgaproxy-рёбра) ·
[[rpc/iam-internal-iam-service]] (новые Register/UnregisterResource) ·
[[packages/corelib-grpcsrv]] / [[packages/corelib-grpcclient]] (mTLS).

## DoD (эпик)

- mTLS opt-in (enable=false = текущий dev); production — service→service mTLS, раздельные
  client/server cert; anonymous fail-closed; FGA недостижим вне IAM.
- vpc/compute/nlb без прямого FGA (`grep openfga clients/` = 0).
- каждый внутренний компонент — SA с least-priv ролью (audit: нет лишних permission).
- JWT-флоу не изменён; публичные ресурсные контракты не изменены (breaking-diff=0).
- стенд `make dev-up` (mTLS) поднимается: сервисы + vpc-operator + kube-ovn, e2e зелёные.

## Прогресс

- 2026-06-11: дизайн + system-design-review (CHANGES→внесено, dual-write→outbox).
- 2026-06-11: **acceptance-фаза завершена — 7/7 APPROVED** (acceptance-author→reviewer).
  v1: B/D/E APPROVED, A/C/F/G CHANGES (ground-truth: ReBAC vs flat-caps, 4-сегментные
  permission, SPIRE-SAN, exempt-fgaproxy, тест-харнесс). Решения внесены в эпик §4.1.
  v2: A/C/F APPROVED; G — 1 блокер (namespace SAN). v3: G APPROVED (вариант B,
  `ns/kacho-vpc-operator`). Acceptance-доки: `docs/specs/sub-phase-SEC-{A..G}-*-acceptance.md`.
- **Волна 1 реализована (APPROVED, на ветках, не в main):**
  - SEC-A — `kacho-proto` ветка `SEC-A-proto-fga-proxy` (commit `489326c`): Internal
    RegisterResource/UnregisterResource (exempt, идемпотентны), gen регенерён, buf-гейты
    зелёные, public breaking-diff=0, conformance-тесты RED→GREEN. proto-api-reviewer: APPROVED.
  - SEC-B — `kacho-corelib` ветка `SEC-B-corelib-mtls` (commits `eb8dede`+`08e2d79`):
    opt-in mTLS в grpcsrv/grpcclient + TLSServer/TLSClient value-структуры (per-edge,
    LoadPrefixed) + cert→identity (SPIFFE-SAN) + trust-инвариант; 19 сценариев + SEC-B-16
    defense-in-depth GREEN (`go test -race`). go-style-reviewer: APPROVED.
- **Волна 1 в main**: kacho-proto `caa1d47`, kacho-corelib `f886a40` (смёржено, запушено).
- **Волна 2 (SEC-C) в main**: kacho-iam `1981a21` — FGA-proxy RegisterResource/Unregister
  (sync, exempt) через fga_outbox+drainer (идемпотентно, fail-safe A-07/A-08), ReBAC-гейт
  fga_writer@iam_fgaproxy:system (Unavailable vs PermissionDenied), least-priv SA-роли seed
  (миграция 0009), cert→SA mapping (SPIFFE-SAN). db+go+system-design APPROVED; go test -race зелёный.
- **Режим**: автономная реализация до завершения эпика. Следующие волны: 3 (D vpc/compute/nlb
  + E api-gateway) → 4 (F deploy PKI) → 5 (G операторы/OVN) → финал (верификация операторов
  + док cert→role mapping).

## Связанные

GitHub Issue N5 (best-effort dual-write FGA) — завести в kacho-vpc + kacho-compute,
закрыть в SEC-D.
