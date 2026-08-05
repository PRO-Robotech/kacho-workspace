---
title: InternalDiskTypeService
aliases:
  - InternalDiskTypeService (storage)
  - storage InternalDiskTypeService
proto_file: kacho/cloud/storage/v1/disk_type_service.proto
category: rpc
backend: kacho-storage
backend_port: 9091
visibility: internal
domain: storage
methods_count: 3
async_methods: 0
status: stable
verified_against: "перечень RPC и REST-маршруты сверены с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-storage
  - storage
  - internal
---

# InternalDiskTypeService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/disk_type_service.proto` — **тот же файл**,
что у публичного чтения ([[storage-disktype-service]]); два `service`-блока в одном файле
**Backend**: сервис `kacho-storage`, **cluster-internal** листенер **:9091**
**Public/Internal**: админский CRUD каталога, никогда на внешнем TLS-крае (ban #6)

## Методы (3)

| Метод | Ответ | Sync/Async | REST | отношение |
|---|---|---|---|---|
| `Create` | **`DiskType`** | sync | `POST /storage/v1/diskTypes` | `system_admin` на синглтоне кластера |
| `Update` | **`DiskType`** | sync | `PATCH /storage/v1/diskTypes/{disk_type_id}` | `system_admin` на синглтоне кластера |
| `Delete` | `DeleteDiskTypeResponse` | sync | `DELETE /storage/v1/diskTypes/{disk_type_id}` | `system_admin` на синглтоне кластера |

> [!important] Мутации возвращают РЕСУРС синхронно, а не `Operation` — задокументированное отступление
> Конвенция `api-conventions.md` требует от мутаций `Operation` (ban #9). Здесь её нет, и
> это **решение, а не пропуск**: обработчик не заводит ни строки операции, ни фонового
> воркера — в пути CRUD каталога нет вообще ничего асинхронного. Обоснование записано в
> двух местах продукта — в обзоре архитектуры сервиса (`services/storage/docs/
> architecture/overview.md`, раздел про sync-vs-async) и в шапке пакета use-case: у
> админского каталога нет долгой работы, которую стоило бы заворачивать в конверт.
> Ровно та же форма у соседнего каталога geo ([[rpc/geo-region-service]]), где
> админские мутации возвращают уже завершённый конверт, — так что «как у соседа» здесь
> **не** совпадает буквально, и копировать форму вслепую нельзя.

> [!important] `Update` — ПОЛНАЯ ЗАМЕНА, а не PATCH
> `UpdateDiskTypeRequest` **не несёт `FieldMask`**. Значит дисциплины маски здесь нет и
> быть не может: тело заменяет все мутабельные поля целиком. Поле, не переданное в
> запросе, обнулится — это не «частичное обновление с пустым полем». `id` — назначаемый
> администратором слаг, неизменяемый и приходящий сегментом пути.

## Один REST-путь на две поверхности — гейт изоляции ключуется на ПАРУ

Эти три метода делят REST-путь с публичным чтением каталога и отличаются от него
**только методом HTTP**: `GET /storage/v1/diskTypes` публичен, `POST` по тому же пути —
внутренний. Поэтому гейт края, следящий, чтобы внутреннее не выставилось наружу, здесь
ключуется на **пару (метод, путь)**, а не на путь. Проверка «внутренние пути не пересекают
публичные» на одном пути дала бы либо ложную находку, либо ложную тишину.

## Наблюдение о каталоге, которое стоит знать до правки

Все пять засеянных классов идут с **пустым** списком зон, а пустой список означает «во
всех зонах». Практическое следствие для этого сервиса: пока `zone_ids` никем не
заполнен, зональное ограничение каталога существует только как контракт — проверка,
которую оно питает на создании тома, не отвергла ни одного запроса. Заполнение
`zone_ids` — задача **этого** сервиса, и оно эту проверку оживит. Развёрнуто —
[[storage-disktype-service]] §«Пустой `zone_ids`».

## Расхождение в текстах прав (не влияет на решение)

Строки разрешений этих трёх методов записаны в дереве **в двух формах**: контракт и обе
встроенные копии каталога прав (у iam и у края) пишут `storage.disk_types.*`, а
зеркальная карта самого сервиса — `storage.diskTypes.*`. На решение это не влияет:
карта сервиса ключуется **по имени RPC**, а тексты отношения и объекта у всех совпадают,
поэтому обе стороны выносят один и тот же вердикт. Но это третье место об одном
предмете, расходящееся в тексте с двумя авторитетными, — и следующая сверка каталога
поимённо на него наткнётся.

## См. также

[[storage-disktype-service]] · [[storage-internal-volume-service]] ·
[[storage-internal-image-service]] · [[rpc/geo-region-service]] ·
[[rpc/compute-machinetype-service]]

#rpc #kacho-storage #storage #internal
