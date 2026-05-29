# kacho-ui — единый лайаут детализации ресурсов + формы-панели (design)

**Date**: 2026-05-29
**Status**: approved (brainstorming) — pending implementation plan
**Epic**: KAC (см. YouTrack tracking-issue)
**Repo**: kacho-ui
**Заменяет конвенцию**: `kacho-ui/CLAUDE.md §3` (Create/Edit строго через модалки, без `/create`·`/edit` routes) → формы-панели + уникальные URI.

## 1. Проблема / цель

UI сейчас разнороден: generic `ResourceListPage`/`ResourceDetailPage` + ~8 кастомных detail-страниц (Network/Subnet/SG/NIC/RT/Address/Instance/TargetGroup), формы — модалки (`ResourceFormModal` + `GlobalResourceFormModal`, открытие через `?modal=`). Нет единого паттерна детализации, связанные ресурсы показываются по-разному, у форм нет своего URI.

**Цель**: единый, максимально переиспользуемый лайаут для всех ресурсов всех доменов (IAM/VPC/Compute/NLB): 3-зонный shell, табы, формы как расширение страницы (правая зона), уникальный URI на каждую страницу.

## 2. Решения (зафиксированы в brainstorming)

- **Подход**: registry-driven `<ResourceShell>` + `<FormPanel>` + слоты для спец-кейсов (verb-кнопки/виджеты) — как нынешний `secondaryActions`. (Вариант A.)
- **Форма — всегда правая зона**:
  - из списка (sidebar | таблица) → `create` → **sidebar | таблица | ФОРМА** (таблица остаётся).
  - из detail (sidebar | табы | инфо) → `edit` / `create связного` → **sidebar | табы | ФОРМА** (форма заменяет инфо; инфо возвращается при закрытии).
- **Табы зоны 2**: **Обзор / JSON / Связанные** (+ опц. per-resource: Operations; у NLB-TG «Targets»).
- **Связанные** = таб со списком встроенных таблиц (тот же `<ResourceTable>`, что на списке) + кнопка «Создать» (→ форма-панель) + клик по строке → detail того ресурса.
- **Каждая страница — уникальный URI** (path-сегменты, не `?tab=`).
- **Фазинг**: фреймворк + 1 эталон (**VPC Network**) end-to-end → апрув → миграция по доменам (VPC остальное → Compute → IAM → NLB), каждый — свой PR.

## 3. URI-схема

```
LIST              /projects/:pid/<mod>/<res>
LIST + create     /projects/:pid/<mod>/<res>/create
DETAIL (Обзор)    /projects/:pid/<mod>/<res>/:id
DETAIL JSON       /projects/:pid/<mod>/<res>/:id/json
DETAIL Связанные  /projects/:pid/<mod>/<res>/:id/related
DETAIL + edit     /projects/:pid/<mod>/<res>/:id/edit
CREATE связного   /projects/:pid/<mod>/<res>/:id/<child>/create
```
(account-scoped IAM-ресурсы — аналогично, но `/accounts/:aid/...` где применимо.)

## 4. Зоны (`<ResourceShell>`)

```
СПИСОК:                 DETAIL:                  DETAIL+форма:
┌────┬─────────┐        ┌────┬────┬──────┐       ┌────┬────┬──────┐
│side│ таблица │        │side│табы│ инфо │       │side│табы│ФОРМА │
│bar │ [+созд] │        │bar │Обз │(таб) │       │bar │Обз │edit/ │
└────┴─────────┘        │    │JSON│      │       │    │JSON│create│
 (+create→+форма)       │    │Связ│      │       └────┴────┴──────┘
                        └────┴────┴──────┘
```
- **Зона 1** — текущий сайдбар (`src/lib/service-modules.tsx` + `Layout`). Не меняем.
- **Зона 2** — табы (Обзор/JSON/Связанные + extra). Управляется URL-сегментом.
- **Зона 3** — контент активного таба ИЛИ форма (по URL: `/edit`, `/create`, `/<child>/create`).

## 5. Компоненты (переиспользование = главный критерий)

| Компонент | Роль |
|---|---|
| `<ResourceShell spec slots?>` | 3-зонный каркас; рулит зоной 2/3 по URL; один на все ресурсы |
| `<FormPanel spec mode>` | замена `ResourceFormModal`: тот же field-driven рендер (`FormField`/`spec.fields`/`sanitize`/`hydrate`/Operation-polling), контейнер = правая зона |
| `<ResourceTable spec>` | существует; один и на списке, и встроенный в таб «Связанные» (= «синхронизация вида») |
| Таб «Связанные» | из `spec.related[]` рендерит N `<ResourceTable>` + «Создать» |
| Таб JSON | сырой ресурс (read-only) |
| слоты (`secondaryActions`-стиль) | verb-кнопки/виджеты (disk attach, NLB targets, Start/Stop) |

## 6. Registry (единый источник истины)

`ResourceSpec` (в `src/lib/resource-registry.tsx`) расширяется:
- `tabs?: TabDef[]` — дефолт `[Обзор, JSON, Связанные]` + per-resource extra (`operations`, `targets`).
- `related?: { specId: string; filterField: string }[]` — встроенные таблицы таба «Связанные» (напр. `networks.related = [{subnets, network_id}, {route-tables, network_id}, {security-groups, network_id}, {gateways, network_id}]`).
- Существующие `columns/fields/template/sanitize/hydrate/apiPath/payloadKey` — переиспользуются как есть.

## 7. Эталон-миграция: VPC Network

- `NetworkDetailPage` (кастомная) → `<ResourceShell spec=networks>` (+ слоты, если нужны).
- `networks.related = [subnets, route-tables, security-groups, gateways]`.
- edit Network → `<FormPanel>` на `/networks/:id/edit`.
- создание дочерних (Subnet/RT/SG) из таба «Связанные» → `<FormPanel>` на `/networks/:id/<child>/create`.
- **Критерий паритета**: кастомная `NetworkDetailPage` удалена, всё поведение выражено фреймворком.

## 8. Конвенции / cleanup

- Переписать `kacho-ui/CLAUDE.md §3`: модалки → form-panel + уникальные URI (формы появляются в правой зоне, два кейса из §2).
- `ResourceFormModal` / `GlobalResourceFormModal` → deprecated; удаляются после миграции ВСЕХ доменов (на время перехода фреймворк сосуществует с модалками).
- Vault: новые `packages/ui-*` записи для `ResourceShell`/`FormPanel`; обновить per-resource при миграции.

## 9. Тестирование (TDD, обязательно)

- **vitest** на каждый новый компонент: `<ResourceShell>` (рендер зон/табов по URL), `<FormPanel>` (create/edit submit → правильный wire-payload, Operation-polling, ошибка не закрывает форму), таб «Связанные» (рендер встроенных таблиц из `related`), URI-routing (каждый URL → правильная зона/режим).
- **Эталон Network**: компонентные тесты detail+табы, related-таблицы, edit-форма, create-дочернего — RED→GREEN.
- Существующие 126 тестов остаются зелёными (миграция не ломает поведение).

## 10. Acceptance (Given-When-Then) — отдельный док (гейт §1)

Полный GWT — `docs/specs/sub-phase-X.Y-ui-unified-layout-acceptance.md` (acceptance-author → acceptance-reviewer APPROVE до кодинга, per workspace CLAUDE.md «Запреты» #1). Ключевые сценарии: URI→зона, форма-панель create/edit, связанные таблицы + create-дочернего, паритет Network, отсутствие регрессий.

## 11. Декомпозиция (эпик → subtasks, порядок)

1. **Framework**: `ResourceShell` + `FormPanel` + registry `tabs`/`related` + URI-routing helpers + tests. (без миграции ресурсов)
2. **Reference**: VPC Network на фреймворк (удалить `NetworkDetailPage`) + tests + стенд-проверка.
3. **Migrate VPC**: Subnet / SecurityGroup / RouteTable / Address / NIC / Gateway / AddressPool.
4. **Migrate Compute**: Instance / Disk / Image / Snapshot.
5. **Migrate IAM**: Account / Project / User / SA / Group / Role / AccessBinding.
6. **Migrate NLB**: NetworkLoadBalancer / Listener / TargetGroup (включая Targets-слот KAC-230).
7. **Cleanup**: удалить `ResourceFormModal`/`GlobalResourceFormModal`; финализировать `CLAUDE.md §3`.

Каждый пункт — отдельный KAC-subtask + PR. Acceptance-гейт перед кодингом фазы 1-2.

## 12. Out of scope

- Редизайн визуальной палитры/типографики (остаётся YC-style §4.6).
- Изменение backend/proto/API (чисто UI-слой).
- Мобильная адаптация 3-зон (на узких экранах — стек/драверы — отдельная фаза, не сейчас).
