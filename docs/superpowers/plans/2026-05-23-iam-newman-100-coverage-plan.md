# План: iam — 100% покрытие newman + зелёный CI

**Дата:** 2026-05-23
**Триггер:** на `main` упал `newman-e2e` (run `26332687259`, 87 failed
assertions в 6 collections); параллельно — обнаружен пробел покрытия
(10 из 22 gRPC-сервисов имеют newman-кейсы, 12 — ноль).

## Текущая картина (диагностика)

### Что упало на `main` (PR #30 KAC-135 merge)

| Collection | Статус | Failed | Размер (requests / assertions) |
|---|---|---|---|
| authz-deny | ❌ | 1 | — |
| iam-access-binding | ❌ | 8 | 34 / 72 |
| iam-account | ✅ | 0 | 48 / 101 |
| iam-compliance-report | ❌ | 10 | 19 / 45 |
| iam-group | ✅ | 0 | 46 / 85 |
| iam-internal-only-check | ❌ | 10 | 14 / 22 |
| iam-jit-pending | ❌ | 33 | 23 / 45 |
| iam-project | ✅ | 0 | 56 / 101 |
| iam-role | ✅ | 0 | 38 / 68 |
| iam-service-account | ✅ | 0 | 35 / 71 |
| iam-user | ❌ | 25 | 29 / 57 |
| authz-sa-apitoken | ✅ | 0 | — |

**Прочие CI-задачи** на этом коммите main — зелёные (ci, integration,
docker-build, security-scan, govulncheck, gosec, trivy). Падение
исключительно в `newman-e2e`.

### Покрытие RPC-surface — 113 entry-points, 22 сервиса (по archgraph)

**Есть newman-кейс (10 сервисов):** AccessBinding, Account, ComplianceReport,
Group, ServiceAccount, Project, Role, User, JitPending, InternalIAM (только
Check — 1 из 7 методов).

**НЕТ newman-кейса вовсе (13 сервисов):**

| Сервис | RPC | Замечание |
|---|---|---|
| AccessReviewService | 7 | access-reviews / certification |
| AuthorizeService | 5 | публичный Check/BatchCheck/Expand/ListObjects/ListSubjects |
| ConditionsService | 6 | IAM-conditions CRUD + Evaluate |
| FederationExchangeService | 1 | exchange external token → kacho |
| GdprErasureService | 4 | GDPR erasure requests |
| InternalAuthorizeService | 5 | FGA store admin |
| InternalBreakGlassService | 6 | emergency access flow |
| InternalUserService | 3 | internal user lookup |
| JITEligibilityService | 5 | JIT eligibility (НЕ путать с JitPending) |
| OpaBundleService | 3 | OPA bundles |
| SAKeyService | 3 | service-account keys |
| TrustPolicyService | 5 | federation trust policy CRUD |
| InternalIAM (остаток) | 6 | помимо Check — Initialize/SyncFGA/… |

Итого **57 RPC** (50%+) с нулевым newman-покрытием.

## Цель

1. CI `newman-e2e` зелёный на `main` (0 failed assertions).
2. Каждый из 113 RPC iam покрыт минимум одним happy-path и одним
   negative-кейсом (NotFound / FailedPrecondition / InvalidArgument /
   Unauthenticated, в зависимости от семантики).
3. Каждый сервис имеет declarative case-файл `tests/newman/cases/iam-<svc>.py`,
   из которого `gen.py` генерит `tests/newman/collections/iam-<svc>.postman_collection.json`.

## Фазы

### Фаза 1 — Починить упавшие assertions (87, 6 collections)

**Цель:** локально воспроизвести каждое падение, root-cause, фикс
*(в коде или в кейсе — по факту)*. Test-first: до правки кейса
подтвердить, что бэкенд возвращает то, что должен по контракту, иначе фикс
в коде.

#### 1.1. Поднять локальный стенд + воспроизвести
- `cd project/kacho-deploy && make dev-up`
- `cd project/kacho-iam/tests/newman && ./scripts/run.sh <suite>` для
  каждого failing-набора. Сохранить JSON-репорты.

#### 1.2. Триаж по типам отказа (вероятная классификация)
- **Schema drift** — Phase 6–8 (KAC-127 / KAC-133 / KAC-135) добавили
  поля во ResponseMessage, assertions проверяют exact-shape. Fix:
  ослабить `pm.expect(body).to.eql(...)` → field-pick где надо;
  обновить fixture-объекты.
- **Async LRO timing** — Operation-poll-loop в gen.py с фиксированным
  числом ретраев. Phase 7/8 ввели медленнее воркеров → bump retry-count
  в LRO helper.
- **Authz regression** — KAC-127 ужесточил default-deny. Кейсы, которые
  раньше прокидывали admin-token, теперь упираются в FGA Check.
  Fix: посеять FGA-tuples в fixture (`crud-fixture/`).
- **Removed/renamed endpoints** — Phase 7b раcщепил `JitPending` /
  переименовал. 33 fail в `iam-jit-pending` — кандидат №1.

Per-collection: `iam-jit-pending` (33), `iam-user` (25), `iam-compliance-report`
(10), `iam-internal-only-check` (10), `iam-access-binding` (8), `authz-deny` (1).
Начинать с самого крупного — там вероятнее одна root-cause тянет много assertions.

**DoD фазы 1:** `./scripts/run.sh all` локально зелёный. Push в branch
`fix/iam-newman-main` (или KAC-N), PR, CI зелёный.

### Фаза 2 — Закрыть coverage-gap: 13 новых case-файлов

Per service — новый `tests/newman/cases/iam-<svc>.py` с CASES, через
`gen.py` → collection, добавить в `newman-e2e.yml` matrix.

**Приоритет (по риску):**

1. **InternalIAMService (остаток 6 методов)** — критично, vpc/compute зовут;
   расширить `iam-internal-only-check.py`.
2. **AuthorizeService** — главная публичная authz-поверхность.
3. **InternalAuthorizeService** — FGA store admin (read/write tuples).
4. **InternalBreakGlassService** — security-критично.
5. **TrustPolicyService** + **FederationExchangeService** — federation flow.
6. **SAKeyService** — SA keys (часть SA жизненного цикла).
7. **ConditionsService** — IAM-conditions CRUD.
8. **AccessReviewService** — access reviews.
9. **JITEligibilityService** — JIT eligibility.
10. **GdprErasureService** — GDPR.
11. **OpaBundleService** — OPA bundles.
12. **InternalUserService** — internal user lookup.

**На каждый сервис** в case-файле:
- Setup: создать предусловия (account/project/user через corresponding `iam-*`
  use-case, либо через `crud-fixture/seed`).
- Per RPC из L2-якорей (см. `kacho-iam/docs/arch/_l1-kacho-iam.md` →
  «Контракт»): **happy-path** + **negative** (минимум одна).
- Teardown: idempotent (повторный прогон не должен сломаться).
- Декларативный стиль `Case(...)` как в существующих файлах. Подсмотри
  `iam-account.py` (большой, 6 RPC × ~8 кейсов = 48 requests) как эталон.

**Оценка объёма:**
- 57 непокрытых RPC × ~3 newman-request на RPC (happy + negative + LRO-poll
  для async) ≈ **~170 новых requests**.
- На существующие 10 collections — также пройти ревью и дописать missing
  RPC (Account=6 RPC vs 48 reqs/8 на RPC ✓; но напр. ComplianceReport=4 RPC vs
  19 reqs — нормально; нужно сверить каждый).

### Фаза 3 — Сверка покрытия с inventory archgraph (gate)

Скрипт `tests/newman/scripts/coverage.py`:
- Парсит `archgraph arch-audit` (entry-points list).
- Парсит collections (URL → RPC FQN).
- На выходе таблица: RPC → есть кейс / нет.
- В CI: `coverage.py --min 100` падает, если есть RPC без кейса.

Это и есть «100% покрытие» — детерминируемый машинный гейт. Без него
любой новый RPC сразу даёт `coverage FAIL`.

### Фаза 4 — Усиление newman-e2e CI gate

Сейчас `assert authz suites green` — единственный финальный assert. Расширить:
- Запускать ВСЕ collections в matrix (не только authz-deny / authz-sa-apitoken).
- Каждый — собственный job (parallel).
- Final-step: aggregate summary, fail если любая FAILED > 0.
- Добавить `coverage.py` гейт из фазы 3.

### Фаза 5 — Регрессионная гигиена

- **Pre-commit / pre-push hook**: `gen.py` + `newman run` локально на
  изменённых case-файлах.
- **Per-PR**: newman-e2e обязателен (required check).
- **schema-drift guard**: при изменении `.proto` для iam — `gen.py` должен
  ругнуться, если кейс ссылается на удалённое поле. Это вне scope первой
  итерации; на будущее.

## Структура артефактов

| Где | Что |
|---|---|
| `tests/newman/cases/iam-<svc>.py` | декларативные `CASES` per сервис (13 новых + дописать 10 существующих) |
| `tests/newman/collections/` | `gen.py` пересоберёт |
| `tests/newman/scripts/coverage.py` | новый gate |
| `.github/workflows/newman-e2e.yml` | расширить matrix + coverage-gate |
| `docs/specs/sub-phase-4.1-iam-newman-coverage-acceptance.md` | GWT acceptance (по регламенту kacho, если кодинг бэкенда понадобится для фиксов фазы 1) |

## Оценка

| Фаза | Объём | Срок |
|---|---|---|
| 1 — фикс 87 fail | ~6 collections, средний фикс — 1–2 часа на root-cause + правка | 1–2 дня |
| 2 — 13 новых case-файлов | ~170 requests + setup/teardown | 3–5 дней |
| 2.5 — дополнить 10 существующих до полного покрытия их сервисов | ~30 requests | 1 день |
| 3 — coverage.py + matrix | один скрипт + workflow tweak | 0.5 дня |
| 4 — newman-e2e расширение | yml + assertions | 0.5 дня |
| 5 — гигиена | hooks | в фоне |

Полный цикл: **~7–10 дней** focused work; критичный путь — фаза 1 (CI
зелёный) → фаза 3 (coverage gate) → фаза 2 (закрыть пробел).

## Definition of Done

- [ ] `newman-e2e` на `main` зелёный (все assertions = OK).
- [ ] Все 113 entry-points iam имеют ≥1 happy + ≥1 negative newman-кейс.
- [ ] `coverage.py` в CI: 113/113 покрыто.
- [ ] `newman-e2e.yml` matrix запускает все 22+ collections.
- [ ] Документация: `tests/newman/README.md` обновлён с правилами per-service.

## Открытые вопросы

1. Phase 7/8 фикстуры FGA — где seed (`crud-fixture/`)? Нужно обновить под
   новый bootstrap.
2. Какие сервисы с 0 покрытием — public vs internal-only по `visibility`?
   Internal-only (как `InternalIAMService`) тестируются на cluster-internal
   endpoint, не через api-gateway TLS. Newman-e2e нужно проверить, что
   internal-host доступен в kind+helm umbrella.
3. KAC-ticket для эпика — заводим (сейчас YT-индексация рассинхрон)? Можно
   tracking issue в `PRO-Robotech/kacho-iam` с label `epic`.
