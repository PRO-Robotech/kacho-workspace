---
title: corelib-grpcsrv
category: packages
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - grpc
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/grpcsrv — серверная сборка, личность пира и граница доверия

**Каталог**: `pkg/grpcsrv/` · импорт `github.com/PRO-Robotech/kacho/pkg/grpcsrv`
**Прежде** (полирепо): `kacho-corelib/grpcsrv`.
**Импортирует**: `crypto/tls`, `crypto/x509`, `log/slog`, `google.golang.org/grpc` +
`health`, `health/grpc_health_v1`, `reflection`, `credentials`,
`credentials/insecure`, `keepalive`, `peer`, а также `pkg/operations` (тип личности).
**Импортируют** (`go list` на `96b2879a`, non-test): iam 5 · compute 3 · vpc 2 ·
storage 2 · registry 2 · nlb 2 · geo 2 · gateway 2 · `pkg/auth` 1. То есть **все семь**
сервисов и шлюз — по два потребителя у большинства (композиционный корень плюс
слой проверки).

Сборка gRPC-сервера с обязательным набором: служба здоровья, рефлексия,
восстановление после паники, — плюс всё, что относится к вопросу «кто на том конце
и за кого ему позволено говорить».

## Экспортируемое API (снято с дерева)

```go
func NewServer(opts ...grpc.ServerOption) *grpc.Server
func DefaultKeepaliveEnforcement() keepalive.EnforcementPolicy
const PrincipalTypeServiceAccount = "service_account"
```

### SEC-B — opt-in mTLS server-creds (`tls.go`)

- `TLSServer{Enable, CertFile, KeyFile, ClientCAFiles []string}` — per-edge config (FD-3, нет глобального TLS-синглтона). `enable=false` ⇒ insecure (FD-1, backward-compat).
- `TLSServerCreds(TLSServer) (grpc.ServerOption, error)` — единая точка истины (FD-7). `enable=true` ⇒ server-cert + client-CA + `RequireAndVerifyClientCert` (FD-2). Misconfig (нечитаемый cert / пустой client-CA) ⇒ error, НЕ silent insecure fallback (FD-6). Гард SEC-B-19 (`tls_guard_test.go`): прямой `credentials.NewTLS`/`tls.Config` вне helper'а — RED.

### SEC-B — cert-identity extractor + trust-invariant (`cert_identity.go`)

- `CertIdentity(*x509.Certificate) string` — verbatim opaque SAN `spiffe://kacho.cloud/...` из verified client-cert (FD-5; без parse/resolve в SA — это SEC-C). nil/no-SAN/чужой trust-domain ⇒ `""` (детерминированно); multi-SAN ⇒ первый kacho-spiffe.
- `WithCertIdentity` / `CertIdentityFromContext(ctx) (id string, verified bool)` — носитель cert-identity + mTLS-verified флага.
- `UnaryCertIdentityExtract()` / `StreamCertIdentityExtract()` — классифицируют peer (insecure / TLS-no-verified-cert / mTLS-verified) и кладут cert-identity в ctx. Ставить ПЕРЕД principal-extract.
- `UnaryTrustedPrincipalExtract(opts...)` / `StreamTrustedPrincipalExtract(opts...)` + `TrustedPrincipalFromContext(ctx) (operations.Principal, bool)` — инвариант доверия (FD-4): principal-metadata доверяется ⟺ peer mTLS-verified; TLS-без-verified-cert ⇒ principal отбрасывается. cert-identity (модуль) и principal (пользователь) — ортогональны, оба доступны downstream для аудита.
- `WithTrustedForwarders(sans ...string)` — allow-list SAN'ов, которым разрешено **говорить за пользователя**.

> [!important] mTLS-verified — это НЕ «кто», а «предъявил сертификат нашего CA»
> Одной trust-aware пары **недостаточно**, и это главная ловушка узла: `principalIsTrusted`
> сверяет пира со списком **только если список непуст**. Пустой список означает
> **«не сужаем»**, а не «запрещаем».
>
> Отсюда — требование из **четырёх** частей (пара извлечения · непустой круг из конфигурации ·
> boot-guard, отказывающий в старте · измерение в самоотчёте, которое оценивает гейт посадки),
> все вместе, любые три без четвёртой дают контроль, который не работает или которого не видно.
>
> **Полная формулировка, разбор двух подклассов и правило «круг пинится по фактическим
> отправителям» — `security.md` §«AuthN+AuthZ ВЕЗДЕ», п. 5. Он канон; здесь не пересказ,
> а ссылка** — предмет уже один раз разъехался между этими двумя местами (2026-07-27:
> правило обобщили, записку дополнили), и повторять это не нужно.

### sub-phase 5.4 — acr carrier (`acr.go` + `cert_identity.go`)

- `MDKeyTokenACR = "x-kacho-token-acr"` — trusted metadata-ключ с validated JWT `acr` (api-gateway forwards на mTLS-verified gateway→iam re-dial, рядом с `x-kacho-principal-*`).
- `UnaryTrustedPrincipalExtract` доп. читает `acr` и кладёт в trusted-carrier **только когда trusted** (тот же FD-4 boundary): на untrusted/unverified peer `acr` отбрасывается вместе с principal (anti-spoof). `acr` едет по той же границе, что и личность, — иначе шаг-ап подделывался бы отдельно от того, за кого говорят.
- `TrustedACRFromContext(ctx) (acr string, trusted bool)` — accessor. `WithTrustedACR(ctx, acr, trusted)` — test-support helper (mirror `WithCertIdentity`).
- `ACRRank(acr) int` (`""/"0"<"1"<"2"<"3"`, неизвестное ⇒ 0) + `ACRSatisfies(presented, required) bool` (`required==""/"0"` ⇒ пропуск) — **единая** точка ранжирования, общая для гейта повышения уровня на крае и порога в iam, чтобы две стороны не разъехались.
- `EvaluateStepUp(in StepUpInput) StepUpVerdict` (+ типы `StepUpInput`/`StepUpVerdict`) — само правило повышения уровня, вынесенное в фундамент отдельно от места применения. Прежней редакции записки эта тройка известна не была.

### Извлечение личности без привязки к доверию (`principal_extract.go`)

- `UnaryPrincipalExtract(opts...)` / `StreamPrincipalExtract(opts...)` +
  `WithPrincipalDebug(bool)` / `WithPrincipalDebugLogger(*slog.Logger)`;
  `WithTrustedPrincipal(ctx, p, trusted)` — вспомогательная установка для проб.
- Ключи метаданных: `MDKeyPrincipalType`, `MDKeyPrincipalID`, `MDKeyPrincipalDisplay`
  (их же реэкспортирует [[corelib-auth]], чтобы вызывающему не тащить весь этот пакет
  ради трёх строк).

Это **не** trust-aware пара: у `*PrincipalExtract` нет требования проверенного
сертификата. На развёрнутом сервисе принимать переданную личность полагается
**только** парой `*CertIdentityExtract` → `*TrustedPrincipalExtract`.

## Конвенция

- Каждый сервис в `cmd/<svc>/main.go` зовёт `grpcsrv.NewServer(...)` для public-listener (9090) и отдельно для internal-listener (9091).
- Interceptor chain (UnaryInterceptor) дополняется в самом сервисе: `recovery`, `logging`, `validate`, `auth`. Порядок на **обоих** листенерах: `UnaryCertIdentityExtract` → `UnaryTrustedPrincipalExtract(WithTrustedForwarders(...))` → authz-Check → бизнес. Internal (:9091) от authz **не освобождён**.
- `enable=false` (insecure-транспорт) — состояние периода внедрения SEC-B, а **не** режим эксплуатации: любой развёрнутый стенд, включая локальный, работает в production-posture (core rule #16). Insecure-путь допустим только в in-process unit/integration-фикстурах, потому что именно он маскирует всё, что этот узел защищает: неверифицированный пир доходит как доверенный форвардер.

## См. также

[[corelib-grpcclient]] [[corelib-config]] [[corelib-auth]] [[corelib-observability]]
(поле самоотчёта о суженном круге отправителей) [[vpc-cmd-vpc]]
[[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-corelib #grpc
