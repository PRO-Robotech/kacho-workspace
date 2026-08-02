---
title: "kacho-corelib/authz"
aliases:
  - corelib authz
  - authz interceptor
category: packages
repo: kacho-corelib
layer: corelib
tags:
  - packages
  - kacho-corelib
  - authz
  - cross-service
  - e3
---

# kacho-corelib/authz

Cross-cutting authz пакет: gRPC unary+stream interceptor поверх внешнего
`CheckClient`-port'а (реализуется per-service adapter'ом к
`kacho-iam.InternalIAMService.Check`).

**Layer:** corelib (shared across kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-iam).

## Файлы

| Файл | Назначение |
|---|---|
| `doc.go` | overview + ASCII-схема pipeline. |
| `types.go` | `RPCMap`, `RPCEntry`, `ObjectExtractor`, `StaticExtractor`, `Decision`, sentinel-errors, `FormatObject`, `FormatSubject`. |
| `cache.go` | `Cache` — TTL=5s positive-only кеш + `InvalidateBySubject` + `InvalidateAll` + thread-safe. |
| `check_client.go` | port `CheckClient`, helper `CheckClientFunc`, port `CreatorTupleWriter` (D-11). |
| `subject_extract.go` | `defaultSubjectExtractor` через `operations.PrincipalFromContext` (E2). |
| `interceptor.go` | `Interceptor` + `NewInterceptor` + `Unary()` / `Stream()` + lock-free Metrics + `EvictInactiveSubjects`. |
| `rate_limiter.go` | token-bucket per-principal на denied-storm (I10). |
| `listen_invalidate.go` | `ListenInvalidator.Run(ctx)` — pgx LISTEN-loop `kacho_iam_subjects` → `Cache.InvalidateBySubject`. |

## API (порты, экспортируется наружу)

```go
type CheckClient interface {
    Check(ctx, subjectID, relation, object) (bool, error)
}
type CreatorTupleWriter interface {
    WriteCreatorTuple(ctx, subjectID, relation, object) error
}
type ObjectExtractor func(req any) (objectType, objectID string, err error)
func StaticExtractor(objectType string, extractID func(req any) (string, error)) ObjectExtractor
type RPCMap map[string]RPCEntry
type RPCEntry struct { Relation string; Extract ObjectExtractor; Public bool }

// Sentinel errors (KAC-133):
var ErrUnmapped   = errors.New("authz: RPC not mapped in PermissionMap")
var ErrUnavailable = errors.New("authz: check service unavailable")
var ErrNoPath     = errors.New("authz: no FGA path to resource")  // → DecisionNoPath passthrough
```

## Decision pipeline (interceptor.authorize)

1. Breakglass=true → `Allowed` + WARN (на развёрнутом стенде недостижимо, см. Fail modes).
2. RPCMap lookup; **not found → `Unmapped` → `PermissionDenied` (fail-closed)**, без
   исключений — stream в том числе.
   > [!important] Пропуск Check выдаётся ЗАПИСЬЮ в карте, а не выводится из имени метода
   > Прежде здесь стояла эвристика по имени (`Internal*` ⇒ пропуск). Имя метода —
   > свойство строки, а не решение о доступе: любой новый RPC, попавший под шаблон,
   > молча получал пропуск, и добавление такого RPC выглядело в диффе как обычная
   > фича. Теперь `DecisionInternal` выдаётся **только** явной записью `Public=false` /
   > `ScopeFiltered=true` — то есть кто-то принял решение и оставил его в карте, где
   > drift-guard-тест его видит. Незамапленный RPC отказывает.
3. Principal extract; пусто → `Denied`. **Безусловно**, в том числе для
   `ScopeFiltered`-полосы: за ней нет per-RPC Check, на который можно откатиться,
   поэтому неопознанный вызывающий не имеет запасного пути.
4. Object extract; ошибка → `Denied`.
5. Cache lookup (positive-only); hit → `Allowed`/`Denied`.
6. Rate-limit per-principal (denied-storm).
7. `Client.Check(subject, relation, object)`; err →
   - `errors.Is(err, ErrNoPath)` → **DecisionNoPath**: pass-through к handler'у,
     который вернёт `NOT_FOUND` из БД (вместо masking как 403). Используется
     когда FGA hierarchy-tuple для объекта ещё не записан — KAC-133.
   - иначе → `Unavailable` (fail-closed).
8. allowed → cache positive + `Allowed`; иначе `Denied`.

## Fail modes (acceptance D-6)

- FGA/kacho-iam недоступен → fail-closed `PermissionDenied`.
- **Breakglass — аварийный полный обход Check, и он гейтится посадкой, а не дисциплиной.**
  В `production`/`production-strict` `Config.Validate()` **отказывает в старте**, называя
  ручку в тексте отказа (message-lock'нуто тестами в geo/registry/compute). Ручка,
  снимающая контроль, обязана быть недостижима на развёрнутом стенде — иначе она есть
  всегда, а «мы ею не пользуемся» проверить нечем. Живёт только в in-process
  unit/integration-фикстурах.

> [!note] Не путать с `ClusterBreakGlassGrant`
> Это **разные** механизмы. Здесь — config-ручка процесса (обход Check целиком).
> [[../resources/iam-cluster-break-glass-grant]] — доменный ресурс: аварийная выдача
> прав с двумя подписантами, сроком и kill-switch'ем, то есть решение внутри модели,
> а не в обход неё.

## Окно отзыва — ОБЪЯВЛЕННАЯ политика, а не сумма умолчаний

Кешируются **только положительные** вердикты. Поэтому свежая **выдача** видна
сразу (промах по кешу всегда идёт к авторитетному Check), а **отзыв ждёт**: запись
«разрешено» живёт до истечения своего срока. Значит срок жизни записи **и есть**
окно отзыва — время, в течение которого субъект, у которого право уже отобрали,
продолжает проходить. Асимметрия намеренная: выдавший не ждёт, отобравший ждёт
ограниченное и **объявленное** время.

Политика живёт в `pkg/authz/revocation_policy.go` — одним местом на все сервисы.
До этого окно было **эмерджентным**: шесть сервисов несли положительный кеш, каждый
называл своё число в своём комментарии, и ни одно место не говорило, каким числу
быть позволено. Параметр безопасности, которого никто не выбирал, нельзя ни
обсудить, ни отозвать, ни заметить при смене. Гейт связывает запись с деревом:
смена умолчания без правки политики роняет проверку.

> [!warning] Push-invalidate по каналу НЕ работает — у канала нет отправителя
> Прежняя редакция этой записки обещала проактивное снятие записи через
> `pg_notify('kacho_iam_subjects', subject_id)` и складывала из этого бюджет
> распространения. **В репозитории у этого канала нет ни одного отправителя** —
> только слушатели. Слагаемое было фиктивным, а обещание ложным: следующий
> читатель стал бы оптимизировать путь, которого нет. Итоговое число от снятия
> слагаемого не изменилось, но теперь это **объявленный потолок**, а не сумма с
> несуществующим членом.
>
> Слушатель (`ListenInvalidator`, выделенное соединение; переподключение →
> консервативный сброс всего кеша) в коде есть и провязан — отсюда и обманчивость:
> механизм выглядит рабочим с обеих сторон, кроме той, где его нет.
>
> **Немедленный отзыв учётных данных по этому окну не ездит** и остаётся на своём
> пути. Это записано здесь, чтобы «сделать окно поменьше» не подменяло «снять
> учётные данные».

## Decoupling

corelib НЕ импортирует kacho-proto stubs — adapter (`<service>/internal/.../check_client.go`)
живёт в сервисе и импортирует `iamv1.InternalIAMServiceClient`.

## Used by

- [[vpc-apps-kacho-check]] (kacho-vpc)
- [[compute-internal-check]] (kacho-compute)
- kacho-loadbalancer (TODO, KAC-108)
- kacho-iam (self-check для AccessBindingService action)

## See also

[[../edges/iam-to-openfga-check]] [[../edges/vpc-to-iam-check]] [[../edges/compute-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-corelib #authz #cross-service #e3
