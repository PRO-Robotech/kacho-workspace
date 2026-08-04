---
title: corelib-retry
category: package
repo: kacho-corelib
path: pkg/retry
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - retry
  - grpc
---

# pkg/retry — повторы вызовов к соседнему сервису

**Каталог**: `pkg/retry/` · импорт `github.com/PRO-Robotech/kacho/pkg/retry`
**Прежде** (полирепо): `kacho-corelib/retry`.
**Импортирует**: `context`, `errors`, `time`, `grpc/codes`, `grpc/status`,
[[corelib-backoff]].
**Импортируют** (`go list` на `96b2879a`, non-test): nlb 4 · registry 2 · vpc 1 ·
compute 1 — все точки — клиенты к соседям.

## Экспортируемое API (снято с дерева)

```go
func OnUnavailable(ctx context.Context, fn func(ctx context.Context) error) error
func OnAborted(ctx context.Context, fn func(ctx context.Context) error) error
func OnCodes(ctx context.Context, fn func(ctx context.Context) error, retryCodes ...codes.Code) error

var Defaults = struct {
    InitialInterval     time.Duration // 100ms
    Multiplier          float64       // 2.0
    MaxInterval         time.Duration // 5s
    MaxElapsed          time.Duration // 30s
    RandomizationFactor float64       // 0.2
}{...}
```

Поле называется `MaxElapsed` (не `MaxElapsedTime`) — имя проверяемо, в предыдущей
редакции оно было переписано «по смыслу» и не совпало бы с деревом.

## Что повторяем — и, что важнее, чего НЕ повторяем

- `OnUnavailable` — сосед недоступен (перезапуск, сетевой сбой). Это единственный
  класс, где повтор идентичного запроса имеет шанс.
- `OnAborted` — конфликт CAS/OCC; повтор после перечитывания состояния законен.
- `OnCodes(...)` — общая форма для явно перечисленного набора.

> [!warning] Отказ в правах — НЕ временный
> Повтор идентичного запроса, которому отказал владелец прав, не пройдёт никогда.
> Классификация такого отказа как временного уже приводила к тому, что строка
> исходящей очереди **вечно** блокировала свою партицию и ни одна регистрация не
> доезжала, тогда как синхронный путь работал и всё выглядело исправным
> (`data-integrity.md` §Межсервисное намерение). Классификатор чужих ошибок обязан
> иметь явный терминальный разряд, а не корзину «прочее → повторим».

## Бюджет времени принадлежит запросу

Повтор живёт **внутри** дедлайна вызова: `MaxElapsed` — потолок серии, а не право
превысить срок вызывающего. На пути мутации исчерпанная серия отдаёт `Unavailable`
(fail-closed), а не «как-нибудь продолжим».

## См. также

[[corelib-backoff]] [[vpc-clients]] [[corelib-grpcclient]]

#packages #kacho-corelib #retry #grpc
