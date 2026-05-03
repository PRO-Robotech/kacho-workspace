# Sub-phase 0.4 — Compute (Instance / Disk / Image / Snapshot + Reconciler) — Implementation Plan

> **For agentic workers:** Acceptance APPROVED commit `9bc31d0` в `kacho-workspace/docs/specs/sub-phase-0.4-compute-acceptance.md` (88 сценариев, 16 групп A–O; P = Definition of Done).

**Goal:** `kacho-proto` получает домен compute; `kacho-compute` — полностью реализованный сервис с reconciler-ом, симулирующим lifecycle VM/Disk/Snapshot; cross-service клиенты к resource-manager и vpc; finalizer `compute.kacho.io/disk-detach`; сервис деплоится в kind-кластер через Helm.

**Architecture:** Clean Architecture per `kacho-workspace/CLAUDE.md`: handler → service → repo с port-интерфейсами. Reconciler — отдельный пакет `internal/reconciler/`, горутина-per-resource-type с `pg_advisory_lock(uid_hash)` для координации реплик. Watch Hub реиспользуется из `kacho-corelib/watch`. Cross-service клиенты реализуют port-интерфейсы из `service/` в `internal/clients/`. Симулированные задержки параметризуются через env-переменные.

**Tech stack:** Go 1.22+ (golang.org/x/exp/slog), buf, pgx/v5, sqlc, goose миграции, testcontainers-go, grpcurl для e2e, `kacho-corelib` (watch, outbox, db, grpcsrv, grpcclient).

---

## §0. Resolutions для 7 OQ и 6 nits

### OQ-resolutions

| # | Вопрос | Решение |
|---|---|---|
| OQ-1 | Точные интервалы симулированных задержек | Параметризуются env-переменными: `KACHO_COMPUTE_SIM_<STAGE>_MIN_MS` / `_MAX_MS`. Prod defaults: `PROVISIONING` 5000–30000 мс, `STOPPING`/`STARTING` 5000–15000 мс, `SNAPSHOT` 10000–30000 мс, `CREATING` (Disk) 3000–10000 мс. В integration-тестах: `MIN_MS=100`, `MAX_MS=200`. |
| OQ-2 | Snapshot progress_percent — политика инкрементов | Вариант A: фиксированные шаги `0 → 25 → 50 → 75 → 100`. Reconciler спит `totalDuration / 4` между шагами. Каждый шаг эмитирует `MODIFIED` событие через `UpdateSnapshotStatus`. |
| OQ-3 | Disk attach в PROVISIONING | Вариант C: отдельная фаза. Reconciler: `PROVISIONING → (диски: ATTACHING → READY-attached) → RUNNING`. Диски видимо проходят через `ATTACHING` до перехода Instance в `RUNNING` — покрывает сценарии F1, F2. |
| OQ-4 | status.ips.internal — назначение IP | Вариант C + A: детерминированный псевдо-IP `10.0.0.<hash(uid) % 250 + 2>`. Если клиент задал `spec.networkInterfaces[0].primaryV4Address.address` — приоритет за ним. Нет cross-service IPAM в 0.4. |
| OQ-5 | Image без Watch | Подтверждено: `ImageService` — read-only, методы `Get`/`List` только. `Watch` отсутствует. Images — seed-каталог без runtime-изменений. |
| OQ-6 | Restart RPC response | `InstanceRestartResponse` возвращает полный объект `Instance` (с обновлённым `metadata.restartedAt`) — единообразно с другими мутирующими RPC. |
| OQ-7 | Reconciler при накопленных переходах | Вариант A: «завершить текущий переход → следующий poll цикл». Без cancellation. Reconciler замечает изменённый `desiredPowerState` после завершения текущего шага и начинает новый цикл. |

### Nit-resolutions

| # | Nit | Решение |
|---|---|---|
| N1 | RESTARTING в публичном enum | Убрать `RESTARTING` из публичного `Instance.Status.State`. Reconciler внутри делает stop+start цикл. Watch при Restart покажет: `STOPPING → STOPPED → STARTING → RUNNING`. |
| N2 | Upsert с bootDisk не в READY | Добавить test case `TestInstance_E6extra_BootDiskNotReady`: `DiskService/Upsert` с диском в состоянии `CREATING` → `FAILED_PRECONDITION`. |
| N3 | G3 Watch assert | `TestInstance_G3_DesiredStoppedFromCreation` явно ожидает `STOPPED` через Watch в течение 60 секунд (не только проверяет отсутствие `RUNNING`). |
| N4 | N1–N5 naming | Тесты миграций именуются `TestMigration_N1_SeedZones`, `TestMigration_N2_SeedDiskTypes` и т.д. в пакете `migrations_test`. |
| N5 | J1 multi-replica test | Использовать channel-based synchronization barrier: оба goroutine ждут `ready` канал перед началом попытки взять lock — детерминированность теста. |
| N6 | Косметика §17 | В acceptance-документе убрать `(§11)` из заголовка §17 (при следующем редактировании). В плане используем корректное именование. |

---

## §1. File map (cross-repo)

### `kacho-proto/` — Phase A
```
proto/kacho/cloud/compute/v1/
  instance.proto          — InstanceService (Upsert/Delete/List/Watch/Restart) + messages
  disk.proto              — DiskService (Upsert/Delete/List/Watch) + messages
  image.proto             — ImageService (Get/List) + messages
  snapshot.proto          — SnapshotService (Upsert/Delete/List/Watch) + messages
  internal.proto          — ComputeInternal (InstanceExists/UpdateInstanceStatus/UpdateDiskStatus/
                              UpdateSnapshotStatus/UpdateInstanceMetadata)
gen/go/kacho/cloud/compute/v1/
  *.pb.go                 — committed после buf generate
  *_grpc.pb.go
```

### `kacho-compute/` — Phase B (основная работа)
```
cmd/compute/main.go                        — composition root (serve/migrate subcommands)

internal/domain/
  instance.go                              — entity Instance (stdlib + kacho-proto только)
  disk.go                                  — entity Disk
  image.go                                 — entity Image
  snapshot.go                              — entity Snapshot
  types.go                                 — shared enums, ResourceSpec, NetworkInterface и т.д.

internal/service/
  ports.go                                 — InstanceRepo, DiskRepo, ImageRepo, SnapshotRepo,
                                             FolderClient, SubnetClient port-интерфейсы
  instance.go                              — InstanceService use-cases
  disk.go                                  — DiskService use-cases
  image.go                                 — ImageService use-cases
  snapshot.go                              — SnapshotService use-cases
  instance_test.go                         — unit-тесты с mock-port-интерфейсами
  disk_test.go
  snapshot_test.go

internal/repo/
  instance_repo.go                         — реализует InstanceRepo (pgx + sqlc + outbox)
  disk_repo.go
  image_repo.go
  snapshot_repo.go
  queries/                                 — sqlc-generated (instances.sql.go, disks.sql.go, …)
  filter_builder.go                        — WHERE-clause builder для FieldSelector

internal/clients/
  folder_client.go                         — реализует FolderClient (gRPC → resource-manager)
  subnet_client.go                         — реализует SubnetClient (gRPC → vpc)

internal/reconciler/
  dispatcher.go                            — главный цикл: SELECT pending resources → dispatch
  instance_handler.go                      — PROVISIONING→RUNNING, Stop/Start, Restart, Finalizer
  disk_handler.go                          — CREATING→READY
  snapshot_handler.go                      — CREATING с прогрессом → READY
  advisory_lock.go                         — pg_advisory_lock helpers

internal/handler/
  instance_handler.go                      — gRPC transport для InstanceService
  disk_handler.go
  image_handler.go
  snapshot_handler.go
  internal_handler.go                      — ComputeInternal (НЕ регистрируется в api-gateway)

migrations/
  common/                                  — sync из kacho-corelib (resource_events, seq)
  0001_initial.sql                         — instances, disks, images, snapshots, attachments,
                                             zones, disk_types, platforms, images_catalog таблицы
  0002_seed_catalogs.sql                   — seed-данные: zones, disk_types, platforms, images_catalog

deploy/
  Dockerfile
  Chart.yaml
  values.yaml
  values.dev.yaml
  templates/
    deployment.yaml
    service.yaml
    configmap.yaml

Makefile
go.mod
go.sum
.github/workflows/ci.yaml
```

### `kacho-deploy/` — Phase C
```
helm/umbrella/Chart.yaml           — раскомментировать compute dep
helm/umbrella/values.dev.yaml      — добавить compute: секцию
e2e/0.4/
  O1-full-flow.sh
  O2-restart.sh
  O3-power-state.sh
  O4-delete-with-finalizer.sh
  O5-snapshot.sh
  O6-helm-deploy.sh
```

---

## §2. Phase A — kacho-proto/compute/v1

**Acceptance scenarios:** A1–A6

### A.1 instance.proto

```protobuf
syntax = "proto3";
package kacho.cloud.compute.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/compute/v1;computev1";

import "kacho/cloud/common/v1/resource_meta.proto";
import "kacho/cloud/common/v1/selector.proto";
import "kacho/cloud/common/v1/watch_event.proto";
import "google/protobuf/timestamp.proto";

// ResourceSpec — CPU/RAM конфигурация
message ResourceSpec {
  int32 cores = 1;
  string memory = 2;   // "4Gi"
  int32 core_fraction = 3;  // опционально, 0 = 100%
}

// AttachedDisk — ссылка на Disk при монтировании к Instance
message AttachedDisk {
  string disk_id = 1;
  string device_name = 2;
  bool auto_delete = 3;
}

// NetworkInterface — сетевой интерфейс Instance
message NetworkInterface {
  string subnet_id = 1;
  repeated string security_group_ids = 2;
  PrimaryV4Address primary_v4_address = 3;
}

message PrimaryV4Address {
  string address = 1;  // если задан клиентом — используется как ip
}

message InstanceSpec {
  string display_name = 1;
  string description = 2;
  string platform_id = 3;
  string zone_id = 4;
  ResourceSpec resources = 5;
  AttachedDisk boot_disk = 6;
  repeated AttachedDisk secondary_disks = 7;
  repeated NetworkInterface network_interfaces = 8;
  SchedulingPolicy scheduling_policy = 9;
  map<string, string> metadata = 10;  // user-data
  string fqdn = 11;
  DesiredPowerState desired_power_state = 12;
}

message SchedulingPolicy {
  bool preemptible = 1;
}

enum DesiredPowerState {
  DESIRED_POWER_STATE_UNSPECIFIED = 0;
  RUNNING = 1;
  STOPPED = 2;
}

message InstanceIPs {
  string internal = 1;
  string external = 2;  // зарезервировано
}

message InstanceStatus {
  enum State {
    STATE_UNSPECIFIED = 0;
    PROVISIONING = 1;
    RUNNING = 2;
    STOPPING = 3;
    STOPPED = 4;
    STARTING = 5;
    // RESTARTING намеренно отсутствует (nit-1): цикл stop+start без отдельного видимого state
    UPDATING = 7;
    ERROR = 8;
    DELETING = 9;
  }
  State state = 1;
  google.protobuf.Timestamp state_last_transition_at = 2;
  InstanceIPs ips = 3;
  string fqdn = 4;
  string host_id = 5;
  google.protobuf.Timestamp last_restart_completed_at = 6;
  repeated StatusCondition conditions = 7;
}

message StatusCondition {
  string type = 1;
  string status = 2;
  string reason = 3;
  string message = 4;
}

message Instance {
  kacho.cloud.common.v1.ResourceMeta metadata = 1;
  InstanceSpec spec = 2;
  InstanceStatus status = 3;
}

// --- Request/Response messages ---

message InstanceUpsertRequest { repeated Instance instances = 1; }
message InstanceUpsertResponse { repeated Instance instances = 1; }

message InstanceDeleteRequest {
  message Item { string uid = 1; string name = 2; }
  repeated Item items = 1;
}
message InstanceDeleteResponse {}

message InstanceListRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string page_token = 10;
  int32 page_size = 11;
}
message InstanceListResponse {
  repeated Instance instances = 1;
  string resource_version = 2;
  string next_page_token = 3;
}

message InstanceWatchRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string resource_version = 2;
}

message InstanceRestartRequest {
  message Item { string uid = 1; }
  repeated Item instances = 1;
}
message InstanceRestartResponse { repeated Instance instances = 1; }  // OQ-6: полный объект

service InstanceService {
  rpc Upsert(InstanceUpsertRequest) returns (InstanceUpsertResponse);
  rpc Delete(InstanceDeleteRequest) returns (InstanceDeleteResponse);
  rpc List(InstanceListRequest) returns (InstanceListResponse);
  rpc Watch(InstanceWatchRequest) returns (stream kacho.cloud.common.v1.WatchEvent);
  rpc Restart(InstanceRestartRequest) returns (InstanceRestartResponse);
}
```

### A.2 disk.proto

`Disk.Spec` содержит поля: `disk_type_id`, `zone_id`, `size` (string "50Gi"), `image_id` (опционально), `display_name`, `description`.

`Disk.Status.State` enum: `STATE_UNSPECIFIED`, `CREATING`, `READY`, `ATTACHING`, `DETACHING`, `ERROR`, `DELETING`.

`Disk.Status` дополнительно содержит `attached_to_instance_id string` и `device_name string`.

`DiskService` с методами `Upsert`, `Delete`, `List`, `Watch` (аналогично InstanceService).

### A.3 image.proto

`ImageService` — только `Get` и `List` (без Upsert/Delete/Watch — сценарий C4). `Image.Status.state` всегда `READY`. `Image.Spec` содержит `display_name`, `description`, `os_type`, `min_disk_size` (string). Нет folderId — образы глобальные.

### A.4 snapshot.proto

`Snapshot.Spec`: `disk_id string`, `display_name string`, `description string`.

`Snapshot.Status.State` enum: `CREATING`, `READY`, `ERROR`, `DELETING`.

`Snapshot.Status` дополнительно содержит `progress_percent int32` (0–100) — сценарии D2, D3, L3.

`SnapshotService`: `Upsert`, `Delete`, `List`, `Watch`.

### A.5 internal.proto

```protobuf
service ComputeInternal {
  rpc InstanceExists(InstanceExistsRequest) returns (InstanceExistsResponse);
  rpc UpdateInstanceStatus(UpdateInstanceStatusRequest) returns (UpdateInstanceStatusResponse);
  rpc UpdateDiskStatus(UpdateDiskStatusRequest) returns (UpdateDiskStatusResponse);
  rpc UpdateSnapshotStatus(UpdateSnapshotStatusRequest) returns (UpdateSnapshotStatusResponse);
  rpc UpdateInstanceMetadata(UpdateInstanceMetadataRequest) returns (UpdateInstanceMetadataResponse);
}
```

`InstanceExistsResponse.exists = false` для soft-deleted Instance (сценарии K2, K3).

### A.6 Deliverables Phase A

- 5 `.proto` файлов в `kacho-proto/proto/kacho/cloud/compute/v1/`
- `gen/go/kacho/cloud/compute/v1/*.pb.go` + `*_grpc.pb.go` — committed после `buf generate`
- `buf lint` чистый (A1), `buf breaking` не регрессирует (A2)
- CI kacho-proto: buf-lint + buf-breaking + buf-generate (без drift в gen/) зелёный

---

## §3. Phase B — kacho-compute service

**Acceptance scenarios:** B1–B9, C1–C5, D1–D6, E1–E9, F1–F3, G1–G4, H1–H4, I1–I4, J1–J5, K1–K7, L1–L5, M1–M10, N1–N5

### B.1 Skeleton + go.mod + sqlc setup

**go.mod** module: `github.com/PRO-Robotech/kacho-compute`

Зависимости:
- `github.com/PRO-Robotech/kacho-proto` — grpc-stubs
- `github.com/PRO-Robotech/kacho-corelib` — watch, outbox, db, grpcsrv, grpcclient, ids, errors, observability
- `github.com/jackc/pgx/v5`
- `github.com/pressly/goose/v3`
- `google.golang.org/grpc`
- `google.golang.org/protobuf`
- `github.com/testcontainers/testcontainers-go` (dev)
- `github.com/stretchr/testify` (dev)

**sqlc.yaml**: генерация в `internal/repo/queries/` из `migrations/*.sql` + `internal/repo/sql/*.sql` (SQL-запросы). Engine: `postgresql`. Эмитирует: `sqlc.v1`.

**Makefile targets:** `generate` (buf + sqlc), `test`, `lint`, `build`, `docker-build`.

### B.2 Migrations

#### 0001_common (sync из kacho-corelib)

Содержит таблицу `resource_events` и sequence `resource_version_seq` — синхронизируется из `kacho-corelib/migrations/common/`. Команда `make sync-migrations`.

#### 0001_initial.sql — основная схема

```sql
-- kacho_compute database schema

CREATE TABLE zones (
  name        TEXT PRIMARY KEY,
  region_id   TEXT NOT NULL,
  description TEXT
);

CREATE TABLE disk_types (
  id          TEXT PRIMARY KEY,
  description TEXT
);

CREATE TABLE platforms (
  id          TEXT PRIMARY KEY,
  description TEXT,
  cores_min   INT  NOT NULL DEFAULT 1,
  cores_max   INT  NOT NULL DEFAULT 96,
  memory_min  TEXT NOT NULL DEFAULT '1Gi',
  memory_max  TEXT NOT NULL DEFAULT '512Gi'
);

CREATE TABLE images_catalog (
  uid                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                TEXT        UNIQUE NOT NULL,
  display_name        TEXT,
  description         TEXT,
  os_type             TEXT,
  min_disk_size       TEXT        NOT NULL DEFAULT '10Gi',
  status              TEXT        NOT NULL DEFAULT 'READY',
  creation_timestamp  TIMESTAMPTZ NOT NULL DEFAULT now(),
  labels              JSONB       NOT NULL DEFAULT '{}'
);

CREATE TABLE disks (
  uid                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                      TEXT        NOT NULL,
  folder_id                 UUID        NOT NULL,
  labels                    JSONB       NOT NULL DEFAULT '{}',
  annotations               JSONB       NOT NULL DEFAULT '{}',
  finalizers                TEXT[]      NOT NULL DEFAULT '{}',
  creation_timestamp        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletion_timestamp        TIMESTAMPTZ,
  resource_version          BIGINT      NOT NULL DEFAULT nextval('resource_version_seq'),
  generation                BIGINT      NOT NULL DEFAULT 1,
  -- spec fields
  disk_type_id              TEXT        NOT NULL REFERENCES disk_types(id),
  zone_id                   TEXT        NOT NULL REFERENCES zones(name),
  size                      TEXT        NOT NULL,
  image_id                  UUID        REFERENCES images_catalog(uid),
  display_name              TEXT,
  description               TEXT,
  -- status fields
  state                     TEXT        NOT NULL DEFAULT 'CREATING',
  state_last_transition_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  attached_to_instance_id   UUID,       -- FK добавляется после CREATE TABLE instances
  device_name               TEXT,
  UNIQUE (folder_id, name)
);
CREATE INDEX idx_disks_folder_id ON disks(folder_id);
CREATE INDEX idx_disks_labels ON disks USING gin(labels jsonb_path_ops);

CREATE TABLE instances (
  uid                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                        TEXT        NOT NULL,
  folder_id                   UUID        NOT NULL,
  labels                      JSONB       NOT NULL DEFAULT '{}',
  annotations                 JSONB       NOT NULL DEFAULT '{}',
  finalizers                  TEXT[]      NOT NULL DEFAULT '{"compute.kacho.io/disk-detach"}',
  creation_timestamp          TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletion_timestamp          TIMESTAMPTZ,
  resource_version            BIGINT      NOT NULL DEFAULT nextval('resource_version_seq'),
  generation                  BIGINT      NOT NULL DEFAULT 1,
  restarted_at                TIMESTAMPTZ,
  -- spec fields (JSONB для сложных вложенных структур)
  platform_id                 TEXT        NOT NULL REFERENCES platforms(id),
  zone_id                     TEXT        NOT NULL REFERENCES zones(name),
  resources_cores             INT         NOT NULL,
  resources_memory            TEXT        NOT NULL,
  resources_core_fraction     INT         NOT NULL DEFAULT 100,
  boot_disk_id                UUID        REFERENCES disks(uid),
  boot_disk_device_name       TEXT,
  boot_disk_auto_delete       BOOLEAN     NOT NULL DEFAULT false,
  secondary_disks             JSONB       NOT NULL DEFAULT '[]',   -- [{disk_id, device_name, auto_delete}]
  network_interfaces          JSONB       NOT NULL DEFAULT '[]',   -- [{subnet_id, sg_ids, primary_v4_addr}]
  scheduling_policy           JSONB       NOT NULL DEFAULT '{}',
  user_metadata               JSONB       NOT NULL DEFAULT '{}',
  fqdn                        TEXT,
  desired_power_state         TEXT        NOT NULL DEFAULT 'RUNNING',
  -- status fields
  state                       TEXT        NOT NULL DEFAULT 'PROVISIONING',
  state_last_transition_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ips_internal                TEXT,
  last_restart_completed_at   TIMESTAMPTZ,
  UNIQUE (folder_id, name)
);
CREATE INDEX idx_instances_folder_id ON instances(folder_id);
CREATE INDEX idx_instances_labels ON instances USING gin(labels jsonb_path_ops);
CREATE INDEX idx_instances_state ON instances(state) WHERE deletion_timestamp IS NULL;

-- FK от disks.attached_to_instance_id → instances
ALTER TABLE disks ADD CONSTRAINT fk_disk_instance
  FOREIGN KEY (attached_to_instance_id) REFERENCES instances(uid) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE snapshots (
  uid                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                      TEXT        NOT NULL,
  folder_id                 UUID        NOT NULL,
  labels                    JSONB       NOT NULL DEFAULT '{}',
  annotations               JSONB       NOT NULL DEFAULT '{}',
  finalizers                TEXT[]      NOT NULL DEFAULT '{}',
  creation_timestamp        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletion_timestamp        TIMESTAMPTZ,
  resource_version          BIGINT      NOT NULL DEFAULT nextval('resource_version_seq'),
  generation                BIGINT      NOT NULL DEFAULT 1,
  -- spec
  disk_id                   UUID        NOT NULL REFERENCES disks(uid),
  display_name              TEXT,
  description               TEXT,
  -- status
  state                     TEXT        NOT NULL DEFAULT 'CREATING',
  state_last_transition_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  progress_percent          INT         NOT NULL DEFAULT 0,
  UNIQUE (folder_id, name)
);
CREATE INDEX idx_snapshots_folder_id ON snapshots(folder_id);

-- BEFORE UPDATE triggers: resource_version + generation
CREATE OR REPLACE FUNCTION kacho_compute_bump_rv() RETURNS trigger AS $$
BEGIN
  NEW.resource_version := nextval('resource_version_seq');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_instances_rv BEFORE UPDATE ON instances
  FOR EACH ROW EXECUTE FUNCTION kacho_compute_bump_rv();
CREATE TRIGGER trg_disks_rv BEFORE UPDATE ON disks
  FOR EACH ROW EXECUTE FUNCTION kacho_compute_bump_rv();
CREATE TRIGGER trg_snapshots_rv BEFORE UPDATE ON snapshots
  FOR EACH ROW EXECUTE FUNCTION kacho_compute_bump_rv();
```

Стратегия FK: same-DB, RESTRICT (нет cascade через границу сервиса). `attached_to_instance_id` — DEFERRABLE для транзакций с одновременной вставкой instance + disk.

#### 0002_seed_catalogs.sql — seed-данные (сценарии N1–N5)

```sql
-- Zones (N1)
INSERT INTO zones (name, region_id, description) VALUES
  ('kacho-zone-a', 'kacho-region-a', 'Availability zone A'),
  ('kacho-zone-b', 'kacho-region-a', 'Availability zone B')
ON CONFLICT (name) DO NOTHING;

-- Disk types (N2)
INSERT INTO disk_types (id, description) VALUES
  ('network-hdd',              'Network HDD'),
  ('network-ssd',              'Network SSD'),
  ('network-ssd-nonreplicated','Network SSD non-replicated')
ON CONFLICT (id) DO NOTHING;

-- Platforms (N3)
INSERT INTO platforms (id, description, cores_min, cores_max) VALUES
  ('standard-v1', 'Intel Broadwell',   2, 32),
  ('standard-v2', 'Intel Cascade Lake', 2, 80),
  ('standard-v3', 'Intel Ice Lake',    2, 96)
ON CONFLICT (id) DO NOTHING;

-- Images catalog (N4)
INSERT INTO images_catalog (name, display_name, os_type, min_disk_size, status) VALUES
  ('ubuntu-2204-lts', 'Ubuntu 22.04 LTS', 'LINUX', '10Gi', 'READY'),
  ('debian-12',       'Debian 12',        'LINUX', '10Gi', 'READY')
ON CONFLICT (name) DO NOTHING;
```

`ON CONFLICT DO NOTHING` обеспечивает идемпотентность повторного применения (N5).

Тесты миграций именуются `TestMigration_N1_SeedZones`, `TestMigration_N2_SeedDiskTypes`, `TestMigration_N3_SeedPlatforms`, `TestMigration_N4_SeedImages`, `TestMigration_N5_SeedIdempotent` в пакете `migrations_test` (nit-4).

### B.3 Domain entities

#### internal/domain/instance.go

```go
package domain

import "time"

// Instance — entity ВМ; импортирует только stdlib.
type Instance struct {
    UID                    string
    Name                   string
    FolderID               string
    Labels                 map[string]string
    Annotations            map[string]string
    Finalizers             []string
    CreationTimestamp      time.Time
    DeletionTimestamp      *time.Time
    ResourceVersion        int64
    Generation             int64
    RestartedAt            *time.Time

    // Spec
    PlatformID             string
    ZoneID                 string
    ResourcesCores         int32
    ResourcesMemory        string
    ResourcesCoresFraction int32
    BootDisk               *AttachedDiskRef
    SecondaryDisks         []AttachedDiskRef
    NetworkInterfaces      []NetworkInterfaceRef
    DesiredPowerState      DesiredPowerStateEnum
    UserMetadata           map[string]string
    FQDN                   string

    // Status
    State                  InstanceState
    StateLastTransitionAt  time.Time
    IPsInternal            string
    LastRestartCompletedAt *time.Time
}

type AttachedDiskRef struct {
    DiskID     string
    DeviceName string
    AutoDelete bool
}

type NetworkInterfaceRef struct {
    SubnetID         string
    SecurityGroupIDs []string
    PrimaryV4Address string
}

type DesiredPowerStateEnum string
const (
    DesiredRunning DesiredPowerStateEnum = "RUNNING"
    DesiredStopped DesiredPowerStateEnum = "STOPPED"
)

type InstanceState string
const (
    InstanceProvisioning InstanceState = "PROVISIONING"
    InstanceRunning      InstanceState = "RUNNING"
    InstanceStopping     InstanceState = "STOPPING"
    InstanceStopped      InstanceState = "STOPPED"
    InstanceStarting     InstanceState = "STARTING"
    InstanceUpdating     InstanceState = "UPDATING"
    InstanceError        InstanceState = "ERROR"
    InstanceDeleting     InstanceState = "DELETING"
    // RESTARTING отсутствует (nit-1)
)
```

Аналогично `disk.go` (DiskState: CREATING/READY/ATTACHING/DETACHING/ERROR/DELETING), `image.go` (всегда READY), `snapshot.go` (SnapshotState + ProgressPercent int32).

**Запрет:** `domain/` и `service/` не импортируют `pgx`, sqlc-types, grpc-stubs — это правило Clean Architecture.

### B.4 Service ports + use-cases

#### internal/service/ports.go

```go
package service

import (
    "context"
    "github.com/PRO-Robotech/kacho-compute/internal/domain"
)

type InstanceRepo interface {
    Get(ctx context.Context, uid string) (*domain.Instance, error)
    GetByName(ctx context.Context, folderID, name string) (*domain.Instance, error)
    List(ctx context.Context, filter FieldFilter, page Pagination) ([]*domain.Instance, int64, error)
    Upsert(ctx context.Context, inst *domain.Instance) (*domain.Instance, error)
    SoftDelete(ctx context.Context, uid string) error
    Delete(ctx context.Context, uid string) error   // физическое (для reconciler finalizer)
    GetPendingReconcile(ctx context.Context, limit int) ([]*domain.Instance, error)
}

type DiskRepo interface {
    Get(ctx context.Context, uid string) (*domain.Disk, error)
    GetByName(ctx context.Context, folderID, name string) (*domain.Disk, error)
    List(ctx context.Context, filter FieldFilter, page Pagination) ([]*domain.Disk, int64, error)
    Upsert(ctx context.Context, disk *domain.Disk) (*domain.Disk, error)
    Delete(ctx context.Context, uid string) error
    GetAttachedDisks(ctx context.Context, instanceUID string) ([]*domain.Disk, error)
    UpdateStatus(ctx context.Context, uid string, status domain.DiskStatusPatch) error
}

type SnapshotRepo interface {
    Get(ctx context.Context, uid string) (*domain.Snapshot, error)
    List(ctx context.Context, filter FieldFilter, page Pagination) ([]*domain.Snapshot, int64, error)
    Upsert(ctx context.Context, snap *domain.Snapshot) (*domain.Snapshot, error)
    Delete(ctx context.Context, uid string) error
    GetPendingReconcile(ctx context.Context, limit int) ([]*domain.Snapshot, error)
}

type ImageRepo interface {
    Get(ctx context.Context, uid string) (*domain.Image, error)
    List(ctx context.Context, filter FieldFilter, page Pagination) ([]*domain.Image, int64, error)
}

// FolderClient — port-интерфейс для cross-service вызова к resource-manager
type FolderClient interface {
    Exists(ctx context.Context, folderUID string) (bool, error)
}

// SubnetClient — port-интерфейс для cross-service вызова к vpc
type SubnetClient interface {
    Exists(ctx context.Context, subnetUID string) (bool, error)
}

type ZoneRepo interface {
    Exists(ctx context.Context, name string) (bool, error)
}

type DiskTypeRepo interface {
    Exists(ctx context.Context, id string) (bool, error)
}

type PlatformRepo interface {
    Exists(ctx context.Context, id string) (bool, error)
}
```

#### internal/service/instance.go — ключевые use-cases

**Upsert**: проверки в порядке (все через port-интерфейсы):
1. `metadata.name` непустой — INVALID_ARGUMENT (E8)
2. `status` в запросе → INVALID_ARGUMENT (E7)
3. `spec.resources.cores >= 1` — INVALID_ARGUMENT (M3)
4. `spec.networkInterfaces` непустой — INVALID_ARGUMENT (M8)
5. `spec.desiredPowerState` валидный enum — INVALID_ARGUMENT (M2)
6. `page_size <= 1000` при List — INVALID_ARGUMENT (M9)
7. `FolderClient.Exists(folderId)` — NOT_FOUND с ResourceInfo (E4); UNAVAILABLE при сбое (K4)
8. `SubnetClient.Exists(subnetId)` — NOT_FOUND с ResourceInfo (E5); UNAVAILABLE при сбое (K5)
9. `PlatformRepo.Exists(platformId)` — INVALID_ARGUMENT (E9)
10. `ZoneRepo.Exists(zoneId)` — INVALID_ARGUMENT
11. `DiskRepo.Get(bootDisk.diskId)` — INVALID_ARGUMENT если not found или не в READY (E6, nit-2)
12. Idempotency check: если (folderId, name) совпадают и spec без diff → no-op (E2)
13. Автоматически добавить finalizer `"compute.kacho.io/disk-detach"` если есть boot/secondary диски (E1)
14. Upsert → запись в repo с outbox event ADDED/MODIFIED

**Delete**: soft-delete (выставить `deletionTimestamp`), записать MODIFIED event с state=DELETING (I1). Reconciler завершает физическое удаление.

**Restart**: (H1–H4, M6, M7)
1. Получить Instance по uid — NOT_FOUND если нет (M6)
2. Проверить state == RUNNING — FAILED_PRECONDITION если нет (H3, M7)
3. Обновить `metadata.restartedAt = now()` через `UpdateInstanceMetadata`
4. Вернуть полный объект Instance (OQ-6)

Idempotency Restart: если `restartedAt == lastRestartCompletedAt` → no-op (H4).

#### internal/service/disk.go — ключевые use-cases

**Upsert**:
1. `status` в запросе → INVALID_ARGUMENT (B9)
2. `FolderClient.Exists` — NOT_FOUND (B7)
3. `DiskTypeRepo.Exists(diskTypeId)` — INVALID_ARGUMENT (B8)
4. `ZoneRepo.Exists(zoneId)` — INVALID_ARGUMENT (M4)
5. Idempotency check (B3)
6. Upsert → CREATING state; finalizers=[] (у Disk нет finalizer)

**Delete**:
1. Проверить `attached_to_instance_id` не NULL → FAILED_PRECONDITION (M5)
2. Физическое удаление (нет finalizers у Disk) + DELETED event (B5)

**OCC (Optimistic Concurrency Control)**: upsert используeт `resource_version` в WHERE-условии UPDATE → ABORTED при конфликте (M1).

#### internal/service/snapshot.go

**Upsert**:
1. `DiskRepo.Get(diskId)` — INVALID_ARGUMENT если not found (D4)
2. Проверить `disk.state == READY` — FAILED_PRECONDITION если нет (D6)
3. Upsert → CREATING state, progress=0

**Delete**: физическое удаление (нет finalizers) + DELETED event (D5).

### B.5 Repo (sqlc + handwritten)

#### internal/repo/instance_repo.go

Реализует `InstanceRepo`. Использует:
- `kacho-corelib/db.Transactor` для транзакций
- `kacho-corelib/outbox.Writer` для атомарной записи событий
- `internal/repo/filter_builder.go` для WHERE-clause по FieldSelector

```go
func (r *InstanceRepo) Upsert(ctx context.Context, inst *domain.Instance) (*domain.Instance, error) {
    return r.transactor.WithTx(ctx, func(tx pgx.Tx) (*domain.Instance, error) {
        // INSERT ... ON CONFLICT (folder_id, name) DO UPDATE SET ... WHERE resource_version = $prev_rv
        // Если 0 rows affected → ABORTED (OCC)
        result, err := r.queries.UpsertInstance(ctx, tx, toDBParams(inst))
        if err != nil { return nil, mapPgErr(err) }

        event := outbox.Event{
            ResourceKind: "Instance",
            ResourceUID:  inst.UID,
            EventType:    determineEventType(inst),
            Data:         marshalInstance(result),
        }
        if err := r.outboxWriter.WriteEvent(ctx, tx, event); err != nil {
            return nil, err
        }
        return fromDB(result), nil
    })
}
```

`GetPendingReconcile`: возвращает Instance в промежуточных состояниях (PROVISIONING, STOPPING, STARTING, DELETING) или с `restartedAt > lastRestartCompletedAt`, лимит задаётся dispatcher-ом (J4).

#### internal/repo/filter_builder.go

Генерирует параметризованный WHERE-clause из `FieldFilter`:

```go
type FieldFilter struct {
    FolderID  string
    Name      string
    LabelSel  map[string]string
}

func BuildWhere(f FieldFilter) (string, []interface{}) {
    var clauses []string
    var args []interface{}
    n := 1
    if f.FolderID != "" {
        clauses = append(clauses, fmt.Sprintf("folder_id = $%d", n))
        args = append(args, f.FolderID); n++
    }
    // ... аналогично для Name, LabelSel (jsonb @> $n)
    return strings.Join(clauses, " AND "), args
}
```

### B.6 Handler (thin gRPC transport)

#### internal/handler/instance_handler.go

```go
func (h *InstanceHandler) Upsert(ctx context.Context, req *computev1.InstanceUpsertRequest) (*computev1.InstanceUpsertResponse, error) {
    // 1. parse request → domain.Instance slice
    // 2. validate presence (reject if req.Instances[i].Status != nil → INVALID_ARGUMENT)
    // 3. call h.instanceSvc.Upsert(ctx, instances)
    // 4. format response
    return resp, nil
}

func (h *InstanceHandler) Watch(req *computev1.InstanceWatchRequest, stream computev1.InstanceService_WatchServer) error {
    rv, err := parseResourceVersion(req.ResourceVersion)
    if err != nil { return status.Errorf(codes.InvalidArgument, "resource_version: %v", err) }  // M10
    filter := parseSelectors(req.Selectors)
    sub, err := h.hub.Subscribe(stream.Context(), filter, rv)
    if err != nil { return mapWatchErr(err) }  // OUT_OF_RANGE для Gone (L5)
    defer h.hub.Unsubscribe(sub)
    for evt := range sub.C {
        if err := stream.Send(toProtoEvent(evt)); err != nil { return err }
    }
    return nil
}

func (h *InstanceHandler) Restart(ctx context.Context, req *computev1.InstanceRestartRequest) (*computev1.InstanceRestartResponse, error) {
    // тонкий transport: парсит uid-список → service.Restart → возвращает Instance objects
}
```

**Запрет:** никакой бизнес-логики в handler. Валидация `status != nil` — это transport-проверка (проверяет наличие поля в wire-формате), остальное — в service.

#### internal/handler/internal_handler.go

`ComputeInternal` реализует `InstanceExists`, `UpdateInstanceStatus`, `UpdateDiskStatus`, `UpdateSnapshotStatus`, `UpdateInstanceMetadata`. Этот handler **не регистрируется** через api-gateway наружу (constraint из CLAUDE.md §7).

### B.7 Reconciler — наиболее сложный компонент

**Acceptance scenarios:** F1–F3, G1–G4, H1–H4, I1–I4, J1–J5

#### internal/reconciler/dispatcher.go

```go
type Dispatcher struct {
    instanceRepo   service.InstanceRepo
    diskRepo       service.DiskRepo
    snapshotRepo   service.SnapshotRepo
    internalClient computev1.ComputeInternalClient
    simConfig      SimConfig
    pollInterval   time.Duration
}

func (d *Dispatcher) Run(ctx context.Context) {
    ticker := time.NewTicker(d.pollInterval)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done(): return
        case <-ticker.C:
            d.pollInstances(ctx)
            d.pollDisks(ctx)
            d.pollSnapshots(ctx)
        }
    }
}

func (d *Dispatcher) pollInstances(ctx context.Context) {
    pending, _ := d.instanceRepo.GetPendingReconcile(ctx, 10)  // J4: batch LIMIT 10
    for _, inst := range pending {
        go d.handleInstance(ctx, inst)   // goroutine per resource
    }
}
```

#### internal/reconciler/advisory_lock.go

```go
// TryAcquire пытается взять pg_try_advisory_lock(bigint) в текущей транзакции.
// Возвращает (true, releaseFunc, nil) при успехе; (false, nil, nil) если занято другой репликой.
func TryAcquire(ctx context.Context, pool *pgxpool.Pool, uid string) (bool, func(), error) {
    hash := hashUID(uid)
    var acquired bool
    err := pool.QueryRow(ctx,
        "SELECT pg_try_advisory_lock($1)", hash).Scan(&acquired)
    if err != nil { return false, nil, err }
    if !acquired { return false, nil, nil }
    release := func() {
        pool.QueryRow(ctx, "SELECT pg_advisory_unlock($1)", hash)
    }
    return true, release, nil
}

func hashUID(uid string) int64 {
    h := fnv.New64a()
    h.Write([]byte(uid))
    return int64(h.Sum64())
}
```

Тест J1 использует channel-based barrier (nit-5): два goroutine ждут `ready := make(chan struct{})` перед попыткой lock — детерминированный старт.

#### internal/reconciler/instance_handler.go — жизненный цикл Instance

```go
func (d *Dispatcher) handleInstance(ctx context.Context, inst *domain.Instance) {
    acquired, release, err := advisory.TryAcquire(ctx, d.pool, inst.UID)
    if err != nil || !acquired { return }  // другая реплика обрабатывает (J1)
    defer release()

    switch {
    case inst.DeletionTimestamp != nil && hasFinalizer(inst, "compute.kacho.io/disk-detach"):
        d.runFinalizerDetach(ctx, inst)  // I1, I2, I3

    case inst.State == domain.InstanceProvisioning:
        d.runProvisioning(ctx, inst)  // F1, F2, G3, OQ-3

    case inst.State == domain.InstanceStopping:
        d.runStopping(ctx, inst)  // G1, G4, J3

    case inst.State == domain.InstanceStarting:
        d.runStarting(ctx, inst)  // G2

    case inst.State == domain.InstanceRunning &&
         inst.RestartedAt != nil &&
         (inst.LastRestartCompletedAt == nil || inst.RestartedAt.After(*inst.LastRestartCompletedAt)):
        d.runRestartCycle(ctx, inst)  // H1, H2

    case inst.State == domain.InstanceRunning && inst.DesiredPowerState == domain.DesiredStopped:
        d.triggerStopping(ctx, inst)  // G1

    case inst.State == domain.InstanceStopped && inst.DesiredPowerState == domain.DesiredRunning:
        d.triggerStarting(ctx, inst)  // G2

    default:
        // J2: no-op для Instance в стабильном состоянии
    }
}
```

**runProvisioning** (сценарии F1, F2, OQ-3, G3):
1. Симулированная задержка `SimConfig.ProvisioningDelay()` (случайное в диапазоне `[MIN_MS, MAX_MS]`)
2. Фаза disk-attach (OQ-3, F2):
   - Для каждого диска (bootDisk + secondaryDisks): `UpdateDiskStatus(ATTACHING)` → sleep(diskAttachDelay) → `UpdateDiskStatus(READY, attached_to_instance_id=inst.uid)`
3. Назначить `ips.internal = computeInternalIP(inst.UID)` (OQ-4)
4. Если `DesiredPowerState == STOPPED`: `UpdateInstanceStatus(STOPPED)` (G3)
5. Иначе: `UpdateInstanceStatus(RUNNING)`

**computeInternalIP** (OQ-4):
```go
func computeInternalIP(uid string) string {
    h := fnv.New32a()
    h.Write([]byte(uid))
    return fmt.Sprintf("10.0.0.%d", h.Sum32() % 250 + 2)
}
```
Если `spec.networkInterfaces[0].primaryV4Address.address` задан клиентом — использует его.

**runStopCycle / runStartCycle** (G1, G2):
- При RUNNING→STOPPED: `UpdateInstanceStatus(STOPPING)` → sleep(StopDelay) → `UpdateInstanceStatus(STOPPED)`
- При STOPPED→RUNNING: `UpdateInstanceStatus(STARTING)` → sleep(StartDelay) → `UpdateInstanceStatus(RUNNING)`

**runRestartCycle** (H1, H2, OQ-7):
1. `internalRestartPhase` — внутреннее поле dispatcher-а (не БД), чтобы не затирать `desiredPowerState`:
   - Фаза 1: если `state == RUNNING`, запустить stop → STOPPING → sleep → STOPPED
   - Фаза 2: если `state == STOPPED` (пришли сюда), запустить start → STARTING → sleep → RUNNING
   - После RUNNING: `UpdateInstanceMetadata(lastRestartCompletedAt = restartedAt)` (H1)
2. OQ-7: reconciler «завершить текущий переход → следующий poll цикл». Если `desiredPowerState` изменился в середине Restart — reconciler замечает это после завершения текущего шага (J2 + OQ-7).

**runFinalizerDetach** (I1, I2, I3):
1. Получить все attached disks для instance через `DiskRepo.GetAttachedDisks(instanceUID)`
2. Если дисков нет (I3) → сразу перейти к п.4
3. Для каждого диска:
   - `UpdateDiskStatus(DETACHING)` + emit MODIFIED event для Disk
   - sleep(detachDelay)
   - `UpdateDiskStatus(READY, attached_to_instance_id=NULL, device_name=NULL)` + emit MODIFIED event
   - Если `autoDelete == true` → `DiskRepo.Delete(diskUID)` + emit DELETED event для Disk (I2)
4. Удалить finalizer из Instance: `UpdateInstanceMetadata(finalizers=[])` 
5. `InstanceRepo.Delete(instanceUID)` (физическое) + emit DELETED event (I1, I4)

#### internal/reconciler/disk_handler.go — lifecycle диска (сценарии B2)

```go
func (d *Dispatcher) handleDisk(ctx context.Context, disk *domain.Disk) {
    if disk.State != domain.DiskCreating { return }  // J2-аналог для Disk

    acquired, release, _ := advisory.TryAcquire(ctx, d.pool, disk.UID)
    if !acquired { return }
    defer release()

    time.Sleep(d.simConfig.DiskCreatingDelay())
    d.internalClient.UpdateDiskStatus(ctx, &computev1.UpdateDiskStatusRequest{
        Uid:   disk.UID,
        State: computev1.DiskStatus_READY,
    })
}
```

#### internal/reconciler/snapshot_handler.go — прогресс снепшота (OQ-2, D2, D3, L3)

```go
func (d *Dispatcher) handleSnapshot(ctx context.Context, snap *domain.Snapshot) {
    if snap.State != domain.SnapshotCreating { return }

    acquired, release, _ := advisory.TryAcquire(ctx, d.pool, snap.UID)
    if !acquired { return }
    defer release()

    totalDuration := d.simConfig.SnapshotDuration()  // 10–30 с (100–200 мс в тестах)
    stepDuration := totalDuration / 4

    steps := []int32{25, 50, 75, 100}  // OQ-2: фиксированные шаги 0→25→50→75→100
    for _, pct := range steps {
        time.Sleep(stepDuration)
        if pct < 100 {
            d.internalClient.UpdateSnapshotStatus(ctx, &computev1.UpdateSnapshotStatusRequest{
                Uid: snap.UID, ProgressPercent: pct,
            })
        } else {
            d.internalClient.UpdateSnapshotStatus(ctx, &computev1.UpdateSnapshotStatusRequest{
                Uid: snap.UID, State: computev1.SnapshotStatus_READY, ProgressPercent: 100,
            })
        }
    }
}
```

#### SimConfig — параметризация задержек (OQ-1)

```go
type SimConfig struct {
    ProvisioningMinMs int
    ProvisioningMaxMs int
    StopMinMs         int
    StopMaxMs         int
    StartMinMs        int
    StartMaxMs        int
    SnapshotMinMs     int
    SnapshotMaxMs     int
    DiskCreatingMinMs int
    DiskCreatingMaxMs int
}

func SimConfigFromEnv() SimConfig {
    return SimConfig{
        ProvisioningMinMs: envInt("KACHO_COMPUTE_SIM_PROVISIONING_MIN_MS", 5000),
        ProvisioningMaxMs: envInt("KACHO_COMPUTE_SIM_PROVISIONING_MAX_MS", 30000),
        StopMinMs:         envInt("KACHO_COMPUTE_SIM_STOP_MIN_MS", 5000),
        StopMaxMs:         envInt("KACHO_COMPUTE_SIM_STOP_MAX_MS", 15000),
        StartMinMs:        envInt("KACHO_COMPUTE_SIM_START_MIN_MS", 5000),
        StartMaxMs:        envInt("KACHO_COMPUTE_SIM_START_MAX_MS", 15000),
        SnapshotMinMs:     envInt("KACHO_COMPUTE_SIM_SNAPSHOT_MIN_MS", 10000),
        SnapshotMaxMs:     envInt("KACHO_COMPUTE_SIM_SNAPSHOT_MAX_MS", 30000),
        DiskCreatingMinMs: envInt("KACHO_COMPUTE_SIM_DISK_CREATING_MIN_MS", 3000),
        DiskCreatingMaxMs: envInt("KACHO_COMPUTE_SIM_DISK_CREATING_MAX_MS", 10000),
    }
}

func (c SimConfig) ProvisioningDelay() time.Duration {
    return randomBetween(c.ProvisioningMinMs, c.ProvisioningMaxMs)
}
// ... аналогично для остальных
```

Тесты переопределяют: `KACHO_COMPUTE_SIM_*_MIN_MS=100`, `KACHO_COMPUTE_SIM_*_MAX_MS=200`.

### B.8 Cross-service clients

#### internal/clients/folder_client.go

Реализует `service.FolderClient`. Использует `kacho-corelib/grpcclient` для dial с retry/timeout.

```go
type FolderGRPCClient struct {
    client resourcemanagerv1.FolderInternalServiceClient
}

func (c *FolderGRPCClient) Exists(ctx context.Context, folderUID string) (bool, error) {
    ctxWithTimeout, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()
    resp, err := c.client.Exists(ctxWithTimeout, &resourcemanagerv1.ExistsRequest{Uid: folderUID})
    if err != nil {
        if status.Code(err) == codes.Unavailable {
            return false, fmt.Errorf("resource-manager unavailable: %w", ErrUpstream)
        }
        return false, err
    }
    return resp.Exists, nil
}
```

Timeout 5 с, retry 1× на UNAVAILABLE (согласно constraints из задания).

#### internal/clients/subnet_client.go

Аналогично через `kacho-corelib/grpcclient` → vpc InternalService.

### B.9 cmd/main.go — composition root

```go
func serve(ctx context.Context, cfg Config) error {
    pool, err := db.NewPool(ctx, cfg.DBDsn)
    // ...
    transactor  := db.NewTransactor(pool)
    outboxWriter := outbox.NewWriter("kacho_compute")
    hub := watch.NewHub(ctx, pool, watch.HubOpts{
        ChannelName: "kacho_compute",
        SVC: "compute",
    })

    // Repos
    instanceRepo := repo.NewInstanceRepo(pool, transactor, outboxWriter)
    diskRepo     := repo.NewDiskRepo(pool, transactor, outboxWriter)
    imageRepo    := repo.NewImageRepo(pool)
    snapshotRepo := repo.NewSnapshotRepo(pool, transactor, outboxWriter)
    zoneRepo     := repo.NewZoneRepo(pool)
    diskTypeRepo := repo.NewDiskTypeRepo(pool)
    platformRepo := repo.NewPlatformRepo(pool)

    // Cross-service clients
    rmConn, _     := grpcclient.Dial(cfg.ResourceManagerAddr)
    vpcConn, _    := grpcclient.Dial(cfg.VPCAddr)
    folderClient  := clients.NewFolderGRPCClient(rmConn)
    subnetClient  := clients.NewSubnetGRPCClient(vpcConn)

    // Services
    instanceSvc := service.NewInstanceService(instanceRepo, diskRepo, zoneRepo, platformRepo, folderClient, subnetClient, hub)
    diskSvc     := service.NewDiskService(diskRepo, zoneRepo, diskTypeRepo, folderClient, hub)
    imageSvc    := service.NewImageService(imageRepo)
    snapshotSvc := service.NewSnapshotService(snapshotRepo, diskRepo, folderClient, hub)

    // Internal gRPC client (для reconciler → internal handler в том же процессе)
    // Используем loopback: reconciler вызывает internal через gRPC на localhost (or direct service call)
    internalSvc := service.NewInternalService(instanceRepo, diskRepo, snapshotRepo, hub)

    // Reconciler
    simCfg := reconciler.SimConfigFromEnv()
    dispatcher := reconciler.NewDispatcher(instanceRepo, diskRepo, snapshotRepo, internalSvc, pool, simCfg)
    go dispatcher.Run(ctx)

    // Cleanup goroutine (J5)
    go watch.RunCleanup(ctx, pool, "kacho_compute")

    // gRPC server
    grpcSrv := grpcsrv.NewServer(grpcsrv.WithHealthCheck())
    computev1.RegisterInstanceServiceServer(grpcSrv, handler.NewInstanceHandler(instanceSvc, hub))
    computev1.RegisterDiskServiceServer(grpcSrv, handler.NewDiskHandler(diskSvc, hub))
    computev1.RegisterImageServiceServer(grpcSrv, handler.NewImageHandler(imageSvc))
    computev1.RegisterSnapshotServiceServer(grpcSrv, handler.NewSnapshotHandler(snapshotSvc, hub))
    computev1.RegisterComputeInternalServer(grpcSrv, handler.NewInternalHandler(internalSvc))
    // ComputeInternal регистрируется на том же порту, но НЕ проксируется api-gateway (constraint #7)

    return grpcSrv.Serve(listener)
}
```

Subcommands: `serve` (запуск сервиса), `migrate` (goose up). В Kubernetes: init-container запускает `migrate`, основной container — `serve`.

### B.10 Helm chart + Dockerfile

#### Dockerfile (multi-stage)

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/compute ./cmd/compute

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/compute /compute
ENTRYPOINT ["/compute"]
CMD ["serve"]
```

Image: `prorobotech/kacho-compute:0.4.0`

#### deploy/Chart.yaml

```yaml
apiVersion: v2
name: compute
version: 0.4.0
appVersion: "0.4.0"
description: Kacho Compute service — Instance/Disk/Image/Snapshot control plane
```

#### deploy/values.yaml / values.dev.yaml

Ключевые поля: `image.repository`, `image.tag`, `replicaCount: 1`, `env.KACHO_COMPUTE_DB_DSN`, `env.KACHO_COMPUTE_RESOURCE_MANAGER_ADDR`, `env.KACHO_COMPUTE_VPC_ADDR`, `env.KACHO_COMPUTE_SIM_*_MS`, `service.port: 9090`, `livenessProbe` / `readinessProbe` через grpc_health_probe (O6).

Init-container в `deployment.yaml`:
```yaml
initContainers:
  - name: migrate
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command: ["/compute", "migrate"]
    env: [...]  # те же DB_DSN env
```

### B.11 Tests

#### Unit-тесты service/ (через mock port-интерфейсов)

Именование: `Test<Resource>_<ScenarioID>_<ShortDesc>`, например:
- `TestInstance_E4_FolderNotFound`
- `TestInstance_E7_StatusInUpsert`
- `TestInstance_H3_RestartFromStopped`
- `TestDisk_B8_InvalidDiskTypeId`
- `TestDisk_M5_DeleteAttachedDisk`
- `TestSnapshot_D4_DiskNotFound`
- `TestSnapshot_D6_DiskNotReady`
- `TestInstance_E6extra_BootDiskNotReady` (nit-2)

Все через `testify/mock` — нет реального Postgres.

#### Integration-тесты (testcontainers-Postgres)

Тесты в `internal/service/*_acceptance_test.go`. Запускают Postgres container, применяют миграции, тестируют полный flow включая reconciler с задержками 100–200 мс.

Важные группы:
- **B-группа**: `TestDisk_B1_Create`, `TestDisk_B2_LifecycleCreatingToReady`, `TestDisk_B3_Idempotency`, `TestDisk_B4_ListByFolder`, `TestDisk_B5_DeleteNoFinalizer`, `TestDisk_B6_Watch`
- **C-группа**: `TestImage_C1_ListSeedImages`, `TestImage_C2_GetByUID`, `TestImage_C3_NotFound`, `TestImage_C4_NoUpsertDelete`, `TestImage_C5_FilterByName`
- **D-группа**: `TestSnapshot_D1_Create`, `TestSnapshot_D2_ProgressToReady`, `TestSnapshot_D3_WatchProgress`, `TestSnapshot_D4_InvalidDiskId`, `TestSnapshot_D5_Delete`, `TestSnapshot_D6_DiskNotReady`
- **E/F-группа**: `TestInstance_E1_Create`, `TestInstance_F1_ProvisioningToRunning`, `TestInstance_F2_DiskAttach`
- **G-группа**: `TestInstance_G1_StopRunning`, `TestInstance_G2_StartStopped`, `TestInstance_G3_DesiredStoppedFromCreation` (nit-3: явный Watch assert STOPPED), `TestInstance_G4_ReconcilerRecovery`
- **H-группа**: `TestInstance_H1_Restart`, `TestInstance_H2_DoubleRestart`, `TestInstance_H3_RestartFromStopped`, `TestInstance_H4_RestartIdempotent`
- **I-группа**: `TestInstance_I1_DeleteWithFinalizer`, `TestInstance_I2_AutoDeleteDisk`, `TestInstance_I3_DeleteNoDisks`, `TestInstance_I4_DoubleDelete`
- **J-группа**: `TestReconciler_J1_AdvisoryLock` (channel barrier, nit-5), `TestReconciler_J2_Idempotent`, `TestReconciler_J3_Recovery`, `TestReconciler_J4_BatchPoll`, `TestReconciler_J5_CleanupLock`
- **K-группа**: `TestInternal_K1_InstanceExists`, `TestInternal_K2_NotFound`, `TestInternal_K3_SoftDeleted`, `TestInternal_K6_UpdateStatus`, `TestInternal_K7_UpdateStatusNoOp`
- **L-группа**: `TestWatch_L1_FullLifecycle`, `TestWatch_L2_FolderFilter`, `TestWatch_L3_SnapshotProgress`, `TestWatch_L4_CatchUp`, `TestWatch_L5_Gone`
- **M-группа**: `TestInstance_M1_OCC`, `TestInstance_M2_InvalidPowerState` и т.д.
- **N-группа (миграции)**: `TestMigration_N1_SeedZones`, `TestMigration_N2_SeedDiskTypes`, `TestMigration_N3_SeedPlatforms`, `TestMigration_N4_SeedImages`, `TestMigration_N5_SeedIdempotent` (nit-4)

К4 и К5 (cross-service UNAVAILABLE) тестируются с mock FolderClient/SubnetClient возвращающими ошибку `ErrUpstream`.

Все временны́е assertions используют timeout 60 секунд (acceptance §0). В тестах задержки = 100–200 мс через env-overrides.

---

## §4. Phase C — kacho-deploy (umbrella + e2e/0.4)

**Acceptance scenarios:** O1–O6

### C.1 Helm umbrella update

`kacho-deploy/helm/umbrella/Chart.yaml` — раскомментировать:
```yaml
dependencies:
  - name: compute
    version: "0.4.0"
    repository: "file://../compute"
```

`kacho-deploy/helm/umbrella/values.dev.yaml` — добавить:
```yaml
compute:
  image:
    repository: prorobotech/kacho-compute
    tag: "0.4.0"
  replicaCount: 1
  env:
    KACHO_COMPUTE_DB_DSN: "postgres://kacho:kacho@postgres-compute:5432/kacho_compute?sslmode=disable"
    KACHO_COMPUTE_RESOURCE_MANAGER_ADDR: "resource-manager.kacho.svc.cluster.local:9090"
    KACHO_COMPUTE_VPC_ADDR: "vpc.kacho.svc.cluster.local:9090"
    # Prod delays (e2e использует их с timeout 60 s)
    KACHO_COMPUTE_SIM_PROVISIONING_MIN_MS: "5000"
    KACHO_COMPUTE_SIM_PROVISIONING_MAX_MS: "30000"
    KACHO_COMPUTE_SIM_STOP_MIN_MS: "5000"
    KACHO_COMPUTE_SIM_STOP_MAX_MS: "15000"
    KACHO_COMPUTE_SIM_START_MIN_MS: "5000"
    KACHO_COMPUTE_SIM_START_MAX_MS: "15000"
    KACHO_COMPUTE_SIM_SNAPSHOT_MIN_MS: "10000"
    KACHO_COMPUTE_SIM_SNAPSHOT_MAX_MS: "30000"
```

### C.2 E2e bash скрипты (port-forward)

`kacho-deploy/e2e/0.4/` — 6 скриптов:

**O1-full-flow.sh** (O1): Полный flow Folder → Network → Subnet → Disk (wait READY, 30 с) → Instance (wait RUNNING, 60 с) → List. Port-forward: 9090 (resource-manager), 9091 (vpc), 9092 (compute).

**O2-restart.sh** (O2): Restart Instance → дождаться `STOPPING → STARTING → RUNNING` через Watch (60 с). Проверить `lastRestartCompletedAt == restartedAt`.

**O3-power-state.sh** (O3): Upsert с `desiredPowerState=STOPPED` → Watch `STOPPING → STOPPED` в 30 с.

**O4-delete-with-finalizer.sh** (O4): Delete Instance (с finalizer) → Watch Instance `DELETING → DELETED`, Watch Disk `DETACHING → READY → DELETED` (autoDelete=true) в 30 с.

**O5-snapshot.sh** (O5): Upsert Snapshot → Watch `ADDED(progress=0) → MODIFIED(0<p<100) → MODIFIED(READY, p=100)` в 60 с.

**O6-helm-deploy.sh** (O6): `helm upgrade --install`, wait pod Ready, grpc_health_probe, проверка таблиц в psql.

### C.3 Postgres для compute в dev-стенде

`kacho-deploy/` должен включать отдельный Postgres deployment/StatefulSet для `kacho_compute` (database-per-service, constraint #9). В `values.dev.yaml` — секция `postgres-compute:`.

---

## §5. Phase D — Smoke + tag v0.4.0

### D.1 Smoke-сценарий

```bash
# 1. Поднять стенд
cd kacho-deploy && make dev-up

# 2. Проверить compute pod
kubectl wait pod -l app=compute -n kacho --for=condition=Ready --timeout=90s

# 3. Port-forward
kubectl port-forward svc/compute 9092:9090 -n kacho &

# 4. Запустить e2e
make e2e-test PHASE=0.4

# 5. Убедиться в наличии seed-данных
kubectl exec -n kacho deploy/compute -- /compute migrate status

# 6. Снести стенд
make dev-down
```

### D.2 CHANGELOG

Добавить запись в `kacho-workspace/docs/specs/CHANGELOG.md`:
```
## [v0.4.0] — 2026-xx-xx

### Sub-phase 0.4 — Compute

- kacho-proto: добавлен домен compute/v1 (instance, disk, image, snapshot, internal)
- kacho-compute: реализован сервис с Clean Architecture
  - Instance lifecycle: PROVISIONING → RUNNING / STOPPING / STOPPED / STARTING
  - Reconciler с pg_advisory_lock, симулированными задержками (env-параметры)
  - Finalizer compute.kacho.io/disk-detach
  - Snapshot с прогрессом 0→25→50→75→100%
  - Cross-service валидация: FolderExists (resource-manager), SubnetExists (vpc)
  - Restart RPC (STOPPING → STOPPED → STARTING → RUNNING без видимого RESTARTING)
- kacho-deploy: compute добавлен в umbrella helm chart, e2e/0.4 сценарии
- 88 acceptance-сценариев покрыты тестами (integration + e2e)
```

### D.3 Tag

```bash
git tag -a kacho-compute:0.4.0 -m "sub-phase 0.4 complete"
```

---

## §6. Definition of Done

Повторяет acceptance §16 (P-группа) с дополнениями из nit-resolutions:

1. **Все 88 сценариев A1–O6** покрыты:
   - Integration-тесты (testcontainers) в `kacho-compute` — зелёные
   - E2e bash-скрипты в `kacho-deploy/e2e/0.4/*.sh` — зелёные при `make e2e-test PHASE=0.4`

2. **Proto** `kacho-proto/proto/kacho/cloud/compute/v1/`:
   - 5 файлов: `instance.proto`, `disk.proto`, `image.proto`, `snapshot.proto`, `internal.proto`
   - `RESTARTING` отсутствует в публичном `Instance.Status.State` enum (nit-1)
   - `gen/go/` committed; `buf lint` + `buf breaking` зелёные

3. **kacho-compute Clean Architecture** (проверяется `go-style-reviewer`):
   - `domain/` и `service/` не импортируют `pgx`, sqlc-types, grpc-stubs
   - `handler/` содержит только transport-логику
   - Глобальных синглтонов нет вне `cmd/`

4. **Reconciler**:
   - `pg_advisory_lock(uid_hash)` per-resource (J1)
   - Симулированные задержки из env (`KACHO_COMPUTE_SIM_*_MS`) с prod-defaults
   - Snapshot: фиксированные шаги 0→25→50→75→100 с sleep(total/4) между (OQ-2)
   - Disk-attach: отдельная фаза ATTACHING → READY до перехода Instance в RUNNING (OQ-3)
   - Restart: STOPPING → STOPPED → STARTING → RUNNING без RESTARTING в Watch (nit-1)
   - Recovery после краша: завершает незаконченный переход (J3, G4)
   - Cleanup горутина с `pg_advisory_xact_lock` (J5)

5. **Cross-service validation**:
   - Timeout 5 с, retry 1× на UNAVAILABLE (K4, K5)
   - `InstanceExists` возвращает `false` для soft-deleted (K3)

6. **Finalizer `compute.kacho.io/disk-detach`**:
   - Автоматически добавляется при Upsert Instance (E1)
   - `autoDelete=true` → диск удаляется после detach (I2)
   - Orphaned instance (диски уже удалены) — finalizer удаляется немедленно (I3)

7. **Seed-таблицы** (N1–N5): zones, disk_types, platforms, images_catalog с `ON CONFLICT DO NOTHING`

8. **status через /upsert → INVALID_ARGUMENT** (B9, E7, constraint #6)

9. **IP-назначение**: `10.0.0.<hash(uid)%250+2>`, приоритет за `spec.networkInterfaces[0].primaryV4Address.address` если задан (OQ-4)

10. **Helm chart** в `kacho-deploy/helm/compute/` + umbrella dep добавлен

11. **CI** зелёный:
    - `kacho-proto`: buf-lint, buf-breaking, buf-generate
    - `kacho-compute`: golangci-lint, go test ./... (включая integration)
    - `kacho-deploy`: helm lint

12. **Naming conventions**:
    - Proto package: `kacho.cloud.compute.v1`
    - DB: `kacho_compute`
    - Env: `KACHO_COMPUTE_*`
    - k8s service: `compute.kacho.svc.cluster.local`
    - Docker image: `prorobotech/kacho-compute:0.4.0`
    - Finalizer: `compute.kacho.io/disk-detach`

13. **Test naming** (nit-4): миграционные тесты `TestMigration_N1_SeedZones` и т.д.

14. **J1 test** (nit-5): channel-based synchronization barrier

15. `CHANGELOG.md` обновлён, tag `kacho-compute:0.4.0` поставлен

---

## §7. Execution mode (subagent-driven, параллелизм)

Пользователь дал автономию до готового блока. Цепочка subagents:

1. **Этот план** — скелет для исполнителей

2. **Phase A** (`proto-sync` subagent, Sonnet): kacho-proto/compute/v1 — 5 .proto файлов + buf generate + CI update. Нет зависимостей на Phase B.

3. **Phase B** (несколько `service-scaffolder` + `rpc-implementer` subagents):
   - **B.1–B.2** (scaffold+migrations): skeleton структуры, go.mod, sqlc.yaml, migrations 0001 и 0002. Блокируется Phase A (нужны grpc-stubs для go.mod depends).
   - **B.3–B.5** (domain+service+repo): domain entities, service use-cases с port-интерфейсами, repo с sqlc + handwritten. Параллельно по ресурсам (Instance, Disk, Snapshot, Image).
   - **B.6** (handler): thin transport layer. Блокируется B.3–B.5.
   - **B.7** (reconciler): самый сложный; `instance_handler.go` + `disk_handler.go` + `snapshot_handler.go` + `advisory_lock.go`. Блокируется B.3–B.5.
   - **B.8** (cross-service clients): FolderClient + SubnetClient. Параллельно с B.6, B.7.
   - **B.9** (cmd/main.go): composition root. Блокируется B.6, B.7, B.8.
   - **B.10** (helm+dockerfile): параллельно с B.9.
   - **B.11** (tests): integration-тесты. Блокируется всеми B.x.

4. **Phase C** (`api-gateway-registrar`-like subagent + bash): kacho-deploy umbrella update + e2e/0.4 bash-скрипты. Блокируется Phase B.

5. **Phase D** (myself): smoke run + CHANGELOG + tag. Блокируется Phase C.

### Параллелизм Phase B

```
Phase A ──────────────────────────────────────────────────────→ done
         │
         └─→ B.1+B.2 (scaffold) ─→ B.3+B.5 (domain+repo) ─┐
                                 ─→ B.3+B.5 (disk)         ├─→ B.6 (handler) ─→ B.9 (main)
                                 ─→ B.3+B.5 (snapshot)     │
                                 ─→ B.7 (reconciler)      ─┘
                                 ─→ B.8 (clients)         ─┘
                                                            └─→ B.11 (tests)
         └─→ B.10 (helm) ─→ Phase C ─→ Phase D
```

Возврат к пользователю после Phase D → grpcurl smoke-верификация → approve.
