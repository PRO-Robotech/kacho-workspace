---
title: kacho-corelib (сегодня — каталог pkg/ монорепо)
aliases:
  - kacho-corelib
category: repo
repo: kacho-corelib
service_type: shared-library
status: legacy
tags:
  - kacho
  - kacho-corelib
  - shared
  - go
  - legacy
---

# kacho-corelib — сегодня это `pkg/` в монорепо

> [!warning] Предмет записки — отдельный репозиторий — существует, но разработка в нём не ведётся
> Общий фундамент живёт в **`pkg/`** монорепо `PRO-Robotech/kacho`. Записка сохранена как
> точка перехода для входящих ссылок (их 3); описанием сегодняшнего дня она не является —
> состав пакетов читается из дерева.

## Где это сегодня

| Тогда | Сегодня |
|---|---|
| репозиторий `github.com/PRO-Robotech/kacho-corelib` | каталог `pkg/` монорепо |
| import `…/kacho-corelib/<pkg>` | import `github.com/PRO-Robotech/kacho/pkg/<pkg>` |
| отдельный модуль, бамп пина на каждый релиз | один `go.mod`, порядок = порядок импортов |
| `make sync-migrations` — копия общих миграций в каждое сервисное репо | `pkg/migrations/common/` читается напрямую, копий нет |

## Состав `pkg/` — замер `kacho@96b2879a`, единица счёта: каталог первого уровня (22)

`api` (сгенерённые стабы — **руками не править**) · `auth` · `authz` · `backoff` ·
`baggage` · `config` · `db` · `dbready` · `errors` · `filter` · `grpcclient` · `grpcsrv` ·
`ids` · `internal` · `migrations` · `observability` · `operations` · `outbox` · `retry` ·
`safeconv` · `shutdown` · `validate`.

Что изменилось против прежней таблицы «Пакеты (15)»:

- **появились** и в ней не значились: `api` (дом сгенерённых стабов — прежде отдельный
  репозиторий), `auth`, `authz` (per-RPC Check и list-фильтрация), `grpcclient`
  (единый builder peer-клиентов), `dbready`, `safeconv`, `internal`;
- **исчезли**: `selector/` (label-selector парсер) и `audit/` — в дереве их нет. Про
  `audit/` прежняя редакция писала «no-op в текущей фазе»: фаза кончилась удалением,
  и запись про исключение пережила свой предмет;
- **`validate/`** живёт и экспортирует `Name`, `NameVPC`, `NameCompute`, `NameGateway`,
  `Description`, `Labels`, `ResourceID`, `UpdateMask`, `ZoneId`, `PageSize`, `IPAddress`,
  `DhcpDomainName`, `DdosProvider`, `SmtpCapability` — прежний перечень сошёлся, кроме
  добавившегося `Name`/`NameCompute`. Определение «стилистические валидаторы чужого
  облака» снято: это **собственные** конвенции Kachō (запрет #2), и описывать их через
  чужой продукт значит воспроизводить ровно то, что запрещено;
- **`filter/`** — парсер `name="value"` с whitelist полей; та же правка формулировки;
- **`ids/`** — `NewID(prefix)`; **prefix уже не всегда 3 символа**: действующий канон —
  дефисная форма `<prefix>-<crockford-base32>` для новых ресурсов, слитная 3-символьная
  остаётся валидной для legacy. Единый источник — `ids.KnownHyphenPrefixes()`. Прежняя
  формулировка «3-char prefix» описывала половину действительности.

Действующий канон переиспользования — `.claude/rules/architecture.md` §«Переиспользование»;
здесь он не дублируется, чтобы два места об одном предмете не разошлись.

## Связь с `corlib` (H-BF) — по-прежнему живая

`github.com/H-BF/corlib` — **внешняя** библиотека, не путать с `pkg/`. Проверено на
`kacho@96b2879a`: пин `v1.2.31-dev` в `go.mod`, 36 Go-файлов дерева её импортируют.

- `H-BF/corlib/pkg/dict.HDict[K,V]` — для `RcLabels` в domain;
- `H-BF/corlib/pkg/option.ValueOf[T]` — для optional newtypes;
- `H-BF/corlib/pkg/parallel.ExecAbstract` — для composition root (serve + migrate-runner);
- `H-BF/corlib/client/grpc` — builder gRPC-клиентов с retries/LB/TLS.

Скил `evgeniy` ссылается на неё как на часть канонического Go-стиля.

Соседний `packages.md` **удалён**: входящих ссылок ноль, перечень пакетов расходился с
деревом, а per-package записки живут в категории `packages/` (127 файлов) — это её предмет.

## См. также

- [[../README|vault hub]] · [[../architecture|архитектура]]
- `.claude/rules/architecture.md` — слои, dependency rule, переиспользование
- `.claude/rules/polyrepo.md` — раскладка монорепо

#kacho #kacho-corelib #shared #go #legacy
