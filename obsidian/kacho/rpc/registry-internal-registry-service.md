---
title: InternalRegistryService
aliases:
  - InternalRegistryService (registry)
  - registry InternalRegistryService
proto_file: kacho/cloud/registry/v1/internal_registry_service.proto
category: rpc
backend: kacho-registry
backend_port: 9091
visibility: internal
domain: registry
related_resource: "[[resources/registry-repository]]"
methods_count: 2
async_methods: 1
status: stable
verified_against: "перечень RPC сверен с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-registry
  - registry
  - internal
---

# InternalRegistryService (registry)

**Контракт**: `proto/kacho/cloud/registry/v1/internal_registry_service.proto`
**Backend**: сервис `kacho-registry`, **cluster-internal** листенер **:9091**
**Public/Internal**: внутрикластерно, никогда на внешнем TLS-крае (ban #6)

Эксплуатационная половина реестра: уборка мусора и инфра-статистика.

## Методы (2)

| Метод | Ответ | Sync/Async | отношение | REST |
|---|---|---|---|---|
| `TriggerGarbageCollection` | `Operation` | **async** | `admin` на `registry_registry:<id>` | нет |
| `GetRegistryStats` | `RegistryStats` | sync | `system_viewer` на синглтоне кластера | нет |

`google.api.http` не объявлен ни у одного — маршрутов нет. Метаданные операции —
`TriggerGarbageCollectionMetadata`, результат — `GarbageCollectionResult{registry_id,
blobs_removed, bytes_reclaimed}`.

> [!important] Внутренний листенер НЕ освобождён от авторизации
> Оба метода проходят per-RPC Check наравне с публичными: «internal = доверенный, хватит
> mTLS» — запрещённое допущение (`security.md` §«AuthN+AuthZ ВЕЗДЕ»). Внутренний
> периметр не доверенный.

## Два разных яруса — и разница между ними содержательная

`TriggerGarbageCollection` спрашивает **администратора конкретного реестра**: действие
разрушающее и адресовано одному объекту с индивидуальным владельцем.

`GetRegistryStats` спрашивает **ярус чтения кластера**, а не глагол объекта, — и это
выбрано намеренно. Ответ — инфра-проекция пространства имён (`repository_count`,
`tag_count`, `total_size_bytes`, `blob_count`), то есть данные о физике хранения, а не
арендаторское «намерение и результат». Ярус кластера здесь **сужает**, потому что, в
отличие от справочного отношения, он не выполняется подстановочной записью: арендатор
его не получает.

> [!note] Почему это не тот же случай, что публичный справочник
> Отношение справочного чтения кластера выполняется подстановочной записью и означает
> «аутентифицирован» (см. [[storage-disktype-service]] §про подстановочный знак). Ярус,
> взятый здесь, — другой, и в этом весь смысл: одна и та же форма записи каталога
> («вопрос про синглтон кластера») даёт совершенно разный охват в зависимости от того,
> какие записи это отношение выполняют. Читая чужую запись каталога, спрашивайте не
> «какой объект», а «какие записи выполняют это отношение».

## Границы, о которых стоит знать до правки

- **Сборка мусора — рукопожатие, а не работа.** Воркер только **побуждает** движок
  хранения к уборке; собственно освобождение делает его штатный планировщик. Поэтому
  повторный вызов безвреден, а вернувшийся результат не следует читать как «столько
  освобождено прямо сейчас».
- **`RegistryStats.last_gc_at` объявлено, но НИКОГДА не заполняется**: движок отметки о
  разовой уборке не отдаёт. Поле осознанно оставлено незаполненным, а не приведено к
  вечному нулю — вечный ноль неотличим от «уборки не было» и был бы утверждением,
  которого никто не делал. Проба, ждущая тут значения, зелёной не станет никогда, и это
  правильно.
- **Инфра-статистика живёт ТОЛЬКО здесь.** На публичной поверхности реестра
  ([[registry-registry-service]]) её нет и быть не должно: `security.md` §«Инфра-
  чувствительные данные» — про данные, а не про методы, и это отдельный, более строгий
  запрет, чем ban #6.

## См. также

[[registry-registry-service]] · [[resources/registry-repository]] ·
[[edges/registry-dataplane-public-tls]] · [[edges/registry-to-iam-fga-register]] ·
[[storage-internal-disktype-service]]

#rpc #kacho-registry #registry #internal
