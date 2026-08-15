---
title: InternalImageService
aliases:
  - InternalImageService (storage)
  - storage InternalImageService
proto_file: kacho/cloud/storage/v1/internal_image_service.proto
category: rpc
backend: kacho-storage
backend_port: 9091
visibility: internal
domain: storage
methods_count: 1
async_methods: 0
status: stable
verified_against: "перечень RPC сверен с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-storage
  - storage
  - internal
---

# InternalImageService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/internal_image_service.proto`
**Backend**: сервис `kacho-storage`, **cluster-internal** листенер **:9091**
**Public/Internal**: внутрикластерно, никогда на внешнем TLS-крае (ban #6)

Самый маленький контракт домена: **один** метод. Существует ради двухпроекционной формы
ресурса, а не ради поведения.

## Метод (1)

| Метод | Ответ | Sync/Async | отношение | REST |
|---|---|---|---|---|
| `GetInternal` | `ImageInternal` | sync | `viewer` на `storage_image:<image_id>` | нет |

`google.api.http` не объявлен — маршрута у метода нет ни на публичном, ни на внутреннем
мультиплексоре края.

## Зачем отдельный сервис под один метод

Публичная поверхность ресурса показывает арендатору «намерение и результат»; всё, что
помогает картировать физику (раскладка блобов, бакет, узел хранения, числовой инфра-id),
живёт **только** во внутренней проекции. Это не про поверхность **методов** (ban #6), а
про **данные** — `security.md` §«Инфра-чувствительные данные». Две проекции одного
ресурса — допустимая и рекомендованная форма; отдельный internal-message — один из двух
её вариантов, и storage выбрал именно его.

> [!important] Проекция объявлена, но пока ПУСТА — и это осознанно, а не забыто
> `ImageInternal` сегодня несёт **только** публичный `Image`; инфра-поля стоят
> зарезервированным диапазоном номеров и не заполняются. Резервирование — не заглушка:
> оно занимает номера полей, чтобы будущее наполнение не оказалось ломающим изменением.
> Практическое следствие: **сегодня внутренняя проекция образа не отличается от
> публичной**, и проба, утверждающая «internal отдаёт больше», была бы зелёной по
> недоразумению.

В отличие от `GetInternal` у [[storage-internal-volume-service]], **этот метод
реализован**: обработчик делегирует обычному чтению и заворачивает результат.
Асимметрия реальна — не считать один вывод верным для обоих.

## См. также

[[storage-image-service]] · [[storage-internal-volume-service]] ·
[[storage-internal-disktype-service]] · [[resources/geo-region]]

#rpc #kacho-storage #storage #internal
