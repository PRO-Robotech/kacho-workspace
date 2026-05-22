---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.FederationExchangeService/Exchange
  - rpc: kacho.cloud.iam.v1.TrustPolicyService/Create
  - rpc: kacho.cloud.iam.v1.TrustPolicyService/Delete
  - rpc: kacho.cloud.iam.v1.TrustPolicyService/Get
  - rpc: kacho.cloud.iam.v1.TrustPolicyService/List
  - rpc: kacho.cloud.iam.v1.TrustPolicyService/Update
status: implemented
source_sha: ""
---

# Workload federation

Федерация workload-identity: внешний CI/cloud-провайдер (GitHub Actions, AWS,
GCP, …) обменивает свой OIDC-токен на kacho-токен по доверенной политике, без
статичных секретов. `FederationExchangeService` — сам обмен (RFC 8693),
`TrustPolicyService` — CRUD trust-policy.

## Зачем

Хранить долгоживущий SA-secret в CI — антипаттерн (утечка = компрометация). С
федерацией CI предъявляет короткоживущий OIDC-токен своей платформы, kacho-iam
верифицирует его против trust-policy и выдаёт собственный bound-токен. Секретов
в пайплайне нет.

## Контракт

**`FederationExchangeService`** (public, internet-reachable):
- `Exchange` — sync; RFC 8693 token-exchange: внешний JWT → kacho
  bound-access-token.

**`TrustPolicyService`** (internal 9091 — §Запрет #6): CRUD federation
trust-policies:
- `Create` / `Update` / `Delete` — async (`Operation`); `Get` / `List` — sync.
- Политика: `service_account_id`, `issuer`, `subject_pattern` (RE2-regex),
  `audience`, `max_token_ttl` (DB-CHECK ≤15min), опц. `additional_claims_filter`,
  `condition_id`, обязательный `expires_at`.

## Lifecycle

Поток `Exchange`: распарсить внешний JWT → резолвить JWKS issuer'а →
проверить подпись → найти `trust_policy WHERE issuer=$iss AND enabled` →
сматчить `sub` против `subject_pattern` → применить claims-filter + linked
condition → проверить `audience` → подписать kacho-токен с TTL ≤
`max_token_ttl`, subject = `service_account_id`.

## Gotchas

- `subject_pattern` — RE2-regex **без `*`-wildcard** (защита от
  confused-deputy: широкий паттерн пускает чужой workload).
- `max_token_ttl` DB-CHECK ≤ 900s; `issuer` / `subject_pattern` immutable
  (менять — пересоздавать политику).
- Class A (static client_credentials) — **не** через Exchange, через
  SA-keys (`l2-service-accounts`).
- Issuer JWKS недоступен → fail-closed (`Unavailable`).
