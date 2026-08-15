---
title: api-gateway-middleware-authz
aliases:
  - apigw authz middleware
  - per-rpc authz
category: packages
repo: kacho-api-gateway
path: gateway/internal/middleware
layer: middleware
status: stable
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-api-gateway
  - middleware
  - authz
  - fga
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# Проверка прав на крае — по каталогу, а не по имени метода

**Где живёт**: `gateway/internal/middleware/` — файлы `authz.go`, `authz_cache.go`,
`authz_metrics.go`, `authz_overrides.go`, `authz_public_allowlist.go`,
`authz_util.go`, `permission_catalog.go`, `permission_catalog_embed.go`,
`permission_denied_response.go`. **Отдельного подпакета `authz` нет** — всё в общем
пакете middleware.

> [!warning] Прежняя редакция описывала проект, а не реализацию
> Записка была помечена «планируется» и описывала выведение глагола из имени метода
> отдельным реестром, разбор объекта по форме запроса и **мягкий проход на чтении**
> как настраиваемую политику. Реализация пошла иначе по всем трём пунктам, а
> названные типы, файл реестра и шесть переменных окружения из её таблицы в дереве
> отсутствуют. Мягкий проход на чтении вдобавок противоречит норме: ошибка проверки
> прав — **fail-closed**, недоступный ответ модели не есть «да».

## Экспортируемое API (снято с дерева)

```go
type AuthzMiddlewareConfig struct{ ... }
func NewAuthzMiddleware(cfg AuthzMiddlewareConfig) (*AuthzMiddleware, error)
func (m *AuthzMiddleware) Unary() grpc.UnaryServerInterceptor
func (m *AuthzMiddleware) Stream() grpc.StreamServerInterceptor
func (m *AuthzMiddleware) HTTP(next http.Handler) http.Handler
func (m *AuthzMiddleware) Metrics() *AuthzMetrics
func (m *AuthzMiddleware) Reload() error
func (m *AuthzMiddleware) InvalidateCache()
func (m *AuthzMiddleware) MaybeFlushOnMutation(fqn string, httpStatus int)
func (m *AuthzMiddleware) AsInvalidator() AuthzInvalidator
type AuthorizeChecker interface{ ... }   // порт к проверке прав
type RestRouteResolver interface{ ... }  // путь REST → полное имя метода
```

Три поверхности (`Unary`, `Stream`, `HTTP`) — не дублирование: край принимает и
gRPC, и REST, и пропуск одной из них сделал бы её обходом другой.

## Решение принимает КАТАЛОГ

`permission_catalog.go` — запись на метод: требуемое отношение, извлечение области
(`ScopeExtractor`), признак освобождения (`IsExempt`), признак скрытия существования
при отказе (`HidesExistenceOnDeny`). Каталог **генерируется** из контрактов, встроен
в двоичный файл, и обе встроенные копии (у края и в первичной загрузке домена прав)
обязаны быть побайтово равны — гейт роняет сборку при расхождении.

Отсутствие записи о выставленном методе — **отказ** в рантайме, а не пропуск.

### Извлечение области — это анти-BOLA, а не удобство

Для метода, оперирующего конкретным объектом по идентификатору из запроса, проверка
идёт **против целевого объекта**, а не только против права на метод. Иначе
вызывающий, имеющий право на метод вообще, дотягивается до чужого объекта.

### Скрытие существования обязано быть побайтово неотличимо

Когда край прячет неавторизованный доступ под «не найдено», текст обязан **дословно**
совпадать с настоящим ответом владельца об отсутствии. Любой различимый текст — это
способ отличить «нет доступа» от «не существует», то есть ровно то, что скрытие
закрывало (`security.md` §Hardening-инварианты, п. 6).

## Кэш вердиктов — окно отзыва, а не оптимизация

Кэшируются положительные вердикты, поэтому свежая **выдача** видна сразу, а **отзыв**
ждёт истечения записи. Отсюда `InvalidateCache`, `MaybeFlushOnMutation` (сброс после
мутаций, меняющих субъект) и `AsInvalidator`. Срок жизни записи **и есть** окно
отзыва — объявленный параметр безопасности, а не сумма умолчаний ([[corelib-authz]]).

## См. также

[[api-gateway-middleware-dpop]] [[apigw-middleware]] [[corelib-authz]]
[[../rpc/iam-authorize-service]] [[../edges/api-gateway-to-iam-authorize]]
[[../KAC/KAC-127]]

#packages #kacho-api-gateway #middleware #authz #fga
