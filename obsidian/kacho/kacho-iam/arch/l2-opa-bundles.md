---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.OpaBundleService/GetBundle
  - rpc: kacho.cloud.iam.v1.OpaBundleService/GetBundleSignature
  - rpc: kacho.cloud.iam.v1.OpaBundleService/GetRevision
status: implemented
source_sha: ""
---

# OPA bundles

Раздача подписанных OPA policy-bundle'ов. `OpaBundleService` — bundle-сервер:
OPA-sidecar каждого сервиса (vpc / compute / api-gateway) полл'ит его и получает
централизованную policy.

## Зачем

REBAC отвечает на «есть ли у subject'а relation» — но часть решений
org-wide и policy-driven: cluster-deny, регуляторные ограничения, step-up-MFA,
квоты, классификация данных. Эти правила — Rego-policy, и распространяться они
должны централизованно, версионированно и подписанно, чтобы агент не доверял
неподписанному контенту.

## Зачем `Internal*`

Сервис — internal-listener (9091): bundle описывает security-политику
платформы, его раздача — не tenant-facing операция (§Запрет #6).

## Контракт

- `GetBundle` — отдаёт gzip-tarball bundle'а (`.manifest`, `*.rego`,
  `data.json`); ETag-кэширование для polling-агента.
- `GetBundleSignature` — cosign-подпись bundle'а (supply-chain verification).
- `GetRevision` — текущая revision bundle'а (агент сравнивает, нужно ли
  перекачивать).

## Lifecycle

- CI собирает bundle, подписывает (cosign), публикует через сервис.
- OPA-агент периодически полл'ит `GetRevision` / `GetBundle`, верифицирует
  подпись через preconfigured public-key; verify-fail → fail-closed.
- Активная revision bump'ается при изменении policy (например, после reload
  authorization-model).

## Gotchas

- ВСЕ OPA-решения раздаются signed-bundle'ом — никаких inline unsigned-policy.
- Polling eventually-consistent (интервал агента) — изменение policy
  применяется не мгновенно.
- ETag-кэш снижает трафик; артефакт также может зеркалироваться в object-store
  для multi-region replay.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-opa-bundles]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
