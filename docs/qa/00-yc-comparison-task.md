# QA-задача: сравнение Kachō с эталонным YC API

Цель — найти corner-cases, где наш control plane (1.0) отличается от поведения YC. Используем CLI `yc` как **опорное поведение**, наш REST через `api-gateway` — как тестируемое.

## 0. Скоуп

Покрываем 7 ресурсов из `/v1/qa-scope`:
- `Organization` — `/organization-manager/v1/organizations` ↔ `yc organization-manager organization`
- `Cloud` — `/resource-manager/v1/clouds` ↔ `yc resource-manager cloud`
- `Folder` — `/resource-manager/v1/folders` ↔ `yc resource-manager folder`
- `Network` — `/vpc/v1/networks` ↔ `yc vpc network`
- `Subnet` — `/vpc/v1/subnets` ↔ `yc vpc subnet`
- `Address` — `/vpc/v1/addresses` ↔ `yc vpc address`
- `RouteTable` — `/vpc/v1/routeTables` ↔ `yc vpc route-table`

**Не покрываем (frozen в 1.0):** compute (Instance/Disk/Image/Snapshot), loadbalancer (NLB/TargetGroup), SecurityGroup, IAM, Operations API нюансы.

## 1. Подготовка стенда

### 1.1 YC CLI

Установить + авторизоваться:
```bash
yc init                          # привязка к billing-аккаунту
yc config set folder-id <test-folder>
```

Создать **отдельный test-folder** в YC чтобы случайно не задеть production. Все YC-команды работают в текущем `folder-id`.

### 1.2 Kachō стенд

Поднять локально:
```bash
cd kacho-deploy && make dev-up
kubectl port-forward -n kacho svc/api-gateway 8080:8080 &
```

Проверка:
```bash
curl -s http://localhost:8080/healthz   # → {"status":"ok"}
curl -s http://localhost:8080/readyz    # → SERVING для resourcemanager+vpc
```

`yc` указывает в свой CLI-config; наш стенд — `localhost:8080`. Пара переменных для удобства:
```bash
export KACHO=http://localhost:8080
export YC_FORMAT=json    # чтобы yc выдавал JSON для diff-ов
```

## 2. Методология

Каждый сценарий выполняется **трижды**:

| Шаг | Где | Команда |
|---|---|---|
| 1. | YC | `yc ... ` сохраняем JSON ответ + код выхода + текст ошибки |
| 2. | Kachō | `curl ${KACHO}/...` сохраняем JSON ответ + HTTP-код |
| 3. | diff | сравнить fields, error code (`ALREADY_EXISTS=6`, `NOT_FOUND=5` и т.д.), validation message |

Если есть расхождения — **открыть тикет в kacho-workspace/docs/qa/findings/** с шаблоном:

```markdown
# Сценарий: <id>
- YC: <команда> → <результат>
- Kachō: <команда> → <результат>
- Расхождение: <что отличается>
- Категория: missing-feature / wrong-error-code / wrong-validation / ...
```

## 3. Сценарии: Cloud/Folder/Organization

### 3.1 Создание

| ID | Сценарий | YC ожидание | Kachō проверка |
|---|---|---|---|
| O-CR-1 | Create Org с валидным name `my-test-org` | OK, returns Operation | `POST /organization-manager/v1/organizations`, body `{"name":"my-test-org","title":"Test"}` |
| O-CR-2 | Create Org с пустым name | INVALID_ARGUMENT (3) | проверить тот же code |
| O-CR-3 | Create Org с дублирующимся name | ALREADY_EXISTS (6) | тот же |
| O-CR-4 | Name из 64+ символов | INVALID_ARGUMENT, мы должны падать с regex | сверить message |
| O-CR-5 | Name начинается с цифры (`1abc`) | INVALID_ARGUMENT по regex | сверить |
| O-CR-6 | Name UPPERCASE (`MyOrg`) | INVALID_ARGUMENT | сверить |
| O-CR-7 | Description > 256 символов | INVALID_ARGUMENT | сверить (у нас в proto length=<=256) |
| O-CR-8 | 65 labels (превышение лимита) | INVALID_ARGUMENT | сверить |
| O-CR-9 | label-value > 63 chars | INVALID_ARGUMENT | сверить |
| O-CR-10 | label-key с `_UPPERCASE` | INVALID_ARGUMENT (regex `[a-z][-_0-9a-z]*`) | сверить |
| O-CR-11 | Concurrent create с одинаковым name (2 параллельных POST) | один OK, второй ALREADY_EXISTS | повторить |

Аналогично для Cloud (плюс validate `organization_id`) и Folder (плюс `cloud_id`).

### 3.2 Update

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| C-UP-1 | Update Cloud, изменить только description через `update_mask=description` | meta-fields сохраняются | сверить FieldMask поведение |
| C-UP-2 | Update без update_mask, body содержит частичный set полей | YC применяет ВСЕ переданные | сверить (наша логика тоже) |
| C-UP-3 | Update с пустым name | INVALID_ARGUMENT | сверить |
| C-UP-4 | Update name на занятый | ALREADY_EXISTS | **проверено выше — fixed** |
| C-UP-5 | Update несуществующего id | NOT_FOUND (5) | сверить |
| C-UP-6 | Update labels: добавить новый key | merge или replace? | YC делает **replace**; проверить наш |

### 3.3 Delete

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| C-DL-1 | Delete Cloud без folders → Operation | done=true success | сверить |
| C-DL-2 | Delete Cloud с одной folder (есть зависимости) | FAILED_PRECONDITION в Operation.error | сверить (наш hard-delete блокируется на FK RESTRICT через service.HasDependents) |
| C-DL-3 | Delete уже удалённого id | NOT_FOUND или idempotent OK? | YC обычно идемпотентен, проверить |
| C-DL-4 | Delete folder, в котором есть Networks | YC: ?? | проверить наш — у нас Folder.Delete пока без cross-service dependents check (vpc у нас отдельный сервис) |

## 4. Сценарии: VPC/Network

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| N-CR-1 | Create network с valid name | OK | curl POST /vpc/v1/networks |
| N-CR-2 | Create network с дублирующимся name в folder | ALREADY_EXISTS | сверить |
| N-CR-3 | Create network в несуществующем folder | NOT_FOUND или INVALID_ARGUMENT | сверить (у нас FolderClient validate с retry) |
| N-CR-4 | Create network с label-value пустой строкой | OK (YC разрешает) | сверить |
| N-DEL-1 | Delete network с зависимыми subnets | FAILED_PRECONDITION | сверить (у нас HasDependents) |
| N-DEL-2 | Delete network с зависимыми SG | FAILED_PRECONDITION | у нас SG frozen — проверить только subnets |
| N-DEL-3 | Delete network с зависимыми RouteTable | FAILED_PRECONDITION | проверить |

## 5. Сценарии: VPC/Subnet (CIDR — крутая зона corner cases)

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| SU-CIDR-1 | CIDR `10.0.0.0/24` валидный | OK | curl |
| SU-CIDR-2 | CIDR с host-bits set: `10.0.0.5/24` | INVALID_ARGUMENT | сверить (наша валидация — net.ParseCIDR не отлавливает host-bits, нужен дополнительный check) |
| SU-CIDR-3 | CIDR `/16` (макс) | OK | сверить |
| SU-CIDR-4 | CIDR `/30` (мин — у YC нижняя граница `/16` для VPC subnet?) | YC `/16-/28` валидно | сверить лимиты |
| SU-CIDR-5 | CIDR overlap: создать subnet `10.0.0.0/24`, потом `10.0.0.128/25` | YC: ALREADY_EXISTS / FAILED_PRECONDITION | у нас не проверяем overlap — **известный gap** |
| SU-CIDR-6 | CIDR из публичного диапазона `8.8.8.0/24` | YC: INVALID_ARGUMENT (только RFC1918) | сверить — **возможно gap** |
| SU-CIDR-7 | IPv6 CIDR в `v4_cidr_blocks` | INVALID_ARGUMENT | сверить |
| SU-CIDR-8 | Empty `v4_cidr_blocks` | INVALID_ARGUMENT (required) | сверить |
| SU-CIDR-9 | 2 CIDRs в одном subnet | YC: разрешено? | сверить proto |
| SU-NET-1 | Subnet ссылается на network в другом folder | INVALID_ARGUMENT | у нас same-DB FK не проверяет cross-folder; **проверить** |
| SU-ZONE-1 | Subnet в zone которой нет (`kacho-zone-x`) | INVALID_ARGUMENT в YC | у нас seed table только zone-a/b/c — должен быть FK violation; сверить gentle error |
| SU-CIDR-IM-1 | Update Subnet, попытка изменить cidr_block | YC: IMMUTABLE — отклоняется | у нас proto говорит "field can be set only at creation time" — **проверить наш Update** |

## 6. Сценарии: VPC/Address

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| A-CR-1 | Create EXTERNAL без явного `external_ipv4_address` | YC выделяет случайный | у нас 203.0.113.0/24 random; сверить |
| A-CR-2 | Create EXTERNAL с указанным `external_ipv4_address.address=1.2.3.4` | YC проверяет принадлежность пулу | у нас валидация — есть ли check? **проверить** |
| A-CR-3 | Create INTERNAL с `subnet_id` несуществующим | NOT_FOUND/INVALID_ARGUMENT | **проверить — у нас наш subnet check ?** |
| A-CR-4 | Create INTERNAL без указания subnet | INVALID_ARGUMENT | сверить |
| A-CR-5 | Create с oneof external+internal одновременно | INVALID_ARGUMENT | сверить proto contract |
| A-CR-6 | Reserve без use → status `reserved=true, used=false` | сверить flag-логику | у нас status enum vs YC bool flags |
| A-DL-1 | Delete address с `deletion_protection=true` | FAILED_PRECONDITION | у нас флаг есть в proto, проверить service-логику |
| A-DL-2 | Delete address с `used=true` (присвоен инстансу) | FAILED_PRECONDITION или OK с warning | у нас compute frozen, поведение не проверяется через UI; проверить через DB |

## 7. Сценарии: VPC/RouteTable

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| RT-CR-1 | Create empty static_routes | OK | сверить |
| RT-CR-2 | Create с 1 static_route `dest=10.10.0.0/16, next_hop=10.0.0.1` | OK | сверить |
| RT-CR-3 | static_route с invalid CIDR | INVALID_ARGUMENT | сверить |
| RT-CR-4 | static_route next_hop вне subnet network | YC: INVALID_ARGUMENT | у нас не проверяем, **gap** |
| RT-UP-1 | Update static_routes — full-replace? merge? | YC: full-replace | сверить наш |

## 8. Сценарии: Operations API

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| OP-1 | Operation Get для существующего id | OK | curl /operations/{id} |
| OP-2 | Operation Get несуществующий | NOT_FOUND | сверить |
| OP-3 | Operation Cancel pending operation | YC поддерживает Cancel? | у нас `Cancel` есть в proto, но MarkDone-with-error реализован? **проверить** |
| OP-4 | Operation Cancel done operation | YC: FAILED_PRECONDITION | сверить |
| OP-5 | Operation после Create resource — `metadata.@type` | YC: `type.googleapis.com/yandex.cloud.compute.v1.CreateNetworkMetadata` | у нас `kacho.cloud....`; сверить shape |
| OP-6 | Operation `response` после Create — содержит созданный resource | сверить shape | у нас Network как Any; сверить fields присутствуют |

## 9. Сценарии: Список и пагинация

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| L-1 | List clouds with `--page-size 5` | YC возвращает `next_page_token` | сверить наш `next_page_token` |
| L-2 | List с `page_token` от предыдущего | непрерывная страница | сверить |
| L-3 | List без folder_id (для folder-scoped resource) | INVALID_ARGUMENT? | у нас опциональный — **проверить** |
| L-4 | List с filter expression `name = "default"` | YC: filter-DSL поддерживает | у нас есть `filter` поле в request? **возможно gap** |
| L-5 | List in empty folder | возвращает пустой массив, не error | сверить |

## 10. Сценарии: Errors

| ID | Сценарий | YC | Kachō |
|---|---|---|---|
| E-1 | Запрос на несуществующий path | 404 + Status JSON | сверить (api-gateway return) |
| E-2 | Запрос с невалидным JSON | 400 | сверить grpc-gateway behavior |
| E-3 | Internal server error (DB down) | 500 + детали в Status | сверить |
| E-4 | Multi-violation: несколько fields invalid | YC возвращает `BadRequest.field_violations[]` | у нас coreerrors.AddFieldViolation; сверить shape |
| E-5 | gRPC code → HTTP mapping | YC: 6→409, 5→404, 3→400, 9→412, 13→500 | сверить через grpc-gateway default mapping |

## 11. Шаблон comparison-скрипта

Bash-helper для парного запроса:

```bash
#!/usr/bin/env bash
# Usage: compare.sh <scenario-id> <yc-cmd> <kacho-curl-cmd>
set -e
SC=$1; YC=$2; CURL=$3

echo "=== Scenario $SC ==="
echo "--- YC ---"
yc_out=$(eval "$YC" 2>&1) || yc_rc=$?
echo "$yc_out"
echo "rc=${yc_rc:-0}"

echo "--- Kachō ---"
k_out=$(eval "$CURL" 2>&1) || k_rc=$?
echo "$k_out"
echo "rc=${k_rc:-0}"

# diff на ключевые поля
y_code=$(echo "$yc_out" | jq -r '.code // empty' 2>/dev/null)
k_code=$(echo "$k_out" | jq -r '.code // empty' 2>/dev/null)
if [ "$y_code" != "$k_code" ]; then
  echo "MISMATCH: code ($y_code vs $k_code)"
fi
```

Использование:
```bash
./compare.sh O-CR-3 \
  'yc organization-manager organization create --name default --title Test 2>&1' \
  'curl -s -X POST $KACHO/organization-manager/v1/organizations -d "{\"name\":\"default\",\"title\":\"Test\"}" 2>&1'
```

## 12. Минимальный starter pack

Для начала тестировщику пройти **9 главных сценариев** в указанном порядке (~30 мин):

1. O-CR-3 — Create org duplicate name
2. C-UP-4 — Update cloud rename to occupied (мы это уже исправили — проверить regression)
3. C-DL-2 — Delete cloud with folders
4. N-DEL-1 — Delete network with subnets
5. SU-CIDR-2 — host-bits CIDR
6. SU-CIDR-IM-1 — попытка immutable Update Subnet
7. A-CR-3 — Internal address с несуществующим subnet
8. OP-3 — Operation Cancel
9. E-4 — multi field-violation

Это покажет 80% gap-ов между нашей реализацией и YC. Остальные сценарии — по полной программе.

## 13. Документ-доставка

Тестировщик создаёт `findings/` в этом каталоге:
```
docs/qa/findings/
  O-CR-3.md
  N-DEL-1.md
  SU-CIDR-5.md
  ...
```
Для каждого расхождения — отдельный файл с YC-результатом, Kachō-результатом и категорией. Каждый файл потом → Github issue / тикет.

---

**Версия:** 1.0 (на момент Kachō v1.0.0).
**Update-ить:** при изменении API контракта или backend behavior.
