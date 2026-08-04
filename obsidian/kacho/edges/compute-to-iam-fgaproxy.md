---
title: "compute → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - compute to iam fgaproxy
  - compute register resource
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: done
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
  - "[[../KAC/SEC-D-services-fga-via-iam-mtls]]"
tags:
  - edge
  - kacho-compute
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Реализовано в SEC-D (caller); callee — SEC-C
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-compute вызывает это ребро с SEC-D:
> прямой OpenFGA-клиент удалён, owner-tuple intent пишется в `compute_fga_register_outbox`
> в writer-tx ресурса, register-drainer → IAM.RegisterResource по (opt-in) mTLS.
> Контракт «FGA за IAM» (эпик #6); dual-write баг N5 устранён.

# compute → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `compute → iam` (ацикличность сохранена).

## Контракт

Идентичен [[vpc-to-iam-fgaproxy]]: `RegisterResource`/`UnregisterResource` с
`{subject_id, relation, object, trace_id}`, идемпотентность как контракт (write
`already_exists`→OK, delete absent→OK), at-least-once через transactional-outbox (SEC-D).
IAM эмитит owner-tuple в `kacho_iam.fga_outbox`+drainer для compute-ресурсов
(`compute_instance:<...>` и т.п.).

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute` → `sva`-id compute
→ ReBAC `Check(service_account:<sva-compute>, fga_writer, iam_fgaproxy:system)`. compute-SA
несёт relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## Caller-side mechanics (SEC-D, kacho-compute)

- **Intent в writer-tx**: `internal/repo/outbox.go::emitFGARegisterIntent` пишет строку в
  `compute_fga_register_outbox` (миграция `0010`) В ТОЙ ЖЕ tx, что Insert/Delete ресурса
  (Instance/Disk/Image/Snapshot + inline boot/secondary disks). `event_type ∈
  {fga.register, fga.unregister}`; payload — set из `fgaintent.Tuple`
  (`project:<projectId> #project @compute_<kind>:<id>`) + (RSAB β) `labels` + `parent_project_id`
  для наполнения IAM `resource_mirror`. Tx abort → intent откатывается (no orphan).
- **Update-on-labels trigger (RSAB β / T3.1 #113)**: register-intent эмитится и на `Update`,
  когда `labels` в update-mask (gated `emitLabelsRegister`, full-PATCH ⇒ true), чтобы mirror не
  протух и ARM_LABELS-грант ревокался. Instance — с β; **Disk/Image/Snapshot — с T3.1**
  (`{disk,image,snapshot}_repo.go::Update(…, emitLabelsRegister)`). Полное снятие меток → upsert
  `labels={}` (НЕ Unregister — ресурс жив, G-3). Эмит в той же writer-tx, что UPDATE.
- **Drainer**: corelib `outbox/drainer` (`cmd/compute/main.go::startRegisterDrainer`,
  default-on `KACHO_COMPUTE_FGA_REGISTER_DRAINER_ENABLED`), channel/table
  `compute_fga_register_outbox`. Applier — `internal/clients/iam_register_applier.go`
  (`RegisterResource`/`UnregisterResource`). CAS-claim/advisory-lock → exactly-once across replicas.
- **Error-маппинг (сверено 2026-08-05)**: `InvalidArgument` **и** `PermissionDenied` → poison
  (повтор идентичного запроса не может пройти — решение зависит от (вызывающий, отношение,
  объект); держать отказ по правам временным значило бы заклинить голову партиции на всё окно
  повторов). Прочее (Unavailable / дедлайн / mTLS-mismatch / транспорт) → transient retry с
  backoff. IAM down → intent durable, Operation не падает (tuple не теряется). Отравленные
  строки переигрывает периодический `RedrivePoisoned` (`cmd/compute/backstop.go`) — иначе
  отравление означало бы объект, навсегда невидимый в authz-фильтрованном списке.
- **mTLS**: per-edge `cfg.IAMRegisterMTLS` (`grpcclient.TLSClient`). Server-listener creds —
  `PUBLIC_SERVER_MTLS`/`INTERNAL_SERVER_MTLS` (`grpcsrv.TLSServer`).
  > [!warning] По этому ребру передаются ЗАПИСИ О ПРАВАХ — mTLS здесь не опция
  > Ребро пишет owner-tuple, из которого потом выводится доступ к ресурсу, поэтому цена
  > неаутентифицированного писателя тут — **выдача прав**, а не «открытый транспорт».
  > Per-edge включатель существует ради поэтапной раскатки PKI и остаётся переходной формой:
  > на любом развёрнутом стенде mTLS обязателен, а production boot-guard обязан отказывать в
  > старте, если ребро живое и не защищено. Симметрично требуется **непустой** allow-list
  > SAN'ов законных отправителей на принимающей стороне: пустой список означает «не сужаем»,
  > а не «запрещаем» (`security.md` §AuthN+AuthZ ВЕЗДЕ п.1 и п.5). Тот же инвариант —
  > [[nlb-to-iam-fga-register]], [[storage-to-iam-fgaproxy]], [[vpc-to-iam-fgaproxy]].
- **Удалено**: клиент прямой записи в FGA и пакет-эмиттер кортежей создателя (имена снятых
  файлов здесь намеренно не воспроизводятся в кавычках — так они читались бы как координаты
  в дереве). Проверяется тем же способом, что и всё остальное: у compute не должно быть
  импорта FGA-клиента, и это держит проба `internal/clients/no_direct_fga_test.go`.

## Барьера на видимость НЕТ — механизм снят целиком

> [!warning] Здесь стоял раздел про confirm-gate — в дереве его нет (перепись 2026-08-05)
> Прежняя редакция описывала как действующее: `Create`-операция достигает успеха **только
> после** подтверждающего чтения владельческого кортежа, с отдельным дедлайном
> подтверждения и ссылкой на приёмку. Перепись по монорепо `96b2879a`: ни `RunWithConfirm`,
> ни `OwnerConfirmer`, ни `WithConfirmationDeadline`, ни переменная дедлайна, ни интеграционная проба гейта — **ноль
> вхождений** (предикат: `git grep` по каждому из пяти имён; сами имена здесь не
> воспроизводятся в кавычках, чтобы разбор не стал новой ложной координатой). Снят по system-design-review как нарушение ban #9:
> `Operation.done` — durability предмета мутации, а не видимость downstream-эффекта; на
> fail-closed барьер рождает фантом (строка закоммичена, имя занято, операция — ошибка).

**Синхронный регистратор остался и работает** (`internal/clients/iam_sync_registrar.go`) —
но как **ускоритель**, а не как условие успеха: он сокращает окно, в котором создатель ещё
не видит свой ресурс, а его ошибка даёт WARN и никогда не проваливает Operation. Остаточный
лаг закрывается ограниченным клиентским повтором, а не серверным подтверждением. Что делает
приёмная сторона с этими двумя доставками — [[iam-register-resource-callee-contract]].

## History

- **SEC-D** ([[../KAC/SEC-D-services-fga-via-iam-mtls]]): caller-сторона реализована — прямой FGA
  удалён, transactional-outbox + register-drainer + opt-in mTLS. Закрыт dual-write баг N5.
- **owner-tuple-opgate (заведён, затем снят целиком)**: Create какое-то время гейтился на
  подтверждающем чтении владельческого кортежа; снят по system-design-review (ban #9).
  Из той работы в дереве остался **синхронный регистратор** — уже без роли барьера.
- **раскол блочного хранения доведён**: у compute больше нет собственных Disk/Image/Snapshot
  (миграция `0021_drop_block_storage_duplicates.sql`, связующая таблица снята `0013`).
  Поэтому набор регистрируемых объектов этого ребра сегодня — **`compute_instance`**
  (предикат: литералы FGA-типов в `internal/fgaintent/`, `internal/check/permission_map.go`,
  `internal/authzfilter/actions.go` — `compute_instance` и только он). Абзацы ниже,
  называющие Disk/Image/Snapshot, описывают состояние ДО раскола.
- **2026-08-05** — записка приведена к дереву `96b2879a`: снят раздел про confirm-gate,
  дополнена классификация отказов (отказ по правам терминален), добавлена ссылка на
  контракт приёмной стороны.
- **T3.1 / #113** ([[../KAC/sub-phase-T3.1-cross-service-label-revoke]], PR kacho-compute#62):
  Update-on-labels emit достроен на Disk/Image/Snapshot (раньше — только Instance) → ARM_LABELS
  revoke на снятие/смену метки. G-3 upsert-not-unregister. Create-эмит compute уже нёс labels
  (bare-create-бага, как у vpc.SG/nlb.listener, у compute нет). by-design compute §9.1.

## See also

[[iam-register-resource-callee-contract]] (приёмная сторона: зеркало, гашение повторной
доставки, пост-коммитный форвард, счётчик)
[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[compute-to-iam-check]] [[vpc-to-iam-fgaproxy]] [[iam-to-openfga-grant-write]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

> [!note] iam применяет тот же owner-tuple-co-commit к СВОИМ ресурсам (sub-phase 1.4 S2)
> Consumer'ы (vpc/compute/nlb) делают owner-tuple write через это сетевое ребро (`RegisterResource` по mTLS);
> iam как leaf-owner своих ресурсов делает ровно тот же co-commit **in-process** (свой `fga_outbox` + drainer) —
> см. [[iam-to-openfga-grant-write]].

#edge #kacho-compute #kacho-iam #cross-service #security #internal
