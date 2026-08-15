---
title: apigw-health
category: packages
repo: kacho-api-gateway
path: gateway/internal/health
layer: handler
status: stable
tags:
  - packages
  - kacho-apigw
  - health
  - k8s
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# gateway/internal/health — живость и готовность края

**Каталог**: `gateway/internal/health/` (`health.go` + проба)
**Прежде** (полирепо): `kacho-api-gateway/internal/health`.

## Экспортируемое API (снято с дерева)

```go
func NewServer(backends proxy.Backends) *Server
func (s *Server) Check(...) (*healthpb.HealthCheckResponse, error)   // grpc.health.v1
func RegisterGRPCHealth(s *grpc.Server, backends proxy.Backends)
func HTTPHealthz(w http.ResponseWriter, _ *http.Request)             // GET /healthz
func HTTPReadyz(backends proxy.Backends, critical map[string]bool, logger *slog.Logger) http.HandlerFunc
func EvaluateReadiness(serving map[string]bool, critical map[string]bool) (map[string]string, bool)
```

## Готовность различает КРИТИЧНЫЕ домены и остальные

Прежняя редакция утверждала: готовность отдаёт 200 «только если край может
дозвониться до **всех** активных доменов», и перечисляла три домена, один из которых
снят вовсе. По дереву иначе и лучше: обработчик готовности опрашивает у каждого
домена его собственную службу здоровья, а решение принимает `EvaluateReadiness` по
**множеству критичных**. Некритичный домен, лежащий на боку, не выводит из ротации
весь край.

Это важно понимать до правки: список критичных — **решение о доступности**, а не
список подключённых. Добавить домен в опрос и добавить его в критичные — разные
действия с разными последствиями.

`Check` службы здоровья по gRPC отвечает про **сам край** и намеренно не опрашивает
домены: это разные вопросы, и смешивать их значит выводить край из ротации при
чужом сбое.

> [!note] Готовность не является доказательством посадки
> «Под готов» означает лишь «не падал» — в частности, под, переживший смену
> настроек без перезапуска, останется готовым со старым окружением. Посадка
> (режим аутентификации, шифрование к БД, mTLS на обоих слушателях) утверждается
> **самоотчётом процесса при старте** плюс независимым подтверждением со стороны
> БД: см. [[corelib-observability]] и `security.md` §Production-mode, п. 2а.

## См. также

[[apigw-cmd]] [[apigw-proxy]] [[corelib-observability]]

#packages #kacho-apigw #health #k8s
