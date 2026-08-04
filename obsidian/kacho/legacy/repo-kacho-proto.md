---
title: kacho-proto (сегодня — каталог proto/ монорепо)
aliases:
  - kacho-proto
category: legacy
repo: kacho-proto
service_type: proto-stubs
status: legacy
tags:
  - kacho
  - proto
  - grpc
  - legacy
---

# kacho-proto — сегодня это `proto/` в монорепо

> [!warning] Предмет записки — отдельный репозиторий — существует, но разработка в нём не ведётся
> `PRO-Robotech/kacho-proto` не заархивирован на GitHub, последний push — середина июля
> 2026. Все `.proto` живут в **`proto/`** монорепо `PRO-Robotech/kacho`; прежние полирепо
> клонируются только по `KACHO_CLONE_LEGACY_POLYREPOS=1`. Записка сохранена как **точка
> перехода** для входящих ссылок (их 4) и как след топологии — не как описание сегодняшнего дня.

## Где это сегодня

| Тогда | Сегодня |
|---|---|
| репозиторий `github.com/PRO-Robotech/kacho-proto` | каталог `proto/` монорепо |
| `proto/kacho/cloud/<domain>/v1/*.proto` | **тот же путь** внутри монорепо |
| `gen/go/...`, коммитились в repo | `pkg/api/...` — сгенерённые стабы, **руками не править** |
| import `…/kacho-proto/gen/go/…` | import `github.com/PRO-Robotech/kacho/pkg/api/…` |
| отдельный Go-модуль, versioned require | **один** `go.mod` на дерево, ноль `replace` |

Правило «новый `.proto` — **всегда** в `proto/`, сервисные каталоги `.proto` не содержат»
живёт в `.claude/rules/polyrepo.md`, здесь не дублируется.

## Домены в `proto/kacho/cloud/` — замер `kacho@96b2879a`, единица счёта: файл `.proto`

| Домен | Файлов | Что внутри |
|---|---:|---|
| `iam` | 34 | Account / Project / User / ServiceAccount / Group / Role / AccessBinding + `Internal*` |
| `vpc` | 19 | Network / Subnet / Address / RouteTable / SecurityGroup / Gateway / NetworkInterface + `Internal*` |
| `compute` | 11 | Instance / MachineType (+ живой дубль блочного хранения — раскол не завершён) |
| `storage` | 11 | Volume / Snapshot / Image / DiskType |
| `loadbalancer` | 10 | домен **nlb**; каталог proto по-прежнему `loadbalancer/`, код — `services/nlb/` |
| `geo` | 7 | Region / Zone — leaf-owner оси размещения |
| `registry` | 4 | Registry / Repository / Tag (OCI) |
| `operation` | 3 | LRO-конверт `Operation` + `OperationService.Get` |
| `access` · `api` · `apigateway` · `reference` | по 1 | + корневой `validation.proto` |

Каталог proto и имя сервиса совпадают не везде (`loadbalancer/` ↔ `services/nlb/`) — это
факт дерева, а не опечатка; проверяй по каталогу, а не по имени домена.

## Что в прежней редакции было НЕВЕРНО

Выписано, чтобы ошибка не воспроизвелась при чтении старых копий:

- **«Envelope: `metadata` + `spec` + `status`»** — прямо противоположно действующей
  конвенции. Ресурс Kachō — **плоский** message с domain-полями на верхнем уровне,
  K8s-конверт запрещён (`.claude/rules/api-conventions.md` §«Форма ресурса»).
- **«Standard 4 RPCs per resource: `Upsert/Delete/List/Watch`»** — такого набора нет.
  Стандартный: `Get`/`List` синхронно + `Create`/`Update`/`Delete` через `Operation`.
  **`Upsert` не существует**; публичного `Watch` тоже — единственный `rpc Watch` в дереве
  живёт в `compute/v1/internal_watch_service.proto` и cluster-internal.
- **Домены `resourcemanager` / `organizationmanager`** — сняты (KAC-124), каталогов нет.
- **Домены `maintenance`, `common`** — в дереве отсутствуют.
- **`compute` как владелец Geography** — Geography вынесена в `geo` (эпик #82); в
  `proto/kacho/cloud/compute/v1/` нет ни region-, ни zone-контракта.
- **`PrivateEndpoint` в составе vpc** — в дереве ноль файлов по этому имени (снят).
- **Числа файлов** (vpc 22 / compute 41 / loadbalancer 6) не сходятся ни с одним каталогом;
  таблица выше перемерена по индексу git.

Соседний `domains.md` (поимённый перечень proto-файлов) **удалён**: входящих ссылок ноль,
а перечень расходился с деревом по всем трём осям — состав доменов, состав файлов, их число.
Действующий состав читается из дерева одной командой — дешевле, чем держать его копию.

## См. также

- [[../README|vault hub]] · [[../architecture|архитектура]]
- `.claude/rules/polyrepo.md` — раскладка монорепо и порядок работы
- `.claude/rules/api-conventions.md` — форма ресурса, шаблон сервиса, error-format

#kacho #proto #grpc #legacy
