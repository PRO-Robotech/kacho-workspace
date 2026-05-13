# In-cluster нагрузочное тестирование Kachō + HPA + IPAM-рефактор до 10k allocate/sec

**Дата:** 2026-05-14
**Цель:** Sustained **10 000 successful `Address.Create` (reserved external IPv4) per second** через api-gateway в развёрнутом Kachō-кластере (`/tmp/e2c825-merged.kubeconfig`, namespace `kacho`), при этом каждый компонент по умолчанию **`replicas=1`** и масштабируется автоматически через **HPA** под нагрузкой.

Разрешено: тюнить Postgres и менять код.

---

## 1. Контекст

Имеющийся baseline (`project/kacho-vpc/tests/k6/results/BASELINE.md`):
- Network.Create через direct gRPC, 1 pod: 5778/sec ✅
- AllocateExternalIP (IPAM): **73 alloc/sec на /16 pool** — это и есть текущий потолок нашего write-path.
- api-gateway 1 pod: ~3500 RPS limit.

Причина 73/sec — текущий аллокатор использует **random-pick → UNIQUE-violation retry**: каждое allocate под concurrency=200 проходит через round-trip `UPDATE addresses SET ip=<random>` → ловит UNIQUE-conflict → retry. Quadratic-в-concurrency деградация. Никакой horizontal scaling не вытянет 10k через этот цикл — pool-row contention доминирует.

В текущем кластере (`KUBECONFIG=/tmp/e2c825-merged.kubeconfig`, ns `kacho`) workloads вручную смасштабированы (api-gateway=24, vpc=8, rm=4) и **HPA не настроен** (`kubectl get hpa -n kacho` = пусто).

## 2. Цели и не-цели

### В скоупе

1. **HPA на всех Kachō-сервисах** (`api-gateway`, `vpc`, `resource-manager`, `compute`, `ui`) с дефолтом `replicas=1` и автоскейлом до 10 по CPU 70%.
2. **Resource requests/limits** в helm-чартах (без них HPA не сработает).
3. **PG-tune** в `values.dev.yaml` (`synchronous_commit=local`, `max_connections=300`, `shared_buffers=512MB`, `work_mem=16MB`, `effective_cache_size=2GB`, resources requests/limits).
4. **App-tune** kacho-vpc (`KACHO_VPC_DB_MAX_CONNS=200`, `KACHO_VPC_DEFAULT_SG_INLINE=false`, folder cache на 30s — проверить default).
5. **IPAM-рефактор (B'):** materialized freelist `address_pool_free_ips` + `FOR UPDATE SKIP LOCKED ORDER BY ip LIMIT 1` + safety-net unique index на `addresses(pool_id, external_ipv4)`.
6. **In-cluster k6 Job** (Dockerfile + `loadtest-job.yaml` + Makefile target). Бьёт по `api-gateway.kacho.svc.cluster.local:8080`. Inline cleanup (Create → poll → Delete → poll). Thresholds для SLO.
7. **Bench-репорт**: измерить baseline (1 replica, default config) → tuned (HPA + DB tune + IPAM-рефактор) → обновить `BASELINE.md`.

### Не в скоупе (backlog)

- **IPv6 sparse allocator** (отдельный design — sparse single-IP с cursor + range leasing, `ipv6_pool_cursors`/`ipv6_allocated_ips`/`ipv6_released_offsets`). Реализуем после IPv4-цели.
- pgBouncer (pgxpool достаточно — добавим если станет узким местом).
- DB sharding / read-replicas.
- Compute/RM HPA-тюнинг под их специфические сценарии (compute не главный write-path).
- KEDA с RPS-based scaling (CPU достаточно).

## 3. Архитектурный обзор

```
┌────────────────────────────────────────────────────────────────┐
│  in-cluster k6 Job (ns kacho)                                  │
│  - Dockerfile: grafana/k6:0.55 + scripts                       │
│  - env: BASE_URL=http://api-gateway:8080, FOLDER_ID, ZONE_ID   │
│  - script: reserved-ext-allocate.js (Create → poll → Delete)  │
└──────────────────────────┬─────────────────────────────────────┘
                           │ HTTP (REST через grpc-gateway)
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  api-gateway (HPA: 1..10, target CPU 70%)                      │
│  - grpc-proxy → vpc:9090                                       │
└──────────────────────────┬─────────────────────────────────────┘
                           │ gRPC
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  vpc (HPA: 1..10, target CPU 70%)                              │
│  - Address.Create handler                                      │
│  - AllocateExternalIP (NEW: PG-native freelist via SKIP LOCKED)│
│  - pgxpool(KACHO_VPC_DB_MAX_CONNS=200)                         │
└──────────────────────────┬─────────────────────────────────────┘
                           │ pgx (SQL)
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  pg-vpc (1 pod, synchronous_commit=local, max_conn=300, ...)   │
│  - addresses                                                   │
│  - address_pools                                               │
│  - address_pool_free_ips  (NEW — materialized freelist)        │
│  - UNIQUE INDEX addresses_pool_ip_unique  (NEW — safety net)   │
└────────────────────────────────────────────────────────────────┘
```

`resource-manager` отвечает на folder existence через `folderClient.Exists` в worker'е — TTL-cache 30s держит миссы вне hot-path (повторных запросов на тот же folder ≪ 1 на каждые 30s).

## 4. Изменения по компонентам

### 4.1 helm-чарты — HPA + requests/limits

Каждый чарт-репо (`kacho-vpc/deploy`, `kacho-api-gateway/deploy`, `kacho-resource-manager/deploy`, `kacho-compute/deploy`, `kacho-ui/deploy`):

**values.yaml:**
```yaml
replicas: 1   # дефолт по требованию пользователя

resources:
  requests:
    cpu: 100m
    memory: 256Mi    # vpc / api-gateway
  limits:
    cpu: 2000m       # vpc; api-gateway: 1000m
    memory: 1Gi      # vpc; api-gateway: 512Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
      - type: Percent
        value: 100   # удвоение каждые 30s
        periodSeconds: 30
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
      - type: Percent
        value: 25
        periodSeconds: 60
```

**templates/hpa.yaml** (новый файл, gated `{{- if .Values.autoscaling.enabled }}`):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Values.name }}
  namespace: kacho
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Values.name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
  behavior:
    scaleUp: {{ toYaml .Values.autoscaling.scaleUp | nindent 6 }}
    scaleDown: {{ toYaml .Values.autoscaling.scaleDown | nindent 6 }}
```

**templates/deployment.yaml** — добавить `resources:` блок (берётся из `.Values.resources`).

### 4.2 PG-tune — values.dev.yaml umbrella

`pg-vpc`, `pg-compute`, `pg-resource-manager`:
```yaml
pg-vpc:
  primary:
    extendedConfiguration: |
      synchronous_commit = local
      max_connections = 300
      shared_buffers = 512MB
      work_mem = 16MB
      effective_cache_size = 2GB
      checkpoint_timeout = 15min
      max_wal_size = 2GB
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 4000m
        memory: 4Gi
```

`synchronous_commit=local` — компромисс: WAL flush на primary без ожидания replicas (у нас нет replicas). Безопаснее, чем `=off` (который теряет последние commits при crash). Для bench-теста и dev-стенда — OK.

### 4.3 App env — kacho-vpc

`kacho-vpc/deploy/values.yaml`:
```yaml
env:
  KACHO_VPC_DB_MAX_CONNS: "200"
  KACHO_VPC_DEFAULT_SG_INLINE: "false"   # убирает 2 INSERT + 1 UPDATE из Network.Create hot-path; для Address это не критично, но дешёвый win
  KACHO_VPC_FOLDER_CACHE_TTL: "30s"      # если ещё не default
```

### 4.4 IPAM-рефактор — миграция

`kacho-vpc/internal/migrations/0014_address_pool_freelist.sql`:

```sql
-- Migration: address_pool_free_ips — materialized freelist для IPv4 allocator (PG-native).
-- Заменяет random+UNIQUE-retry pattern на atomic SKIP LOCKED pop.

CREATE TABLE address_pool_free_ips (
    pool_id  TEXT NOT NULL REFERENCES address_pools(id) ON DELETE CASCADE,
    ip       INET NOT NULL,
    PRIMARY KEY (pool_id, ip)
);

CREATE INDEX address_pool_free_ips_pool_idx
    ON address_pool_free_ips(pool_id);

-- Safety-net уже на месте: UNIQUE INDEX `addresses_external_pool_ip_uniq`
-- (0001_initial.sql:511) гарантирует уникальность (pool_id, ip) на addresses.
-- Дублировать не нужно — наш freelist-flow + существующий unique index закрывают
-- и manual reservation race, и потенциальные баги аллокатора.

-- Backfill: для каждого существующего pool заполняем freelist.
-- Для /16 → 65k INSERT'ов одной командой (через generate_series).
-- Исключаем network/broadcast (.0 и .255 для /24-/30; для /16 это .0.0 и .255.255).
-- Также исключаем уже-аллоцированные IP (которые присутствуют в addresses).
DO $$
DECLARE
    pool_row RECORD;
    cidr_str TEXT;
BEGIN
    FOR pool_row IN SELECT id, cidr_blocks FROM address_pools LOOP
        FOREACH cidr_str IN ARRAY pool_row.cidr_blocks LOOP
            -- Берём только IPv4 prefix; IPv6 идут в backlog (sparse allocator).
            IF family(cidr_str::cidr) = 4 THEN
                INSERT INTO address_pool_free_ips (pool_id, ip)
                SELECT pool_row.id, host(addr)::inet
                FROM generate_series(
                    network(cidr_str::cidr) + 1,                  -- skip .0 (network)
                    broadcast(cidr_str::cidr) - 1                 -- skip .255 (broadcast)
                ) AS addr
                WHERE NOT EXISTS (
                    SELECT 1 FROM addresses a
                    WHERE (a.external_ipv4 ->> 'address_pool_id') = pool_row.id
                      AND (a.external_ipv4 ->> 'address') = host(addr)
                )
                ON CONFLICT (pool_id, ip) DO NOTHING;
            END IF;
        END LOOP;
    END LOOP;
END $$;
```

> ⚠️ Backfill для /16 пула отрабатывает ~150ms (одна транзакция, 65k INSERT). Для /12 (1M IP) — ~2-5s. Для production огромных пулов это лучше делать через **lazy materialization** в worker'е (chunk by 4096); но для нашего dev-стенда и /16 теста — fine bulk.

> Точная форма expression для UNIQUE-индекса зависит от текущей схемы `external_ipv4` JSONB. В service-слое `address_repo.SetIPSpec` пишет `{address: "X", address_pool_id: "Y"}` — JSON path выше предполагает этот shape. Проверить перед написанием миграции через `\d+ addresses` в kacho_vpc и при необходимости поправить path.

### 4.5 IPAM-рефактор — service code

`internal/service/address.go::AllocateExternalIP` переписывается:

```go
func (s *AddressService) AllocateExternalIP(ctx context.Context, addressID string) (*AllocateResult, error) {
    addr, err := s.repo.Get(ctx, addressID)
    if err != nil { return nil, err }
    if addr.ExternalIpv4 == nil {
        return nil, status.Errorf(codes.FailedPrecondition, "address %s has no external_ipv4 spec", addressID)
    }
    if addr.ExternalIpv4.Address != "" {
        return &AllocateResult{IP: addr.ExternalIpv4.Address, PoolID: addr.ExternalIpv4.AddressPoolID, AlreadyAllocated: true}, nil
    }

    resolved, err := s.pools.ResolvePoolForAddressObj(ctx, addr)
    if err != nil { return nil, status.Errorf(codes.FailedPrecondition, "resolve address pool: %v", err) }
    pool := resolved.Pool

    // Atomic allocate через freelist (всё в одной транзакции на repo-уровне):
    //   1. SELECT … FROM address_pool_free_ips WHERE pool_id=$1 ORDER BY ip LIMIT 1 FOR UPDATE SKIP LOCKED
    //   2. DELETE …               RETURNING ip
    //   3. UPDATE addresses SET external_ipv4 = jsonb_build_object(...)
    //         WHERE id=$2 AND (external_ipv4 ->> 'address') IS NULL OR (external_ipv4 ->> 'address') = ''
    //   4. COMMIT
    ip, err := s.repo.AllocateIPFromFreelist(ctx, pool.ID, addressID)
    if err != nil {
        if errors.Is(err, ErrPoolExhausted) {
            return nil, status.Errorf(codes.FailedPrecondition, "address pool %s exhausted", pool.ID)
        }
        return nil, err
    }
    return &AllocateResult{IP: ip, PoolID: pool.ID}, nil
}
```

`internal/repo/address_repo.go::AllocateIPFromFreelist` (новый метод):

```go
const allocateFromFreelistSQL = `
WITH picked AS (
    SELECT ip FROM address_pool_free_ips
    WHERE pool_id = $1
    ORDER BY ip
    LIMIT 1 FOR UPDATE SKIP LOCKED
), removed AS (
    DELETE FROM address_pool_free_ips f
    USING picked p
    WHERE f.pool_id = $1 AND f.ip = p.ip
    RETURNING f.ip
)
UPDATE addresses a
SET external_ipv4 = jsonb_set(
    jsonb_set(COALESCE(a.external_ipv4, '{}'::jsonb), '{address}', to_jsonb(host(r.ip))),
    '{address_pool_id}', to_jsonb($1::text)
)
FROM removed r
WHERE a.id = $2
  AND ((a.external_ipv4 ->> 'address') IS NULL OR (a.external_ipv4 ->> 'address') = '')
RETURNING host(r.ip)::text;
`

func (r *AddressRepo) AllocateIPFromFreelist(ctx context.Context, poolID, addressID string) (string, error) {
    var ip string
    err := r.pool.QueryRow(ctx, allocateFromFreelistSQL, poolID, addressID).Scan(&ip)
    if errors.Is(err, pgx.ErrNoRows) {
        return "", ErrPoolExhausted
    }
    return ip, err
}
```

> Один statement = одна короткая транзакция = меньше WAL + меньше lock holding time. `SKIP LOCKED` обеспечивает zero contention между параллельными аллокаторами.

`Address.Delete` — расширить с return-to-freelist:

```sql
INSERT INTO address_pool_free_ips (pool_id, ip)
SELECT $1, $2::inet
ON CONFLICT (pool_id, ip) DO NOTHING;
```

В service-коде: внутри той же транзакции, что DELETE'ит address. Если address не имел allocated IP — skip.

`InternalAddressPoolService.Create` — расширить с populate freelist:

```sql
-- После INSERT INTO address_pools:
INSERT INTO address_pool_free_ips (pool_id, ip)
SELECT $pool_id, host(addr)::inet
FROM generate_series(network($cidr) + 1, broadcast($cidr) - 1) addr
WHERE family($cidr::cidr) = 4
ON CONFLICT (pool_id, ip) DO NOTHING;
```

Edge case: если в коде есть **explicit reservation** (admin создаёт Address с заданным `external_ipv4.address`) — sync-precheck должен DELETE из freelist первым, потом UPDATE addresses. Существующая ветка (`req.ExternalSpec.Address != ""`) в `address.go::doCreate` должна вызвать новый repo-метод `ReserveSpecificIPFromFreelist(poolID, ip)` — он атомарно проверяет, что IP свободен в freelist, удаляет его, и тогда дальше UPDATE addresses.

### 4.6 In-cluster k6 Job

Кластер уже умеет запускать `grafana/k6:0.55.0` (pulled, есть пример Job `k6-12k`).
Свой Dockerfile **не нужен** — script инжектится через ConfigMap.

`kacho-deploy/load-tests/k6-address-allocate.yaml`:
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: k6-address-allocate
  namespace: kacho
data:
  script.js: |
    # содержимое см. ниже
---
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-address-allocate
  namespace: kacho
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: k6
        image: grafana/k6:0.55.0
        imagePullPolicy: IfNotPresent
        args: ["run", "--quiet", "/scripts/script.js"]
        env:
          - name: BASE_URL
            value: "http://api-gateway.kacho.svc.cluster.local:8080"
          - name: FOLDER_ID
            value: "b1gf63pakyt2tb1qjd6v"
          - name: TARGET_RPS
            value: "10000"
          - name: TEST_DURATION
            value: "5m"
        resources:
          requests: { cpu: "4", memory: "4Gi" }
          limits:   { cpu: "8", memory: "14Gi" }
        volumeMounts:
          - { name: scripts, mountPath: /scripts }
      volumes:
        - name: scripts
          configMap: { name: k6-address-allocate }
```

`scripts/reserved-ext-allocate.js` (k6 scenario):
```javascript
import { sleep } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';
import http from 'k6/http';

const BASE_URL = __ENV.BASE_URL || 'http://api-gateway:8080';
const FOLDER_ID = __ENV.FOLDER_ID;
const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '10000');
const TEST_DURATION = __ENV.TEST_DURATION || '5m';

export const options = {
  scenarios: {
    allocate: {
      executor: 'constant-arrival-rate',
      rate: TARGET_RPS,
      timeUnit: '1s',
      duration: TEST_DURATION,
      preAllocatedVUs: 500,
      maxVUs: 4000,
    },
  },
  thresholds: {
    http_req_failed:    ['rate<0.005'],          // < 0.5%
    http_req_duration:  ['p(99)<200'],           // p99 < 200ms
    'address_alloc_rate': ['rate>0.99'],         // ≥ 99% allocate-success
    'iterations':       [`count>=${TARGET_RPS * 250}`], // sustained ~target RPS for ~5min
  },
};

const allocLatency = new Trend('address_alloc_latency', true);
const allocRate = new Rate('address_alloc_rate');

function post(path, body) {
  return http.post(`${BASE_URL}${path}`, JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json', 'x-kacho-actor': 'loadtest@kacho' },
  });
}
function get(path)  { return http.get(`${BASE_URL}${path}`); }
function del(path)  { return http.del(`${BASE_URL}${path}`, null); }

function pollOp(opId, deadlineMs = 3000) {
  const start = Date.now();
  while (Date.now() - start < deadlineMs) {
    const r = get(`/operation/v1/operations/${opId}`);
    if (r.status === 200 && r.json('done') === true) return r;
    sleep(0.02);
  }
  return null;
}

export default function () {
  const start = Date.now();
  const r = post('/vpc/v1/addresses', {
    folderId: FOLDER_ID,
    externalIpv4AddressSpec: {},   // request reserved external IPv4 — IPAM выбирает IP
  });
  if (r.status !== 200) { allocRate.add(false); return; }

  const op = pollOp(r.json('id'));
  if (!op) { allocRate.add(false); return; }

  const addrId = op.json('response.id');
  if (!addrId) { allocRate.add(false); return; }
  allocLatency.add(Date.now() - start);
  allocRate.add(true);

  // Inline cleanup → возвращает IP в freelist, pool не исчерпает.
  const delR = del(`/vpc/v1/addresses/${addrId}`);
  if (delR.status === 200) { pollOp(delR.json('id')); }
}
```

`kacho-deploy/Makefile`:
```makefile
loadtest-address-allocate:
	kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	kubectl -n kacho apply -f load-tests/k6-address-allocate.yaml
	kubectl -n kacho wait --for=condition=complete job/k6-address-allocate --timeout=600s || true
	kubectl -n kacho logs -l job-name=k6-address-allocate --tail=-1

loadtest-address-allocate-clean:
	kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	kubectl -n kacho delete cm k6-address-allocate --ignore-not-found
```

### 4.7 Метрики / observability

Кластер уже имеет VictoriaMetrics (`in-cloud-monitoring` ns) и metrics-server. Для interpretation нужно:

1. **kacho-vpc должен экспортировать Prometheus метрики**:
   - `kacho_vpc_address_allocate_total{result=success|conflict|exhausted}` Counter
   - `kacho_vpc_address_allocate_latency_seconds` Histogram
   - `kacho_vpc_address_pool_free_count{pool_id}` Gauge — для алертов на ёмкость freelist
   - Если ещё не настроено через `kacho-corelib/observability` — добавить (но не блокировать дизайн на этом).
2. **PG метрики** через postgres-exporter (sidecar в bitnami chart? проверить). Если не настроено — `pg_stat_activity` ручной снимок в тестовый отчёт.
3. **HPA-decisions**: `kubectl describe hpa <svc>` после прогона для verification что autoscale сработал.

## 5. Порядок выполнения

1. **Charts** (kacho-vpc/deploy, kacho-api-gateway/deploy, …): `templates/hpa.yaml` + `resources` блок в deployment + `values.yaml` autoscaling. Helm package + commit.
2. **values.dev.yaml** umbrella: PG-tune (`extendedConfiguration` + resources на pg-vpc).
3. **kacho-vpc app env**: добавить env vars в `deployment.yaml`.
4. **Migration 0014_address_pool_freelist.sql**: написать + написать integration test (testcontainers) проверяющий что freelist populate'ится при создании pool, и что concurrent allocate возвращает уникальные IP без конфликтов.
5. **Service rewrite**: `AddressService.AllocateExternalIP` + `AddressRepo.AllocateIPFromFreelist` + `AddressService.Delete` return-to-freelist + `InternalAddressPoolService.Create` populate. Unit + integration tests.
6. **Bench**: расширить `address_allocate_bench_test.go`, измерить before/after на testcontainers Postgres.
7. **Build kacho-vpc image** + load в кластер (через registry или kubectl).
8. **Helm upgrade** umbrella → apply все изменения.
9. **k6 Job build & deploy**: `make loadtest-cluster-build` + `make loadtest-cluster-run`.
10. **Baseline measurement**: 1 replica vpc / 1 api-gateway, HPA включён → запуск → собрать данные (RPS, p99, HPA scaling timeline).
11. Если 10k не достигнуто → итерация tune (PG `max_connections`, `shared_buffers`, `KACHO_VPC_DB_MAX_CONNS`, HPA maxReplicas) → re-run.
12. **Update `BASELINE.md`** в `kacho-vpc/tests/k6/results/` с новой эволюцией и достигнутыми числами.

## 6. Success criteria

**Hard requirements (MUST):**
- ✅ Sustained ≥ **10 000 successful `Address.Create` per second** в течение **5 min**.
- ✅ p99 `Address.Create` latency (включая Operation poll) < **200ms**.
- ✅ Error rate < **0.5%**.
- ✅ HPA автоматически масштабирует vpc и api-gateway во время теста; `kubectl describe hpa` показывает корректные scaling-decisions.
- ✅ После теста все ресурсы (адреса) удалены; freelist возвращена в исходное состояние; нет dangling Operations.
- ✅ По умолчанию (вне нагрузки) replicas=1 для каждого компонента (после ScaleDown stabilization).

**Soft (nice-to-have):**
- Linear scaling ratio: 1 pod → X RPS, 5 pod → ~5X. (Если нет — указать почему: lock contention, network, PG-side.)
- Updated `BASELINE.md` с эволюцией шагов и вкладом каждого изменения.

## 7. Риски и митигации

| Риск | Митигация |
|---|---|
| PG single-writer становится bottleneck до 10k | tune `synchronous_commit=local` + `max_connections=300` + `shared_buffers=512MB`. Если мало — `=off`. Если всё ещё мало — добавим в backlog pgBouncer + tx-pooling. |
| Operation polling overhead забивает k6 RPS budget | `pollOp` использует `sleep(0.02)` — выводит polling в N=50 polls/sec на VU. При 10k RPS / 4k maxVUs = 2.5 alloc/sec/VU — polling ≪ allocate. Sanity-check на первом прогоне. |
| api-gateway HTTP/2 stream limit (250 concurrent) | gRPC streams reset между requests; настроить `grpc.MaxConcurrentStreams` если нужно. Не в hot-path сейчас. |
| Migration backfill блокирует таблицу при rollout | `address_pools` таблица маленькая (5-10 rows в dev). Backfill ≈ 150ms на /16 → не блокирует prod-данные. |
| UNIQUE conflicts в `addresses_pool_ip_unique` под burst | Не возникнут при freelist-flow (freelist гарантирует unique pop). Возникают только при manual reservation race — sync-pre-check ловит. |
| Freelist исчерпание во время теста (если cleanup отстаёт) | Inline cleanup в k6: каждый iter возвращает IP. Free pool ≈ steady-state. Использовать /16 → 65k IP подушка. |
| Kubernetes Job ressource starvation на 4 CPU | k6 Job limits=4000m/2Gi — достаточно для 4k VUs. При необходимости увеличить. |

## 8. Closed questions (resolved during pre-flight)

- **Bitnami PG config keys**: `primary.extendedConfiguration` (string-конфиг appended) + `primary.resources` — стандартные Bitnami chart 13.x пути. ✅
- **k6 image / registry**: `grafana/k6:0.55.0` уже доступен в кластере (`docker.io/grafana/k6` pulled). Свой Dockerfile не нужен. Скрипт инжектится через ConfigMap. ✅
- **kacho-vpc image registry**: эфемерный `ttl.sh/kacho-<datestamp>:24h`. При rebuild — push нового tag и обновление `image:` в values. ✅
- **`addresses_external_pool_ip_uniq`**: уже на месте (`0001_initial.sql:511`). Дополнительный safety-net не требуется. ✅
- **kacho-corelib observability**: вопрос отложен — для текущей цели достаточно VictoriaMetrics-side metrics + `kubectl top pod`. Если IPAM-detail метрики (success/conflict counters) нужны — добавим инкрементально, не блокируя достижение 10k.

## 9. Out-of-scope backlog (отдельные специ)

1. **IPv6 sparse allocator** (важная фаза 2):
   - `ipv6_pool_cursors(pool_id, next_offset NUMERIC(39,0))`
   - `ipv6_allocated_ips(pool_id, ip INET, offset NUMERIC(39,0), PRIMARY KEY(pool_id, ip))`
   - `ipv6_released_offsets(pool_id, offset)` — small reuse pool
   - Allocate: try `released_offsets` SKIP LOCKED → fallback `UPDATE ipv6_pool_cursors SET next_offset = next_offset + 1 RETURNING …` → compute `ip = pool_base + offset` → INSERT allocated.
   - Range leasing батчами по 4096 offset для разгрузки hot-row cursor.
2. **Lazy freelist populate** для больших IPv4 pool (/12+): worker пополняет chunk'ами по 4096, когда `count(free) < threshold`.
3. **pgBouncer** перед kacho-vpc если pgxpool окажется недостаточным.
4. **KEDA**-based scaling по `kacho_vpc_address_allocate_total` rate (replace CPU-based HPA для более точного reactive scaling).
5. **Comprehensive load suite**: соседние сервисы (Compute.Create, NetworkInterface.Create) после того, как Address-RPS закрыт.

## 10. Контракты с существующим кодом

- `address.go::doCreate` — calls `AllocateExternalIP` после `repo.Insert(address)`. Этот контракт сохраняется.
- `AllocateResult{IP, PoolID, AlreadyAllocated}` — сохраняется.
- `ErrPoolExhausted` — новый sentinel в `errors.go`; `mapRepoErr` маппит на `FailedPrecondition`.
- `InternalAddressService.AllocateExternalIP` (admin RPC) — сохраняется, использует новый path.
- Существующие тесты в `address_test.go`, `address_allocate_bench_test.go`, `ipam_cascade_integration_test.go` — все должны пройти (cascade resolve логика не меняется).
- Не трогаем internal IPv4 allocation (`AllocateInternalIP`) — она по subnet CIDR, отдельный path, его рефактор — в backlog.

## 11. Verification checklist

После реализации:
- `make test` в kacho-vpc — все тесты зелёные, включая новый integration test на concurrent allocate.
- `make loadtest-cluster-run` — sustained 10k+ RPS за 5 min, thresholds зелёные.
- `kubectl describe hpa -n kacho` — показывает scale events.
- `kubectl -n kacho get pods -l app=vpc` после теста — количество подов вернулось к 1 (через ScaleDown 5min window).
- `kacho-vpc/tests/k6/results/BASELINE.md` обновлён с новой строчкой эволюции.
- Migration `0014_*` присутствует в `internal/migrations/`, проходит `goose up` + `goose down`.

---

**Готов перейти к writing-plans (детальный пошаговый план реализации) после approval этого spec'а.**
