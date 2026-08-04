---
title: corelib-errors
category: packages
repo: kacho-corelib
path: pkg/errors
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - errors
  - grpc
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/errors — типизированный билдер gRPC-ошибок

**Каталог**: `pkg/errors/` · импорт `github.com/PRO-Robotech/kacho/pkg/errors`
(в сервисах обычно под алиасом `coreerrors`).
**Прежде** (полирепо): `kacho-corelib/errors`.
**Импортирует**: `google.golang.org/genproto/googleapis/rpc/errdetails`, `grpc/codes`,
`grpc/status`.
**Импортируют** (`go list` на `96b2879a`, non-test): nlb 2 · registry 1 · compute 1 ·
`pkg/validate` 1 · `pkg/operations` 1.

> [!note] Прямых потребителей мало — но пакет не узкий
> Большинство сервисов доходит сюда **транзитивно**, через [[corelib-validate]]:
> валидатор строит свою ошибку этим билдером. Считать востребованность по числу
> прямых импортов здесь неверно — предикат врёт в меньшую сторону.

## Экспортируемое API (снято с дерева)

```go
func NotFound(kind, id string) *Builder        // "<Kind> <id> not found"
func AlreadyExists(kind, id string) *Builder
func InvalidArgument() *Builder                // дефолтный message "invalid argument"
func FailedPrecondition(msg string) *Builder
func Aborted(msg string) *Builder              // CAS-конфликты
func Unavailable(msg string) *Builder          // peer недоступен, fail-closed мутации
func Internal(msg string) *Builder

func (b *Builder) AddFieldViolation(field, desc string) *Builder
func (b *Builder) WithLocale(locale string) *Builder
func (b *Builder) Err() error
```

Финализатор — **`Err()`**. Прежняя редакция называла `.Field(...)`, `.Build()`,
`.Status()` и билдер `Gone(msg)`; ни одного из этих имён в дереве нет — записка
пережила свой предмет, а пример кода из неё не скомпилировался бы.

## Тон сообщений — часть контракта, а не косметика

`"<Resource> %s not found"`, `"<field> is immutable after <Resource>.Create"`,
`"Illegal argument <thing>"`, `"network is not empty"`. Тексты меняются только
осознанно, через тикет: на них завязаны e2e-утверждения и, важнее, byte-identity
скрытия существования — текст отказа в доступе обязан **дословно** совпадать с
настоящим ответом владельца об отсутствии, иначе само различие становится способом
отличить «нет доступа» от «нет ресурса» (`security.md` §Hardening-инварианты, п. 6).

Отсюда же понятно, почему `NotFound(kind, id)` принимает **и** вид ресурса, **и**
id: форма сообщения фиксирована конструкцией, а не собирается заново каждым
вызывающим.

> [!note] Здесь стоял раздел про паритет с чужим облаком — он снят
> Прежняя редакция объясняла форму сообщений совместимостью с чужим облаком (называя
> его сокращением в четырёх местах) и ссылалась на строку воркспейса, которой там
> больше нет. Конвенции Kachō —
> собственные (core §Non-negotiables, п. 2: никаких упоминаний чужих облаков), а
> стабильность тона обоснована тем, что на него опирается скрытие существования, а
> не чьим-то паритетом.

## Дефолтная ветка маппера — фиксированный текст

`Internal(msg)` вызывается с **определённым** текстом. Эхо `err.Error()` в
`codes.Internal` запрещено: незамапленная ошибка драйвера уносит наружу параметры
подключения. Регрессия на такой фикс утверждает **сообщение**, а не только код
(`testing.md` §Regression-lock).

## См. также

[[corelib-validate]] [[vpc-apps-kacho-shared-serviceerr]]

#packages #kacho-corelib #errors #grpc
