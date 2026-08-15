---
title: kacho-vpc (сегодня — каталог services/vpc/ монорепо)
aliases:
  - kacho-vpc
category: legacy
repo: kacho-vpc
service_type: control-plane
domain: vpc
status: legacy
tags:
  - kacho
  - kacho-vpc
  - control-plane
  - grpc
  - cqrs
  - legacy
---

# kacho-vpc — сегодня это `services/vpc/` в монорепо

> [!warning] Предмет записки — отдельный репозиторий — существует, но разработка в нём не ведётся
> Сервис живёт в **`services/vpc/`** монорепо `PRO-Robotech/kacho`. Записка сохранена как
> точка перехода: входящих ссылок у неё **7** — больше, чем у любой другой записки этого
> ряда. Именно поэтому её нельзя было ни удалить, ни переименовать механически: половина
> утверждений прежней редакции разошлась с деревом, и подстановка нового пути превратила бы
> их из очевидно устаревших в уверенно неверные.

## Публичные ресурсы и их id-префиксы (замер `kacho@96b2879a` по `pkg/ids/ids.go`)

| Ресурс | Префикс id | Комментарий |
|---|---|---|
| Network | `net` | контейнер подсетей |
| Subnet | `sub` | EXCLUDE на пересечение CIDR, авто-привязка к RouteTable (DB-триггер) |
| Address | `adr` | внешний/внутренний, v4/v6; IPAM-выдача внутри сервиса |
| RouteTable | `rtb` | статические маршруты + `AddRoutes`/`RemoveRoutes`/`UpdateRoute` |
| SecurityGroup | `sgr` | правила + OCC через `xmin` |
| Gateway | `gtw` | только shared-egress; строгое имя (`NameGateway`) |
| NetworkInterface | `nic` | first-class ресурс, отдельный от инстанса |
| AddressPool | `apl` | **админский**, только на внутреннем порту `:9091` |

> [!important] Прежняя таблица префиксов была неверна целиком
> В ней стояли `enp` и `e9b`, причём **по два-три ресурса на один префикс** — то есть по
> id нельзя было прочитать тип, ради чего префикс и существует. Ни одного из этих двух
> значений в `pkg/ids/` нет. Это ровно тот случай, ради которого волна запрещает
> механическую замену имён: путь `kacho-vpc` → `services/vpc` подставить легко, а таблица
> под ним осталась бы ложной и выглядела бы свежей.

Форма id: legacy — слитная `<prefix><17-base32>`; going-forward канон — дефисная
`<prefix>-<crockford-base32>`, где префикс бывает 2-символьным. Генерация ещё не
мигрирована, роутер принимает **обе** формы. Канон — `.claude/rules/api-conventions.md`.

## Чего в дереве НЕТ, а прежняя редакция называла действующим

- **`PrivateEndpoint`** — ноль файлов по этому имени в `proto/` и `services/vpc/`. Ресурс,
  каталог use-case'а и упоминание в заголовке сервиса сняты.
- **Ребро `vpc → compute` ради валидации зоны.** Geography вынесена в **`geo`** (эпик #82):
  `Subnet`/`AddressPool` валидируют `zone_id` через `geo.v1.ZoneService.Get`. Прежнее
  «→ kacho-compute: ZoneService.Get (после KAC-15)» описывает ребро, которого нет, — и
  правило `polyrepo.md` прямо называет его **ложным**.
- **`kacho-vpc-implement` как дом data-plane** — репозиторий в дереве не представлен;
  `kacho-vpc-operator` вдобавок не резолвится на GitHub (404).
- **`InternalWatchService` у vpc** — единственный `rpc Watch` в дереве живёт в
  `compute/v1/internal_watch_service.proto`, не в vpc.
- **Определение сервиса через «стилистику чужого облака»** снято: конвенции Kachō —
  собственные (запрет #2), и описывать их через чужой продукт значит нарушать запрет в
  той самой строке, которая его объясняет. То же касается «ENI-подобности» интерфейса:
  верное здесь — что `NetworkInterface` **first-class ресурс, отдельный от инстанса**, и
  это утверждение о нашей модели, а не о чужой.

## Что осталось верным и полезным

- **`services/vpc` — эталон нескольких tree-wide свойств.** Порядок «проверка формата
  пагинации → резолв прав → короткое замыкание пустого гранта» реализован в **7 из 7**
  списочных хендлеров и заперт пробой `TestListPaginationFormatCheckedBeforeIdentityShortCircuit`;
  свойство всего дерева держит AST-гейт `internal/repohygiene`. Ссылки на vpc как на эталон
  в `security.md` и `api-conventions.md` — про это.
- **Раскладка слоёв** (`domain/` → `apps/kacho/api/<ресурс>/` → `repo/` + `clients/` →
  `handler/`, composition root в `cmd/`) держится и сегодня; канон — `architecture.md`,
  Go-стиль — скил `evgeniy`.
- Снятое в KAC-266 (`Move`/`Relocate`, `AttachToInstance`/`DetachFromInstance`,
  `InternalCloudService`, `:check`/`:explainResolution`, per-address override) снято и
  сегодня — см. [[../KAC/KAC-266]].
- AddressPool получил `AddCidrBlocks`/`RemoveCidrBlocks` и перестал менять состав CIDR
  через `Update` — см. [[../KAC/KAC-269]].

Соседние `dependencies.md`, `resources.md` и `patterns/api-network-subnet.md` **удалены**:
входящих ссылок у каждого ноль. Первые два описывали граф зависимостей и ресурсы полирепо;
третий — снимок формы кода на май (49 КБ, при потолке записки 1-3 КБ), где часть
описанного уже не существует (`MoveNetworkUseCase`, авторизация по владению папкой), а
форма кода как предмет принадлежит скилу `godzila`, а не vault.

## См. также

- [[../README|vault hub]] · [[../architecture|архитектура]] · [[../KAC/KAC-266]] · [[../KAC/KAC-269]]
- `.claude/rules/architecture.md` — слои и dependency rule
- `.claude/rules/data-integrity.md` — DB-инварианты, placement-когерентность

#kacho #kacho-vpc #control-plane #grpc #cqrs #legacy
