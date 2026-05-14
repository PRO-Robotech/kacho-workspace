# In-cluster Load Test + HPA + IPAM Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sustained 10 000 successful `Address.Create` (reserved external IPv4) per second через api-gateway в развёрнутом Kachō-кластере (`KUBECONFIG=/tmp/e2c825-merged.kubeconfig`, ns `kacho`); каждый компонент по умолчанию `replicas=1`, автоскейл через HPA.

**Architecture:** PG-native materialized freelist `address_pool_free_ips` + atomic `FOR UPDATE SKIP LOCKED ORDER BY ip LIMIT 1` allocator (zero pool-row contention) + HPA на 5 сервисах (CPU 70%, 1..10) + Postgres tune (`synchronous_commit=local`, max_connections=300, shared_buffers=512MB) + in-cluster k6 Job через ConfigMap-script.

**Tech Stack:** Go 1.22 + pgx/pgxpool, Postgres 16 (Bitnami chart), goose migrations, Helm 3, Kubernetes HPA v2, k6 0.55.

**Reference docs:**
- Spec: `docs/superpowers/specs/2026-05-14-in-cluster-loadtest-hpa-10k-ipam-design.md`
- Existing baseline: `project/kacho-vpc/tests/k6/results/BASELINE.md`
- Workspace policy: `CLAUDE.md` (KAC ticketing, Conventional Commits, branch naming `KAC-<N>`)

---

## Phase 0: Ticketing & branches (workspace policy)

Workspace `CLAUDE.md` требует: feature ≥ 3 репо → epic в YouTrack `KAC` + subtasks + добавление в текущий спринт; ветка `KAC-<N>` в каждом затронутом репо. Затронутые репо (8): `kacho-workspace`, `kacho-vpc`, `kacho-api-gateway`, `kacho-resource-manager`, `kacho-compute`, `kacho-ui`, `kacho-deploy`, и опционально `kacho-corelib` (только если потребуются shared helpers — пока нет).

### Task 0.1: Создать YouTrack-эпик KAC-<E>

**Files:** none (внешний tracker).

- [ ] **Step 1:** Через MCP `mcp__youtrack__create_issue` создать issue в проекте `KAC`:
  - summary: `[EPIC] In-cluster load test + HPA + IPAM refactor → 10k Address.Create/sec`
  - description: ссылка на spec `docs/superpowers/specs/2026-05-14-in-cluster-loadtest-hpa-10k-ipam-design.md`; декомпозиция (см. ниже); cross-repo порядок выполнения; DoD (sustained 10k, p99<200ms, error<0.5%, HPA scaled, BASELINE.md updated).

- [ ] **Step 2:** Добавить эпик в текущий спринт (`POST /api/commands` с `Board kacho <sprint-name>`).

- [ ] **Step 3:** Создать 7 subtasks (KAC-<E+1> .. KAC-<E+7>); каждый описан, привязан к эпику через link `subtask of`, проставлен `агент` (роль из workspace), добавлен в текущий спринт:
  - `KAC-<E+1>` — `[chart] HPA + resources в kacho-vpc` (агент: `service-scaffolder`)
  - `KAC-<E+2>` — `[chart] HPA + resources в 4 сервисах (api-gateway / resource-manager / compute / ui)` (агент: `service-scaffolder`)
  - `KAC-<E+3>` — `[deploy] PG tune в umbrella values.dev.yaml + load-test job manifest` (агент: `service-scaffolder`)
  - `KAC-<E+4>` — `[vpc] migration 0014 + AddressPoolFreelist repo + integration tests` (агенты: `migration-writer`, `db-architect-reviewer`)
  - `KAC-<E+5>` — `[vpc] AllocateExternalIP rewrite + Delete return-to-freelist + InternalAddressPoolService.Create populate + unit tests + bench` (агенты: `rpc-implementer`, `go-style-reviewer`)
  - `KAC-<E+6>` — `[vpc] env vars (KACHO_VPC_DB_MAX_CONNS, KACHO_VPC_DEFAULT_SG_INLINE, FOLDER_CACHE_TTL) в deploy chart` (агент: `service-scaffolder`)
  - `KAC-<E+7>` — `[workspace] спрятать spec/plan/baseline updates под одним PR` (агент: `claude`)

- [ ] **Step 4:** Записать `KAC-<E>` (id эпика) и id-ы subtasks (`KAC-<E+1>...<E+7>`) в локальный scratch — будут использоваться как branch names в каждом репо.

### Task 0.2: Создать ветки во всех затронутых репо

**Files:** none (git operations).

- [ ] **Step 1:** В `kacho-workspace`: `git checkout main && git pull && git checkout -b KAC-<E+7>`
- [ ] **Step 2:** В каждом из `project/kacho-{vpc,api-gateway,resource-manager,compute,ui,deploy}`: `git checkout main && git pull && git checkout -b KAC-<E+X>` где `<E+X>` — id соответствующего subtask.
- [ ] **Step 3:** `git status` в каждом из них — clean working tree, на ветке `KAC-<...>`.

---

## Phase 1: HPA + resources в helm-чартах (5 репо)

Чартам нужно: `resources.requests/limits` в `templates/deployment.yaml` (HPA не работает без requests на CPU) + новый `templates/hpa.yaml` + `autoscaling.*` секция в `values.yaml`.

### Task 1.1: kacho-vpc — добавить resources + HPA

**Files:**
- Modify: `project/kacho-vpc/deploy/values.yaml`
- Modify: `project/kacho-vpc/deploy/templates/deployment.yaml`
- Create: `project/kacho-vpc/deploy/templates/hpa.yaml`
- Create: `project/kacho-vpc/deploy/templates/_helpers.tpl` (если ещё нет — для DRY)

- [ ] **Step 1: Дописать `values.yaml`** (полный финальный contents — заменяет существующий):

```yaml
name: vpc
replicas: 1
image: kacho-vpc:dev
imagePullPolicy: IfNotPresent
ports:
  grpc: 9090
  internalGrpc: 9091
db:
  host: kacho-umbrella-pg-vpc
  port: "5432"
  user: vpc
  name: kacho_vpc
  passwordSecretName: kacho-umbrella-pg-vpc
  passwordSecretKey: password
resourceManagerAddr: "resource-manager.kacho.svc.cluster.local:9090"

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 2000m
    memory: 1Gi

env:
  KACHO_VPC_DB_MAX_CONNS: "200"
  KACHO_VPC_DEFAULT_SG_INLINE: "false"
  KACHO_VPC_FOLDER_CACHE_TTL: "30s"

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

- [ ] **Step 2: Добавить `resources` блок в deployment.yaml.** Найти `containers: - name: {{ .Values.name }}` блок (он один — основной контейнер, не initContainer) и после `livenessProbe:` добавить:

```yaml
          resources:
            requests:
              cpu: {{ .Values.resources.requests.cpu }}
              memory: {{ .Values.resources.requests.memory }}
            limits:
              cpu: {{ .Values.resources.limits.cpu }}
              memory: {{ .Values.resources.limits.memory }}
          {{- if .Values.env }}
          {{- range $k, $v := .Values.env }}
            - name: {{ $k }}
              value: {{ $v | quote }}
          {{- end }}
          {{- end }}
```

> ⚠️ Внимание: env-блок добавляется в **существующий** `env:` массив (после KACHO_VPC_RESOURCE_MANAGER_GRPC_ADDR), а `resources:` — на уровне `name: {{ .Values.name }}` рядом с `image:`/`ports:`. Прочитать current deployment.yaml перед правкой и точно вставить в правильные места.

- [ ] **Step 3: Создать `templates/hpa.yaml`**:

```yaml
{{- if .Values.autoscaling.enabled }}
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
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
{{- end }}
```

- [ ] **Step 4: Helm lint**:

Run: `cd project/kacho-vpc/deploy && helm lint .`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Helm template render** — проверить что HPA генерируется и resources в Deployment попали:

Run:
```bash
cd project/kacho-vpc/deploy && helm template test . | grep -A 6 "kind: HorizontalPodAutoscaler"
cd project/kacho-vpc/deploy && helm template test . | grep -A 8 "resources:"
```

Expected:
- HPA с `minReplicas: 1`, `maxReplicas: 10`, `averageUtilization: 70`.
- `resources.requests.cpu: 200m` под Deployment'ом.

- [ ] **Step 6: Commit**:

```bash
cd project/kacho-vpc && git add deploy/ && git commit -m "$(cat <<'EOF'
feat(deploy): HPA + resources + load-test env vars

Adds HPA (CPU 70%, 1..10 replicas) and resource requests/limits to vpc
chart. Adds load-test-friendly env vars (DB_MAX_CONNS=200, SG_INLINE=false,
FOLDER_CACHE_TTL=30s) so 1-replica default scales smoothly under
in-cluster k6 nагрузку.

KAC-<E+1>
EOF
)"
```

### Task 1.2: kacho-api-gateway — добавить resources + HPA

**Files:**
- Modify: `project/kacho-api-gateway/deploy/values.yaml`
- Modify: `project/kacho-api-gateway/deploy/templates/deployment.yaml`
- Create: `project/kacho-api-gateway/deploy/templates/hpa.yaml`

- [ ] **Step 1: Read `project/kacho-api-gateway/deploy/values.yaml`** и `deployment.yaml`, чтобы понять текущую структуру (есть ли уже `env:`).

- [ ] **Step 2: Append к `values.yaml`** (после существующего блока):

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

- [ ] **Step 3: Добавить `resources:` блок в `templates/deployment.yaml`** (внутри основного контейнера; формат идентичен Task 1.1.Step 2 без env-блока).

- [ ] **Step 4: Создать `templates/hpa.yaml`** (тот же шаблон, что 1.1.Step 3 — `{{ .Values.name }}` подставится из api-gateway values).

- [ ] **Step 5: Helm lint + template** — как 1.1.Step 4-5.

- [ ] **Step 6: Commit:**

```bash
cd project/kacho-api-gateway && git add deploy/ && git commit -m "$(cat <<'EOF'
feat(deploy): HPA + resources

Adds HPA (CPU 70%, 1..10 replicas) and resource requests/limits.
api-gateway is the request-side bottleneck for 10k load test
(baseline: ~3500 RPS/pod), so default 1 replica scales up linearly
under load.

KAC-<E+2>
EOF
)"
```

### Task 1.3: kacho-resource-manager — добавить resources + HPA

**Files:**
- Modify: `project/kacho-resource-manager/deploy/values.yaml`
- Modify: `project/kacho-resource-manager/deploy/templates/deployment.yaml`
- Create: `project/kacho-resource-manager/deploy/templates/hpa.yaml`

- [ ] **Step 1: Read** existing files.

- [ ] **Step 2: Append values:**

```yaml
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

(maxReplicas=5: rm сидит за TTL-cache в vpc → реальная нагрузка ≪ vpc.)

- [ ] **Step 3-5:** Аналогично 1.2.

- [ ] **Step 6: Commit:**

```bash
cd project/kacho-resource-manager && git add deploy/ && git commit -m "$(cat <<'EOF'
feat(deploy): HPA + resources

KAC-<E+2>
EOF
)"
```

### Task 1.4: kacho-compute — добавить resources + HPA

Аналогично Task 1.3, отдельный commit. compute не критичен под Address-load test (не на write-path), но единая политика по всем сервисам.

- [ ] **Step 1: Read** files; values следующие (compute обычно тяжелее RM):

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

- [ ] **Step 2-5:** Аналогично 1.2.

- [ ] **Step 6: Commit:**

```bash
cd project/kacho-compute && git add deploy/ && git commit -m "$(cat <<'EOF'
feat(deploy): HPA + resources

KAC-<E+2>
EOF
)"
```

### Task 1.5: kacho-ui — добавить resources + HPA

Аналогично, конфигурация лёгкая:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70
```

- [ ] **Step 1-5:** Аналогично 1.2.

- [ ] **Step 6: Commit** с message `feat(deploy): HPA + resources` и `KAC-<E+2>`.

---

## Phase 2: PG-tune + load-test Job в kacho-deploy

### Task 2.1: PG tune в umbrella values.dev.yaml

**Files:**
- Modify: `project/kacho-deploy/helm/umbrella/values.dev.yaml`

- [ ] **Step 1: Прочитать текущий values.dev.yaml** (в этом spec'е уже видели целиком — `pg-vpc`, `pg-compute`, `pg-resource-manager`).

- [ ] **Step 2: Расширить блок pg-vpc** (заменить существующие строки на новые):

```yaml
pg-vpc:
  auth:
    username: vpc
    password: dev-vpc-password
    database: kacho_vpc
  primary:
    persistence:
      enabled: false
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 4000m
        memory: 4Gi
    extendedConfiguration: |
      synchronous_commit = local
      max_connections = 300
      shared_buffers = 512MB
      work_mem = 16MB
      effective_cache_size = 2GB
      checkpoint_timeout = 15min
      max_wal_size = 2GB
  image:
    repository: bitnamilegacy/postgresql
  volumePermissions:
    image:
      repository: bitnamilegacy/os-shell
```

- [ ] **Step 3: Симметрично для `pg-compute` и `pg-resource-manager`** (compute / rm используют меньше connections, но та же конфигурация для единообразия — `max_connections=300`, `shared_buffers=256MB`, resources requests=200m/512Mi limits=2000m/2Gi).

- [ ] **Step 4: Helm template render** для проверки структуры:

Run: `cd project/kacho-deploy/helm/umbrella && helm dependency build && helm template test . -f values.dev.yaml | grep -B 2 -A 10 "extendedConfiguration\|resources:" | head -60`

Expected: видим конфигурацию в ConfigMap'е bitnami chart'а и resources в StatefulSet'е PG.

### Task 2.2: Load-test Job manifest (ConfigMap + Job + Makefile)

**Files:**
- Create: `project/kacho-deploy/load-tests/k6-address-allocate.yaml`
- Modify: `project/kacho-deploy/Makefile`

- [ ] **Step 1: Создать директорию + manifest:**

`project/kacho-deploy/load-tests/k6-address-allocate.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: k6-address-allocate
  namespace: kacho
data:
  script.js: |
    import http from 'k6/http';
    import { sleep } from 'k6';
    import { Trend, Counter, Rate } from 'k6/metrics';

    const BASE_URL = __ENV.BASE_URL || 'http://api-gateway.kacho.svc.cluster.local:8080';
    const FOLDER_ID = __ENV.FOLDER_ID;
    const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '10000', 10);
    const TEST_DURATION = __ENV.TEST_DURATION || '5m';

    const HEADERS = {
      'Content-Type': 'application/json',
      'x-kacho-actor': 'lt-allocate@kacho',
      'x-kacho-folder-id': FOLDER_ID,
    };

    export const options = {
      scenarios: {
        allocate: {
          executor: 'constant-arrival-rate',
          rate: TARGET_RPS,
          timeUnit: '1s',
          duration: TEST_DURATION,
          preAllocatedVUs: 2000,
          maxVUs: 16000,
        },
      },
      thresholds: {
        http_req_failed:    ['rate<0.005'],
        'address_alloc_ok': ['rate>0.99'],
        'address_alloc_latency': ['p(99)<200'],
      },
      summaryTrendStats: ['min','avg','med','p(90)','p(95)','p(99)','max'],
    };

    const allocLatency = new Trend('address_alloc_latency', true);
    const allocOk = new Rate('address_alloc_ok');
    const allocCount = new Counter('addresses_allocated');

    function uid(p='lt') {
      return `${p}-${Date.now().toString(36)}${Math.floor(Math.random()*1e6).toString(36)}`;
    }

    function pollOp(opId, deadlineMs = 3000) {
      const start = Date.now();
      while (Date.now() - start < deadlineMs) {
        const r = http.get(`${BASE_URL}/operation/v1/operations/${opId}`);
        if (r.status === 200 && r.json('done') === true) return r;
        sleep(0.02);
      }
      return null;
    }

    export default function () {
      const start = Date.now();
      const r = http.post(
        `${BASE_URL}/vpc/v1/addresses`,
        JSON.stringify({ folderId: FOLDER_ID, name: uid('addr'), externalIpv4AddressSpec: {} }),
        { headers: HEADERS }
      );
      if (r.status !== 200) { allocOk.add(false); return; }

      const op = pollOp(r.json('id'));
      if (!op) { allocOk.add(false); return; }

      const addrId = op.json('response.id') || op.json('metadata.addressId');
      if (!addrId) { allocOk.add(false); return; }

      allocLatency.add(Date.now() - start);
      allocOk.add(true);
      allocCount.add(1);

      // Inline cleanup — return IP to freelist; pool stays steady-state.
      const delR = http.del(`${BASE_URL}/vpc/v1/addresses/${addrId}`, null, { headers: HEADERS });
      if (delR.status === 200) { pollOp(delR.json('id')); }
    }
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

- [ ] **Step 2: Дописать Makefile** в `kacho-deploy/Makefile`:

```makefile

# ─── Load testing ────────────────────────────────────────────────

loadtest-address-allocate:
	@kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	@kubectl -n kacho apply -f load-tests/k6-address-allocate.yaml
	@echo "→ Job created, waiting for completion (max 600s)…"
	@kubectl -n kacho wait --for=condition=complete job/k6-address-allocate --timeout=600s || \
	  kubectl -n kacho wait --for=condition=failed job/k6-address-allocate --timeout=10s
	@kubectl -n kacho logs -l job-name=k6-address-allocate --tail=-1

loadtest-address-allocate-clean:
	@kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	@kubectl -n kacho delete cm k6-address-allocate --ignore-not-found
```

- [ ] **Step 3: Validate Makefile** — `make -n loadtest-address-allocate` должен показать команды без ошибок.

- [ ] **Step 4: Commit (объединённый с PG-tune):**

```bash
cd project/kacho-deploy && git add helm/umbrella/values.dev.yaml load-tests/ Makefile && git commit -m "$(cat <<'EOF'
feat(deploy): PG tune + in-cluster k6 load-test job

- pg-{vpc,compute,resource-manager}: synchronous_commit=local,
  max_connections=300, shared_buffers=512MB, explicit resources
  requests/limits.
- load-tests/k6-address-allocate.yaml: ConfigMap (k6 script) + Job
  (grafana/k6:0.55.0, image already pulled in cluster).
  Profile: constant-arrival-rate 10k/sec for 5m, inline cleanup
  (Create → poll → Delete → poll). Thresholds: error<0.5%,
  address_alloc_ok>99%, p99 latency<200ms.
- Makefile targets: loadtest-address-allocate / -clean.

KAC-<E+3>
EOF
)"
```

---

## Phase 3: IPAM рефактор в kacho-vpc — миграция

### Task 3.1: Migration 0014_address_pool_freelist.sql

**Files:**
- Create: `project/kacho-vpc/internal/migrations/0014_address_pool_freelist.sql`

- [ ] **Step 1: Создать SQL-миграцию:**

```sql
-- +goose Up
-- +goose StatementBegin

-- Materialized freelist of available IPv4 addresses per pool.
-- Replaces random-pick + UNIQUE-retry allocator with atomic SKIP LOCKED pop:
--    WITH p AS (SELECT ip FROM address_pool_free_ips
--               WHERE pool_id=$1 ORDER BY ip LIMIT 1 FOR UPDATE SKIP LOCKED)
--    DELETE … RETURNING ip
-- Zero contention between concurrent allocators.
--
-- Safety net `addresses_external_pool_ip_uniq` already in 0001_initial.sql:511
-- guarantees uniqueness of (pool_id, ip) at the addresses level.

CREATE TABLE address_pool_free_ips (
    pool_id  TEXT NOT NULL REFERENCES address_pools(id) ON DELETE CASCADE,
    ip       INET NOT NULL,
    PRIMARY KEY (pool_id, ip)
);

CREATE INDEX address_pool_free_ips_pool_idx
    ON address_pool_free_ips (pool_id);

-- Backfill: for each existing pool, populate freelist from its IPv4 CIDR
-- blocks, excluding network/broadcast and any already-allocated IPs.
DO $$
DECLARE
    pool_row RECORD;
    cidr_str TEXT;
BEGIN
    FOR pool_row IN SELECT id, cidr_blocks FROM address_pools LOOP
        FOREACH cidr_str IN ARRAY pool_row.cidr_blocks LOOP
            IF family(cidr_str::cidr) = 4 THEN
                INSERT INTO address_pool_free_ips (pool_id, ip)
                SELECT pool_row.id, host(addr)::inet
                FROM generate_series(
                    network(cidr_str::cidr) + 1,
                    broadcast(cidr_str::cidr) - 1
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

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS address_pool_free_ips;
-- +goose StatementEnd
```

- [ ] **Step 2: Validate goose syntax** — открыть в редакторе, проверить что `+goose Up`/`Down`/`StatementBegin`/`StatementEnd` маркеры на отдельных строках без trailing-spaces.

- [ ] **Step 3: Commit миграции отдельно** (чтобы было легко ревьювить — `db-architect-reviewer`):

```bash
cd project/kacho-vpc && git add internal/migrations/0014_address_pool_freelist.sql && git commit -m "$(cat <<'EOF'
feat(vpc): migration 0014 — address_pool_free_ips materialized freelist

Adds materialized freelist table that backs the new IPAM allocator
(PG-native FOR UPDATE SKIP LOCKED). Backfills from existing
address_pools.cidr_blocks (IPv4 only; IPv6 sparse allocator deferred
to a separate phase).

Safety-net unique index addresses_external_pool_ip_uniq already in
0001_initial.sql:511 — no duplicate index needed here.

KAC-<E+4>
EOF
)"
```

### Task 3.2: Integration test для миграции и concurrent allocate

**Files:**
- Create: `project/kacho-vpc/internal/repo/address_pool_freelist_integration_test.go`

- [ ] **Step 1: Read** существующие integration test файлы (напр. `ipam_cascade_integration_test.go`) — чтобы понять scaffold testcontainers + sequenced migrations.

- [ ] **Step 2: Написать failing test:**

```go
package repo_test

import (
    "context"
    "fmt"
    "sync"
    "testing"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/stretchr/testify/require"

    "github.com/PRO-Robotech/kacho-vpc/internal/domain"
    "github.com/PRO-Robotech/kacho-vpc/internal/repo"
)

// TestFreelist_BackfillPopulatesIPs verifies migration 0014 backfills
// freelist from existing pool CIDRs.
func TestFreelist_BackfillPopulatesIPs(t *testing.T) {
    ctx, pool := setupTestDB(t)  // existing helper from this package
    defer pool.Close()

    // Insert pool with /28 CIDR (16 addrs, 14 usable)
    poolID := insertTestPool(t, pool, "198.51.100.0/28")

    var count int
    err := pool.QueryRow(ctx,
        `SELECT COUNT(*) FROM address_pool_free_ips WHERE pool_id = $1`,
        poolID,
    ).Scan(&count)
    require.NoError(t, err)
    require.Equal(t, 14, count, "expected 14 usable IPs for /28 (excl. network + broadcast)")
}

// TestFreelist_ConcurrentAllocateUnique verifies SKIP LOCKED gives
// each goroutine a distinct IP.
func TestFreelist_ConcurrentAllocateUnique(t *testing.T) {
    ctx, pool := setupTestDB(t)
    defer pool.Close()

    poolID := insertTestPool(t, pool, "198.51.100.0/28")  // 14 IPs
    repo := repo.NewAddressRepo(pool)

    const N = 14
    addrIDs := make([]string, N)
    for i := range addrIDs {
        addrIDs[i] = insertTestAddress(t, pool)  // creates Address with empty external_ipv4
    }

    var (
        mu     sync.Mutex
        allIPs = make(map[string]bool, N)
        wg     sync.WaitGroup
    )

    for i := 0; i < N; i++ {
        wg.Add(1)
        go func(addrID string) {
            defer wg.Done()
            ip, err := repo.AllocateIPFromFreelist(ctx, poolID, addrID)
            require.NoError(t, err)
            mu.Lock()
            require.False(t, allIPs[ip], "duplicate IP allocated: %s", ip)
            allIPs[ip] = true
            mu.Unlock()
        }(addrIDs[i])
    }
    wg.Wait()
    require.Equal(t, N, len(allIPs), "expected %d unique IPs", N)

    // Pool exhausted → next allocation returns ErrPoolExhausted
    addr15 := insertTestAddress(t, pool)
    _, err := repo.AllocateIPFromFreelist(ctx, poolID, addr15)
    require.ErrorIs(t, err, repo.ErrPoolExhausted)
}

// TestFreelist_DeleteReturnsIP verifies that deleting an Address with
// an allocated IP returns it to the freelist (idempotent on retry).
func TestFreelist_DeleteReturnsIP(t *testing.T) {
    ctx, pool := setupTestDB(t)
    defer pool.Close()

    poolID := insertTestPool(t, pool, "198.51.100.0/28")
    repo := repo.NewAddressRepo(pool)

    addrID := insertTestAddress(t, pool)
    ip, err := repo.AllocateIPFromFreelist(ctx, poolID, addrID)
    require.NoError(t, err)

    var freelistCount int
    pool.QueryRow(ctx, `SELECT COUNT(*) FROM address_pool_free_ips WHERE pool_id=$1`, poolID).Scan(&freelistCount)
    require.Equal(t, 13, freelistCount)

    err = repo.ReturnIPToFreelist(ctx, poolID, ip)
    require.NoError(t, err)
    pool.QueryRow(ctx, `SELECT COUNT(*) FROM address_pool_free_ips WHERE pool_id=$1`, poolID).Scan(&freelistCount)
    require.Equal(t, 14, freelistCount)

    // Idempotent: returning same IP again is a no-op
    err = repo.ReturnIPToFreelist(ctx, poolID, ip)
    require.NoError(t, err)
    pool.QueryRow(ctx, `SELECT COUNT(*) FROM address_pool_free_ips WHERE pool_id=$1`, poolID).Scan(&freelistCount)
    require.Equal(t, 14, freelistCount)
}

// helpers (declare locally — using package-internal db setup)

func insertTestPool(t *testing.T, pool *pgxpool.Pool, cidr string) string {
    t.Helper()
    id := fmt.Sprintf("apl%012d", t.Name()[len(t.Name())-1])  // simple unique-per-test id
    _, err := pool.Exec(context.Background(), `
        INSERT INTO address_pools (id, name, cidr_blocks, kind)
        VALUES ($1, $2, ARRAY[$3], 'EXTERNAL_PUBLIC')`,
        id, t.Name(), cidr,
    )
    require.NoError(t, err)
    // Trigger the same backfill the migration does
    _, err = pool.Exec(context.Background(), `
        INSERT INTO address_pool_free_ips (pool_id, ip)
        SELECT $1, host(addr)::inet
        FROM generate_series(network($2::cidr) + 1, broadcast($2::cidr) - 1) AS addr
        ON CONFLICT (pool_id, ip) DO NOTHING`,
        id, cidr,
    )
    require.NoError(t, err)
    return id
}

func insertTestAddress(t *testing.T, pool *pgxpool.Pool) string {
    t.Helper()
    id := fmt.Sprintf("e9b%013x", t.Name()[len(t.Name())-1])
    _, err := pool.Exec(context.Background(), `
        INSERT INTO addresses (id, folder_id, addr_type, ip_version, reserved, used)
        VALUES ($1, 'b1gtest', 'external', 'IPV4', true, false)`,
        id,
    )
    require.NoError(t, err)
    return id
}
```

> ⚠️ Тест ссылается на `repo.AllocateIPFromFreelist`, `repo.ReturnIPToFreelist`, `repo.ErrPoolExhausted` — они ещё **не существуют**. Тест должен fail на стадии compile.

- [ ] **Step 3: Run test to verify it fails:**

Run: `cd project/kacho-vpc && go test ./internal/repo/... -run TestFreelist -v`
Expected: build error `undefined: AllocateIPFromFreelist` / `undefined: ReturnIPToFreelist` / `undefined: ErrPoolExhausted`. ✅ TDD red.

> Если build error не показывает test'ов как fail — это норма (tests can't even compile). Двигаемся дальше.

### Task 3.3: Repo — AllocateIPFromFreelist + ReturnIPToFreelist + sentinel error

**Files:**
- Modify: `project/kacho-vpc/internal/repo/address_repo.go`
- Modify: `project/kacho-vpc/internal/repo/errors.go` (если есть; иначе в address_repo.go)

- [ ] **Step 1: Read** `address_repo.go` чтобы понять package-level constants и existing patterns; `errors.go` чтобы выяснить, есть ли там `ErrNotFound` etc., чтобы добавить `ErrPoolExhausted` рядом.

- [ ] **Step 2: Добавить sentinel error**:

В файле где определены `ErrNotFound` и т.п.:

```go
// ErrPoolExhausted — address_pool_free_ips empty for the given pool;
// caller should map to gRPC FailedPrecondition.
var ErrPoolExhausted = errors.New("address pool exhausted")
```

- [ ] **Step 3: Добавить новые методы в `address_repo.go`** (в конец файла):

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
RETURNING host(r.ip)::text;
`

// AllocateIPFromFreelist atomically:
//   1) pops one free IP from address_pool_free_ips for pool_id (SKIP LOCKED → zero contention),
//   2) writes it to addresses.external_ipv4{address, address_pool_id} for address_id,
//   3) returns the allocated IP string.
// Returns ErrPoolExhausted if no free IPs.
func (r *AddressRepo) AllocateIPFromFreelist(ctx context.Context, poolID, addressID string) (string, error) {
    var ip string
    err := r.pool.QueryRow(ctx, allocateFromFreelistSQL, poolID, addressID).Scan(&ip)
    if errors.Is(err, pgx.ErrNoRows) {
        return "", ErrPoolExhausted
    }
    if err != nil {
        return "", fmt.Errorf("allocate from freelist: %w", err)
    }
    return ip, nil
}

// ReturnIPToFreelist puts an IP back into the pool's freelist.
// Idempotent: ON CONFLICT DO NOTHING.
func (r *AddressRepo) ReturnIPToFreelist(ctx context.Context, poolID, ip string) error {
    _, err := r.pool.Exec(ctx, `
        INSERT INTO address_pool_free_ips (pool_id, ip)
        VALUES ($1, $2::inet)
        ON CONFLICT (pool_id, ip) DO NOTHING
    `, poolID, ip)
    if err != nil {
        return fmt.Errorf("return ip to freelist: %w", err)
    }
    return nil
}
```

- [ ] **Step 4: Run test to verify it passes:**

Run: `cd project/kacho-vpc && go test ./internal/repo/... -run TestFreelist -v -count=1`
Expected: 3 tests PASS.

> Если тест helpers (`setupTestDB`, etc.) отличаются по имени от того что в существующих integration tests — поправить импорт/имена в `address_pool_freelist_integration_test.go`. Это не должно требовать смены production-кода.

- [ ] **Step 5: Commit:**

```bash
cd project/kacho-vpc && git add internal/repo/address_repo.go internal/repo/errors.go internal/repo/address_pool_freelist_integration_test.go && git commit -m "$(cat <<'EOF'
feat(vpc): AddressRepo.AllocateIPFromFreelist + ReturnIPToFreelist

PG-native IPAM allocator backed by address_pool_free_ips materialized
freelist (migration 0014). Single-statement SKIP LOCKED pop + addresses
update — zero contention between concurrent allocators.

Replaces random-pick + UNIQUE-retry pattern (baseline ~73 alloc/sec on
/16 pool) — projected sustained throughput ≥ 2k/sec per pod, enabling
HPA-driven scaling to 10k+ aggregate.

Adds integration tests covering backfill, concurrent uniqueness,
return-on-delete (idempotent).

KAC-<E+4>
EOF
)"
```

---

## Phase 4: IPAM service rewrite + populate-on-pool-create

### Task 4.1: Service — переписать AllocateExternalIP на freelist

**Files:**
- Modify: `project/kacho-vpc/internal/service/address.go` (функция `AllocateExternalIP`, ~lines 963-1100)

- [ ] **Step 1: Read** текущую `AllocateExternalIP` (строки 963-1100; уже читали в spec-фазе).

- [ ] **Step 2: Заменить тело функции** (после `pool := resolved.Pool` — лидирующая часть с `addr.repo.Get`, idempotency-check, `ResolvePoolForAddressObj` остаётся):

Вместо двухфазного random-pick/sweep loop:

```go
    // PG-native allocator: single-statement SKIP LOCKED pop from
    // address_pool_free_ips (migration 0014). Zero contention.
    ip, err := s.repo.AllocateIPFromFreelist(ctx, pool.ID, addressID)
    if err != nil {
        if errors.Is(err, ErrPoolExhausted) {
            return nil, status.Errorf(codes.FailedPrecondition,
                "address pool %s exhausted", pool.ID)
        }
        return nil, status.Errorf(codes.Internal, "allocate from freelist: %v", err)
    }
    return &AllocateResult{IP: ip, PoolID: pool.ID}, nil
}
```

> ⚠️ Удаляются также `usableIPv4Sweep`, `pickRandomIPv4` если они больше не используются нигде. **Проверить** через grep — они могут быть нужны для `AllocateInternalIP` (внутри subnet) и `AllocateInternalIPv6`. Если используются — оставить как есть.

> ⚠️ `ErrPoolExhausted` импортируется как `service.ErrPoolExhausted` — нужно re-export из repo (либо просто `var ErrPoolExhausted = repo.ErrPoolExhausted` в service.errors).

- [ ] **Step 3: Расширить `mapRepoErr`** (в `network.go` или где определён) добавить кейс:

```go
case errors.Is(err, ErrPoolExhausted):
    return status.Error(codes.FailedPrecondition, "address pool exhausted")
```

- [ ] **Step 4: Run unit tests:**

Run: `cd project/kacho-vpc && make test-short`
Expected: все unit-tests зелёные. Если `AllocateExternalIP` тесты используют random-pick assumptions — поправить (теперь deterministic).

- [ ] **Step 5: Commit:**

```bash
cd project/kacho-vpc && git add internal/service/address.go internal/service/errors.go && git commit -m "$(cat <<'EOF'
feat(vpc): rewrite AllocateExternalIP via PG-native freelist

Replaces 2-phase random+sweep allocator with single-statement
SKIP LOCKED pop from address_pool_free_ips (migration 0014).

baseline 73 alloc/sec/pod (UNIQUE-retry contention) →
projected ≥2k alloc/sec/pod (zero contention).

KAC-<E+5>
EOF
)"
```

### Task 4.2: Service — Address.Delete возвращает IP в freelist

**Files:**
- Modify: `project/kacho-vpc/internal/service/address.go` (`AddressService.Delete`, ~line 650 onwards; specifically the `operations.Run` worker block)

- [ ] **Step 1: Read** текущий Delete (видели в pre-flight).

- [ ] **Step 2: Изменить worker-функцию.** Заменить:

```go
    operations.Run(ctx, s.opsRepo, op.ID, func(ctx context.Context) (*anypb.Any, error) {
        if err := s.repo.Delete(ctx, id); err != nil {
            return nil, mapRepoErr(err)
        }
        return anypb.New(&emptypb.Empty{})
    })
```

на:

```go
    operations.Run(ctx, s.opsRepo, op.ID, func(ctx context.Context) (*anypb.Any, error) {
        // Capture allocated IP / pool BEFORE delete — needed to return to freelist.
        var (
            allocatedIP, poolID string
        )
        if existing.ExternalIpv4 != nil {
            allocatedIP = existing.ExternalIpv4.Address
            poolID = existing.ExternalIpv4.AddressPoolID
        }

        if err := s.repo.Delete(ctx, id); err != nil {
            return nil, mapRepoErr(err)
        }

        // Best-effort return-to-freelist. Failure here doesn't fail the Delete
        // (the address is gone — IP just won't be reused; safety-net unique
        // index ensures consistency).
        if allocatedIP != "" && poolID != "" {
            if rerr := s.repo.ReturnIPToFreelist(ctx, poolID, allocatedIP); rerr != nil {
                slog.WarnContext(ctx, "address delete: failed to return IP to freelist",
                    "address_id", id, "pool_id", poolID, "ip", allocatedIP, "err", rerr)
            }
        }
        return anypb.New(&emptypb.Empty{})
    })
```

- [ ] **Step 3: Run integration test** что verify Delete возвращает IP:

```go
// add to address_pool_freelist_integration_test.go
func TestService_AddressDelete_ReturnsIPToFreelist(t *testing.T) {
    // setup: create pool, allocate one address with IP
    // run: AddressService.Delete(addressID) → wait Operation done
    // assert: address_pool_free_ips contains the freed IP
}
```

(Скелет — конкретику дописать с использованием существующего service-test scaffold — `mock_test.go`/`address_test.go`.)

Run: `cd project/kacho-vpc && go test ./internal/service/... -run AddressDelete -v -count=1`
Expected: PASS.

- [ ] **Step 4: Commit:**

```bash
cd project/kacho-vpc && git add internal/service/address.go && git commit -m "$(cat <<'EOF'
feat(vpc): Address.Delete returns IP to address_pool_free_ips

Pairs with AllocateIPFromFreelist (migration 0014): IPs
released by Delete are immediately reusable, keeping pool
in steady state under sustained load.

Best-effort: failure here logs a warning but doesn't fail
the Delete (safety-net unique index covers duplicate corner cases).

KAC-<E+5>
EOF
)"
```

### Task 4.3: Service — InternalAddressPoolService.Create populates freelist

**Files:**
- Modify: `project/kacho-vpc/internal/service/address_pool_service.go`

- [ ] **Step 1: Read** существующий `Create`/`Insert` для AddressPool — найти точку после успешного INSERT pool в БД.

- [ ] **Step 2: Добавить populate-step** в той же транзакции (если pool.Insert возвращает свежеинсертированный pool):

```go
// Populate freelist from CIDR blocks immediately after pool creation.
// Idempotent (ON CONFLICT DO NOTHING) — safe to retry.
if err := s.poolRepo.PopulateFreelistForPool(ctx, created.ID); err != nil {
    return nil, status.Errorf(codes.Internal, "populate freelist: %v", err)
}
```

И в `address_pool_repo.go` добавить:

```go
// PopulateFreelistForPool inserts all usable IPv4 addresses from
// pool's CIDR blocks into address_pool_free_ips. Idempotent.
// IPv6 CIDRs are skipped (sparse allocator phase).
func (r *AddressPoolRepo) PopulateFreelistForPool(ctx context.Context, poolID string) error {
    _, err := r.pool.Exec(ctx, `
        DO $$
        DECLARE cidr_str TEXT;
        BEGIN
            FOR cidr_str IN
                SELECT unnest(cidr_blocks) FROM address_pools WHERE id = $1
            LOOP
                IF family(cidr_str::cidr) = 4 THEN
                    INSERT INTO address_pool_free_ips (pool_id, ip)
                    SELECT $1, host(addr)::inet
                    FROM generate_series(
                        network(cidr_str::cidr) + 1,
                        broadcast(cidr_str::cidr) - 1
                    ) AS addr
                    ON CONFLICT (pool_id, ip) DO NOTHING;
                END IF;
            END LOOP;
        END $$;
    `, poolID)
    if err != nil {
        return fmt.Errorf("populate freelist: %w", err)
    }
    return nil
}
```

> ⚠️ pgx не любит `$1` внутри DO-блока (DO не принимает параметры). Альтернатива — вычитать `cidr_blocks` сначала, потом построить SQL без DO, через цикл в Go. Если миграционный DO работает (без параметров — он строкой), но запрос на runtime — параметризован, то лучше написать без DO:

```go
func (r *AddressPoolRepo) PopulateFreelistForPool(ctx context.Context, poolID string) error {
    var cidrs []string
    err := r.pool.QueryRow(ctx,
        `SELECT cidr_blocks FROM address_pools WHERE id = $1`, poolID,
    ).Scan(&cidrs)
    if err != nil {
        return fmt.Errorf("read cidr_blocks: %w", err)
    }
    for _, cidr := range cidrs {
        // Skip IPv6 (sparse allocator phase).
        // We use generate_series only for IPv4.
        if _, err := r.pool.Exec(ctx, `
            INSERT INTO address_pool_free_ips (pool_id, ip)
            SELECT $1, host(addr)::inet
            FROM generate_series(network($2::cidr) + 1, broadcast($2::cidr) - 1) AS addr
            WHERE family($2::cidr) = 4
            ON CONFLICT (pool_id, ip) DO NOTHING
        `, poolID, cidr); err != nil {
            return fmt.Errorf("populate freelist for %s: %w", cidr, err)
        }
    }
    return nil
}
```

(Этот вариант предпочтителен — параметризовано безопасно.)

- [ ] **Step 3: Run integration test** что create pool заполняет freelist:

```go
func TestPoolService_Create_PopulatesFreelist(t *testing.T) {
    // setup: create test address pool service (with deps mocked or in-process)
    // run: InternalAddressPoolService.Create(cidr=/28)
    // assert: address_pool_free_ips contains 14 entries for that pool
}
```

Run: `cd project/kacho-vpc && go test ./internal/service/... -run PoolService_Create -v -count=1`
Expected: PASS.

- [ ] **Step 4: Commit:**

```bash
cd project/kacho-vpc && git add internal/service/address_pool_service.go internal/repo/address_pool_repo.go && git commit -m "$(cat <<'EOF'
feat(vpc): InternalAddressPool.Create populates freelist

Newly created pools immediately have their IPv4 CIDR blocks
materialized into address_pool_free_ips via
AddressPoolRepo.PopulateFreelistForPool. Idempotent
(ON CONFLICT DO NOTHING).

IPv6 CIDRs are skipped — sparse allocator deferred to a
separate phase.

KAC-<E+5>
EOF
)"
```

### Task 4.4: Bench — replicate baseline measurement

**Files:**
- Modify: `project/kacho-vpc/internal/service/address_allocate_bench_test.go`

- [ ] **Step 1: Read** существующий bench — понять как настроен тест-стенд.

- [ ] **Step 2: Добавить bench для нового path** (если не существует):

```go
func BenchmarkAllocateExternalIP_Freelist(b *testing.B) {
    ctx, pool := setupTestDB(b)
    defer pool.Close()

    poolID := insertTestPool(b, pool, "10.10.0.0/16")  // 65k IPs
    repo := repo.NewAddressRepo(pool)
    addrIDs := make([]string, b.N)
    for i := range addrIDs {
        addrIDs[i] = insertTestAddress(b, pool)
    }

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _, err := repo.AllocateIPFromFreelist(ctx, poolID, addrIDs[i])
        if err != nil { b.Fatal(err) }
    }
}
```

И добавить parallel-bench:

```go
func BenchmarkAllocateExternalIP_Freelist_Parallel(b *testing.B) {
    ctx, pool := setupTestDB(b)
    defer pool.Close()
    poolID := insertTestPool(b, pool, "10.10.0.0/16")
    repo := repo.NewAddressRepo(pool)

    b.ResetTimer()
    b.RunParallel(func(pb *testing.PB) {
        for pb.Next() {
            addrID := insertTestAddress(nil, pool)  // panic on err — bench helper
            _, err := repo.AllocateIPFromFreelist(ctx, poolID, addrID)
            if err != nil { b.Fatal(err) }
        }
    })
}
```

- [ ] **Step 3: Run benches:**

Run: `cd project/kacho-vpc && go test ./internal/repo/... -bench BenchmarkAllocateExternalIP_Freelist -benchmem -count=3 -run=^$`
Expected: показывает ns/op + B/op + allocs/op. Сохранить вывод в `tests/k6/results/bench-freelist-<date>.txt`.

- [ ] **Step 4: Commit:**

```bash
cd project/kacho-vpc && git add internal/service/address_allocate_bench_test.go tests/k6/results/bench-freelist-*.txt && git commit -m "$(cat <<'EOF'
test(vpc): add benchmark for AllocateIPFromFreelist (sequential + parallel)

Captures local measurement of the new PG-native allocator under
testcontainers Postgres. Bench results saved to
tests/k6/results/bench-freelist-<date>.txt for reference.

KAC-<E+5>
EOF
)"
```

---

## Phase 5: Build, deploy, measure

### Task 5.1: Build kacho-vpc image + push в registry

**Files:** none (build operation).

- [ ] **Step 1: Build:**

Run:
```bash
cd project/kacho-vpc && \
  TAG="ttl.sh/kacho-loadtest-$(date +%Y%m%d%H%M%S)/kacho-vpc:24h" && \
  docker build -t "$TAG" . && \
  docker push "$TAG" && \
  echo "TAG=$TAG"
```

Expected: образ запушен, тег записан.

- [ ] **Step 2: Записать TAG** в scratch — будет использован в helm upgrade.

### Task 5.2: Helm upgrade umbrella с новым image и values

**Files:** none (cluster operation).

- [ ] **Step 1: Build umbrella deps:**

Run: `cd project/kacho-deploy/helm/umbrella && helm dependency build`

- [ ] **Step 2: Apply upgrade с overriding image:**

Run:
```bash
KUBECONFIG=/tmp/e2c825-merged.kubeconfig helm upgrade --install kacho-umbrella \
  project/kacho-deploy/helm/umbrella \
  -n kacho \
  -f project/kacho-deploy/helm/umbrella/values.dev.yaml \
  --set vpc.image="$TAG" \
  --wait --timeout 300s
```

Expected: rollout завершён, все podы Running.

- [ ] **Step 3: Verify HPA создан:**

Run: `KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho get hpa`
Expected: 5 HPA (vpc, api-gateway, resource-manager, compute, ui), все с `TARGETS: <unknown>/70%` или `<число>%/70%`.

- [ ] **Step 4: Verify migration 0014 applied:**

Run:
```bash
KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho exec -it kacho-umbrella-pg-vpc-0 -- \
  psql -U vpc -d kacho_vpc -c '\dt address_pool_free_ips' -c 'SELECT pool_id, count(*) FROM address_pool_free_ips GROUP BY pool_id;'
```
Expected: таблица существует, для существующих pools видим `count(*)` ≥ 0.

> ⚠️ Если existing pool в кластере отсутствует или CIDR не /16 — создать нужный pool через `InternalAddressPoolService.Create` (см. `kacho-vpc/CLAUDE.md` §16.7 admin workflow):

```bash
KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho port-forward svc/api-gateway 18080:8080 &
sleep 2
curl -s -XPOST http://localhost:18080/vpc/v1/addressPools \
  -H 'content-type: application/json' \
  -d '{"name":"loadtest-pool","kind":"EXTERNAL_PUBLIC","zoneId":"ru-central1-a","cidrBlocks":["10.250.0.0/16"],"isDefault":true}'
```

Затем повторить freelist count check — должно быть 65534 free IPs.

### Task 5.3: Прогон baseline (до scale-out)

**Files:**
- Create: `project/kacho-vpc/tests/k6/results/run-<date>-baseline.txt`

- [ ] **Step 1: Force vpc replicas=1 (HPA min):**

Run: `KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho scale deploy/vpc --replicas=1`

Подождать ScaleDown stabilization (5 min) или временно отключить HPA для чистоты baseline. Альтернатива: установить `maxReplicas=1` в HPA через patch — но проще временно `kubectl delete hpa vpc -n kacho`, прогнать baseline, потом `helm upgrade` снова создаст.

- [ ] **Step 2: Уменьшить TARGET_RPS** в Job manifest temporarily для baseline:
```bash
KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho create cm k6-address-allocate \
  --from-file=script.js=project/kacho-deploy/load-tests/k6-address-allocate.yaml.script.js \
  --dry-run=client -o yaml | kubectl apply -f -
# простейший вариант: запустить с TARGET_RPS=1000 чтобы понять single-pod ceiling
```

(Альтернатива — встроить env override в Job manifest напрямую и переапplyить.)

- [ ] **Step 3: Запустить baseline run:**

Run: `cd project/kacho-deploy && KUBECONFIG=/tmp/e2c825-merged.kubeconfig make loadtest-address-allocate`

Дождаться завершения (5 min). Сохранить логи:

```bash
KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho logs -l job-name=k6-address-allocate \
  > project/kacho-vpc/tests/k6/results/run-$(date +%Y%m%d-%H%M)-baseline.txt
```

- [ ] **Step 4: Извлечь метрики** из k6 summary (последние строки логов):
- `address_alloc_ok` rate
- `http_req_duration` p99
- `iterations` total
- `addresses_allocated` total

Записать в `BASELINE.md` строкой "1 replica baseline после freelist-рефактора: X alloc/sec".

### Task 5.4: Прогон с HPA до 10k

- [ ] **Step 1: Восстановить HPA:** `helm upgrade …` (если в Step 5.3.1 удалили).

- [ ] **Step 2: Восстановить TARGET_RPS=10000** в k6 Job (если меняли).

- [ ] **Step 3: Запустить full run:**

Run: `cd project/kacho-deploy && KUBECONFIG=/tmp/e2c825-merged.kubeconfig make loadtest-address-allocate`

В отдельном терминале мониторить scale events:
```bash
watch -n 5 'KUBECONFIG=/tmp/e2c825-merged.kubeconfig kubectl -n kacho get hpa,pod | grep -E "vpc|api-gateway"'
```

- [ ] **Step 4: Сохранить логи и метрики** в `run-<date>-hpa-10k.txt`.

- [ ] **Step 5: Verify success criteria:**
- ✅ `address_alloc_ok` rate > 0.99
- ✅ `http_req_duration` p99 < 200
- ✅ `addresses_allocated` count ≥ 10000 × 250s = 2.5M (за 5 min)
- ✅ HPA scaled vpc to N replicas (по `kubectl describe hpa vpc -n kacho`)

Если что-то не выполнено — итерация tune (см. `BASELINE.md` для recipes: increase `KACHO_VPC_DB_MAX_CONNS`, `max_connections`, etc.) → re-run.

### Task 5.5: Update BASELINE.md + finalize spec/plan в workspace

**Files:**
- Modify: `project/kacho-vpc/tests/k6/results/BASELINE.md`

- [ ] **Step 1: Дописать новую секцию** в начало BASELINE.md:

```markdown
## 🚀 ПОДТВЕРЖДЁННЫЙ РЕЗУЛЬТАТ: 10 000 Address.Create/sec через api-gateway + HPA

**Дата:** YYYY-MM-DD
**Окружение:** `/tmp/e2c825-merged.kubeconfig`, ns `kacho`
**Endpoint:** `http://api-gateway.kacho.svc.cluster.local:8080` (REST через grpc-gateway)

| Метрика | Значение |
|---|---|
| Sustained Address.Create/sec | XXX |
| p99 latency | XX ms |
| Error rate | X.XX% |
| HPA peak vpc replicas | X |
| HPA peak api-gateway replicas | X |

Конфигурация:
- IPAM via PG-native freelist (migration 0014, SKIP LOCKED) — заменил random+UNIQUE-retry
- HPA: vpc 1..10, api-gateway 1..10, target CPU 70%
- Postgres: synchronous_commit=local, max_connections=300, shared_buffers=512MB
- KACHO_VPC_DB_MAX_CONNS=200, KACHO_VPC_DEFAULT_SG_INLINE=false

Запуск: `cd project/kacho-deploy && make loadtest-address-allocate`
Артефакт: `tests/k6/results/run-YYYY-MM-DD-hpa-10k.txt`
```

- [ ] **Step 2: Commit kacho-vpc обновления BASELINE.md и run logs:**

```bash
cd project/kacho-vpc && git add tests/k6/results/BASELINE.md tests/k6/results/run-*.txt && git commit -m "$(cat <<'EOF'
docs(vpc): update BASELINE.md — 10k Address.Create/sec achieved

In-cluster k6 over api-gateway, HPA + IPAM freelist + PG tune.
Run logs preserved as tests/k6/results/run-*.txt.

KAC-<E+5>
EOF
)"
```

- [ ] **Step 3: Update workspace spec + plan** (для KAC-<E+7> branch):

Уже создан spec и plan. Что дополнительно записать в workspace:
- В `docs/superpowers/specs/2026-05-14-...-design.md` §6 Success criteria — отметить final numbers.
- Опционально: краткий «retrospective» в plan.md что прошло, что нет.

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace && \
  git add docs/superpowers/specs/2026-05-14-* docs/superpowers/plans/2026-05-14-* && \
  git commit -m "$(cat <<'EOF'
docs(superpowers): in-cluster load-test 10k spec + plan

Spec: docs/superpowers/specs/2026-05-14-in-cluster-loadtest-hpa-10k-ipam-design.md
Plan: docs/superpowers/plans/2026-05-14-in-cluster-loadtest-hpa-10k-ipam-plan.md

Tracks KAC-<E> epic and KAC-<E+1>..<E+7> subtasks.
EOF
)"
```

---

## Phase 6: PR'ы и YouTrack-комментарии

### Task 6.1: Push branches + open PR в каждом репо

- [ ] **Step 1:** В каждом репо: `git push -u origin KAC-<E+X>` (X — соответствующий subtask id).

- [ ] **Step 2:** В каждом репо: `gh pr create --title "[KAC-<E+X>] <summary>" --body "<что и зачем; Closes KAC-<E+X>>"`.

- [ ] **Step 3: Записать ссылку на каждый PR** комментарием в соответствующий YouTrack subtask (через `mcp__youtrack__add_comment`).

### Task 6.2: Перевести taski в Test → после CI зелёного → в Done

- [ ] **Step 1:** Каждый subtask `KAC-<E+X>` → `Test` после открытия PR (`mcp__youtrack__update_issue_state`).

- [ ] **Step 2:** После merge'а PR (CI зелёный) → `Done`.

- [ ] **Step 3:** Эпик `KAC-<E>` в `Done` после того, как все subtasks закрыты и `BASELINE.md` обновлён.

---

## Self-review (заполнено автором плана)

**1. Spec coverage:**
- ✅ §4.1 HPA + resources → Phase 1 Tasks 1.1-1.5
- ✅ §4.2 PG tune → Phase 2 Task 2.1
- ✅ §4.3 App env → Phase 1 Task 1.1 (объединено с vpc chart)
- ✅ §4.4 Migration 0014 → Phase 3 Task 3.1
- ✅ §4.5 Service rewrite (allocate/delete/populate) → Phase 4 Tasks 4.1-4.3
- ✅ §4.6 In-cluster k6 Job → Phase 2 Task 2.2
- ✅ §4.7 Метрики (отложено на инкрементальную фазу — записано в spec §8)
- ✅ §5 Порядок выполнения → Phases 1→2→3→4→5→6
- ✅ §6 Success criteria → Phase 5 Task 5.4 Step 5
- ✅ Phase 0 Task 0.1: KAC-эпик + subtasks (workspace policy CLAUDE.md)

**2. Placeholder scan:** проверил — все шаги имеют конкретные команды/код. `<E>` / `<E+X>` — placeholder под id YouTrack-эпика, который заполняется на Phase 0; везде явно помечен.

**3. Type consistency:**
- `repo.AllocateIPFromFreelist` ⇄ `repo.ReturnIPToFreelist` ⇄ `repo.PopulateFreelistForPool` — все 3 метода в `address_repo.go` / `address_pool_repo.go`.
- `ErrPoolExhausted` определён в repo, re-export'ится в service.
- `mapRepoErr` расширен для `ErrPoolExhausted`.
- HPA template одинаковый во всех 5 чартах (отличается только через `.Values.name` substitution).

---

## Execution handoff

**Plan complete and saved to** `docs/superpowers/plans/2026-05-14-in-cluster-loadtest-hpa-10k-ipam-plan.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — я диспатчу свежий subagent под каждую task (предпочтительно по Phases — один subagent per phase или per chart-репо), ревью между задачами, изоляция через worktrees где нужно.

2. **Inline Execution** — выполняю шаги в этой же сессии через `executing-plans` skill, batch с checkpoints для review.

**Какой подход выбираешь?**
