---
title: "Obsidian vault — local CLAUDE.md"
aliases:
  - vault CLAUDE
category: hub
tags:
  - vault
  - conventions
---

# Obsidian vault — local CLAUDE.md

> [!important] Перед изменением vault
> Прочитай workspace `kacho-workspace/CLAUDE.md` §«Obsidian vault — обязательный context-источник и trail». Это правило обязательно для всех Kacho-проектов.

## Принципы (mirror правила workspace)

- **Файлы 1-3KB**, узкие, самодостаточные. Не дублировать содержимое.
- **Категории**: `resources/` / `rpc/` / `packages/` / `edges/` / `KAC/`.
- **Wikilinks** для связей. `[[KAC-94]]` / `[[resources/vpc-network]]`.
- **Tags** для группировки: `#kac`, `#kacho-vpc`, `#resource`, `#rpc`, `#edge`, `#packages`.
- **KAC-trail** обязателен для каждого тикета.
- Source of truth для прямых ссылок на код — путь в `kacho-workspace/project/<repo>/...`.

## Канонические теги (consolidated)

Никогда не создавай новые синонимы. Используй только из этого списка (иначе Bases/фильтры ломаются):

- **Repo**: `kacho-vpc`, `kacho-iam`, `kacho-corelib`, `kacho-proto`, `kacho-api-gateway`, `kacho-compute`, `kacho-deploy`, `kacho-vpc-implement`, `kacho-ui`, `kacho-test` (для каждого репо — **полное** имя, не `vpc`/`iam`/`apigw`). (`kacho-rm`/`kacho-resource-manager` упразднён KAC-124 → `kacho-iam`.)
- **Category**: `resource`, `rpc`, `packages`, `edge`, `kac`, `hub`, `vault`, `conventions`, `index` (используются Bases-фильтрами — не менять).
- **Architecture**: `cqrs`, `architecture`, `dependencies` (не `imports`), `polyrepo`, `proto` (не `protobuf`), `grpc`, `go`, `migrations`, `cross-service`, `internal`, `composition-root`, `cmd`, `config`, `handler`, `repo`, `service`, `domain`, `dto`, `clients`, `usecase`, `ports`.
- **Status**: `done`, `planned`, `deprecated`, `legacy`, `wontfix`, `experimental`, `stable`, `race-fix`.
- **Type (KAC)**: `epic`, `feature`, `fix`, `refactor`, `docs`.
- **NIC alias**: `ni` (не `nic` — кроме legacy в `resources/vpc-networkinterface.md`).
- **Skill/convention**: `evgeniy`, `kepano`.

## Структура

См. [[INDEX]] для алфавитного списка и [[README]] для категориального.

## Bases + Canvas

- **Bases** (kepano-style native database views): [[KAC/all-tickets|KAC tickets]], [[resources/all-resources|resources]], [[rpc/all-services|gRPC services]], [[packages/all-packages|packages]].
- **Canvas**: [[architecture.canvas]] — визуальное полотно repo cards + build/runtime edges.

## Frontmatter discipline (kepano-style)

Каждый узкий файл имеет YAML frontmatter (минимум `title`, `category`, `tags`). Дополнительные поля per-категория:

- **resources/**: `domain`, `id_prefix`, `owner_table`, `folder_level`, `status`, `related_rpc[]`, `related_packages[]`.
- **rpc/**: `proto_file`, `backend`, `backend_port`, `visibility`, `domain`, `related_resource`, `methods_count`, `async_methods`, `status`.
- **packages/**: `repo`, `layer`.
- **edges/**: `caller_repo`, `callee_repo`, `sync_async`, `protocol`, `status`, `related_tickets[]`.
- **KAC/**: `ticket_id`, `status`, `type`, `repos[]`, `prs[]`, `yt_url`, `opened`, `closed`.

Inline `#tag`-строка в конце файла остаётся синхронной с `tags:` (kepano best practice: один источник, две локации).

## Callouts (вместо обычных blockquote)

Где уместно — `> [!type] title` (вместо `> текст` или `> **Warning** ...`). Common types: `note`, `tip`, `warning`, `important`, `quote`, `example`.

## Запреты

- Секреты (токены / пароли) — НЕЛЬЗЯ (vault git-committed).
- 50KB README — НЕЛЬЗЯ (≤ 3KB, разбивать на узкие файлы).
- Stale data — НЕЛЬЗЯ (фикси сразу).

#vault #conventions
