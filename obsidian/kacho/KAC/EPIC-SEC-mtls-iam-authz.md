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
- **Волна 3 (SEC-D + SEC-E) в main**: kacho-compute `922ac5a`, kacho-api-gateway `e82f363`,
  kacho-vpc `8c0d97d` (+ pre-existing compilation-fix addresspool↔proto KAC-269); kacho-nlb —
  финальный testcontainers-прогон перед мёржем (race в listener устранён; падал лишь default
  10m-таймаут пакета repo/pg — инфра, не баг → перезапуск с -timeout 30m). Прямой FGA убран
  из vpc/compute/nlb (outbox-intent→IAM.RegisterResource), opt-in mTLS per-edge, Issue N5 closed.
- **Волна 4 (SEC-F)**: kacho-deploy cert-manager internal CA + per-svc Certificate ×2 +
  helm mTLS-профиль + FGA NetworkPolicy — реализация идёт.
- **Волна 3 закрыта в main**: compute `922ac5a`, api-gateway `e82f363`, vpc `8c0d97d`, nlb `444c1a5`.
- **Волна 4 (SEC-F) в main**: kacho-deploy `837a9d3`, vpc `53ce6d5`, compute `d4a90ea`,
  nlb `5602169`, api-gateway `b426a7a` — cert-manager internal CA (selfSigned→CA-root→ca-issuer,
  переиспользован kacho-selfsigned) + per-svc Certificate ×2 (server DNS-SAN = реальные Service-имена;
  client URI-SAN = spiffe://kacho.cloud/ns/kacho/sa/<sa>) + per-edge mTLS env/mount в сервисных
  чартах + umbrella mtls.* overlay + FGA NetworkPolicy (openfga←iam, безопасна после SEC-D).
  65 helm-assertions зелёные, dev zero-regression. system-design APPROVED.
- **Режим**: автономно. Осталось: волна 5 (SEC-G операторы/OVN на mTLS) → финал #45
  (верификация видимости ресурсов операторами + док cert→role mapping и ролевые модели).
- Cleanup-issue (ban#11, не блокер): vestigial OpenFGAEndpoint в kacho-vpc config (не читается после SEC-D).

## Связанные

GitHub Issue N5 (best-effort dual-write FGA) — завести в kacho-vpc + kacho-compute,
закрыть в SEC-D.
