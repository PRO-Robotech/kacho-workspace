---
title: "iam internal/clients/jackson"
aliases:
  - jackson client
  - saml client
category: packages
repo: kacho-iam
layer: clients
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - clients
  - saml
  - sso
---

# iam `internal/clients/jackson`

Phase 6 — adapter для Boxyhq Jackson SAML/OIDC bridge. Port-interface defined в `internal/service/saml`, impl here.

## Exported API

```go
type JacksonClient interface {
    UpsertTenantConfig(ctx, tenant string, idpMeta IdPConfig) (*TenantConfigResp, error)
    GetTenantConfig(ctx, tenant string) (*TenantConfigResp, error)
    DeleteTenantConfig(ctx, tenant string) error
    InitiateSSO(ctx, tenant string, relayState string) (redirectURL string, err error)
    ProcessSAMLResponse(ctx, samlResponse []byte) (*SAMLAttrs, error)
    LogoutRequest(ctx, sessionID string) (logoutURL string, err error)
}
```

## Implementation

```go
type jacksonClient struct {
    baseURL    string         // e.g. http://jackson:5225
    httpClient *http.Client
    authToken  string         // shared secret w/ Jackson admin API
    logger     *zap.Logger
    metrics    *prometheus.CounterVec
}

func (j *jacksonClient) UpsertTenantConfig(ctx, tenant, cfg IdPConfig) (*TenantConfigResp, error) {
    body := mustJSON(map[string]any{
        "name":          tenant,
        "tenant":        tenant,
        "product":       "kacho-cloud",
        "redirectUrl":   []string{"https://api.kacho.cloud/saml/" + tenant + "/acs"},
        "defaultRedirectUrl": "https://kacho.cloud",
        "rawMetadata":   cfg.IdPMetadataXML,
        "encodedRawMetadata": base64.StdEncoding.EncodeToString([]byte(cfg.IdPMetadataXML)),
    })
    req, _ := http.NewRequestWithContext(ctx, "POST", j.baseURL+"/api/v1/saml/config", bytes.NewReader(body))
    req.Header.Set("Authorization", "Api-Key "+j.authToken)
    req.Header.Set("Content-Type", "application/json")
    resp, err := j.httpClient.Do(req)
    return parseTenantConfigResp(resp)
}
```

## Configuration

| ENV | Default | Description |
|---|---|---|
| `KACHO_IAM_JACKSON_BASE_URL` | `http://jackson:5225` | sidecar URL |
| `KACHO_IAM_JACKSON_API_KEY` | (required) | shared secret к Jackson admin API |
| `KACHO_IAM_JACKSON_TIMEOUT_MS` | 5000 | per-call timeout |

## Error mapping

| Jackson response | port error |
|---|---|
| 200 | success |
| 400 | `service.ErrInvalidArgument` |
| 404 | `service.ErrNotFound` |
| 409 | `service.ErrAlreadyExists` |
| 5xx | `service.ErrUnavailable` |
| timeout | `service.ErrUnavailable` |

## Imports

- `net/http`, `bytes`, `encoding/base64`, `encoding/json` — stdlib
- `go.uber.org/zap`
- `github.com/prometheus/client_golang`

## Imported by

- `internal/service/saml` — port consumer
- `cmd/kacho-iam/main.go` — composition root

## See also

[[iam-service-scim]] [[../edges/iam-to-jackson-saml]] [[../rpc/iam-saml-sp]] [[../resources/iam-organization]] [[../KAC/KAC-127]]

#packages #kacho-iam #clients #saml #sso
