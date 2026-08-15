---
title: nlb-apps-kacho-api-internal-lifecycle
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - internal
  - lifecycle
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов, ручка ограничения стримов, имя порта; текст записки построчно не пересматривался"
---

# kacho-nlb/internal/apps/kacho/api/internal_lifecycle

**Каталог**: `services/nlb/internal/apps/kacho/api/internal_lifecycle/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/apps/kacho/api/internal_lifecycle/`)
**Implements**: [[../rpc/nlb-internal-resource-lifecycle-service|InternalResourceLifecycleService]]
**Imports**: [[nlb-repo-kacho-pg]] (outbox + watch_cursors), [[corelib-grpcsrv]]

Server-streaming D-13 lifecycle service. **Internal-only** (port 9091, workspace #6).

## Files

| File | Содержание |
|---|---|
| `handler.go` | `Subscribe(req, stream)` целиком: semaphore acquire → `feed.Open` (dedicated LISTEN-сессия вне pool'а) → catchup батчами → WaitForNotification (30s) → `stream.Send`. Здесь же package-doc с полным алгоритмом |
| `semaphore.go` | счётный семафор, ограничивающий число одновременных стримов |
| `*_test.go` | unit + integration (testcontainers): порядок коммита, семафор, resume по курсору |

> [!note] Отдельного файла под цикл подписки в пакете нет
> Прежняя редакция перечисляла ещё три файла — под цикл подписки, под порт и под
> маршалинг события. Ни одного из них в каталоге нет, и, судя по всему, не было:
> цикл живёт целиком в `handler.go`, а порт доступа к фиду вынесен **в repo-слой**
> (`services/nlb/internal/repo/kacho/iface_lifecycle.go`, интерфейс `LifecycleFeed`;
> pgx-реализация — `services/nlb/internal/repo/kacho/pg/lifecycle_feed.go`). Это
> и есть dependency rule: pgx в use-case не поднимается. Имя порта в прежней
> редакции тоже было своё и в дереве не встречается.

## Semaphore guard

Потолок одновременных `Subscribe`-стримов — ключ YAML-конфига `internal-lifecycle.max-streams`,
default **32**. При превышении — `ResourceExhausted`. Защищает от исчерпания pgx-пула:
каждый стрим держит **dedicated** соединение (вне пула), поэтому слот ≈ +1 conn к Postgres.
`Config.Validate()` требует значение > 0, `NewHandler` панику на `<=0` держит как safety-net.

> [!warning] Ручка задаётся конфигом, а не переменной окружения с отдельным именем
> Прежняя редакция называла переменную окружения, которой в дереве нет ни в коде, ни в
> чарте. Конфиг nlb — viper/YAML: canonical-источник — ключ конфигмапа, а переменные
> окружения биндятся автоматически из **того же** ключа (`SetEnvPrefix` + замена `.` на
> `__`), поэтому отдельного имени под этот потолок никто не объявлял. Проверять надо ключ.

## Catchup vs realtime

1. **Catchup batch**: `SELECT FROM nlb_outbox WHERE sequence_no > $cursor ORDER BY sequence_no LIMIT 100` — sends to client as `LifecycleEvent`s.
2. **Realtime**: dedicated pgx-conn `LISTEN nlb_outbox` → `WaitForNotification` 30s; on notification → read row by `sequence_no` → send event.
3. **Cursor save**: `nlb_watch_cursors (subscriber_id, last_sequence_no)` — persisted resume position.

## Consumer

Primarily [[../edges/iam-to-nlb-resource-lifecycle|kacho-iam]] для D-13 FGA hierarchy tuple maintenance.

## See also

[[../rpc/nlb-internal-resource-lifecycle-service]] [[../edges/iam-to-nlb-resource-lifecycle]] [[nlb-repo-kacho-pg]] [[corelib-outbox]]

#packages #kacho-nlb #handler #internal #lifecycle
