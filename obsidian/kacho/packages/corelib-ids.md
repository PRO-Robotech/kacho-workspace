---
title: corelib-ids
category: package
repo: kacho-corelib
path: pkg/ids
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - ids
---

# pkg/ids — генератор и каталог префиксов идентификаторов

**Каталог**: `pkg/ids/` · импорт `github.com/PRO-Robotech/kacho/pkg/ids`
**Прежде** (полирепо): `kacho-corelib/ids`.
**Импортирует**: `crypto/rand`, `encoding/binary`, `os`, `strings`.
**Импортируют** (`go list` на `96b2879a`, non-test): iam 11 · vpc 10 · nlb 6 ·
storage 3 · registry 3 · compute 3 · gateway 1 · `pkg/validate` 1 ·
`pkg/operations` 1.

Идентификатор — **единственная внешне-адресуемая** идентичность ресурса
(core §Non-negotiables, п. 15): он попадает в публичные URL и пути выкачки, в
межсервисные ссылки, в область гранта и в цель проверки прав; он неизменяем на всю
жизнь ресурса и глобально уникален by construction. Человекочитаемое имя —
косметическая метка в пределах проекта и в адресацию не попадает никогда.

## Экспортируемое API (снято с дерева)

```go
func NewID(prefix string) string          // legacy слитная форма: <prefix><17 crockford-base32>
func NewHyphenID(prefix string) string    // going-forward: <prefix>-<crockford-base32>
func NewUID() string                      // без префикса (курсоры, ключи идемпотентности)
func IsValid(id, prefix string) bool
func HasKnownPrefix(id string) bool       // строгая форма: длина + 3-символьный префикс + алфавит тела
func KnownPrefixes() map[string]struct{}
func KnownHyphenPrefixes() map[string]struct{}
```

`KnownPrefixes`/`KnownHyphenPrefixes` — **единый источник** каталога; расширение под
новый домен без релиза фундамента идёт через env-добавку, которую читает
[[corelib-validate]].

> [!warning] Список префиксов в этой записке был неверен целиком
> Прежняя редакция называла `PrefixNetwork = "enp"`, `PrefixSubnet = "e9b"`,
> `PrefixAddress = "e9a"`, `PrefixInstance = "ef3"`, `PrefixDisk = "ef4"`, а также
> имена `PrefixSG`/`PrefixNI`/`PrefixPE`. В дереве нет **ни одного** из этих значений
> и ни одного из этих имён. Это опаснее пустого места: контрибьютор, сверявший id
> по записке, получил бы «префикс не совпал» и пошёл бы искать дефект в коде.
> Ниже — значения на ревизии `96b2879a`; при расхождении верен `pkg/ids/ids.go`.

## Действующие префиксы (по дереву, `96b2879a`)

| Домен | Константы |
|---|---|
| vpc | `PrefixNetwork "net"` · `PrefixSubnet "sub"` · `PrefixAddress "adr"` · `PrefixRouteTable "rtb"` · `PrefixSecurityGroup "sgr"` · `PrefixGateway "gtw"` · `PrefixNetworkInterface "nic"` · `PrefixAddressPool "apl"` · `PrefixAnycastPool "aap"` |
| compute (legacy-дубль) | `PrefixInstance "epd"` · `PrefixDisk "epd"` · `PrefixImage "fd8"` · `PrefixSnapshot "fd8"` |
| storage | `PrefixVolume "vol"` · `PrefixStorageSnapshot "snp"` · `PrefixStorageImage "img"` |
| nlb | `PrefixLoadBalancer "nlb"` · `PrefixListener "lst"` · `PrefixTargetGroup "tgr"` |
| registry | `PrefixRegistry "reg"` · `PrefixOperationReg "rop"` |
| прочее | `PrefixApplication "app"` · `PrefixCloud`/`PrefixFolder "b1g"` · `PrefixOrganization "bpf"` |
| корни операций | `PrefixOperationVPC "enp"` · `PrefixOperationApps "aop"` · `PrefixOperationStorage "sop"` · `PrefixOperationCompute`/`NLB`/`RM` — алиасы соответствующих ресурсных |
| дефисные (B3) | `PrefixMachineTypeHyphen "mt"` · `PrefixInstanceHyphen "ins"` · `PrefixInteractiveClientHyphen "ic"` |

Совпадения значений — намеренные: `PrefixInstance` и `PrefixDisk` делят `epd`, как и
`PrefixImage` с `PrefixSnapshot` — `fd8`; `PrefixCloud` и `PrefixFolder` — `b1g`.
Это не опечатка записки, а состояние дерева: **тип ресурса по префиксу однозначно
не восстанавливается**, и никакая проверка не вправе на это закладываться.

## Две формы и почему приём аддитивен

Слитная форма — legacy и остаётся валидной; дефисная (`ins-…`, `mt-…`, `ic-…`) —
going-forward, сервисы мигрируют свой префикс поодиночке. Крокфордово тело дефиса не
содержит, поэтому дефис — однозначный дискриминатор. Существенно: **генерация ещё не
мигрирована** — `NewID` продолжает эмитить слитную форму, а `NewHyphenID` заведён
вперёд миграции сервисов, чтобы маршрутизатор уже принимал обе.

## `HasKnownPrefix` строже, чем `validate.ResourceID`

`HasKnownPrefix` требует точной длины, трёхсимвольного префикса из каталога и
корректного алфавита тела — это приёмка на крае без знания типа ресурса.
`validate.ResourceID` мягче (family-agnostic, пустую строку пропускает) и живёт на
входе RPC. Разные предикаты — разные места; не подменять один другим.

## См. также

[[corelib-validate]] [[corelib-operations]]

#packages #kacho-corelib #ids
