---
title: kacho-deploy
aliases:
  - kacho-deploy
category: repo
repo: kacho-deploy
service_type: deployment-artifacts
status: stable
tags:
  - kacho
  - kacho-deploy
  - helm
  - docker-compose
  - ci
  - kind
---

# kacho-deploy

Deployment + dev/CI стенды Kachō — Helm umbrella chart + docker-compose CI stack + k8s manifests.

- Repo: `github.com/PRO-Robotech/kacho-deploy`
- Тип: deployment artifacts (не Go binary).

## Структура

```
helm/
├── umbrella/                  — top-level helm chart (зависит от sibling charts):
│   ├── Chart.yaml                — ingress-nginx + postgresql×3 + 5 service-charts.
│   ├── values.dev.yaml           — dev-config (in-memory pg, no persistence).
│   ├── values.prod.yaml          — prod-config (TLS, persistent storage).
│   └── templates/                — NetworkPolicies, ConfigMaps, env-overrides.
└── (subchart-stubs)           — каждый sibling-сервис имеет свой `deploy/Chart.yaml` в своём репо.

ci/
├── docker-compose.yml         — CI stack: pg×3 + 3 services + api-gateway (без helm/k8s).
├── seed.sh                    — fixtures: default Org/Cloud/Folder/zones/AddressPool/Network/Subnet/SG.
└── .seeded-ids.env            — output для newman test runs.

e2e/
├── 0.1/                       — kind-cluster smoke tests (E1 dev-up, E5 secrets, E6 ingress, E7-E9, F1-F2).
└── geography-move.sh          — integration test cross-service ref-validation.
    (cp-resource-model.sh для kube-ovn-эпохи data-plane-модели удалён в KAC-36/79/80.)

kind/
├── kind-config.yaml           — kind cluster config (hostPort 80/443 for ingress).
└── create-cluster.sh

load-tests/                    — k6 load test jobs.

argo-apps/                     — ArgoCD applications (production GitOps).
├── kacho-vpc-operator/
├── kube-ovn/
└── multus/

scripts/                       — bootstrap + helper scripts.
docs/                          — deploy-specific documentation.
```

## Makefile targets

| Target | Action |
|---|---|
| `make dev-up` | `kind create cluster` + `helm upgrade --install kacho-umbrella ./helm/umbrella --wait --timeout 10m`. |
| `make dev-down` | `kind delete cluster kacho`. |
| `make reload-svc SVC=vpc` | helm upgrade одного sibling-chart'а. |
| `make logs-svc SVC=vpc` | `kubectl logs` deployment'а. |
| `make psql SVC=vpc` | `kubectl exec` в pg pod + psql. |
| `make ci-up` | `docker compose up -d` (CI stack без kind). |
| `make ci-down` | `docker compose down -v`. |
| `make ci-seed` | re-run seed.sh against running stack. |
| `make preflight` | проверка наличия `docker`/`kind`/`kubectl`/`helm`. |

## CI workflows

- **`helm-lint`** — `helm dep update && helm lint .` на каждом push/PR.
- **`e2e-on-kind`** — nightly (schedule + workflow_dispatch only): full kind-cluster + e2e/0.1/E*.sh suite + integration tests. Помечен `continue-on-error: true` (kind infra-bound).

## Helm chart dependencies (umbrella)

```yaml
dependencies:
  - ingress-nginx (community)
  - postgresql (bitnami) × N (pg-iam, pg-vpc, pg-compute)   # pg-resource-manager удалён в KAC-124
  - iam               (file://../../../kacho-iam/deploy)          # заменил resource-manager (KAC-124)
  - vpc               (file://../../../kacho-vpc/deploy)
  - compute           (file://../../../kacho-compute/deploy)
  - api-gateway       (file://../../../kacho-api-gateway/deploy)
  - ui                (file://../../../kacho-ui/deploy)         — private repo (best-effort checkout)
```

**Удалены** (Phase 2):
- `pg-netbox` + NetBox subchart (IPAM перенесён в kacho-vpc inline).
- `pg-loadbalancer` (kacho-loadbalancer frozen).

## Build-зависимости

`kacho-deploy` — **не Go-binary**, нет `go.mod`. Зависит от исходников всех сервисов:
- Dockerfile'ы сервисов делают `COPY ../kacho-*` → build context = parent dir.
- `kacho-deploy/Makefile` собирает images через `docker buildx build -f kacho-<svc>/Dockerfile -t kacho-<svc>:dev ..`.

См. [[../architecture]] для cross-repo графа.

## Эпики

- **KAC-94 (часть)** — `ci/seed.sh` fixes для warmup + KAC-71 cidrBlocks + kacho-migrator binary.
- **KAC-96** — kacho-migrator init-container в deployment templates.

#kacho #deploy #helm #docker-compose #ci #kind
