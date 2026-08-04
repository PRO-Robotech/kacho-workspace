---
title: apigw-proxy
category: package
repo: kacho-api-gateway
path: gateway/internal/proxy
layer: handler
status: stable
tags:
  - packages
  - kacho-apigw
  - proxy
  - grpc
---

# gateway/internal/proxy — сквозной gRPC-прокси края

**Каталог**: `gateway/internal/proxy/`
**Прежде** (полирепо): `kacho-api-gateway/internal/proxy`.

Прозрачная передача gRPC для бинарных клиентов — в дополнение к транскодированию
REST ([[apigw-restmux]]).

## Экспортируемое API (снято с дерева)

```go
type Backends map[string]*grpc.ClientConn
type MethodResolver = func(fullMethod string) (string, grpc.ClientConnInterface, bool)

func RoutableDomain(fullMethod string) (string, bool)
func Resolver(backends Backends) MethodResolver
func NewServer(resolve MethodResolver, opts ...grpc.ServerOption) *grpc.Server
func Handler(resolve MethodResolver) grpc.StreamHandler

func IsInternalRoute(fullMethod string) bool
func UnaryRefuseInternalRoute() grpc.UnaryServerInterceptor
func StreamRefuseInternalRoute() grpc.StreamServerInterceptor
```

Файлы — `server.go`, `shimproxy.go`, `route_refusal.go`. Файла-«директора», вокруг
которого была построена прежняя редакция, в дереве нет вовсе (мёртвое имя здесь
намеренно не цитируется координатой); маршрутизацию делает резолвер метода.

## Внутреннее не публикуется — ОТКАЗОМ, а не отсутствием регистрации

Ключевая часть узла — `route_refusal.go`: внутренний метод, пришедший на **внешний**
слушатель, **отвергается явно** отдельным перехватчиком (unary и stream). Это
сильнее, чем «не зарегистрировали»: отсутствие регистрации — свойство сборки, которое
следующий контрибьютор нечаянно меняет обычным добавлением, а явный отказ виден и
проверяем.

Тот же смысл на стороне транскодирования REST: там есть свои проверки внутренних
маршрутов и отдельные пробы на форму отказа и на изоляцию внешнего слушателя.

## Класс методов остаётся закрытым

Резолвер определяет домен по строке метода. Незамапленный метод — **отказ**, а не
догадка; и решение «этот метод внутренний» не выводится из имени эвристикой, а
задаётся перечнем. Эвристика по имени однажды уже давала пропуск любому новому
методу, попавшему под шаблон, — и в диффе это выглядело обычной фичей
(см. [[corelib-authz]]).

## См. также

[[apigw-restmux]] [[apigw-cmd]] [[apigw-opsproxy]] [[apigw-allowlist]]

#packages #kacho-apigw #proxy #grpc
