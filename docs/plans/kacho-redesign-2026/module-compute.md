# Kachō Compute — Instance / MachineType / PlacementGroup (tenant-facing design)

## Ментальная модель

**Instance — единственный вычислительный ресурс Kachō Compute.** Плоский ресурс: один `instanceKind` (`VM | CONTAINER`) — дискриминатор жизненного цикла, а не ярлык. Всё, что нужно для запуска, задаётся **одним `Create`**: «какой размер» (`machineTypeId`), «какая ОС/образ» (`bootSource` + опционально `bootVolumeSizeGiB`/`bootVolumeTypeId`), «в какую сеть» (`networkInterfaceSpecs[]` **или** `useDefaultNetwork`), «какие диски» (`secondaryVolumeSpecs[]`), «какие ключи» (`sshPublicKeys[]`). Create-worker разворачивает attach-саги NIC/Volume **внутри одной `Operation`** — клиент видит один async-вызов, а не три.

**Три sync-каталога перед запуском — «что я могу выбрать» лежит рядом:** `MachineTypeService.List` (размер; фильтруется `family=`/`minGpus=`), `ImageCatalogService.List` (bootable образы, каждый item несёт готовый `ref` **и** inline-фрагмент `bootSource{type,id}`), `VolumeTypeService.List` (типы дисков — boot И secondary). Ни один из трёх не заставляет уходить с launch-поверхности и гадать `id` вслепую.

**Проверить до запуска — `validateOnly:true`:** `Create`/`Update` в dry-run-режиме прогоняют полную валидацию (bookability `machineType` в целевой зоне, zone-coherence subnet/SG, satisfiability spread, registry pull-grant для приватного образа) и возвращают **sync** `FAILED_PRECONDITION`/`InvalidArgument` с конкретной причиной — **без** мутации и без `Operation`, плюс non-fatal `warnings[]` и эхо выведенной зоны. **`validateOnly` намеренно НЕ триггерит STOPPED-gate** — в этом весь смысл capacity-precheck ДО `Stop`: живой `RUNNING`-инстанс проверяется на «влезет ли новый размер», не беря простой.

Четыре опоры, каждая с ОДНИМ источником истины:

1. **Размер — `machineTypeId`** (`mt-…` slug ИЛИ стабильное каталожное имя `std-v3-2`, резолвится server-side в scope проекта; canonical echo — всегда `mt-…`) из sync-каталога `MachineTypeService`. Никаких `platform_id`, `core_fraction`, raw `ResourcesSpec` на входе. Единственный опциональный baseline-регулятор — `cpuGuaranteePercent {0..100}` (0 = burstable) — простой скаляр, применим **только** к CPU-flavor'ам (`family∈{STANDARD,COMPUTE,MEMORY}`); при `family=GPU` игнорируется (`validateOnly`-note). `vCpu`/`memoryMiB`/`gpus` — из каталожной записи, output-only на инстансе.
2. **ОС — `bootSource`** — на входе **две позиции** `{type,id}` (`registry.image | storage.image`); output-only `name` появляется только в GET-ответе. `tag`/`digest` живут внутри `id` на **всех входах** (Create И Reinstall). Размер и тип boot-Volume — опц. `bootVolumeSizeGiB`/`bootVolumeTypeId` на Create. Resolved digest и материализованный boot-Volume — output-only, **вложены под `bootSource`**. Смена ОС после Create — **только через `Reinstall`**. Дискаверинг — `ImageCatalogService.List` (item несёт готовый inline `bootSource{type,id}`).
3. **Placement — зона ИЛИ группа.** `zoneId` авторитетен; при omit и ровно одном зональном subnet в `networkInterfaceSpecs` **выводится из `subnet.zone`**. КРОМЕ случая вступления в `ZONE_SPREAD` `PlacementGroup` с `REQUIRED`-enforcement — тогда `zoneId` пуст, зону назначает scheduler (конфликтующий непустой `zoneId` отвергается синхронно, не молчаливый DEGRADED).
4. **GPU-кремний — только `machineType`.** `family=GPU` → `gpus`+`gpuType` авторитетны; count выбирается **гранулярностью каталога** (`gpu-a100-1/-2/-4/-8`), а не отдельным полем. `requiredCapabilities[]` — ТОЛЬКО под ортогональные фичи, которых нет в каталоге (`local.nvme`, `cpu.arch`). `gpu.*` в capabilities при `family=GPU` → `InvalidArgument` (и `CapabilityVocabulary` заранее помечает `gpu.*` как `mutuallyExclusiveWith="machineType.family=GPU"`).

**Two-projection:** инфра (node/host/scheduler/underlay/numeric-id, host-affinity, opaque `topologyKey`) — только Internal* :9091. Публичная поверхность — намерение + результат.

**Async:** `Get`/`List`/`GetInstanceOutput` — sync; `Create`/`Update`/`Delete`/`Reinstall`/`Reboot`/`AttachVolume`/… → `Operation` (клиент поллит через `OperationService.Get`; Watch нет).

---

## MachineType (flat, sync-каталог)

```jsonc
// GET /compute/v1/machineTypes/mt-7k3q9x2m4n8p1r5t
{
  "id": "mt-7k3q9x2m4n8p1r5t",
  "name": "std-v3-2",                   // стабильное имя — принимается как alt-reference на machineTypeId
  "description": "General-purpose, 2 vCPU / 8 GiB",
  "family": "STANDARD",                 // STANDARD | COMPUTE | MEMORY | GPU
  "effectiveResources": {               // output-only, derived — авторитетный размер
    "vCpu": 2,
    "memoryMiB": 8192,                   // MiB, НЕ байты
    "gpus": 0,
    "gpuType": ""                        // пусто, кроме family=GPU
  },
  "availableZones": ["ru-1a", "ru-1b"], // ° pre-check bookability (sync capacity-hint; авторитетно — validateOnly)
  "status": "AVAILABLE",                // AVAILABLE | DEPRECATED | RETIRED
  "labels": {},
  "createdAt": "2026-07-15T10:00:00Z"
}
```

```jsonc
// GPU-каталог — count выражен ГРАНУЛЯРНОСТЬЮ flavor'а (gpu-a100-1/-2/-4/-8), не отдельным полем.
// '1×A100' = выбор gpu-a100-1, '8×A100' = выбор gpu-a100-8 — модель 'один канал sizing' не меняется.
{
  "id": "mt-a1b2c3d4e5f6g7h8j",
  "name": "gpu-a100-8",
  "family": "GPU",
  "effectiveResources": {
    "vCpu": 96, "memoryMiB": 1179648,
    "gpus": 8, "gpuType": "a100-80g"    // авторитетно: '8×A100' выражается ЗДЕСЬ (см. также gpu-a100-1/-2/-4)
  },
  "availableZones": ["ru-1b"],
  "status": "AVAILABLE"
}
```

> `MachineTypeService.List` перед launch — узнаваемая форма выбора размера. **filter-whitelist**: `name=`, `family=` (напр. `family=GPU` — так дискаверятся GPU-flavor'ы), `minGpus=` (напр. `minGpus=4`). `DEPRECATED` можно использовать на существующих, `RETIRED` отвергается на Create. `machineTypeId` в запросах принимает и `mt-…`, и `name` — indirection List-lookup для статичных IaC-шаблонов не обязателен.

---

## ImageCatalog / VolumeType (sync-discovery, рядом с MachineType)

```jsonc
// GET /compute/v1/imageCatalog  — thin read-projection над storage.image + registry.image
// ownership не меняется: образы остаются у storage/registry, это только bootable-проекция
{ "items": [
  { "type": "storage.image",  "id": "img-9k2m4x7q1n8p", "name": "ubuntu-22-04-lts",
    "family": "linux", "tag": "22.04-lts", "digest": "sha256:9f2a…",
    "minSizeGiB": 10,                              // ° минимум для bootVolumeSizeGiB
    "ref": "img-9k2m4x7q1n8p:22.04-lts",           // ° copy-paste → bootSource.id (id+tag уже склеены)
    "bootSource": { "type": "storage.image", "id": "img-9k2m4x7q1n8p:22.04-lts" } }, // ° готовый inline-фрагмент → CreateInstanceRequest.bootSource
  { "type": "registry.image", "id": "ml/bert-trainer",  "name": "bert-trainer",
    "family": "oci",   "tag": "cu121",     "digest": "sha256:1c7d…",
    "ref": "ml/bert-trainer:cu121",                // ° copy-paste → bootSource.id
    "bootSource": { "type": "registry.image", "id": "ml/bert-trainer:cu121" } }      // ° type не сопоставляется руками
]}
```

```jsonc
// GET /compute/v1/volumeTypes  — vt-… каталог для bootVolumeTypeId и secondaryVolumeSpecs[].volumeTypeId
{ "items": [
  { "id": "vt-ssd", "name": "SSD", "description": "General-purpose SSD",     "status": "AVAILABLE" },
  { "id": "vt-nvme","name": "NVMe","description": "Local-attached high-IOPS", "status": "AVAILABLE" }
]}
```

> Три pre-launch «что я могу выбрать» списка сидят вместе: `MachineTypeService.List` (размер) · `ImageCatalogService.List` (готовый `bootSource{type,id}` → прямо в Create) · `VolumeTypeService.List` (`bootVolumeTypeId` + `volumeTypeId`). Все — sync `Get/List`, чистая read-проекция, ничего не владеют. `item.bootSource` — точный inline-фрагмент, который потребляет launch: ни `ref` сплайсить, ни `type` угадывать руками не нужно.

---

## Instance (flat resource)

```jsonc
// GET /compute/v1/instances/ins-2m9x7k4q1n8p3r6t  (VM)
{
  "id": "ins-2m9x7k4q1n8p3r6t",
  "projectId": "prj-a8f2k9m3q7",         // scope slug, peer-validate (не 'folder')
  "name": "trainer-node-01",             // UNIQUE(project,name); пустое name допустимо (id-only escape-hatch)
  "description": "",
  "labels": { "team": "ml" },
  "createdAt": "2026-07-15T10:05:00Z",
  "instanceKind": "VM",                  // VM (виртуальная машина) | CONTAINER (job) — immutable после Create

  // ── размер (ОДИН источник + опциональный CPU-модулятор) ────
  "machineTypeId": "mt-7k3q9x2m4n8p1r5t", // canonical echo — всегда mt- slug (даже если на входе было имя std-v3-2)
  "cpuGuaranteePercent": 100,            // {0..100}, 0=burstable; применяется ТОЛЬКО к family∈{STANDARD,COMPUTE,MEMORY}
  "effectiveResources": {                // ° output-only зеркало каталога
    "vCpu": 2, "memoryMiB": 8192, "gpus": 0, "gpuType": ""
  },

  // ── ОС (ОДИН вход {type,id}; resolved-факты ВЛОЖЕНЫ) ─────────────
  "bootSource": {                         // Referrer — dependency (чужой ресурс)
    "type": "storage.image",              // storage.image = OS/disk-образ | registry.image = OCI-образ из реестра
    "id":   "img-9k2m4x7q1n8p:22.04-lts", // tag/digest живёт ВНУТРИ id (grammar ниже)
    "name": "ubuntu-22-04-lts",           // ° output-only (в GET-ответе; на входе поля НЕТ)
    "resolvedDigest":     "sha256:9f2a…", // ° resolved
    "materializedVolume": {               // ° материализовано; несёт итоговый размер/тип boot-Volume
      "type": "storage.volume", "id": "vol-3n8p…", "name": "trainer-node-01-boot",
      "sizeBytes": 107374182400, "sizeGiB": 100, "volumeTypeId": "vt-ssd" }  // ° echo bootVolumeSizeGiB/bootVolumeTypeId (bytes+GiB)
  },

  // ── placement ──────────────────────────────────────────
  "zoneId": "ru-1a",                       // авторитетен; ПУСТ при вступлении в ZONE_SPREAD+REQUIRED группу; выводится из subnet.zone при omit
  "placementGroupId": "",                  // slug plg-… либо пусто (SINGULAR — инстанс в одной группе)
  "fqdn": "trainer-node-01.ru-1.kacho.internal",  // region выводится из zone.regionId

  // ── сеть/диски (° output-зеркала; вход — *Specs / useDefaultNetwork на Create) ──
  "networkInterfaces": [                   // ° attach-state у owner vpc
    { "id": "nic-…", "subnetId": "sub-…", "primaryV4": "10.1.4.7",
      "securityGroupIds": ["sg-…"], "externalAddress": "203.0.113.9" }
  ],
  "secondaryVolumes": [                     // ° attach-state у owner storage
    { "volumeId": "vol-7q2m…", "autoDelete": false, "mountPath": "/data",
      "sizeBytes": 107374182400, "sizeGiB": 100 }
  ],
  "sshPublicKeys": ["ssh-ed25519 AAAA… ml@team"],  // next-boot deferred (см. mutability matrix)

  // ── kind-specific (oneof: ровно один блок валиден) ─────
  "vmSpec": {                              // валиден ТОЛЬКО при instanceKind=VM
    "userData": "#cloud-config\n…",        // применяется на next boot
    "metadataOptions": {                   // vendor-agnostic
      "metadataEndpoint": "ENABLED",       // ENABLED | DISABLED
      "metadataTokenRequired": true        // bool
    }
  },
  "containerSpec": null,                    // отсутствует при VM

  "serviceAccountId": "sa-4k8m2q…",         // под ним тянется приватный boot (registry pull-grant)
  "status": "RUNNING",                      // см. таблицу lifecycle
  "statusReason": ""
}
```

```jsonc
// GET /compute/v1/instances/ins-5p8k2m9x4q7n1r3t  (CONTAINER — training job)
{
  "id": "ins-5p8k2m9x4q7n1r3t",
  "projectId": "prj-a8f2k9m3q7",
  "name": "bert-finetune-run-42",
  "instanceKind": "CONTAINER",
  "machineTypeId": "mt-a1b2c3d4e5f6g7h8j",   // family=GPU → 8×A100 из каталога (gpu-a100-8)
  "effectiveResources": { "vCpu": 96, "memoryMiB": 1179648, "gpus": 8, "gpuType": "a100-80g" },
  // cpuGuaranteePercent НЕ применяется (family=GPU) — на входе игнорируется, validateOnly вернул бы note

  "bootSource": {
    "type": "registry.image", "id": "ml/bert-trainer:cu121", "name": "bert-trainer",
    "resolvedDigest": "sha256:1c7d…"
    // materializedVolume ОТСУТСТВУЕТ by construction — ephemeral rootfs у CONTAINER
  },

  "requiredCapabilities": ["local.nvme"],     // плоский список ключей; ТОЛЬКО ортогональное; gpu.* запрещён при family=GPU

  // CONTAINER нуждается в NIC для egress к приватному реестру
  "networkInterfaces": [ { "id": "nic-…", "subnetId": "sub-…", "primaryV4": "10.1.4.9", "securityGroupIds": ["sg-…"] } ],
  "secondaryVolumes": [                        // ° персист вывода/чекпойнтов job'а
    { "volumeId": "vol-9x1n…", "autoDelete": false, "mountPath": "/data",
      "sizeBytes": 214748364800, "sizeGiB": 200 }
  ],

  "vmSpec": null,                             // отсутствует при CONTAINER
  "containerSpec": {                          // валиден ТОЛЬКО при instanceKind=CONTAINER
    "command": ["python", "train.py"],
    "args": ["--epochs=3", "--lr=5e-5", "--bs=32"],
    "env": { "WANDB_MODE": "offline", "HF_HOME": "/data/hf" },  // /data персистится через mountPath
    "workingDir": "/workspace",               // ° может быть заполнено из образа
    "ports": [ { "name": "metrics", "port": 9000 } ],  // °
    "restartPolicy": "ON_FAILURE",            // NEVER | ON_FAILURE | ALWAYS (default NEVER, one-shot)
    "exitCode": 0                             // ° заполнен на SUCCEEDED/FAILED
  },

  "zoneId": "ru-1b",
  "serviceAccountId": "sa-4k8m2q…",           // registry pull под этим SA

  "status": "SUCCEEDED",                       // терминал job-семантики
  "statusReason": ""
  // vmSpec (userData/metadataOptions) ОТСУТСТВУЕТ — VM-only
}
```

**Kind-specific поля — под oneof (`vmSpec` XOR `containerSpec`):**

| поле | VM | CONTAINER |
|---|---|---|
| `vmSpec.userData` | ✓ (next-boot) | — |
| `vmSpec.metadataOptions` | ✓ | — |
| `containerSpec.command/args/env/workingDir/ports` | — | ✓ |
| `containerSpec.restartPolicy` | — | ✓ |
| `containerSpec.exitCode` ° | — | ✓ (SUCCEEDED/FAILED) |
| `bootSource.materializedVolume` ° | ✓ | — (ephemeral rootfs) |
| `bootVolumeSizeGiB` / `bootVolumeTypeId` (Create-вход) | ✓ | — (нет boot-Volume) |
| `sshPublicKeys`, `secondaryVolumes`, `networkInterfaces` | ✓ | ✓ |

**Instance lifecycle по `instanceKind`:**

| kind | не-терминальные | терминальные | job-поля |
|---|---|---|---|
| `VM` | `PROVISIONING → RUNNING ⇄ STOPPING/STOPPED → DELETING` | `DELETED`, `ERROR` | — |
| `CONTAINER` | `PROVISIONING → RUNNING → …` | `SUCCEEDED` / `FAILED` (+`containerSpec.exitCode`), `DELETED`, `ERROR` | `restartPolicy`, `exitCode` |

---

## PlacementGroup (flat resource)

**Ось разброса — ОДИН первичный дискриминатор `spread`; `scope` выводится из него.** `spread` задаёт «по чему разносим/пакуем»; `placementType` (ZONAL/REGIONAL — coherence-якорь) для половины значений **полностью детерминирован** этой осью и остаётся на ресурсе как **output-derived**. Отдельный вход `scope ∈ {ZONAL,REGIONAL}` требуется **только** для `PARTITION`/`PACK`, где failure-domain действительно свободен. Никакой 2×4 legal-матрицы с illegal-клетками — она исчезает by construction.

**Intent → конфигурация (веди ЭТУ таблицу от намерения, `spread` — единственное обязательное решение):**

| Intent | `spread` | `scope` (вход) | `placementType` (° derived) |
|---|---|---|---|
| Пережить потерю **зоны** — anti-affinity (spread) | `ZONE_SPREAD` | — (выводится) | `REGIONAL` |
| Пережить потерю **хоста** внутри зоны — anti-affinity (spread) | `HOST_SPREAD` | — (выводится) | `ZONAL` |
| Секции/партиции внутри домена | `PARTITION` | **required** `ZONAL`\|`REGIONAL` | = `scope` |
| Co-location / network-locality — affinity (pack) | `PACK` | **required** `ZONAL`\|`REGIONAL` | = `scope` |

> **Zone-spread ПОГЛОЩАЕТ host-spread:** разные зоны ⇒ разные хосты. Чтобы «пережить потерю **host ИЛИ zone**», достаточно **ОДНОЙ** `ZONE_SPREAD`-группы — она уже даёт и host-survival. **Две группы НЕ нужны и невозможны**: `placementGroupId` singular, инстанс вступает ровно в одну группу. (`HOST_SPREAD` берут, когда региональный разброс не нужен/недоступен и достаточно пережить хост в пределах зоны.)

```jsonc
// GET /compute/v1/placementGroups/plg-6q2m8k4x1n7p3r
{
  "id": "plg-6q2m8k4x1n7p3r",
  "projectId": "prj-a8f2k9m3q7",             // 'project', не 'folder'
  "name": "trainer-ha",

  "spread": "ZONE_SPREAD",                    // ПЕРВИЧНЫЙ дискриминатор (ось разброса): ZONE_SPREAD | HOST_SPREAD | PARTITION | PACK
  "scope": "",                                // ZONAL | REGIONAL — required ТОЛЬКО для PARTITION/PACK; пуст для ZONE_SPREAD/HOST_SPREAD
  "placementType": "REGIONAL",               // ° output-derived coherence-якорь: ZONE_SPREAD→REGIONAL, HOST_SPREAD→ZONAL, PARTITION/PACK→scope
  "regionId": "ru-1",                         // ° задан при placementType=REGIONAL; zoneId членов назначает scheduler
  "zoneId": "",                               // ° задан при placementType=ZONAL

  "constraint": {                             // параметры spread — ОДИН intent на группу (не массив)
    "enforcement": "REQUIRED",                // REQUIRED (гарантия) | PREFERRED (best-effort)
    "maxSkew": 0                              // = |max−min| членов по доменам. 0 = строгий равномерный spread
                                              //   (1-на-домен при members==domains); 1 = допускает перекос 2-1-0.
                                              //   (для PACK не применяется — affinity, не spread.)
  },

  "members": [                                // ° roster: verify-spread за ОДИН вызов (two-projection-safe: только id+zone)
    { "instanceId": "ins-2m9x…", "zoneId": "ru-1a" },
    { "instanceId": "ins-5p8k…", "zoneId": "ru-1b" }
  ],

  "status": "OK",                             // OK | DEGRADED (DEGRADED достижим ТОЛЬКО при PREFERRED — см. Rule 6)
  "statusReason": "",                         // counts-only на DEGRADED, БЕЗ идентичности домена
  "labels": {},
  "createdAt": "2026-07-15T09:50:00Z"
  // Группа НЕ провижнит/не заменяет членов; инстансы привязываешь сам через Instance.placementGroupId.
  // skew считается по фактически привязанным members[]. Ранний satisfiability-precheck — через
  // validateOnly:true на PlacementGroup.Create (аргумент intendedMemberCount), НЕ хранимое поле.
}
```

> **maxSkew — модель прямо у поля:** `maxSkew = |max−min|` числа членов по доменам. `maxSkew=0` — **строгий** равномерный spread (ровно 1-на-домен, когда `members==domains`) — именно он защищает от потери зоны (никакие 2 члена не делят домен). `maxSkew=1` — допускает перекос `2-1-0`. Чем меньше значение, тем строже разнос. `PACK` — affinity, `maxSkew` к нему неприменим.
>
> `constraint` — единичный объект (один intent): failure-domain выражается осью `spread`, а не стеком. opaque `topologyKey` раскладки — Internal* :9091 (two-projection), на public не выставлен.

> **Worked HA-пример (строгий 1-per-zone):** сначала `PlacementGroupService.Create` с `validateOnly:true`, `intendedMemberCount:3`, тело `{spread:"ZONE_SPREAD", constraint:{enforcement:"REQUIRED", maxSkew:0}}` → precheck: у `ru-1` ≥3 зон и строгий `maxSkew=0` для 3 членов размещаем 1-1-1 → `OK` (`placementType` эхается `REGIONAL`, `regionId` `ru-1`). Затем реальный `Create` группы → 3 × `Instance{placementGroupId=plg-…, zoneId="", networkInterfaceSpecs:[{subnetId:<REGIONAL/anycast subnet>, …}]}` → scheduler разносит по 3 зонам 1-1-1, `members[]` подтверждает раскладку. Если бы у региона было 2 зоны — `validateOnly` (или Create) отверг бы синхронно: `400 FAILED_PRECONDITION "REQUIRED strict spread (maxSkew=0) of 3 members needs 3 zones, region ru-1 has 2"`.
>
> **subnet под REQUIRED-spread:** т.к. `zoneId` пуст (scheduler назначит зону при размещении), зону инстанса на Create знать нельзя → в `networkInterfaceSpecs` передавай **REGIONAL/anycast subnet** (зоне-независимый). Зональный subnet несовместим со scheduler-выбором зоны и даёт sync `400` coherence-conflict.
>
> Default: `PARTITION`/`PACK` без `scope` → `400` («scope required for spread=PARTITION|PACK»). `statusReason` на DEGRADED — two-projection: «сколько сгруппировано», но не «на каком host/домене».

---

## Placement-таблица (coherence + авторитет зоны)

| Сценарий | `Instance.zoneId` | `PlacementGroup` | Правило |
|---|---|---|---|
| Одиночный инстанс | **required** (или выводится из subnet.zone), immutable | `""` | зона задаётся клиентом/выводится из subnet |
| `HOST_SPREAD`-группа (ZONAL) | required == `group.zoneId` | `spread=HOST_SPREAD` | инстанс и группа в одной зоне |
| `ZONE_SPREAD`-группа, `PREFERRED` | опционально | `spread=ZONE_SPREAD` | пустой → scheduler; заданный → должен ∈ `region` |
| `ZONE_SPREAD`-группа, `REQUIRED` | **должен быть пуст** | `spread=ZONE_SPREAD` | scheduler назначает зону; непустой конфликтующий `zoneId` → **sync 400** |
| `ZONE_SPREAD`+`REQUIRED` → **subnet в NIC** | пуст на входе | `spread=ZONE_SPREAD` | передавай **REGIONAL/anycast subnet** (зону знать нельзя); зональный subnet → **sync 400** coherence-conflict; ошибка/`validateOnly` эхают выведенную/назначенную зону |
| `PARTITION`/`PACK` (ZONAL) | required == `group.zoneId` | `scope=ZONAL` | одна зона |
| `PARTITION`/`PACK` (REGIONAL) | ∈ `region` | `scope=REGIONAL` | тот же регион |
| Instance ↔ NIC(subnet) | == subnet.zone (кроме REGIONAL/anycast subnet) | — | placement-coherent; при omit `zoneId` выводится из единственного зонального subnet |
| Instance ↔ secondary Volume | та же зона | — | placement-coherent |

**Sync-отказы (не тихий DEGRADED):**
- REQUIRED-spread конфликт зоны: `400 InvalidArgument "zoneId must be empty when joining a REQUIRED ZONE_SPREAD placement group; scheduler assigns the zone"`.
- REQUIRED-spread + зональный subnet: `400 FAILED_PRECONDITION "subnet sub-… is zonal (zone ru-1a) but a REQUIRED ZONE_SPREAD member gets its zone from the scheduler; pass a REGIONAL/anycast subnet"`.
- Zone/subnet coupling (называет ОБА поля): `400 InvalidArgument "zoneId ru-1a conflicts with subnet sub-… zone ru-1b"`.

---

## RPC surface

### Публичная (external + internal)

```
service InstanceService {
  rpc Get   (GetInstanceRequest)    returns (Instance);                 // sync
  rpc List  (ListInstancesRequest)  returns (ListInstancesResponse);    // sync (filter: name=, placementGroupId=, instanceKind=)
  rpc GetOutput(GetInstanceOutputRequest) returns (InstanceOutput);     // sync — log-tail (CONTAINER) / serial-console (VM) (см. ниже)
  rpc Create(CreateInstanceRequest) returns (operation.Operation);      // async (validateOnly:true → sync dry-run)
  rpc Update(UpdateInstanceRequest) returns (operation.Operation);      // async (validateOnly:true → sync dry-run)
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation);      // async

  rpc Start    (StartInstanceRequest)     returns (operation.Operation);
  rpc Stop     (StopInstanceRequest)      returns (operation.Operation);
  rpc Reboot   (RebootInstanceRequest)    returns (operation.Operation); // atomic power-cycle в ОДНОЙ op; сохраняет зону/диски/NIC/power-target RUNNING
  rpc Reinstall(ReinstallInstanceRequest) returns (operation.Operation); // деструктивно, confirm

  rpc AttachVolume(AttachVolumeRequest) returns (operation.Operation);   // volume noun сквозняком
  rpc DetachVolume(DetachVolumeRequest) returns (operation.Operation);
  rpc AttachNetworkInterface(AttachNICRequest) returns (operation.Operation);
  rpc DetachNetworkInterface(DetachNICRequest) returns (operation.Operation);
}

service MachineTypeService {                 // sync-каталог, discovery перед launch
  rpc Get (GetMachineTypeRequest)   returns (MachineType);
  rpc List(ListMachineTypesRequest) returns (ListMachineTypesResponse);  // filter: name=, family=, minGpus=
}
service ImageCatalogService {                // sync-discovery — bootable-проекция storage.image + registry.image (items несут bootSource{type,id})
  rpc List(ListImageCatalogRequest) returns (ListImageCatalogResponse);
}
service VolumeTypeService {                  // sync-discovery — vt-… каталог (boot + secondary)
  rpc List(ListVolumeTypesRequest)  returns (ListVolumeTypesResponse);
}

service PlacementGroupService {
  rpc Get   (…) returns (PlacementGroup);           // sync
  rpc List  (…) returns (…);                        // sync
  rpc Create(…) returns (operation.Operation);      // async (validateOnly:true + intendedMemberCount → sync satisfiability-precheck ДО op)
  rpc Update(…) returns (operation.Operation);
  rpc Delete(…) returns (operation.Operation);
}

service CapabilityVocabularyService {        // public discovery — inline читаемые имена + mutuallyExclusiveWith
  rpc List(ListCapabilityVocabularyRequest) returns (ListCapabilityVocabularyResponse);
}
// TopologyVocabularyService УБРАН с public — его единственный вход (topologyKey) теперь Internal*.

// Async happy-path (общий OperationService, kacho.cloud.operation.v1):
//   rpc OperationService.Get(GetOperationRequest) returns (Operation);  // GET /compute/v1/operations/{id}
// Poll-loop: Create → op.metadata.instanceId (доступен сразу) →
//            poll OperationService.Get(op.id) с inter-poll delay пока !done →
//            done && !error → InstanceService.Get(instanceId). Watch RPC нет.
```

**`CreateInstanceRequest` (input-спеки; `°`-поля НЕ на входе):**

```jsonc
{
  "projectId": "prj-a8f2k9m3q7",             // required
  "name": "trainer-node-01",                  // optional (пустое → id-only)
  "instanceKind": "VM",                        // required — сильный первый дискриминатор (VM | CONTAINER)
  "machineTypeId": "mt-7k3q9x2m4n8p1r5t",     // required — mt- slug ИЛИ стабильное имя std-v3-2 (резолв в scope проекта).
                                               //   GPU: выбери machineType family=GPU (ListMachineTypes filter family=GPU) — отдельного gpu-поля нет
  "cpuGuaranteePercent": 100,                  // optional (default 100=full; 0=burstable) — применяется ТОЛЬКО к family∈{STANDARD,COMPUTE,MEMORY}
  "bootSource": { "type": "storage.image", "id": "img-9k2m4x7q1n8p:22.04-lts" }, // required {type,id} (name — output-only, на входе НЕТ)
  "bootVolumeSizeGiB": 100,                    // optional — human-scale GiB, >= image.minSizeGiB; иначе default = image-минимум
  "bootVolumeTypeId": "vt-ssd",                // optional — vt-… для boot-Volume; иначе default-тип
  "zoneId": "ru-1a",                           // conditional: omit → выводится из единственного зонального subnet;
                                               //   MUST be empty при REQUIRED ZONE_SPREAD (scheduler назначит); иначе required
  "placementGroupId": "",                      // optional (singular — одна группа)
  "networkInterfaceSpecs": [                    // required (ЛИБО useDefaultNetwork) — needs existing subnet + SG (см. prerequisite)
    { "subnetId": "sub-…", "securityGroupIds": ["sg-…"], "primaryV4": "" }  // ""→IPAM
  ],
  "useDefaultNetwork": false,                  // optional — true (или omit networkInterfaceSpecs) → compute резолвит project-default subnet+SG
                                               //   в выбранной зоне ЧЕРЕЗ compute→vpc (владение резолюцией в vpc; compute НЕ автосоздаёт).
                                               //   До vpc-side default-subnet — используй prerequisite-runbook (ниже)
  "assignExternalAddress": true,               // optional (convenience) — публичный IP для доступа снаружи
  "secondaryVolumeSpecs": [                     // optional
    { "sizeGiB": 100, "volumeTypeId": "vt-ssd", "autoDelete": true, "mountPath": "/data" }  // human-scale GiB
  ],
  "sshPublicKeys": ["ssh-ed25519 AAAA… ml@team"],  // optional (next-boot)
  "requiredCapabilities": [],                  // optional — плоский список ключей ("local.nvme", …); gpu.* при family=GPU → 400
  "serviceAccountId": "sa-4k8m2q…",            // optional — можно опустить для публичных образов; нужен для приватного registry.image pull
  "acknowledgeUnreachable": false,             // optional — required=true, ЕСЛИ instanceKind=VM без sshPublicKeys И без external-достижимого NIC
  "vmSpec": { "userData": "#cloud-config\n…" },// conditional: iff instanceKind=VM
  "containerSpec": null,                        // conditional: iff instanceKind=CONTAINER
  "validateOnly": false                         // optional — true → полная валидация sync, БЕЗ мутации/Operation (+ warnings[], echo resolvedZoneId)
}
```

> **Field markers:** `required` — projectId, instanceKind, machineTypeId, bootSource, (networkInterfaceSpecs **ИЛИ** useDefaultNetwork). `conditional(trigger)` — zoneId (см. выше), vmSpec (iff VM), containerSpec (iff CONTAINER), acknowledgeUnreachable (iff VM-unreachable). `optional-with-default` — остальные. `serviceAccountId` **опционален** для публичных образов, консультируется только для приватного `registry.image` pull.

**Minimal-USABLE Create (login-capable Linux VM — дефолтный образец):**

```jsonc
{
  "projectId": "prj-a8f2k9m3q7",
  "instanceKind": "VM",
  "machineTypeId": "mt-7k3q9x2m4n8p1r5t",           // canonical mt-slug (также принимается имя std-v3-2; echo всегда mt-)
  "bootSource": { "type": "storage.image", "id": "img-9k2m4x7q1n8p:22.04-lts" },
  "zoneId": "ru-1a",
  "networkInterfaceSpecs": [ { "subnetId": "sub-…", "securityGroupIds": ["sg-…"] } ],
  "sshPublicKeys": ["ssh-ed25519 AAAA… ml@team"],  // иначе в машину не залогиниться
  "assignExternalAddress": true                     // иначе машина недостижима снаружи
}
```

**Minimal-bootable (unreachable) — требует явного acknowledge:**

```jsonc
{
  "projectId": "prj-a8f2k9m3q7",
  "instanceKind": "VM",
  "machineTypeId": "mt-7k3q9x2m4n8p1r5t",
  "bootSource": { "type": "storage.image", "id": "img-9k2m4x7q1n8p:22.04-lts" },
  "zoneId": "ru-1a",
  "networkInterfaceSpecs": [ { "subnetId": "sub-…", "securityGroupIds": ["sg-…"] } ],
  "acknowledgeUnreachable": true    // BEZ ssh И без external IP → RUNNING-но-недостижим; guard требует подтверждения (bastion-only кейс)
}
// Без acknowledgeUnreachable:true → sync 400 FAILED_PRECONDITION
//   "VM will be RUNNING but unreachable (no sshPublicKeys and no external address); set acknowledgeUnreachable:true to proceed".
// 'boots' ≠ 'usable'.
```

> **VPC-prerequisite — пронумерованный runbook (обязательно, actionable):** `networkInterfaceSpecs` требует **уже существующих** subnet + security group в целевой зоне — compute их НЕ авто-создаёт (subnet/SG — vpc-owned, cross-domain, авто-создание = цикл-риск). До первого инстанса выполни:
> 1. `SubnetService.List` (в целевой зоне) — есть subnet? → используй его `subnetId`.
> 2. нет subnet → `SubnetService.Create` (vpc) → дождись, забери `subnetId`.
> 3. `SecurityGroupService.List` → возьми/создай `sg-…`.
> 4. подставь оба в `networkInterfaceSpecs[]`.
>
> **Escape-hatch:** `useDefaultNetwork:true` (или omit `networkInterfaceSpecs`) резолвит project-default subnet+SG в выбранной зоне через существующее ребро compute→vpc (владение резолюцией — в vpc; compute НЕ автосоздаёт). До vpc-side default-subnet-релиза форма присутствует, но не функциональна → используй runbook выше. Отсутствие subnet/SG без escape → sync `FAILED_PRECONDITION "needs an existing subnet+SG in zone ru-1b; discover via SubnetService.List / SecurityGroupService.List, create via SubnetService.Create — or set useDefaultNetwork:true"`.
>
> Возвращает `Operation`; `instanceId` доступен в `Operation.metadata = CreateInstanceMetadata.instanceId` сразу (id аллоцируется при Create, до `done`) и эхается в `Operation.description`. Поллить — `OperationService.Get`.

**`validateOnly:true` ответ (dry-run — sync, БЕЗ мутации/Operation):**

```jsonc
// POST /compute/v1/instances { …, "validateOnly": true }  → sync 200
{
  "valid": true,
  "resolvedZoneId": "ru-1a",                    // ° выведенная зона (из subnet / или назначаемая scheduler для REQUIRED ZONE_SPREAD)
  "warnings": [                                  // ° non-fatal — Create не блокируется (кроме acknowledgeUnreachable-guard)
    { "code": "UNREACHABLE",
      "message": "instance will be RUNNING but unreachable: no sshPublicKeys and no external address" }
  ]
  // fatal-причины отдаются как sync FAILED_PRECONDITION/InvalidArgument (не в этом теле):
  //   bookability machineType в зоне · zone-coherence machineType.availableZones ∩ subnet.zone ∩ zoneId (ОДИН вызов) ·
  //   REQUIRED-spread satisfiability · registry pull-grant (для bootSource.type=registry.image).
  // validateOnly НЕ триггерит STOPPED-gate — power-state-предусловия при dry-run пропускаются by design.
}
```

**`UpdateInstanceRequest` + матрица мутабельности полей (update_mask known-set):**

```jsonc
{
  "instanceId": "ins-2m9x7k4q1n8p3r6t",
  "updateMask": "name,labels,machineTypeId",   // known-set; unknown → InvalidArgument
  "name": "trainer-node-01b",
  "labels": { "team": "ml", "run": "42" },
  "machineTypeId": "mt-…",                       // STOPPED-gated при РЕАЛЬНОМ Update; при validateOnly:true STOPPED-gate НЕ применяется
  "validateOnly": false                          // optional — true → sync bookability/coherence БЕЗ мутации И БЕЗ STOPPED-gate (pre-Stop capacity-check)
}
```

| класс | поля | правило |
|---|---|---|
| **LIVE-mutable** | `name`, `description`, `labels` | применяется на RUNNING сразу |
| **next-boot deferred** | `vmSpec.userData`, `vmSpec.metadataOptions`, `sshPublicKeys` | принимается на RUNNING, `statusReason "takes effect on next boot"` (НЕ reject) |
| **STOPPED-gated** | `machineTypeId`, `cpuGuaranteePercent`, `requiredCapabilities`, `placementGroupId` | реальный Update на не-`STOPPED` → sync `FAILED_PRECONDITION "instance must be STOPPED to change sizing or placement"`; **`validateOnly:true` этот gate НЕ триггерит** |
| **immutable** | `instanceKind`, `zoneId` (после назначения) | mask-содержит → `InvalidArgument "<field> is immutable after Instance.Create"` |
| **Reinstall-only** | `bootSource` | не через Update — только `Reinstall` |

> **Power-state:** `Update` **сохраняет** power-state — инстанс, `STOPPED` до Update, остаётся `STOPPED` и требует явного `Start`. Никакого авто-`RUNNING`.
>
> **Worked runbook — resize живого инстанса (без слепого простоя):**
> 1. `Update{updateMask:"machineTypeId", machineTypeId:"mt-bigger", validateOnly:true}` на **RUNNING** → sync проверяет bookability нового flavor'а в зоне (STOPPED-gate пропущен) → `valid:true` ⇒ размер влезет.
> 2. `Stop` (теперь и только теперь берётся простой).
> 3. `Update{updateMask:"machineTypeId", machineTypeId:"mt-bigger"}` на STOPPED → применяется.
> 4. `Start`.
>
> Это и есть headline «capacity-precheck ДО Stop»: шаг 1 не требует останавливать машину.

**`RebootInstanceRequest` (atomic power-cycle):**

```jsonc
{
  "instanceId": "ins-2m9x7k4q1n8p3r6t",
  "mode": "GRACEFUL"                            // GRACEFUL (ACPI/soft, default) | HARD (force) — опционально
}
// Один async Operation = stop→start внутри саги. Сохраняет зону/диски/NIC и power-target RUNNING.
// Не путать с двумя раздельными Stop+Start (те теряют reboot-семантику и оставляют окно STOPPED).
```

**`ReinstallInstanceRequest` (деструктив, ОДНА грамматика):**

```jsonc
{
  "instanceId": "ins-2m9x7k4q1n8p3r6t",
  "bootSource": { "type": "storage.image", "id": "img-…:24.04-lts" },  // {type,id}; tag/digest ВНУТРИ id (как на Create)
  "confirm": true,                       // acknowledge destroy — обязателен на деструктив
  "startAfter": false                    // optional — deferred авто-Start после rebuild (default false)
}                                         // top-level bootSourceTag/bootSourceDigest УДАЛЕНЫ (дублирующий второй канал)
```

> `confirm` **подтверждает** деструктивный rebuild — он НЕ переопределяет STOPPED-предусловие (оно остаётся hard-enforced). **Blast-radius (документированный контракт):**
> - **сохраняются**: data-volumes / NIC / IP / `machineType`;
> - **пересобирается только** boot-Volume; судьба старого boot-Volume — по `owned=autoDelete`;
> - **REAPPLY на первый boot свежей ОС**: `sshPublicKeys` и `vmSpec.userData`/`metadataOptions` (retained на инстансе — reinstalled-машина НЕ остаётся без логина);
> - **power-state сохраняется**: `STOPPED` до Reinstall → остаётся `STOPPED`, нужен явный `Start` (опциональный `startAfter:true` — deferred, не default).
>
> Пред-условие: инстанс `STOPPED` → иначе синхронно `FAILED_PRECONDITION "instance must be STOPPED to reinstall"`.

**`bootSource.id` grammar (inline, per-type — одна для всех входов):**

```
storage.image  : 'img-<base32>:<tag>'  |  'img-<base32>@sha256:<hex>'
registry.image : '<repo/path>:<tag>'   |  '<repo/path>@sha256:<hex>'    // напр. 'ml/bert-trainer:cu121'
```

> Bare untagged id отвергается с грамматикой в тексте: `400 InvalidArgument "bootSource.id needs a tag or digest, e.g. 'img-<base32>:<tag>' or 'img-<base32>@sha256:<hex>'; use ImageCatalog item.bootSource"`.

**`GetInstanceOutput` (sync — job/log И VM serial-console):**

```jsonc
// CONTAINER: GET /compute/v1/instances/ins-5p8k…:getOutput?stream=log&tailLines=200
{
  "instanceId": "ins-5p8k2m9x4q7n1r3t",
  "stream": "log",                       // log (CONTAINER stdout/stderr) | console (VM serial)
  "exitCode": 0,                         // зеркало containerSpec.exitCode для job'а (только stream=log)
  "logTail": [
    { "ts": "2026-07-15T11:04:02Z", "stream": "stdout", "line": "epoch 3/3 loss=0.021" },
    { "ts": "2026-07-15T11:04:05Z", "stream": "stdout", "line": "saved checkpoint /data/hf/ckpt-42" }
  ],
  "truncated": true                       // больше строк доступно
}
```

```jsonc
// VM: GET /compute/v1/instances/ins-2m9x…:getOutput?stream=console&tailLines=200
{
  "instanceId": "ins-2m9x7k4q1n8p3r6t",
  "stream": "console",                    // serial/console-output гостя — VM-debug для 'не грузится / не принимает SSH'
  "logTail": [
    { "ts": "2026-07-15T10:05:41Z", "stream": "console", "line": "[    3.221] cloud-init: SSH host key: ED25519 …" },
    { "ts": "2026-07-15T10:05:44Z", "stream": "console", "line": "[  OK  ] Reached target Multi-User System." }
  ],
  "truncated": true
}
```

> FAILED job больше не «только `exitCode`»: `stream=log` отдаёт хвост логов; персист вывода — `secondaryVolumeSpecs[].mountPath` (напр. `/data`, куда указывает `HF_HOME`), иначе ephemeral rootfs теряет всё после завершения. Для VM `stream=console` — узнаваемая serial-console debug-поверхность (tenant-facing guest-output, НЕ инфра node/host → two-projection не нарушается).

**`CapabilityVocabulary.List`** — opaque-ключи наружу, но ВСЕГДА inline `displayName`/`description` + `mutuallyExclusiveWith` (кросс-поле видно ДО отправки):

```jsonc
{ "items": [
  { "capabilityKey": "local.nvme", "displayName": "Local NVMe scratch",
    "description": "Host-local ephemeral NVMe", "mutuallyExclusiveWith": "" },
  { "capabilityKey": "cpu.arch",   "displayName": "CPU architecture",
    "description": "Instruction set family", "mutuallyExclusiveWith": "" },
  { "capabilityKey": "gpu.model",  "displayName": "GPU model",
    "description": "Accelerator silicon — set via machineType.family=GPU, not here",
    "mutuallyExclusiveWith": "machineType.family=GPU" }
]}
```

### Internal* (:9091 — инфра-чувствительное, НЕ на external)

```
service InternalHostAffinityService {        // host-placement — раскрывает физику
  rpc Get/List/Create/Update/Delete …        // HostAffinityRule целиком здесь
}
// + node/host/scheduler/underlay/numeric-infra-id проекции Instance
// + opaque topologyKey раскладки PlacementGroup.spread (ZONE_SPREAD/HOST_SPREAD/PARTITION/PACK → topologyKey mapping)
```

`HostAffinityRule` — vendor-agnostic ключи (`kacho.host`/`kacho.hostGroup`), только Internal.

---

## Правила (нормативно)

1. **Один канал sizing + один CPU-модулятор.** `machineTypeId` (каталог; принимает `mt-…` slug ИЛИ стабильное имя `std-v3-2`, canonical echo — всегда `mt-…`) — единственный канал размера; `cpuGuaranteePercent {0..100}` — простой опциональный baseline-модулятор, применим **только** к `family∈{STANDARD,COMPUTE,MEMORY}` (0=burstable, default 100=full; при `family=GPU` игнорируется, `validateOnly`-note). **Никакого oneof и raw-sizing-arm** (raw `ResourcesSpec` запрещён на входе — dead-XOR, удалён, LEAN). `effectiveResources` — output-only. Память в каталоге — MiB.
2. **GPU — только `machineType`, count = гранулярность каталога.** `family=GPU` → `gpus`+`gpuType` авторитетны; конкретное число выбирается flavor'ом (`gpu-a100-1/-2/-4/-8`), НЕ отдельным полем — дискаверинг `ListMachineTypes{family=GPU,minGpus=}`. `gpu.*` в `requiredCapabilities` при `family=GPU` → `InvalidArgument "gpu model/count defined by machineType <id>, remove capability requirement"` (и `CapabilityVocabulary` заранее помечает `gpu.*` как `mutuallyExclusiveWith="machineType.family=GPU"`). `requiredCapabilities` — **плоский список ключей**, только ортогональные фичи; operator/values/tier удалены (YAGNI, LEAN).
3. **Один вход ОС `{type,id}`, одна грамматика.** `bootSource` на входе — две позиции `{type,id}`; `name` — output-only (в GET-ответе, на входе поля нет). tag/digest **внутри `id` на всех входах** (Create И Reinstall). Размер/тип boot-Volume — опц. `bootVolumeSizeGiB`(≥`image.minSizeGiB`)/`bootVolumeTypeId` на Create (форм-parity с `secondaryVolumeSpecs`; echo в `materializedVolume.sizeBytes°`+`sizeGiB°`/`volumeTypeId`). Resolved-факты (`resolvedDigest°`, `materializedVolume°`) **вложены под `bootSource`** — output-only. CONTAINER: `materializedVolume`/`bootVolume*` отсутствуют by construction. Смена ОС — только `Reinstall`. Дискаверинг — `ImageCatalogService.List` (item несёт готовый inline `bootSource{type,id}` → прямо в Create; bare untagged id → 400 с грамматикой в тексте).
4. **One-shot launch + default-network escape.** NIC/Volume/ssh задаются спеками на `Create`; worker разворачивает attach-саги в одной `Operation`; attach-state остаётся у owner (`vpc`/`storage`). `networkInterfaces°`/`secondaryVolumes°` — output-зеркала. `networkInterfaceSpecs` **ИЛИ** `useDefaultNetwork:true` — одно обязательно; subnet+SG **vpc-owned**, compute не авто-создаёт → отсутствие даёт actionable sync `FAILED_PRECONDITION` + пронумерованный prerequisite-runbook (List→Create→List) в quick-start, не только в тексте ошибки. `useDefaultNetwork` резолвит project-default через ребро compute→vpc (владение в vpc); до vpc-релиза форма есть, но не функциональна.
5. **CONTAINER — first-class, kind-поля под oneof.** `vmSpec{userData,metadataOptions}` XOR `containerSpec{command,args,env,workingDir,ports,restartPolicy,exitCode}` — `instanceKind` (сильный первый required-дискриминатор) гейтит ОДИН вложенный блок. Job-семантика: `SUCCEEDED`/`FAILED`+`exitCode`, `restartPolicy {NEVER|ON_FAILURE|ALWAYS}` (default NEVER). Персист вывода — `secondaryVolumeSpecs[].mountPath`; чтение — `GetInstanceOutput` (`stream=log` для CONTAINER, `stream=console` для VM serial). CONTAINER нуждается в NIC для egress к приватному реестру.
6. **Placement: ось `spread` первична, `scope` выводится; REQUIRED = гарантия.** `PlacementGroup.spread ∈ {ZONE_SPREAD,HOST_SPREAD,PARTITION,PACK}` — единственный обязательный дискриминатор оси разброса; `placementType` (coherence-якорь) для `ZONE_SPREAD`→`REGIONAL`/`HOST_SPREAD`→`ZONAL` **output-derived**, отдельный `scope` требуется ТОЛЬКО для `PARTITION`/`PACK`. 2×4 legal-матрица устранена by construction. `zoneId` при omit **выводится из единственного зонального subnet** (conflict → sync `400`, называющий ОБА поля); при `REQUIRED ZONE_SPREAD` `zoneId` пуст (scheduler назначает) → в NIC передавай **REGIONAL/anycast subnet** (зональный → sync `400` coherence-conflict); непустой конфликтующий `zoneId` → sync `400`. Под `REQUIRED` non-placeable член → Create `op.error`; `DEGRADED` достижим **ТОЛЬКО** под `PREFERRED`. **`zone-spread ПОГЛОЩАЕТ host-spread`** — «пережить host ИЛИ zone» = ОДНА `ZONE_SPREAD`-группа (не две; `placementGroupId` singular). Satisfiability-precheck — **не хранимое поле, а `validateOnly:true`+`intendedMemberCount` на `PlacementGroup.Create`** (плюс энфорсмент на join: N-й REQUIRED-член, не размещаемый в оставшихся доменах, роняет свой `Instance.Create` синхронным `FAILED_PRECONDITION`); skew считается по фактически привязанным `members[]`. Группа НЕ провижнит/не заменяет членов. `statusReason` на DEGRADED — counts-only; `members[]` — только `instanceId`+`zoneId` (two-projection-safe).
7. **maxSkew — заданная модель; validateOnly обходит STOPPED-gate; next-boot принимается-и-откладывается.** `constraint.maxSkew = |max−min|` членов по доменам: `maxSkew=0` — строгий равномерный spread (1-на-домен при `members==domains`, каноничная HA-защита от потери зоны), `maxSkew=1` — перекос `2-1-0`; меньше = строже. `validateOnly:true` на `Create`/`Update`/`PlacementGroup` — полная валидация (bookability в зоне, three-way zone-coherence `machineType.availableZones ∩ subnet.zone ∩ zoneId` в ОДНОМ вызове, REQUIRED-spread satisfiability, registry pull-grant) sync, **без** мутации/Operation, с `warnings[]`+`resolvedZoneId`, и **намеренно НЕ триггерит STOPPED-gate** (это pre-Stop capacity-check живого RUNNING). Реальная смена `machineTypeId`/`cpuGuaranteePercent`/`requiredCapabilities`/`placementGroupId` у не-`STOPPED` → sync `FAILED_PRECONDITION "instance must be STOPPED to change sizing or placement"`. Next-boot поля (`vmSpec.userData`/`metadataOptions`/`sshPublicKeys`) на RUNNING — **принимаются с deferral** (`statusReason "takes effect on next boot"`), НЕ reject.
8. **Vendor-agnostic + unreachable-guard.** `metadataOptions{metadataEndpoint:ENABLED|DISABLED, metadataTokenRequired:bool}` (без бренд-префиксов/версий). `HostAffinityRule` и opaque `topologyKey` целиком на Internal* :9091. Intent→config-таблица `spread`/`scope` публична. Во всех doc-строках `folder → project`. `spread` gloss: `ZONE_SPREAD/HOST_SPREAD/PARTITION` — anti-affinity (spread), `PACK` — affinity (co-location). **Unreachable-guard**: `instanceKind=VM` без `sshPublicKeys` И без external-достижимого NIC → `validateOnly` warning + реальный Create требует `acknowledgeUnreachable:true` (не блокирует легальный bastion-only кейс).
9. **Volume noun сквозняком + power-ops.** `AttachVolume`/`DetachVolume`, `Referrer.type=storage.volume`, `volumeId`, `VolumeType` (`vt-…`, дискаверинг `VolumeTypeService.List`, покрывает boot И secondary). `bootVolumeSizeGiB`/`secondaryVolumeSpecs[].sizeGiB` — human-scale GiB на входе (не байты; output-echo несёт `sizeBytes°`+`sizeGiB°`). «Disk» с compute-поверхности убран. `Reboot` — atomic power-cycle в одной Operation (сохраняет зону/диски/NIC/power-target RUNNING), рядом со Start/Stop.
10. **Pull-identity приватного образа + precheck.** `registry.image` тянется под `instance.serviceAccountId`, которому нужен registry pull-grant на repo (`AccessBindingService.Create` — bind SA роль `registry.puller` на repo; см. registry-docs). `serviceAccountId` опционален для публичных образов. **`validateOnly:true` при `bootSource.type=registry.image` включает pull-grant precheck** (вызов на registry/IAM-сторону) в sync-ответ — единый dry-run покрывает «влезет ли flavor» И «доступен ли образ SA». Реальный Create с приватным образом без grant → best-effort sync `FAILED_PRECONDITION "service account sa-… lacks pull-grant on repo ml/bert-trainer"`; сам grant — cross-domain IAM/registry-забота. Грамматика `id`: repo-path + `:tag`|`@digest`.
11. **Two-projection / async / reference-law.** Инфра (node/host/scheduler/underlay/numeric-id, topologyKey) — только Internal*. `Get`/`List`/`GetInstanceOutput` sync, мутации → `Operation` (поллинг через `OperationService.Get` = `GET /compute/v1/operations/{id}`; Watch нет). Within-service → flat `<x>Id`+FK; scope/placement → flat slug + peer-validate; dependency (bootSource/nic/volume) → Referrer. `GetInstanceOutput` `stream=console` — tenant-facing guest-output (не инфра).
12. **Placement-coherence.** ZONAL↔ZONAL — та же зона; REGIONAL → anycast/regional. Instance↔Volume/NIC — та же зона (кроме REGIONAL/anycast subnet). Дискриминатор `placementType` (output-derived из `spread`/`scope`) несёт failure-domain семантику: `ZONE_SPREAD`(REGIONAL)=пережить зону (и хост by subsumption), `HOST_SPREAD`(ZONAL)=пережить хост. Стек «зона И хост» — НЕ две группы (zone-spread уже субсумирует), а одна `ZONE_SPREAD`; `placementGroupId` singular. REQUIRED ZONE_SPREAD ⇒ NIC-subnet должен быть REGIONAL/anycast.
13. **Discoverability.** Три sync pre-launch каталога рядом: `MachineTypeService.List` (filter `name=/family=/minGpus=`) · `ImageCatalogService.List` (item.`bootSource{type,id}` + `ref`) · `VolumeTypeService.List`. `UNIQUE(project,name)` (`AlreadyExists`-тон; partial-index допускает пустое `name`). `fqdn`: region выводится из `zone.regionId`. `List` filter whitelist: `name=`, `placementGroupId=`, `instanceKind=`. `maxSkew=0` — строгий 1-per-domain при `members==domains`; `maxSkew=1` — перекос 2-1-0. Enum-значения (`instanceKind`, `bootSource.type` — `storage.image`=OS/disk-образ, `registry.image`=OCI-контейнер; `spread`; `scope`; `RebootInstanceRequest.mode`; capability) несут inline gloss/displayName. Output-echo дублирует `sizeBytes`+`sizeGiB` (boot И secondary). `machineTypeId` в примерах — canonical `mt-`-slug (нота: также принимается имя `std-v3-2`; echo всегда `mt-`). `zoneId` inline decision-hint (omit→из subnet · MUST be empty при REQUIRED ZONE_SPREAD · иначе required) + эхо `resolvedZoneId` в validateOnly. `Update`/`Reinstall`/`Reboot` сохраняют/восстанавливают заявленный power-target (`Update`/`Reinstall` `STOPPED` → нужен явный `Start`; `Reboot` → RUNNING).
