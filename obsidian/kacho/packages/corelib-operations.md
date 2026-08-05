---
title: corelib-operations
category: packages
repo: kacho-corelib
path: pkg/operations
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - async
  - operations
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/operations — таблица длящихся операций, воркер, реконсайлер

**Каталог**: `pkg/operations/` · импорт
`github.com/PRO-Robotech/kacho/pkg/operations`
**Прежде** (полирепо): `kacho-corelib/operations`.
**Импортирует**: `pkg/baggage`, `pkg/backoff`, `pkg/ids`, `pkg/errors`, `pkg/validate`,
`pgx/v5`, `pgxpool`, `genproto/googleapis/rpc/status`, `grpc/codes`, `grpc/status`,
`protobuf/proto`, `anypb`.
**Импортируют** (`go list` на `96b2879a`, non-test): iam 22 · vpc 13 · nlb 10 ·
geo 9 · compute 9 · storage 8 · registry 4 · gateway 2 · `pkg/grpcsrv` 1 ·
`pkg/authz` 1 · `pkg/auth` 1. **Самый широко потребляемый пакет фундамента.**

Каждая мутация в Kachō возвращает `Operation`, клиент поллит её до `done=true`
(`api-conventions.md`). Здесь живут: таблица и репозиторий, воркер, реконсайлер
осиротевших операций, носитель личности инициатора и метрики.

## Экспортируемое API (снято с дерева)

```go
// создание
func New(domainPrefix, description string, metadata proto.Message) (Operation, error)
func NewFromContext(ctx context.Context, domainPrefix, description string, metadata proto.Message) (Operation, error)
func MetadataFor[T proto.Message](op *Operation) (T, error)

// хранилище
func NewRepo(pool *pgxpool.Pool, schema string) FullRepo
func AsOwned(r Repo) (OwnedOperationRepo, bool)
func ListForCaller(ctx context.Context, repo Repo, filter ListFilter) ([]Operation, string, error)

// исполнение
func NewWorker(opts ...WorkerOption) *Worker
func ConfigureDefault(opts ...WorkerOption) error
func Run(callerCtx context.Context, repo Repo, opID string, fn func(context.Context) (*anypb.Any, error))
func RunWithWorker(w *Worker, callerCtx context.Context, repo Repo, opID string, fn ...)
func RunSync(ctx context.Context, repo Repo, op *Operation, fn ...) error
func Active() int64
func Wait(ctx context.Context) error
func (w *Worker) Start() / Configure(...) / Active() / Ready() / Wait(ctx) / Stop()

// целостность
func NewReconciler(pool *pgxpool.Pool, resolver Resolver, cfg ReconcilerConfig, opts ...ReconcilerOption) *Reconciler

// личность
type Principal struct{ Type, ID, DisplayName string }
type Owner ... ; func OwnerFromPrincipal(p Principal) Owner; func OwnerFromContext(ctx) (Owner, bool)
const AnonymousPrincipalID = "anonymous"

// метрики
func NewMemRecorder() *MemRecorder ; type NopRecorder ...

var ErrNotFound      = errors.New("operation not found")
var ErrAlreadyDone   = errors.New("operation already completed")
var ErrWorkerStarted = errors.New("operations: worker already started; configure before Start")
```

Прежняя редакция называла `ErrShutdownTimeout` и `Repo{Create,Get,List,Update,Heartbeat}` —
таких имён в дереве нет: переходы называются `MarkDone`/`MarkError`/`Cancel`, а
сигнатура рабочей функции принимает `*anypb.Any`, а не `proto.Message`.

## `Repo.Get` и `Repo.Cancel` — БЕЗ предиката владения, и это записано в контракте

Порт объявляет прямо: `Get` и `Cancel` не ограничены владельцем и предназначены
**только** для доверенных внутренних вызовов (воркер, реконсайлер), уже
авторизованных иначе. Для tenant-facing RPC существуют owner-ограниченные варианты
через `OwnedOperationRepo` (`AsOwned`).

Причина названа тут же: строка операции несёт сериализованный ресурс и
идентификаторы, а формат идентификатора публичен и перечислим. То есть неограниченное
чтение — это не «мелкая недоделка», а прямой путь к чужим данным по угаданному id.
Правильная форма и состоит в том, что **порт называет своё ограничение сам**, а не
надеется на дисциплину вызывающего.

## `Operation.done` — durability предмета, НЕ видимость последствий

`done=true` означает «ресурс закоммичен» — и только это. Гейтить `done` на видимость
eventually-consistent последствия (запись отношения у владельца прав, зеркало в
соседнем сервисе, дренаж очереди) **запрещено**: это переопределяет контракт, а на
fail-closed рождает ресурс-фантом — строка закоммичена и имя занято, но операция
отвечает ошибкой. Окно чтения-после-записи закрывается **ограниченным повтором на
клиенте**, а не серверным барьером (`api-conventions.md`).

## Личность инициатора едет в асинхронное продолжение

Операция несёт `Principal`; воркер продолжает **под личностью инициатора**,
захваченной в момент запроса, а контекст переносится через [[corelib-baggage]] с
отброшенным сроком. Анонимный вызывающий имеет отдельный маркер
(`AnonymousPrincipalID`) — чтобы «не назвался» никогда не выглядело как обычный
субъект.

## Реконсайлер и осиротевшие операции

`Reconciler` подбирает операции, чей исполнитель умер, не дописав исход. Это
backstop, а не основной путь: основной — терминальная запись самим воркером с
повторами (метрики `TerminalWriteRetries` / `TerminalWriteFailures` /
`TerminalWriteAlreadyResolved` — три разных исхода, и их не следует складывать).

## Урок про общую схему: таблица у каждого сервиса СВОЯ

`pkg/migrations/common/*` **не применяется** сервисами автоматически — у каждого
своя копия DDL таблицы операций. Изменение пути записи фундамента по новой колонке,
приехавшее **раньше** миграций потребителей, дало отказ на **каждой** вставке
операции во всём флоте и замаскировалось под сбой первичной загрузки.
Правило: миграции потребителей landятся **первыми**, порядок — по графу
зависимостей (`polyrepo.md` §Порядок работы).

## См. также

[[corelib-baggage]] [[corelib-outbox]] [[corelib-outbox-drainer]] [[corelib-ids]]
[[../resources/operation]] [[../rpc/operation-service]]

#packages #kacho-corelib #async #operations
