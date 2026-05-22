---
level: container
repo: kacho-iam
---

# kacho-iam — приклад

`kacho-iam` — сервис идентификации и авторизации платформы Kachō. Канонический
владелец доменных ресурсов **Account / Project / User / ServiceAccount / Group /
Role / AccessBinding** (заменил упразднённый `kacho-resource-manager` в KAC-124 —
старые `Organization / Cloud / Folder` сняты, проекты-пакеты
`resourcemanager.v1` / `organizationmanager.v1` удалены). Сверх базовой
identity-модели сервис несёт весь governance-стек: REBAC-авторизацию (Zanzibar /
OpenFGA Check + Expand), reusable CEL-conditions, периодические access-reviews,
compliance-отчётность, GDPR-erasure pipeline, JIT/PIM-elevation, two-person
break-glass, workload-федерацию (RFC 8693 token-exchange + trust-policies) и
раздачу подписанных OPA-bundle'ов.

## Зона ответственности

- **Identity** — кто есть в системе: `User` (зеркало внешнего IdP, пишется только
  через `InternalUserService`), `ServiceAccount` (workload-identity) и его
  static-credentials (`SAKeyService` / OAuth-clients).
- **Tenancy** — `Account` (биллинг/owner-граница) и `Project` (рабочая
  область внутри account; на неё ссылаются `kacho-vpc` / `kacho-compute` вместо
  старого `folder_id`).
- **Authorization** — `Role` (набор permission'ов), `AccessBinding`
  (subject × role × resource), `Group` (агрегация subjects). Решение
  «можно/нельзя» считается REBAC-движком (OpenFGA) с CEL-conditions-overlay и
  OPA cluster-deny-gate.
- **Governance / compliance** — access-reviews (квартальная рецертификация),
  compliance-reports, GDPR Art.17 erasure, JIT-elevation (PIM), break-glass
  (аварийный доступ под 2-person approve).
- **Federation** — обмен внешних OIDC-токенов (GitHub Actions, AWS, GCP, …) на
  kacho-токены по trust-policy.

Все мутации возвращают `operation.Operation` (async LRO); чтения синхронны.
Инфра-чувствительные / admin-операции вынесены в `Internal*`-сервисы на
internal-listener (port 9091) и не публикуются на external TLS.

## Контракт — 22 gRPC-сервиса

| Сервис | Назначение |
|---|---|
| `AccountService` | CRUD биллинг-аккаунтов |
| `ProjectService` | CRUD проектов + cross-account `Move` |
| `UserService` | read-only справочник пользователей + `Invite` |
| `InternalUserService` | upsert User из внешней identity (OIDC-callback) |
| `ServiceAccountService` | CRUD workload-identity |
| `SAKeyService` | issue/list/revoke static SA-credentials |
| `GroupService` | CRUD групп + членство |
| `RoleService` | CRUD ролей (system + custom) |
| `AccessBindingService` | grant/revoke доступа (subject×role×resource) |
| `AuthorizeService` | REBAC Check / BatchCheck / Expand / List* |
| `InternalAuthorizeService` | write-path FGA-tuple'ов + model/Rego lifecycle |
| `InternalIAMService` | per-RPC authz-gate `Check` для vpc/compute + subject lookup |
| `ConditionsService` | CRUD reusable CEL-conditions + sandbox `Evaluate` |
| `AccessReviewService` | квартальная рецертификация доступов |
| `ComplianceReportService` | генерация и выдача compliance-отчётов |
| `GdprErasureService` | GDPR Art.17 right-to-erasure pipeline |
| `JITEligibilityService` | CRUD eligibility-правил для JIT/PIM |
| `JitPendingService` | approve/deny pending JIT-активаций |
| `InternalBreakGlassService` | аварийный доступ под two-person approve |
| `FederationExchangeService` | RFC 8693 token-exchange (внешний JWT → kacho-токен) |
| `TrustPolicyService` | CRUD federation trust-policies |
| `OpaBundleService` | раздача подписанных OPA policy-bundle'ов |

Плюс общий `kacho.cloud.operation.OperationService` (`Get` / `Cancel`) для
поллинга async-операций.

**Видимость.** Public-listener (9090): Account/Project/User/ServiceAccount/SAKey/
Group/Role/AccessBinding/Authorize/Conditions/AccessReview/ComplianceReport/
GdprErasure/JITEligibility/JitPending/FederationExchange. Internal-listener
(9091, не на external TLS — §Запреты #6): InternalUser/InternalAuthorize/
InternalIAM/InternalBreakGlass/TrustPolicy/OpaBundle.

## Связи

`kacho-iam` — **leaf-owner** в графе доменов: владеет Account/Project, в него
звонят, он сам не зовёт другие kacho-сервисы.

**Кто зовёт kacho-iam:**

- `kacho-vpc → kacho-iam`, `kacho-compute → kacho-iam` — `ProjectService.Get`
  (валидация `project_id` на request-path) + `InternalIAMService.Check`
  (per-RPC authorization-gate перед мутацией ресурса).
- `kacho-api-gateway → kacho-iam` — `AuthorizeService.Check` / `BatchCheck`
  (per-request authz-interceptor), `InternalIAMService.LookupSubject` (резолв
  JWT → principal), `InternalUserService.UpsertFromIdentity` (OIDC-callback).
- OPA-sidecar'ы сервисов → `OpaBundleService` (polling подписанных bundle'ов).
- Внешние CI-провайдеры (GitHub Actions / AWS / GCP / …) → `FederationExchangeService.Exchange`.

**Внешние зависимости kacho-iam** (не kacho-сервисы): внешний IdP (OIDC) —
источник истины для `User`; OpenFGA — store relation-tuple'ов; OPA — cluster-deny
policy-engine. Эти рёбра — runtime, не build-зависимости.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Проект: [[_l0-kacho]]
- ↓ Функциональность: [[l2-access-bindings]]
- ↓ Функциональность: [[l2-access-reviews]]
- ↓ Функциональность: [[l2-account-lifecycle]]
- ↓ Функциональность: [[l2-authorization]]
- ↓ Функциональность: [[l2-break-glass]]
- ↓ Функциональность: [[l2-compliance-reporting]]
- ↓ Функциональность: [[l2-gdpr-erasure]]
- ↓ Функциональность: [[l2-group-management]]
- ↓ Функциональность: [[l2-iam-conditions]]
- ↓ Функциональность: [[l2-jit-elevation]]
- ↓ Функциональность: [[l2-opa-bundles]]
- ↓ Функциональность: [[l2-operations]]
- ↓ Функциональность: [[l2-project-lifecycle]]
- ↓ Функциональность: [[l2-role-model]]
- ↓ Функциональность: [[l2-service-accounts]]
- ↓ Функциональность: [[l2-user-management]]
- ↓ Функциональность: [[l2-workload-federation]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
