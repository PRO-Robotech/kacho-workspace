---
title: "compute → storage: boot/volume Referrer resolve (COMP-1/STOR-1 split)"
aliases:
  - compute to storage volume resolve
category: edge
caller_repo: kacho-compute
callee_repo: kacho-storage
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/redesign-2026]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-storage
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!note] Раскол compute↔storage — доведён; ребро живое
> storage владеет Volume/Image/Snapshot; compute ссылается на них и **привязывает через
> владельца** (не переизобретая хранилище). Дубль на стороне compute снят миграцией
> `0021_drop_block_storage_duplicates.sql`, связующая таблица — `0013`. То есть карта
> владельцев по блочному хранению больше не двоится.

> [!warning] Объём ребра в записке был ШИРЕ дерева (сверено 2026-08-05)
> Записка описывала «резолв boot-источника (`storage.image`/`storage.snapshot`) + attach».
> В дереве `96b2879a` compute держит **один** stub хранилища —
> `storagev1.NewInternalVolumeServiceClient` (предикат: `grep -o "storagev1.New[A-Za-z]*"` по
> не-тестовому коду compute → одно имя), и по ребру ходят ровно три вызова: `Attach`,
> `Detach`, `ListAttachments`. Резолв boot-источника (образ → дайджест → материализованный
> том) в домене помечен как работа следующей фазы: `BootSource` принимает `Type`/`ID`, а
> `ResolvedDigest`/`MaterializedVolume` объявлены **output-only** полями саги, которой ещё нет.
>
> Разница существенна для проектирования: сегодня по этому ребру нельзя «спросить у storage,
> что за образ» — можно только привязать/отвязать/перечислить тома.

# compute → storage: boot/volume resolve (split)

**Caller**: `kacho-compute` (`internal/clients/storage_client.go`).
**Callee**: `kacho-storage` (`InternalVolumeService`, :9091).
**Protocol**: gRPC cluster-internal :9091 (**mTLS** — leaf `kacho-compute-client-tls`, ServerName
`kacho-storage` ∈ SAN серверного сертификата storage; per-edge включатель — переходная форма,
на развёрнутом стенде mTLS обязателен).
**Sync/Async**: вызовы синхронные, внутри Operation-worker'а привязки/отвязки; на чтении —
синхронное дополнение ответа зеркалом.

## When invoked (то, что есть)

- `Instance.AttachVolume` / `DetachVolume` → `InternalVolumeService.Attach`/`Detach`:
  compute форвардит **самоописывающийся** payload (инстанс, его зона, проект, имя), storage
  валидирует **свою** строку одним CAS и **никогда не зовёт compute обратно** — ацикличность
  держится by construction.
- `Instance.Get`/`List` → `ListAttachments`: read-only зеркало привязанных томов. Недоступность
  storage зеркало **опускает**, а не роняет чтение (мягкая деградация, как у NIC-зеркала).
- placement-coherence: зона тома против зоны инстанса — проверяет **владелец** внутри своего
  CAS, потому что только у него обе строки в одной БД.
- Резолв boot-источника по этому ребру **не ходит** — см. предупреждение выше.

## Что происходит при отказе

| Исход | Что видит вызывающий |
|---|---|
| том есть, зона совпала | привязка выполнена (CAS у владельца) |
| тома нет у владельца | `FAILED_PRECONDITION` — полоса peer-validate, **не** `NOT_FOUND` (та означала бы «не нашёл СВОЮ строку») |
| зона тома ≠ зона инстанса | `FAILED_PRECONDITION` (когерентность размещения) |
| storage недоступен | `UNAVAILABLE` — fail-closed на мутации |
| storage недоступен **на чтении** | зеркало привязок опускается, `Get`/`List` отвечают успехом без списка томов |

Последняя строка — та, которую забывают: на чтении отказ пира **не наблюдаем** как ошибка.
«У инстанса пропали тома» и «storage лежит» выглядят одинаково.

## Компенсация саги — ТРЕБОВАНИЕ, а не механизм в дереве (сверено 2026-08-05)

Записка утверждала: «compensation-outbox инициатора эмитит обратные `Delete`/`ClearReference`
до пометки Operation error». **Такой очереди в продукте нет**: `grep -ril
"compensation_outbox\|CompensationOutbox"` по всему монорепо → **ноль** файлов. Слово
«компенсация» встречается в четырёх местах, и все они — либо про откат внутри одной операции
nlb, либо **прямое указание на незакрытый остаток**.

Незакрытый остаток назван самим кодом compute (`internal/repo/instance_repo.go`, godoc
`GateForAttach`) и стоит того, чтобы его знали здесь: предпроверка перед привязкой отвечает
на «есть ли инстанс и в том ли он состоянии» **одним снимком**, но ничего не пишет и строку не
держит, поэтому гонку «привязка против удаления» она **сужает, а не закрывает** — конкурентное
удаление успевает отпустить привязки, пока форвард к storage/vpc ещё в пути. Настоящее
закрытие требует сериализации (счётчик привязок-в-полёте на строке инстанса либо
advisory-lock, удерживаемый обеими сагами) и идёт через db- и system-design-ревью; до тех пор
остаток обязан закрываться компенсацией инициатора и подметальщиком владельца — **обоих в
дереве нет**.

Так что читать этот раздел следует как «чего ещё не хватает», а не как «как оно работает».
Норма — `data-integrity.md` §«Cross-service saga-compensation».

## Ацикличность

storage не зовёт compute обратно (одностороннее). Цикла нет.

## Deploy

compute chart: `storageInternalAddr` (default `kacho-storage…:9091`) + `mtls.edges.storage` +
`mtls.serverName.storage` (first-class edge, commit `a91d9cc`). storage-chart: `fullnameOverride:
kacho-storage` + Certificate SAN `kacho-storage` (commit `fc56e99`).

## History

- **2026-07-20** (redesign-2026, COMP-1/STOR-1): ребро введено split'ом. Backend compute COMP-1 +
  storage STOR-1; deploy first-class wiring. [[storage-to-iam-fgaproxy]] (owner-tuple для scope_extractor).
- **2026-08-05**: записка приведена к дереву `96b2879a` — объём ребра сужен до привязки/отвязки/
  перечисления (резолв boot-источника не landed), компенсация саги названа открытым долгом,
  снята ссылка на несуществующую записку `compute-storage-split-concept`.
