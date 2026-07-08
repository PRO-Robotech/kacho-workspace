# Чистая архитектура + переиспользование

## Clean Architecture (строгое dependency rule)

```
handler ─┐
         ├─→ service/use-case ─→ domain
repo ────┤                       ↑
clients ─┘                       │  (только структуры)
```

`internal/`:
- `domain/` — entities (чистый Go: ТОЛЬКО stdlib + `kacho-proto`). Без pgx/grpc/internal-зависимостей.
- `apps/kacho/api/<resource>/` (use-cases) — бизнес-логика; определяет port-интерфейсы
  (`<Resource>Repo`, `<Peer>Client`); импортирует domain + порты. **Не импортирует transport-слой.**
- `repo/` — adapter: реализует порты, импортирует pgx + domain.
- `clients/` — adapter: реализует порты, импортирует grpc-stubs + domain.
- `handler/` — тонкий transport: parse → use-case → format. **Никакой бизнес-логики.**
- `cmd/<svc>/main.go` — **единственное** место wiring (composition root).
- `internal/tenant/` (или аналог) — нейтральный носитель caller-identity, чтобы use-case
  не зависел от transport (`internal/handler`).

**Запрещено**: `domain`/use-case импортируют pgx/grpc-stubs/sqlc-types; бизнес-логика в
`handler`; глобальные синглтоны (`var globalPool`, `init()`-side-effects) вне `cmd/`.

Тесты по слоям: unit use-case через mock-порты; integration через testcontainers;
e2e через api-gateway. Если service-тест требует Postgres — это утечка adapter в use-case.

Каноничный Go-style ruleset — skill **`evgeniy`** (UseCase pattern, CQRS-порты,
self-validating domain, DTO-таблицы, YAML-config через viper/koanf, отдельный `cmd/migrator`).

## Переиспользование через `kacho-corelib`

Всё горизонтальное (нужное 2+ сервисам) — в `kacho-corelib/<package>/`, не дублировать per-service.
Что там живёт: `ids/`, `errors/`, `config/`, `observability/`, `db/` (pgx pool + transactor),
`grpcsrv/`, `grpcclient/`, `outbox/`, `selector/`, `operations/` (LRO table + Worker + Repo),
`retry/`, `shutdown/`, `backoff/`, `validate/`, `auth/`, `authz/`, `filter/`, `migrations/common/`, `audit/`.

Перед написанием новой утилиты в сервисе — проверь corelib. Будет нужно 2+ сервисам →
сразу в corelib. **Исключение**: доменная бизнес-логика (VPC ref-validation, Compute
reconciler) живёт в сервисном репо.

## Concurrency / lifecycle / читаемость (выведено из audit-раундов)

- **Per-call deadline на КАЖДОМ внешнем вызове.** Любой peer-gRPC / HTTP / DB-запрос обязан
  нести собственный `context.WithTimeout(ctx, …)` — **никогда** `http.DefaultClient.Do(req)` с
  сырым request-ctx на hot-path. `DefaultClient` не имеет Timeout: неотвечающий peer (GC/overload/
  half-open TCP) вешает горутину **навсегда**. Особо критично для authz-Check (OpenFGA): без
  таймаута интерсептор не доходит до fail-closed-ветки, горутины копятся → исчерпание процесса.
  Все sibling-методы клиента обязаны применять один и тот же configured-timeout (не «часть — да,
  часть — нет»).
- **WaitGroup-lifecycle: закрывать счётчик для брошенных задач.** Worker/dispatcher с `wg`:
  на `Stop()` обязан `wg.Done` для КАЖДОЙ задачи, оставшейся в backlog (её `wg.Add` уже сделан),
  и **guard enqueue-after-stop** (не `wg.Add` задачу, которую мёртвый dispatcher не исполнит).
  Иначе `Wait()` никогда не дойдёт до `wg==0` (spurious timeout + утечка `wg.Wait`-горутины).
  Синхронизация backlog-drain и enqueue-guard — под одним mutex.
- **Doc-truthfulness: комментарий/godoc обязан совпадать с кодом.** Комментарий, противоречащий
  коду (напр. описывает `WHERE status='ACTIVE'`, а реально `IN ('ACTIVE','DELETING')`; или
  status-машину, которой worker не реализует; или sentinel, которого код не возвращает) — это
  latent-баг: следующий контрибьютор «чинит» код под неверный док. Если поведение задумано, но
  не реализовано — док отражает **реальность**, не намерение.
- **LEAN: без vestigial-кода.** Мёртвый тип/пакет/ветка/builder (нет prod-импортёров; unreachable
  branch, «документирующая» контракт, который код никогда не производит) — удаляй вместе с его
  тестами. Сложное делать просто, без over-engineering, но без потери функциональности/безопасности/
  контракта (ban #11 «без тех-долга» + LEAN-дименсия аудита).
