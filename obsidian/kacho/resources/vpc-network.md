---
title: Network
aliases:
  - Network (vpc)
  - vpc Network
category: resource
domain: vpc
id_prefix: net
owner_table: kacho_vpc.networks
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05; абзац «Супернет» сверен с деревом продукта 4d26e330 (2026-08-12) — контракт поля и следствие пустого набора, остальной текст записки в тот заход не пересматривался"
related_rpc:
  - "[[rpc/vpc-network-service]]"
  - "[[rpc/vpc-internal-network-service]]"
related_packages:
  - "[[packages/vpc-domain]]"
  - "[[packages/vpc-repo-kacho-pg]]"
tags:
  - resource
  - kacho-vpc
  - network
---

# Network

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (каталог монорепо `services/vpc/`)
**ID prefix**: `net` (`ids.PrefixNetwork`, `pkg/ids/ids.go`)
**Owner table**: `kacho_vpc.networks` (БД `kacho_vpc`)
**Scope**: project — `UNIQUE (project_id, name) WHERE name <> ''`

**Контракт**: `proto/kacho/cloud/vpc/v1/network.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0007, 0015, 0016, 0017

## Поля публичной проекции (`message Network`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `net<17-crockford-base32>`; immutable на всю жизнь ресурса (ban #15) |
| `project_id` | string | cross-service ссылка → **iam** `Project`; без FK через границу сервиса |
| `created_at` | Timestamp | в ответе truncate до секунд |
| `name` | string | косметический project-scoped label, меняется свободно |
| `description` | string | ≤ 256 символов (DB CHECK) |
| `labels` | map<string,string> | ≤ 64 пар (DB CHECK `kacho_labels_valid`) |
| `default_security_group_id` | string | для тенанта output-only; ставится только internal-ручкой |
| `ipv4_cidr_blocks` | repeated string | **объявленный супернет** сети — чистый НАБОР блоков; primary на уровне сети нет |
| `ipv6_cidr_blocks` | repeated string | зеркало v4 |
| `default_route_table_id` | string | output-only; системная RT, создаётся на `Network.Create` и авто-ассоциируется к каждой новой Subnet |

**Супернет (VPC-1 F2/F3; миграции 0015 → 0016 → 0017).** Каждый `Subnet.ipv4_cidr_primary`
обязан быть подмножеством одного из блоков сети. Блоки меняются **только** парой глаголов
`:add-cidr-blocks` / `:remove-cidr-blocks`; через `Update` они неизменяемы.

**Поле опционально на `Create`, но у пустого набора есть цена, и она названа (VPC-1 F7a).**
Сеть, не объявившая супернет семейства, подсеть этого семейства **не принимает** — отказ
синхронный и обучающий: он называет и семейство, и поле, и глагол, которым план объявляют.
Это не «сеть сломана», а «адресного плана у неё пока нет»: `:add-cidr-blocks` переводит сеть в
рабочее состояние без пересоздания. Вложенность из F7 действует безусловно и не пропускается
ни при каком состоянии сети — разбор границ и сценарии живут у потребителя ограничения,
[[vpc-subnet]] §«Супернет сети обязателен».

## Инфра-чувствительное поле `vrf_id` — НЕ на публичной поверхности

Колонка `networks.vrf_id bigint` (миграция `0007_network_vrf_id.sql`): `NOT NULL`, `UNIQUE`,
значение выдаёт последовательность `kacho_vpc.networks_vrf_seq` — аллокация атомарна на
INSERT, а не software check-then-act (ban #10). Это SRv6-идентификатор data-plane, то есть
ровно тот класс, который `security.md` §«Инфра-чувствительные данные» держит только в
`Internal*`-API: читается **исключительно** через `InternalNetworkService.GetNetwork` на
:9091 (`uint32 vrf_id` в `GetInternalNetworkResponse`), в `message Network` его нет.
Две проекции одного ресурса — задокументированный приём, а не дубль.

Колонка `route_distinguisher` из baseline в таблице осталась и в публичный контракт не
входит.

## Constraints / indexes (по DDL, не по памяти)

- `networks_pkey` PRIMARY KEY (id)
- `networks_project_id_name_key` — UNIQUE (project_id, name), partial `WHERE name <> ''`
- `networks_name_check`, `networks_description_check`, `networks_labels_valid` — inline CHECK в baseline
- `networks_vrf_id_key` UNIQUE (vrf_id) + диапазонный CHECK (0007)

## FK-контракт (кто ссылается на Network внутри той же БД)

- `subnets.network_id → networks(id)` — без CASCADE
- `route_tables.network_id → networks(id)` — без CASCADE
- `security_groups.network_id → networks(id) ON DELETE RESTRICT`
- `address_pool_network_default.network_id → networks(id) ON DELETE CASCADE`
- `subnet_cidr_blocks.network_id` — денормализованный ключ scope у EXCLUDE (миграция 0010), не FK

Следствие: `Delete` непустой сети → `FailedPrecondition "network is not empty"`.
Через границу сервиса каскада нет by construction (ban #4).

## Жизненный цикл

Состояние одно; `status`-поля у Network нет — провизионинг-стадии не существует.
Мутации всё равно возвращают `Operation` (ban #9), и `done=true` означает «строка
закоммичена», и только это.

## Gotcha

- **`default_security_group_id` тенант не меняет.** Ручка живёт на internal-листенере
  (`SetDefaultSecurityGroupId`, требует `system_admin`). При `Network.Create` дефолтная SG
  создаётся inline (`services/vpc/internal/apps/kacho/api/network/create.go`).
- **`default_route_table_id` до 0017 был объявлен, но никем не писался** — тенант видел
  пустую строку, хотя 0015 уже называла колонку источником истины. Поучительный экземпляр
  класса «поле объявлено, писателя нет»: `api-conventions.md` §«Принято-и-проигнорировано».
- **`NetworkService.Move` не существует** — снят как contract-removal ([[KAC-266]]);
  `project_id` неизменяем после Create.
- **`List` сети объявлен `<exempt>`** в каталоге прав (см. [[../rpc/vpc-network-service]]) —
  это не «без авторизации», а «без project-scope Check на крае»; отбор всё равно идёт
  фильтром по данным.

> [!note] История: миграции до baseline
> Номера ниже `0001_initial.sql` — археология: физически их нет, финальное состояние
> свёрнуто в baseline. Номера **0002 и выше** в `services/vpc/internal/migrations/` —
> живые, применяются поверх.

> [!note] История: kube-ovn-эпоха
> Поле `vpn_id` и data-plane-модель kube-ovn удалены до свёртки. Оставлено как история,
> а не как описание сегодняшнего дня.

## См. также

[[vpc-subnet]] · [[vpc-securitygroup]] · [[vpc-routetable]] · [[../rpc/vpc-network-service]] · [[../rpc/vpc-internal-network-service]]

#resource #vpc #network
