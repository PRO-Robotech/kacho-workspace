---
title: "Obsidian vault — local CLAUDE.md"
aliases:
  - vault CLAUDE
category: hub
status: active
tags:
  - vault
  - conventions
---

# Obsidian vault — local CLAUDE.md

> [!important] Перед изменением vault
> Прочитай корневой `CLAUDE.md` воркспейса, §«Obsidian vault — обязательный
> context-источник и trail». Это правило обязательно для всех Kacho-проектов.
>
> Здесь стоял путь с лишним префиксом имени репозитория — из корня воркспейса он не
> резолвится (найдено хуком свежести 2026-08-04). Ссылки на файлы воркспейса пишутся
> **от его корня**, а не от каталога, в котором он лежит у конкретного разработчика.

## Принципы (mirror правила workspace)

- **Одна записка — один предмет**, самодостаточно, без дублирования содержимого соседа
  (пересказ разъезжается — соседа **называют ссылкой**). Потолок «1-3KB» снят владельцем
  2026-08-05: предмет экономии — точность и пригодность к переиспользованию, а не объём.
  Канон — `.claude/rules/vault.md`; здесь он не пересказывается, чтобы два места об одном
  предмете не разошлись снова.
- **Категории** (каталог верхнего уровня = категория, других нет):
  `resources/` · `rpc/` · `packages/` · `edges/` · `KAC/` · `lessons/` · `runbooks/` ·
  `docs/` · `legacy/`. Заводить новый каталог — значит заводить новую категорию: сперва
  скажи, чем её предмет отличается от девяти существующих, и впиши её в
  `scripts/vault-index/generate.py` (иначе записки не попадут в указатель).
- **Wikilinks** для связей. Каноническая форма — **от корня хранилища**:
  `[[resources/vpc-network]]`, `[[KAC/KAC-94]]`. Короткая форма `[[KAC-94]]` тоже
  резолвится (Obsidian ищет по базовому имени) и допустима для уникальных имён; форма
  `[[../KAC/KAC-94]]` — исторический хвост, она работает, но ломается при переносе файла
  в другой каталог. Новые ссылки пишем от корня.
- **Tags** для группировки: `#kac`, `#kacho-vpc`, `#resource`, `#rpc`, `#edge`, `#packages`.
- **Trail задачи** обязателен для каждой (`KAC/issue-<N>.md`; каталог сохраняет
  историческое имя — см. `.claude/rules/git-issues.md`).
- Source of truth для прямых ссылок на код — путь в `kacho-workspace/project/<repo>/...`.

## Канонические теги (consolidated)

Никогда не создавай новые синонимы. Используй только из этого списка (иначе Bases/фильтры ломаются):

- **Repo**: `kacho-vpc`, `kacho-iam`, `kacho-geo`, `kacho-nlb`, `kacho-corelib`, `kacho-proto`, `kacho-api-gateway`, `kacho-compute`, `kacho-deploy`, `kacho-vpc-implement`, `kacho-vpc-operator`, `kacho-ui`, `kacho-test`, `kacho-registry` (для каждого репо — **полное** имя, не `vpc`/`iam`/`apigw`). (`kacho-rm`/`kacho-resource-manager` упразднён KAC-124 → `kacho-iam`.)
- **Category**: `resource`, `rpc`, `packages`, `edge`, `kac`, `lesson`, `runbook`, `docs`, `legacy`, `hub`, `vault`, `conventions`, `index` (используются Bases-фильтрами — не менять). Синонимы `package`/`edges`/`KAC`/`repo` сведены к канону 2026-08-05: срез фильтрует значение точным сравнением, и записка с синонимом выпадала из него молча.
- **Architecture**: `cqrs`, `architecture`, `dependencies` (не `imports`), `polyrepo`, `proto` (не `protobuf`), `grpc`, `go`, `migrations`, `cross-service`, `internal`, `composition-root`, `cmd`, `config`, `handler`, `repo`, `service`, `domain`, `dto`, `clients`, `usecase`, `ports`.
- **Status** (как тег): `done`, `planned`, `deprecated`, `legacy`, `wontfix`, `experimental`, `stable`, `race-fix`. Поле `status:` во frontmatter — свой, более широкий словарь, см. §«Оболочка записки».
- **Type (KAC)**: `epic`, `feature`, `fix`, `refactor`, `docs`.
- **NIC alias**: `ni` (не `nic` — кроме legacy в `resources/vpc-networkinterface.md`).
- **Skill/convention**: `evgeniy`, `kepano`.

## Структура

[[README]] — точка входа: что это, как устроено, куда идти за ресурсом / RPC / ребром /
пакетом и **чего в хранилище нет**. [[INDEX]] — полный перечень записок; его машинная
часть собирается из дерева генератором и разойтись с файлами не может.

## Bases + Canvas

- **Bases** (kepano-style native database views): [[KAC/all-tickets|KAC tickets]], [[resources/all-resources|resources]], [[rpc/all-services|gRPC services]], [[packages/all-packages|packages]].
- **Canvas**: [[architecture.canvas]] — визуальное полотно repo cards + build/runtime edges.

## Оболочка записки — одна и та же у всех категорий

Читатель обязан находить одно и то же в одном и том же месте, не читая записку целиком.
Оболочка — это пять ответов; **содержание** записки к ним не сводится и переписыванию
ради формы не подлежит.

| Ответ | Где стоит | Обязательно |
|---|---|---|
| **назначение** — про что записка | `title:` + первый `# `-заголовок | да |
| **категория** — какого рода предмет | `category:` (см. таблицу ниже) | да |
| **состояние** — живо / история / в работе | `status:` | да, кроме витрин-указателей |
| **сверено с чем** — какая ревизия дерева | `verified_against:` | для `resource`/`rpc`/`packages`/`edge` |
| **связи** | `related_*` + wikilinks в теле | да, если предмет их имеет |

`category` берётся из каталога и не выдумывается: `resources/`→`resource`, `rpc/`→`rpc`,
`packages/`→`packages`, `edges/`→`edge`, `KAC/`→`kac`, `lessons/`→`lesson`,
`runbooks/`→`runbook`, `docs/`→`docs`, `legacy/`→`legacy`; указатель категории (её
`README.md`) и корневые точки входа — `hub`.

**`status` — одно значение из канонического словаря, а не свободный текст.** Значения
делятся на три ведра; ведро — то, что читатель хочет знать первым, значение — оттенок:

| Ведро | Значения | Смысл |
|---|---|---|
| **живо** | `stable`, `active`, `done` | предмет есть в дереве **сегодня** |
| **история** | `deprecated`, `legacy`, `superseded`, `wontfix` | предмет снят или заменён; записка верна как прошлое |
| **в работе** | `in-progress`, `test`, `to-do`, `planned`, `experimental`, `reference` | предмета ещё нет либо он не проверен |

Новых синонимов не заводить: срез `all-*.base` фильтрует статусы **поимённо**, и
неизвестное значение проходит фильтр молча (см. [[KAC/README]]).

**`verified_against` — про ревизию, а не про уверенность.** Пишется тем, кто сверял, и
называет **что именно** сверено: `"каталог пакета есть в дереве продукта b4edc5d5
(2026-08-05); текст записки построчно не пересматривался"` — годная формулировка, потому
что по ней видно и предмет сверки, и её границу. `"проверено"` — негодная.

### Дополнительные поля по категориям

- **resources/**: `domain`, `id_prefix`, `owner_table`, `owner_db`, `project_level`,
  `related_rpc[]`, `related_packages[]`.
- **rpc/**: `proto_file`, `backend`, `backend_port`, `visibility`, `domain`,
  `related_resource`, `methods_count`, `async_methods`.
- **packages/**: `repo` (домен, наследие полирепо-словаря), `layer`, `path` (каталог в
  монорепо — машинно проверяемый).
- **edges/**: `caller_repo`, `callee_repo`, `sync_async`, `protocol`, `related_tickets[]`.
- **KAC/**: `ticket_id`, `type`, `repos[]`, `prs[]`, `issue_url`, `opened`, `closed`.
  (`yt_url` — поле прежнего трекера; в записках, заведённых до 2026-08-12, оно остаётся
  как история и не переписывается.)

Inline `#tag`-строка в конце файла остаётся синхронной с `tags:` (kepano best practice: один источник, две локации).

## Чем оболочка держится

- `./scripts/vault-gate/run-all.sh` — `check-02` (висячие ссылки, храповик в обе стороны)
  и `check-03` (оболочка: `title`/`category`/`status` + словарь статусов). Гейты печатают
  **объём осмотренного**, поэтому «ноль находок» отличимо от «ноль прочитанного».
- `./scripts/vault-index/generate.py` — машинная часть [[INDEX]] собирается из дерева;
  `--check` роняет прогон, когда указатель отстал. Рукописную часть указателя генератор
  не трогает.

## Callouts (вместо обычных blockquote)

Где уместно — `> [!type] title` (вместо `> текст` или `> **Warning** ...`). Common types: `note`, `tip`, `warning`, `important`, `quote`, `example`.

## Запреты

- Секреты (токены / пароли) — НЕЛЬЗЯ (vault git-committed).
- Записка обо всём сразу — НЕЛЬЗЯ: не размер, а **число предметов** (два предмета —
  два файла и ссылка между ними). Числового потолка больше нет, см. «Принципы» выше.
- Stale data — НЕЛЬЗЯ (фикси сразу).

#vault #conventions
