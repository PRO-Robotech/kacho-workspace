---
title: Repository (registry)
aliases:
  - Repository (registry)
  - registry Repository
  - repository_configs
category: resource
domain: registry
id_prefix: none
owner_table: kacho_registry.repository_configs
owner_db: kacho_registry
project_level: false
status: in-progress
related_rpc:
  - "[[rpc/registry-registry-service]]"
related_tickets:
  - "[[KAC/RG-1-registry-repository-overlay]]"
tags:
  - resource
  - kacho-registry
  - registry
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!note] Сверка со стволом (2026-08-05)
> Ресурс жив: `message Repository` объявлен в `proto/kacho/cloud/registry/v1/registry.proto`
> (рядом `Registry`, `Tag`, `Referrer`), таблица `repository_configs` создаётся
> `services/registry/internal/migrations/` в схеме `kacho_registry`. Живых таблиц у
> registry семь: `registries`, `repository_configs`, `registry_repository_registration`,
> `registry_push_grant`, `registry_pending_blob`, `registry_outbox`, `operations`.
>
> **Ресурс верхнего уровня называется `Registry`, а не `Namespace`** — заход на
> переименование откачен решением владельца. Слово «namespace» ниже и в самом proto
> употреблено как **описание роли** («тенант-namespace над общим zot-бэкендом»), а не
> как имя ресурса или сообщения: `message Namespace` в дереве отсутствует. Не принимать
> это словоупотребление за имя типа.
>
> `Registry` несёт `region_id` + `placement_type` (единственное живое значение —
> `REGIONAL`, anycast): реестр региональный и зоне-независим, поэтому из зональной
> проверки когерентности исключён by construction.
>
> **Записки `rpc/registry-registry-service` в участке нет** — ссылка выше висит в пустоту.
> Заведение отнесено в остаток волны; контракт — `registry_service.proto` (17 RPC) плюс
> `internal_registry_service.proto` (2 RPC на :9091).

# Repository (registry)

**Domain**: registry — OCI-репозиторий внутри namespace реестра (RG-1). **Config-overlay
первого класса** поверх read-only zot-проекции.
**ID**: натуральный ключ **`(registry_id, name)`** — НЕ генерируемый 3-char prefix
(сохранена проекционная модель). Имя несёт `/` (напр. `backend/api`), REST `{repository=**}`.

## Overlay ⟂ projection (D-1)

Два ортогональных слоя над одним ключом:
- **projection** — read-only зеркало zot (source of truth = zot): `tag_count`, `size_bytes`,
  `updated_at`, `artifact_types`, `last_pulled_at`, `download_count`. Существует пока ≥1 тег.
- **overlay** — DB-owned строка `repository_configs` (durable): `description`, `labels`,
  `visibility`, `created_at`. **Переживает пустоту**.

Публичный `Repository` = LEFT JOIN overlay + projection. Tenant-виден ⟺ есть overlay-строка
ИЛИ проекция несёт ≥1 тег.

## Два класса

- **Ephemeral** — проекция без overlay: register-on-first-push, `visibility=PRIVATE`,
  исчезает при опустошении (back-compat, unchanged).
- **Durable** — есть overlay-строка (Create / Update-promote / Rename-auto-promote):
  survives-empty (`tagCount=0` виден), несёт config, unregister-on-last-tag НЕ срабатывает.

## Инварианты (DB-level, ban #10)

- `PRIMARY KEY(registry_id, name)` — дубликат/rename-collision → 23505 → `ALREADY_EXISTS`.
- `visibility CHECK IN('PRIVATE','PUBLIC')`, fail-safe дефолт `PRIVATE`.
- FK `registry_id → registries(id) ON DELETE CASCADE` (same-DB, ban #4).
- Rename = одностейтментная запись под PK-backstop: **re-key `UPDATE`** (durable) /
  **`INSERT`** (ephemeral auto-promote, A23). Visibility-flip = single-statement CAS (B09).
- **ACTIVE-guard**: overlay-мутации в tx c `SELECT registries.status FOR UPDATE`; `DELETING`
  → `FAILED_PRECONDITION "registry is being deleted"` (A24).

## visibility + anon (D-6/D-7)

`visibility{PRIVATE|PUBLIC}` authoritative на overlay. **Любой путь к PUBLIC требует registry
`admin`**: per-repo flip (B02), create-with-PUBLIC (B08), `default_visibility=PUBLIC` (B10).
Исключение: inherited-default PUBLIC на create без явного поля (gate-at-default, B12).
`visibility=PUBLIC` ⟺ FGA-tuple `user:* v_get registry_repository:<reg>/<repo>` (эмитится
transactional-outbox по итоговому visibility). Anon data-plane pull — **отдельный iam-срез**.

## Lifecycle-мутации (async → Operation)

`CreateRepository` (adopt-additive owner-tuple) · `UpdateRepository` (FieldMask, promote
ephemeral→durable) · `DeleteRepository` (reject-if-tags в worker'е, engine-down→UNAVAILABLE,
A14) · `RenameRepository` (engine re-home fail-closed A21, same-registry only D-5). Read:
`GetRepository` (existence-hiding NOT_FOUND) + `ListReferrers` (bounded projection, C01-C04).

## Gotchas

- Existence-hiding deny → **`NOT_FOUND "repository not found"`** (байт-в-байт unauthorized==absent).
- `created_at` берётся из InsertConfig RETURNING (DB-assigned), не из входного cfg.
- Adopt-owner аддитивен: не снимает owner-tuple исходного пушера (iam дедуплицирует, A03).
- `ListRepositories` = overlay ⊔ projection union (durable-empty survives, A20).

#resource #kacho-registry #registry
