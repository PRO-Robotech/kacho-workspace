# Implementation plan — compute cutover (disk→storage-volume + NIC + cpu_guarantee)

> Acceptance: **✅ APPROVED** (acceptance-reviewer round-2, 2026-07-12 — включая S4 placement-realism S4-03 + per-RPC authz-Check :9091 INV-2a) `docs/specs/sub-phase-compute-storage-volume-attach-acceptance.md` (S3 disk-attach saga, S4 NIC, S5 mirrors/cpu/resize). НЕ переоткрывать гейт.
> Spec: `docs/plans/kacho-storage-volume-and-instance-attach-spec.md` §2/§3/§3a/§3b.
> Тип: **breaking** (clean-boundary, pre-GA) — compute.v1 меняется; compute-CI будет красным пока compute-impl не догонит proto (норм для topo-миграции, не мёржим пока не когерентно).
> Тикет: часть KAC-эпика A. Ветки: kacho-proto `storage-split-proto` (уже), kacho-compute — нов. от main, kacho-vpc `placement-coherence-zc` (доборка used_by_index) или отдельная.

## Что меняется (и что НЕ трогаем сейчас)

**Delicate-инвариант:** storage/vpc **не зовут compute** (ацикличность). Attach — compute-инициируемый self-describing. Уже реализовано на storage-стороне (InternalVolumeService).

### 1. proto (kacho-proto compute/v1, ветка storage-split-proto)
- **Instance** — additive: `+image` (OCI ref), `+image_digest` (OUTPUT immutable pin), `+cpu_guarantee_percent` (int32). `network_interfaces[]` зеркало — уже есть.
- **AttachedDisk / AttachedDiskSpec** — **BREAKING**: `disk_id → volume_id` (ссылка на storage `vol`). `DetachDisk` oneof `{volume_id|device_name}`.
- **InstanceService** — re-add (KAC-266 снёс): `AttachNetworkInterface`/`DetachNetworkInterface` + request/metadata (`AttachedNicSpec{nic_id, index?}`). Additive.
- НЕ удаляем compute.v1 `Disk/Image/Snapshot` (strangler — удаление + data-migration = поздняя фаза).

### 2. kacho-vpc (нужно для NIC-attach)
- Миграция: `ALTER TABLE network_interfaces ADD COLUMN used_by_index integer` + partial `UNIQUE(used_by_id, used_by_index) WHERE used_by_id<>''` (новая goose, ban #5).
- `InternalNetworkInterfaceService.Attach/Detach/ListByInstance` (:9091, mTLS) — self-describing CAS на `used_by_id` c **zone-coherence + anycast-исключение** (`s.placement_type='REGIONAL' OR s.zone_id=$instance_zone_id`). vpc валидирует свою строку, НЕ зовёт compute.

### 3. kacho-compute (импл)
- **Убрать** compute-local `attached_disks` (таблица + FK + in-TX disk-логика) — attach-state теперь в storage. Instance локальной attach-таблицы не держит.
- **Клиенты**: `storage_client.go` (InternalVolumeService.Attach/Detach/ListAttachments) + `vpc_client.go` (InternalNetworkInterfaceService) — per-call timeout, mTLS, fail-closed Unavailable. (vpc-client в compute был удалён KAC-266 — возвращаем, но НЕ обратный вызов.)
- **AttachDisk saga (S3)**: compute-local instance CAS-гейт (`state IN RUNNING/STOPPED`) → `storage.Attach(volume_id, instance_id, instance_name, instance_zone_id, project_id, device_name, is_boot, mode, auto_delete)` → `MarkDone(mirror)`. compute локально ничего не пишет → replay идемпотентен. `DetachDisk` симметрично.
- **Instance.Delete auto_delete (M2)**: instance-строку удалять **последней**; список volume_id → в `Operation.metadata`; per-volume `storage.Detach` + (auto_delete) `storage.Volume.Delete`; НЕТ storage-side sweep (M1).
- **AttachNetworkInterface/DetachNetworkInterface (S4)**: → vpc InternalNetworkInterfaceService; несколько NIC; zone-coherence+anycast — энфорсит vpc.
- **Instance.Get/List зеркала (S5/M4)**: `boot_volume`/`secondary_volumes` из `storage.ListAttachments` (batched); `network_interfaces` из vpc `ListByInstance`; **graceful-degrade** при недоступности owner (Get не падает).
- **cpu_guarantee_percent**: 0=burstable, 1..100 (CHECK); sizing меняется только при STOPPED.
- **image/image_digest**: proto-поля + хранение. **Registry-resolve edge (compute→kacho-registry) — DEFER** (отдельный инкремент; в этой фазе поля есть, резолв/digest-pin помечаем out-of-scope, как storage GetInternal). image-based boot-disk-from-image старый флоу — не используется (OCI-доставка).

### 4. api-gateway (task #8, координация)
- Регистрация storage.v1 `/storage/v1/*` + InternalVolumeService на internal-mux + opsproxy `sop`.
- Новые Instance RPC (Attach*NetworkInterface) на public.
- **object-scoped authz catalog** для storage + новых compute RPC (HIGH-gate go-review) + `make permission-catalog-check`.
- corelib `ids` префиксы `vol/snp/dtp` + op-root `sop` (для cross-repo corevalidate + opsproxy).

### 5. Data-migration (поздняя фаза, со снятием compute.v1.Disk)
- Существующие compute `disks`/`attached_disks` → storage `volumes`/`volume_attachments`; compute `images`/`snapshots` → storage. Для dev/demo-стенда, возможно, no-op (свежие деплои). Идемпотентная, prefix-preserving или re-mint (решить). Пока compute.v1.Disk серв*ится — не срочно.

## Порядок исполнения (topo)
1. proto Instance changes (kacho-proto) → buf lint/gen (buf breaking будет ругаться на disk_id→volume_id — ожидаемо, clean-boundary).
2. vpc: used_by_index migration (db-review) + Internal NIC-attach RPC (TDD, CAS+zone-coherence race).
3. compute impl (TDD): storage/vpc clients, AttachDisk/DetachDisk saga, NIC-attach, delete-saga M2, mirrors M4, cpu_guarantee. Integration (fake storage/vpc ports) + newman.
4. api-gateway registration + authz catalog + corelib ids (#8).
5. deploy chart (kacho-storage + compute env для storage/vpc-edge) + vault/polyrepo trail.
6. Поздн*ее: удалить compute.v1 Disk/Image/Snapshot + data-migration.

## Риски
- **CI compute красный** между шагом 1 (breaking proto) и шагом 3 (impl) — держим на эпик-ветке, не мёржим до когерентности.
- **Потеря compute-local attached_disks** при снятии таблицы — для существующих инстансов; dev-стенд свежий → приемлемо; иначе data-migration до снятия.
- **Ацикличность** — CI-guard: kacho-storage/kacho-vpc `internal/clients` не импортируют compute-stub.
- **NIC multi-attach** — уникальность на NIC (`used_by_id`), НЕ глобальный (урок vpc 0016→0017).
