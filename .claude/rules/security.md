# Безопасность: Internal-vs-external + инфра-чувствительные данные

## AuthN+AuthZ ВЕЗДЕ — инвариант (нельзя игнорировать ни при каких условиях)

**Для public И internal листенеров правила ОДИНАКОВЫЕ.** Никаких
неаутентифицированных и неавторизованных запросов — нигде, ни на одном порту:

1. **Транспорт/AuthN** — всегда **mTLS** (service→service, verified client-cert) либо
   **TLS+JWT** (user→edge, validated token). Plaintext/insecure-gRPC в проде запрещён.
   Internal (:9091) **НЕ** освобождён: mTLS обязателен.
2. **AuthZ** — каждый RPC (public и internal) проходит per-RPC **Check**
   (`InternalIAMService.Check` → OpenFGA/ReBAC). Цепочка интерсепторов **обоих**
   листенеров обязана включать authz-Check; internal-листенер с одним mTLS (без
   `authzIntr.Unary()`) — **нарушение инварианта**, фиксится как баг.
3. Internal RPC несёт `permission`/`required_relation` аннотации и они **энфорсятся**
   (а не «инертны, потому что internal доверенный»). Read-RPC гейтить viewer-tier
   (`system_viewer`), мутации — admin-tier.
4. «Internal = trusted, mTLS достаточно» — **запрещённое допущение**. Внутренний
   периметр не доверенный (defense-in-depth против lateral movement).

Это строже, чем ban #6 (про *поверхность* методов) — здесь про **обязательность
authN+authZ на КАЖДОМ запросе обоих листенеров**. Применяется ретроактивно: любой
существующий листенер без authz-Check на internal — приоритетный security-фикс.

## Internal-vs-external (ban #6)

`Internal.*` методы **не публикуются на external TLS endpoint** (`api.kacho.local:443`,
advertised для внешних клиентов). Они живут на cluster-internal listener (:9091) и могут
быть проброшены через api-gateway REST mux **только** на cluster-internal listener (UI,
admin-tooling, port-forward).

Текущие Internal admin-ресурсы (kacho-only, нет на external): `AddressPool`
(`/vpc/v1/addressPools`, kacho-vpc); `Region`/`Zone` (`/compute/v1/regions`, `/compute/v1/zones`, kacho-compute).

**Admin-UI правило**: любой новый RPC для admin-UI, которого нет в публичном API ресурса —
добавлять **только в `Internal*`-сервис** на :9091 и регистрировать через `*InternalAddr`-блок
в `kacho-api-gateway/internal/restmux/mux.go`. Не расширять публичные сервисы под admin-нужды —
это засветит admin-функции на external endpoint. Ответственность за корректную регистрацию —
агент `api-gateway-registrar`.

## Инфра-чувствительные данные — ТОЛЬКО в Internal*-API

Любая информация, раскрытие которой помогает картировать/таргетировать физику и data-plane,
живёт **исключительно** в `Internal*`-API (:9091) — никогда на публичной gRPC/REST-поверхности:

- **placement / физика**: на каком хосте лежит ресурс; инвентарь/ёмкость хостов.
- **underlay / транспорт**: транспортные/маршрутные id хостов, carrier-адреса, туннельные эндпоинты, id VRF/routing-таблиц.
- **wiring**: имена host-интерфейсов, netns, gateway-anchor'ы, id контейнеров на хостах, статусы программирования ядра.
- **числовой инфра-идентификатор** ресурса.

**Публичная поверхность** ресурса показывает только tenant-facing «намерение + результат»:
id, name/labels, привязки (project/network/subnet/instance), выделенный tenant-адрес(а), `status`.
«Как разложено по железу» — только через `Internal*`.

**Две проекции ресурса** (допустимо): публичная (lean, tenant-facing) + internal (full,
с инфра-полями) — отдельный internal-message либо поле «internal-only, не заполняется в
публичных ответах». (Шире и строже, чем ban #6 про *методы* — здесь про *данные*.)

Зачем: defense-in-depth — даже скомпрометированный публичный API не должен раскрыть
физическую топологию/placement (разведка для lateral movement; tenant A не должен вывести
«мой и чужой инстанс на одном железе»).

## AuthN/AuthZ (текущее состояние)

- Per-RPC authz-gate: `InternalIAMService.Check` (vpc/compute читают caller-identity из
  metadata `x-kacho-project-id` / `x-kacho-admin` / `x-kacho-actor`; identity-носитель — `internal/tenant`).
- **dev-mode `anonymous → full access` — упраздняется** (нарушает инвариант выше):
  допустим только в локальных unit/integration-фикстурах, НИКОГДА в развёрнутом
  стенде/проде. Любой деплой — `production-mode` (anonymous fail-closed) + mTLS/JWT.
  Старый back-compat `KACHO_*_AUTH_MODE=dev` на кластере — security-долг под снос.
- Публичный `List<Resource>` обязан фильтровать результат через listauthz (CI-гейт `make audit-list-filter`).
- Реальный AuthN (validated JWT/IAM-token) — приходит с интеграцией IAM; downstream API
  (`tenant.TenantFromCtx`, `AssertProjectOwnership`) не меняется.
