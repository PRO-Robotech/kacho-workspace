# VPC Newman: единый suite для Kachō и Yandex Cloud — design

**Дата:** 2026-05-05
**Scope:** `kacho-vpc/newman/`
**Стартовый домен:** Network
**Статус:** draft

## Goal

Один и тот же набор Postman/Newman-кейсов VPC-домена должен идентично исполняться:
- против локального Kachō (`--env local`),
- против реального Yandex Cloud VPC API (`--env yc`).

Единственное допустимое расхождение между запусками — наличие в YC pre-allocated `Organization / Cloud / Folder`. Внутри VPC (Network / Subnet / Address / RouteTable / SecurityGroup / Gateway / PrivateEndpoint) поведение тестов идентично.

## Non-goals

- Изменение коллекции `kacho-test/` (RM / Operations / cross-cutting) — вне scope.
- Параллельные runs против одного YC-folder — не поддерживаем.
- xfail-маркировка / условные assertions — запрещены (см. §5).

## Architecture

### Структура коллекции `kacho-vpc.postman_collection.json`

```
Kachō VPC QA Suite (unified)
├─ 00-preflight                     ← всегда первая
│   ├─ pf.gen-runId                 (Math.random → runId)
│   ├─ pf.setup-org      [skip if existingFolderId]
│   ├─ pf.setup-cloud    [skip if existingFolderId]
│   ├─ pf.setup-folder   [skip if existingFolderId]
│   └─ pf.export-suite-vars         (set _suiteOrgId / _suiteCloudId / _suiteFolderId)
│
├─ NET-CR-OK
├─ NET-CR-NAME-MAX
├─ NET-CR-NAME-OVER
├─ NET-CR-LABELS-MAX / -LABELS-OVER
├─ NET-CR-DESC-MAX / -DESC-OVER
├─ NET-CR-EMPTY-FOLDER
├─ NET-CR-DUP-NAME
├─ NET-CR-MISSING-FOLDER
├─ NET-CR-INVALID-FOLDER
├─ NET-CR-EMPTY-NAME
├─ NET-GET-NOTFOUND / -INVALID-FORMAT
├─ NET-LIST / -LIST-FILTER / -LIST-PS-NEG / -LIST-PS-ONE / -LIST-PT-INVALID
├─ NET-LIST-PAGE-TOKEN-LEAK
├─ NET-LIST-OPS / -LIST-SUBNETS-EMPTY / -LIST-SG-DEFAULT / -LIST-RT-EMPTY
├─ NET-UP-NAME / -PATCH-CLEAR-DESC / -PATCH-NOOP / -PATCH-NAME-EMPTY-OK
├─ NET-DESC-UP-OVER
├─ NET-UPDATE-MASK-UNKNOWN
├─ NET-DEL-WITH-SUBNETS
├─ NET-DEFAULT-SG-AUTO
│   ↑ Network domain: ~25 unified кейсов после дедупликации YC-NET-* ↔ N-*
│
└─ 99-teardown                      ← всегда последняя
    ├─ td.cleanup-folder  [skip if existingFolderId]
    ├─ td.cleanup-cloud   [skip if existingFolderId]
    └─ td.cleanup-org     [skip if existingFolderId]
```

Subnet / Address / RouteTable / SG / Gateway / PrivateEndpoint — следующие итерации, тот же шаблон.

### Variable convention

| Переменная | Источник | Использование |
|---|---|---|
| `existingOrgId` / `existingCloudId` / `existingFolderId` | env-файл | YC-env содержит pre-allocated значения; local-env — пусто |
| `_suiteOrgId` / `_suiteCloudId` / `_suiteFolderId` | preflight выставляет | используется во всех VPC-кейсах |
| `runId` | preflight (Math.random.slice 6) | префикс уникальных имён `qa-{{runId}}-net-cr-ok` |
| `<caseId>_<resource>Id` | per-case test-script | временное состояние конкретного кейса (`ncrok_netId`, `ncrok_opId`) |

Префикс `_` у `_suite*` — маркер «collection-managed». Заглавный `runId` — потому что используется в шаблонах request body и совместим с прежней практикой.

## Preflight contract

Pre-request hook на каждом setup-шаге (`pf.setup-org`, `pf.setup-cloud`, `pf.setup-folder`):

```js
if (pm.environment.get('existingFolderId')) {
  pm.environment.set('_suiteOrgId',    pm.environment.get('existingOrgId')    || '');
  pm.environment.set('_suiteCloudId',  pm.environment.get('existingCloudId')  || '');
  pm.environment.set('_suiteFolderId', pm.environment.get('existingFolderId') || '');
  if (pm.execution && pm.execution.skipRequest) pm.execution.skipRequest();
}
```

Иначе шаги выполняются последовательно: POST org → poll op → POST cloud → poll op → POST folder → poll op. Каждый test-script сохраняет id в env (`_suiteOrgId` etc).

Финальный шаг `pf.export-suite-vars` — sanity-проверка:

```js
pm.test('preflight produced suite folder', () => {
  pm.expect(pm.environment.get('_suiteFolderId')).to.match(/^[a-z0-9]{20}$/);
});
```

`pf.gen-runId` выставляет `runId = (Date.now() + Math.random()).toString(36).slice(-6)` — короткий, чтобы укладываться в YC name limit 63.

## Teardown contract

Симметричный hook на `td.cleanup-*`:

```js
if (pm.environment.get('existingFolderId')) {
  if (pm.execution && pm.execution.skipRequest) pm.execution.skipRequest();
}
```

В local — DELETE folder/cloud/org в обратном порядке. В yc — no-op (preallocated не трогаем).

## Per-case skeleton

Каждый VPC-кейс — самодостаточен внутри `_suiteFolderId`. Образец `NET-CR-OK`:

```
NET-CR-OK — Network create + Operation envelope shape
├─ ncrok.create        POST {{baseUrlVpc}}/vpc/v1/networks
│                      body: {folderId:"{{_suiteFolderId}}", name:"qa-{{runId}}-ncrok"}
│                      tests: assert Operation envelope shape (id/createdAt/done:false/metadata.@type)
├─ ncrok.poll-op       GET {{baseUrlOp}}/operations/{{ncrok_opId}}
│                      tests: done:true; response.@type==Network; response.id matches
└─ ncrok.cleanup       DELETE {{baseUrlVpc}}/vpc/v1/networks/{{ncrok_netId}}
                       tests: 200 OK, Operation envelope (done может быть false — допустимо)
```

Никаких setup-org/cloud/folder в кейсе. Никаких per-request skip-маркеров. Никаких ветвлений в assertions.

## Assertion rules

1. **YC verbatim contract = ground truth.** Все assertions описывают поведение реального YC API.
2. **Никаких `if (backendKind === 'yc') ... else ...`** в test-scripts. Если ветвление кажется нужным — это сигнал, что Kachō нужно дорабатывать (или кейс не подходит для unified).
3. **Allowed runtime variation:** id-формат, timestamps, конкретные значения `nextPageToken` (фор­мат may differ — assert только presence/absence).
4. **Disallowed variation:** error codes (`body.code`), HTTP status, response field names/types, validation behavior, наличие/отсутствие полей в response.

Если current Kachō behavior расходится с YC contract — обработка по правилу **Atomic** (см. §«Расхождения KC ↔ YC»).

## Расхождения KC ↔ YC (atomic flow)

При обнаружении расхождения, которое не позволяет identical assertions:

1. **Малое расхождение** (нет/неправильный validation, ошибка в response shape, error code mismatch) — фикс в `kacho-vpc/internal/...` идёт **в том же PR**, что и unified-кейс. Тест проходит идентично в обоих env.
2. **Крупное расхождение** (отсутствующая фича, несовместимый storage layout) — кейс **не включается** в текущую итерацию. Документируется в `kacho-vpc/newman/PARITY.md` (см. §10) с blocker-ID и оценкой.
3. **Kachō-only feature, неприменимая к YC** (например, NetBox sync) — кейс выносится **полностью из VPC unified suite** в отдельный smoke (`kacho-vpc/newman/collections/kacho-vpc-internal.postman_collection.json`, запускается только в local через `npm run test:internal`).

NetBox-кейсы (NETBOX-NETWORK-UPDATE-DESC-SYNC и пр.) попадают в категорию 3.

## Environment files

`local.postman_environment.json`:
```json
{ "key": "existingOrgId",    "value": "" },
{ "key": "existingCloudId",  "value": "" },
{ "key": "existingFolderId", "value": "" },
{ "key": "baseUrlRm",  "value": "http://localhost:18080" },
{ "key": "baseUrlVpc", "value": "http://localhost:18080" },
{ "key": "baseUrlOp",  "value": "http://localhost:18080" },
{ "key": "authHeader", "value": "" }
```

`yc.postman_environment.json`:
```json
{ "key": "existingOrgId",    "value": "" },
{ "key": "existingCloudId",  "value": "b1gmn66gvt2idus3kf1g" },
{ "key": "existingFolderId", "value": "b1g7220ns3r5dts1lha3" },
{ "key": "baseUrlRm",  "value": "https://resource-manager.api.cloud.yandex.net" },
{ "key": "baseUrlVpc", "value": "https://vpc.api.cloud.yandex.net" },
{ "key": "baseUrlOp",  "value": "https://operation.api.cloud.yandex.net" },
{ "key": "authHeader", "value": "Bearer {{ycToken}}" },
{ "key": "ycToken",    "value": "" }
```

**Legacy переменные** (`backendKind`, `requiresCloudMutationOK`, `orgId/cloudId/folderId/networkId/subnetId/operationId`, `ycFolderId/ycCloudId/ycNetworkId/ycSubnetId/ycAddressId/ycRouteTableId`, `ycFolderIdCreated`) — **остаются** в env-файлах superset-ом до полного покрытия всех доменов. Их используют ещё-не-унифицированные кейсы Subnet/Address/RT/SG/GW/PE. Удаляются только после того, как unified-suite поглотит все домены.

## run.sh changes

```bash
./scripts/run.sh                 # все unified кейсы локально (preflight create → cases → teardown delete)
./scripts/run.sh --env yc        # все unified кейсы в YC (preflight reuse → cases → teardown skip)
./scripts/run.sh --folder NET-CR-OK
                                 # одна папка; runner автоматически инжектит preflight + teardown
```

**Block «restrict to YC-* folders»** и `requiresCloudMutationOK` логика — **остаются** до полного покрытия всех доменов (нужны для legacy кейсов Subnet/Address/RT/SG/GW/PE). При наличии `--env yc` без `--folder`:
- newman получает `--folder 00-preflight` + список всех `NET-*` (unified) + список всех `YC-*` (legacy YC) + `--folder 99-teardown`.
- Legacy non-VPC unified кейсы из других доменов (Subnet/Address/...) skip-аются через per-request `requiresCloudMutationOK`-hook (как сейчас).

`--folder X` обёртка автоматически добавляет `--folder 00-preflight --folder X --folder 99-teardown`, чтобы кейс получил `_suiteFolderId`.

## Network domain — первая итерация (deliverable)

Кейсы после дедупликации YC-NET-* ↔ N-*:

| Unified id | Источник (мерджится из) | Note |
|---|---|---|
| `NET-CR-OK` | YC-NET-CR-OK | Operation envelope shape |
| `NET-CR-NAME-MAX` | N-CR-MAX-NAME | name=63 |
| `NET-CR-NAME-OVER` | новый | name=64 → 400 |
| `NET-CR-NAME-ACCEPTS` | YC-NET-CR-NAME-ACCEPTS | name validation rules |
| `NET-CR-LABELS-MAX` | N-CR-LABELS-MAX | |
| `NET-CR-LABELS-OVER` | N-CR-LABELS-OVER | |
| `NET-CR-DESC-MAX` | N-CR-DESC-MAX | description=256 |
| `NET-CR-DESC-OVER` | N-CR-DESC-OVER | description=257 → 400 |
| `NET-CR-EMPTY-FOLDER` | N-CR-EMPTY-FOLDER | sync 400 |
| `NET-CR-EMPTY-NAME` | YC-NET-CR-EMPTY-NAME | empty name |
| `NET-CR-DUP-NAME` | N-CR-DUP-NAME | duplicate within folder |
| `NET-CR-MISSING-FOLDER` | N-CR-MISSING-FOLDER + YC-N-CR-INVALID-FOLDER | NOT_FOUND mapping |
| `NET-CR-INVALID-FOLDER` | N-CR-INVALID-UUID | garbage uuid → NOT_FOUND |
| `NET-GET-NOTFOUND` | N-GET-NOTFOUND + YC-NET-GET-NONEXISTENT | |
| `NET-GET-INVALID-FORMAT` | N-GET-INVALID-FORMAT | |
| `NET-LIST` | YC-NET-LIST | response shape |
| `NET-LIST-FILTER` | N-LIST-FILTER | folderId filter |
| `NET-LIST-PS-NEG` | N-LIST-PS-NEG | |
| `NET-LIST-PS-ONE` | N-LIST-PS-ONE | nextPageToken presence |
| `NET-LIST-PAGE-TOKEN-LEAK` | YC-NET-LIST-PAGE-TOKEN-LEAK | |
| `NET-LIST-PAGE-TOKEN-FORMAT` | YC-NET-LIST-PAGE-TOKEN | |
| `NET-LIST-PT-INVALID` | N-LIST-PT-INVALID | |
| `NET-LIST-OPS` | N-LIST-OPS | |
| `NET-LIST-SUBNETS-EMPTY` | N-LIST-SUBNETS-EMPTY | |
| `NET-LIST-SG-DEFAULT` | N-LIST-SG-DEFAULT | |
| `NET-LIST-RT-EMPTY` | N-LIST-RT-EMPTY | |
| `NET-UP-NAME` | N-UP-NAME | |
| `NET-PATCH-CLEAR-DESC` | N-PATCH-CLEAR-DESC + YC-NET-PATCH-CLEAR | |
| `NET-PATCH-NOOP` | N-PATCH-NOOP | empty body wipes all |
| `NET-PATCH-NAME-EMPTY-OK` | N-PATCH-CLEAR-2 | YC permissive |
| `NET-DESC-UP-OVER` | N-DESC-UP-300 | description=300 → 400 |
| `NET-UPDATE-MASK-UNKNOWN` | UPDATE-MASK-UNKNOWN-NETWORK | |
| `NET-DEL-WITH-SUBNETS` | N-DEL-1 + YC-NET-DEL-NOT-EMPTY | FAILED_PRECONDITION |
| `NET-DEFAULT-SG-AUTO` | N-DEFAULT-SG-AUTO | |

Итого: ~28 unified кейсов после мерджа дублей.

**Out of scope для первой итерации (Network):**
- `N-MOVE-VALID` → `kacho-vpc/newman/PARITY.md` (Network.Move parity нужно verify в YC).
- `NETBOX-NETWORK-UPDATE-DESC-SYNC` → внутренняя коллекция `kacho-vpc-internal` (Kachō-only).
- `OP-VPC-METADATA-TYPE` (Network section) → второй крос­с-доменный кейс, отложить до Subnet/Address/RT.

## PARITY.md registry

Новый файл `kacho-vpc/newman/PARITY.md`:

```markdown
# kacho-vpc parity registry

Кейсы временно вне unified suite. Каждая запись — `<unified-id>` + причина + ожидание.

## pending-parity (домен Network)

| Unified id | Reason | Blocker |
|---|---|---|
| NET-MOVE-VALID | Network.Move в Kachō возвращает Operation, но семантика relocate между folder не реализована | kacho-vpc/internal/service/network/relocate.go missing |

## kacho-only smoke (не в unified VPC suite)

| Suite | Reason |
|---|---|
| NETBOX-NETWORK-UPDATE-DESC-SYNC | NetBox sync — Kachō-specific integration, в YC отсутствует |
```

Этот файл — single source of truth для «почему этого кейса нет в unified».

## Migration plan (Network domain)

Шаги на одном PR:

1. Обновить env-файлы (удалить legacy-переменные, добавить `existingOrgId/CloudId/FolderId`).
2. Создать `00-preflight` и `99-teardown` папки в коллекции.
3. Удалить из коллекции YC-NET-*/ YC-N-*/N-* топ-папки, на их место — NET-* unified.
4. Реализовать первую canonical папку — `NET-CR-OK` — целиком и проверить:
   - `./scripts/run.sh --folder NET-CR-OK` (env=local) → green.
   - `./scripts/run.sh --env yc --folder NET-CR-OK` → green.
5. Скопировать-переписать остальные ~27 кейсов по тому же шаблону.
6. Если кейс ловит расхождение, которое нельзя зафиксить в этом же PR — переносим в `PARITY.md` и удаляем из коллекции.
7. **Не трогать** non-Network top-level папки коллекции — Subnet / Address / RT / SG / GW / PE остаются с прежними skip-маркерами до своих итераций. Legacy `requiresCloudMutationOK` / `backendKind` переменные сохранены.
8. Обновить `README.md`: новая структура, run-команды.
9. Создать `kacho-vpc/newman/PARITY.md`.
10. Закоммитить atomic PR: `feat(newman): unified Network suite for KC+YC`.

## Validation gate

PR не сливается, пока обе команды не green на NET-* подмножестве:

```
./scripts/run.sh --folder 'NET-*'                  # local — 100% pass на всех unified
./scripts/run.sh --env yc --folder 'NET-*'         # yc    — 100% pass на тех же
```

(`--folder 'NET-*'` фильтр — поддержать в run.sh как glob по именам top-level папок.)

Legacy non-Network кейсы (Subnet/Address/...) **не учитываются** в gate — они в текущей итерации не унифицированы.

Если YC-prod недоступен (network/auth) — допускается local-only с явным комментарием в PR-description.

## Non-decisions (что в этом spec НЕ решается)

- Subnet / Address / RT / SG / GW / PE — следующие итерации, тот же pattern.
- Параллельные runs одного и того же `existingFolderId` — не поддерживаются.
- Метрики coverage, CI integration, scheduled runs — отдельный spec.
- Изменения в `kacho-test/` — отдельный spec.
