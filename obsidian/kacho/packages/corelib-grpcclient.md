---
title: corelib-grpcclient
category: packages
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - grpc
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/grpcclient — клиентская сборка соединения к соседу

**Каталог**: `pkg/grpcclient/` · импорт `github.com/PRO-Robotech/kacho/pkg/grpcclient`
**Прежде** (полирепо): `kacho-corelib/grpcclient`.
**Импортирует**: `crypto/tls`, `crypto/x509`, `google.golang.org/grpc` +
`keepalive`, `credentials`, `credentials/insecure`.
**Импортируют** (`go list` на `96b2879a`, non-test): vpc 3 · storage 2 · registry 2 ·
nlb 2 · geo 2 · gateway 2 · compute 2 · iam 1 — то есть **все семь** сервисов и шлюз.
Прежняя редакция перечисляла рёбра прозой, включая уже снятое ребро vpc→compute.

Горизонтальная сборка исходящего соединения: удержание соединения и клиентские
учётные данные TLS.

## Экспортируемое API (снято с дерева)

```go
func KeepaliveParams(permitWithoutStream bool) keepalive.ClientParameters
func KeepaliveDialOption(permitWithoutStream bool) grpc.DialOption
func TLSClientCreds(cfg TLSClient) (grpc.DialOption, error)
func TLSClientTransportCreds(cfg TLSClient) (credentials.TransportCredentials, error)
type TLSClient struct{ Enable bool; CertFile, KeyFile string; CAFiles []string; ServerName string }
```

`TLSClientTransportCreds` — вторая точка, нужная там, где соединение собирается не
через параметр набора, а напрямую (например, HTTP-клиентом); прежняя редакция её не
называла.

> [!important] Срок на КАЖДОМ внешнем вызове — не заменяется удержанием соединения
> Удержание соединения замечает мёртвого пира на уровне транспорта, но не спасает от
> отвечающего слишком долго. Каждый вызов к соседу обязан нести собственный срок:
> без него неотвечающий пир подвешивает горутину навсегда, и особенно опасно это на
> проверке прав — перехватчик не доходит до ветки fail-closed, горутины копятся
> (`architecture.md` §Concurrency).

### SEC-B — opt-in mTLS client-creds (`tls.go`)

- `TLSClient{Enable, CertFile, KeyFile, CAFiles []string, ServerName}` — per-edge config (FD-3). `enable=false` ⇒ insecure dial (FD-1, backward-compat). Env-теги — `KACHO_<DOMAIN>_TLS_CLIENT_*` (полное имя через explicit-tag fallback envconfig).
- `TLSClientCreds(TLSClient) (grpc.DialOption, error)` — единая точка истины (FD-7). `enable=true` ⇒ client-cert + server-CA + проверка `server_name` против SAN серверного cert (FD-2). Пустая пара cert/key при `enable=true` ⇒ one-way TLS (без client-cert) — для теста require-and-verify reject (SEC-B-06/16). Misconfig (нечитаемый cert / пустой `ca_files` / пустой `server_name`) ⇒ error, НЕ silent insecure fallback (FD-6).

## Convention

- Helper'ы — единственный способ собрать TLS-creds для inter-service gRPC (гард SEC-B-19 в `grpcsrv/tls_guard_test.go` ловит прямой `credentials.NewTLS`/`tls.Config` вне `tls.go`).
- mTLS-сторона клиента согласуется с серверной (`grpcsrv.TLSServerCreds`): mismatch enable ⇒ `Unavailable` (per-edge, нет тихого downgrade).
- Включение per-edge — SEC-E (api-gateway→backend), SEC-D (vpc/compute→iam), SEC-G (operator→vpc). SEC-B мёржится с `enable=false`.

## See also

[[corelib-grpcsrv]] [[corelib-config]] [[corelib-auth]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-corelib #grpc
