---
title: corelib-validate
category: packages
repo: kacho-corelib
path: pkg/validate
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - validation
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/validate — общие валидаторы полей

**Каталог**: `pkg/validate/` · импорт `github.com/PRO-Robotech/kacho/pkg/validate`
**Прежде** (полирепо): `kacho-corelib/validate`. Тег `kacho-corelib` здесь означает
**домен общего фундамента**, а не отдельный репозиторий: разработка идёт в монорепо
`PRO-Robotech/kacho`, прежний репозиторий не развивается с середины июля 2026.
**Импортирует**: `net`, `os`, `regexp`, `strings`, `unicode/utf8`, `grpc/codes`,
`grpc/status`, `pkg/errors`, `pkg/ids`.
**Импортируют** (`go list ./...` на ревизии `96b2879a`, non-test): vpc 14 · iam 7 ·
storage 5 · nlb 5 · registry 4 · compute 4 · geo 2 · gateway 1 · `pkg/operations` 1.

Каждый валидатор возвращает готовую gRPC-ошибку `InvalidArgument` с
`BadRequest.field_violations[]` через [[corelib-errors]] — кроме `ResourceID`,
который по контракту отдаёт **flat-message** (см. ниже).

## Экспортируемое API (снято с дерева, не по памяти)

```go
func Name(field, value string) error          // строгая политика имени
func NameVPC(field, value string) error       // Network/Subnet/Address/RouteTable
func NameCompute(field, value string) error   // Disk/Image/Snapshot/Instance
func NameGateway(field, value string) error
func Description(field, value string) error
func Labels(field string, labels map[string]string) error
func ResourceID(resourceType, expectedPrefix, id string) error
func UpdateMask(field string, mask []string, known map[string]struct{}) error
func PageSize(field string, value int64) (int64, error)
func IPAddress(field, value string) error
func ZoneId(field, value string) error
func DdosProvider(field, value string) error
func DhcpDomainName(field, value string) error
func SmtpCapability(field, value string) error

const MaxNameLen = 63; MaxDescriptionLen = 256; MaxLabels = 64
const MaxLabelKeyLen = 63; MaxLabelValueLen = 63
const MaxPageSize int64 = 1000; DefaultPageSize int64 = 50
const EnvExtraResourceIDPrefixes       = "KACHO_EXTRA_RESOURCE_ID_PREFIXES"
const EnvExtraResourceIDHyphenPrefixes = "KACHO_EXTRA_RESOURCE_ID_HYPHEN_PREFIXES"
```

`ZoneId`/`SmtpCapability` несут `//nolint:revive`: имена стабильны и потребляются
сервисами, переименование было бы ломающим изменением.

## Три разных regex имени — это контракт, а не разнобой

- `Name` — `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`: строчные, начинается с буквы, не
  оканчивается дефисом, длина 1..63; одиночная буква валидна.
- `NameVPC` — `^([a-zA-Z]([-_a-zA-Z0-9]{0,61}[a-zA-Z0-9])?)?$`: **допускает пустое
  имя, заглавные и подчёркивание**.
- `NameCompute` — то же, но **без заглавных**.

Пустое имя у VPC/Compute — валидное значение, поэтому обязательность имени там, где
она нужна, проверяется **отдельно** вызывающим. Прежняя редакция записки приводила
один общий regex `^[a-z][-a-z0-9]{1,61}[a-z0-9]$` — он не совпадает ни с одним из
трёх и вдобавок отвергал бы одиночную букву.

## `PageSize` — отвергает, а не подрезает

```go
if value < 0 || value > MaxPageSize {  // → InvalidArgument
    "<field> must be in [0..1000] (0 means default)"
}
if value == 0 { return DefaultPageSize }
```

Это существенно: `page_size` вне диапазона — **ошибка**, а не молчаливый clamp
(`api-conventions.md` §Pagination). Прежняя редакция утверждала «clamp + default» —
неверно на момент замера. Отдельно к порядку: этот гейт обязан отработать **до**
короткого замыкания списка по пустому гранту, иначе мусорный курсор при нулевых
правах уедет в пустую страницу вместо `400`.

## `ResourceID` — family-agnostic по контракту, пустую строку пропускает

Две принимаемые формы (B3, редизайн 2026):

- legacy слитная `<prefix><17-crockford-base32>` — первые 3 символа ∈ каталога;
- going-forward `<prefix>-<crockford-base32>` — сегмент до первого дефиса ∈ каталоге
  дефисных префиксов.

Крокфордово тело дефиса не содержит, поэтому дефис — однозначный дискриминатор
новой формы, а классификация строго **аддитивна**: приём hyphen-формы ничего не
отзывает у legacy.

Два свойства, на которых уже обжигались и которые godoc проговаривает явно:

1. **`expectedPrefix` не читается.** Проверяется лишь членство префикса в
   платформенном каталоге (`ids.KnownPrefixes`/`KnownHyphenPrefixes` + env-добавки).
   Параметр документирует call-site, а не навязывает сверку: id чужого семейства
   обязан дойти до `repo.Get` и получить `NotFound`, а не быть отбитым здесь. Именно
   на это свойство опирается задокументированное исключение «синтаксический gate на
   чужой ссылке» (`api-conventions.md` §By-lane code-split).
2. **Пустая строка ПРОПУСКАЕТСЯ.** Required-проверка — отдельная ответственность
   вызывающего. Иначе пустое значение уезжает в peer-полосу и возвращается
   контракт-тоном отсутствия ресурса с вырезанным id — утверждение о ресурсе,
   которого вызывающий не называл.

Ошибка — готовый `status` с flat-message `"invalid <resourceType> id '<id>'"`, не
field-violation: этого требует контракт тона.

## Расширение каталога префиксов без релиза фундамента

`EnvExtraResourceIDPrefixes` / `EnvExtraResourceIDHyphenPrefixes` — env-добавка к
каталогу для нового домена. Единый источник самих префиксов — [[corelib-ids]].

## См. также

[[corelib-errors]] [[corelib-ids]] [[vpc-domain]]

#packages #kacho-corelib #validation
