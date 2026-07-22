---
tags: [kacho/edge, kacho/registry, kacho/deploy]
---

# registry data-plane → публичный TLS (docker login/push/pull)

Как терминируется HTTPS публичного OCI data-plane (`registry.in-cloud.io`) и почему
серт обязан быть **публично-доверенным**, а не internal-CA.

## Топология

```
docker client ──https:443──▶ Service registry-lb (VIP 89.169.39.46)
                              443 → targetPort dp-tls
                                     │
                              pod registry
                               ├─ dataplane-tls (nginx-unprivileged)  :8443 ssl
                               │    ssl_certificate /etc/registry-tls/tls.crt  ← LE-серт
                               │    location = /iam/token → kacho-iam:9096  (token shim)
                               │    location /           → 127.0.0.1:8080  (data-plane)
                               └─ registry (kacho-registry)            :8080 plaintext
```

- **Server-cert**: `registry-dataplane-le-tls`, Certificate `registry-dataplane-letsencrypt`,
  `ClusterIssuer/letsencrypt-prod`, SAN `registry.in-cloud.io`.
- **Почему LE, а не `kacho-internal-ca`**: серт предъявляется docker-клиенту на ноутбуке —
  internal-CA он отвергает (`x509: certificate signed by unknown authority`).
- **Публичный CA не подписывает** `commonName` и `ipAddresses` (loopback/private-IP) и
  навязывает свою keyalg-политику → в Certificate этих полей быть не должно.

## Trust-anchor iam :9097 — отдельная история (не путать)

`ca.crt` для `SSL_CERT_DIR` (доверие к leaf'у, терминирующему iam JWKS-proxy :9097) берётся:
- `mtls.enable=true` (prod) → из **`mtls.serverSecretName`** (`registry-server-tls`, internal-CA);
- `mtls.enable=false` (dev) → из секрета sidecar-серта.

Отсюда инвариант: **публичный issuer sidecar'а требует `mtls.enable=true`**, иначе `ca.crt`
станет публичной цепочкой и верификация iam :9097 сломается. См. [[registry-to-iam-jwks-fetch]].

## Инцидент 2026-07-15 — дрейф съел HTTPS реестра

Весь TLS-стек data-plane был **наложен руками** (LE Certificate + `kubectl patch svc registry-lb`
443→dp-tls) и не жил в umbrella-values: `service.dataplaneLB.tlsSidecar.enabled` не выставлялся
нигде → дефолт чарта `false` → `helm template` рендерил Service `443 → dataplane` (**plaintext**)
и pod **без sidecar'а вообще**.

Cutover запускается с `--take-ownership` — он усыновил hand-patched Service и перерендерил
его дефолтом. Результат у клиента:

```
docker login registry.in-cloud.io
Error response from daemon: Get "https://registry.in-cloud.io/v2/":
  http: server gave HTTP response to HTTPS client
```

Диагностический признак: изнутри кластера `http→401` (корректный token-challenge), `https→000`.
`kubectl get svc registry-lb -o jsonpath='{.metadata.managedFields[*].manager}'` → `kubectl-patch helm`
(= объект правился руками поверх helm).

**Фикс** (kacho-registry `fix/dataplane-tls-public-issuer`): issuer/имена/SAN серта вынесены в
`service.dataplaneLB.tlsSidecar.cert.*`; `commonName`/`ipAddresses`/`privateKey.algorithm|size`/
`usages` рендерятся только когда непусты; volume берёт `cert.secretName` из values. Оверлей
`values.fe3455-prod.yaml` включает sidecar и указывает LE-серт **именами существующих объектов** →
helm **усыновляет** серт без перевыпуска (LE duplicate-limit 5/нед на одинаковый SAN-набор).

## Урок

Ручной `kubectl patch` на ресурсе, которым владеет helm, — **отложенная авария**: следующий
`helm upgrade` его снесёт, и упадёт то, что «работало месяцами». Любое живое состояние обязано
быть выразимо чартом; если чарт не умеет — правится **чарт**, а не кластер.

Связано: [[registry-to-iam-jwks-fetch]], [[registry-iam-jwks-unify]].
