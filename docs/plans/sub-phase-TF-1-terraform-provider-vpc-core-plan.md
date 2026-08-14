# Terraform-провайдер Kachō, под-фаза TF-1 — план реализации

> [!warning] ПЛАН ИСПОЛНЕН И ЧАСТИЧНО РАЗВЁРНУТ — исполнению заново НЕ подлежит
> Под-фаза TF-1 реализована 2026-08-12, и в тот же день её топологическое решение было
> **развёрнуто**: провайдер сведён обратно в общий Go-модуль. Документ сохранён как
> свидетельство порядка работ, а не как указание к действию.
>
> **Шаги 3 и 6 и все упоминания `terraform/go.mod` ниже описывают снятое.** Сегодня
> `terraform/` входит в тот же модуль, что и продукт; отдельного `go.mod`, гейта изоляции из
> шести условий и второго выхода генерации (`proto/buf.gen.terraform.yaml`) в дереве нет.
> Исполнить эти шаги буквально значит вернуть развёрнутое.
>
> **Предикат** (дерево продукта, `origin/main` `5df7da76`): `git ls-files '*go.mod' | wc -l`
> → **1**. Ответ `2` означал бы, что план снова описывает дерево.
>
> Разбор решения и его цены — врезка над таблицей решений в приёмке
> `docs/specs/sub-phase-TF-1-terraform-provider-vpc-core-acceptance.md`; канон топологии —
> `.claude/rules/polyrepo.md` §«Build-граф». Здесь они не пересказываются.

> **Для исполнителя:** реализовывать задача за задачей. Шаги помечены `- [ ]` для отметок.
> Источник истины — **APPROVED**-приёмка
> `docs/specs/sub-phase-TF-1-terraform-provider-vpc-core-acceptance.md` (41 сценарий).
> План не заменяет её и не пересказывает: он задаёт **порядок** и **границы задач**.
> Расхождение плана с приёмкой — находка в плане.

**Цель:** первый Terraform-провайдер Kachō с двумя ресурсами — `kacho_vpc_network` и
`kacho_vpc_subnet`, — устойчивый к трём свойствам контракта, которые ломают наивный
провайдер: неотличимость «нет доступа» от «не существует», отсутствие ключа
идемпотентности и асинхронность мутаций.

**Архитектура:** отдельный Go-модуль `terraform/` (в графе продукта отсутствует),
`terraform-plugin-framework`, HTTP к REST-краю, тела запросов — `protojson` над
message-типами, сгенерированными из общего `proto/` во **второй** выход.

**Технологии:** Go 1.25 · terraform-plugin-framework · protobuf-go · buf 1.72.0.

## Глобальные ограничения

- Модуль `terraform/` **не импортирует** `github.com/PRO-Robotech/kacho/...`; корневой
  `go.sum` не приобретает строк `hashicorp`; `replace` запрещён (`polyrepo.md`).
- Генерация — **отдельный** шаблон `proto/buf.gen.terraform.yaml`; `proto/buf.gen.yaml`
  **не изменяется**; managed mode обязан нести `disable` для `google`.
- Тесты пишутся **до** кода (ban #12). Каждый гейт имеет парную инъекцию.
- Ни одного маркера отложенной работы (ban #11); ни `insecure`-ручки (Р8).
- Ветка от свежего `origin/main`; коммиты — Conventional Commits, без attribution-трейлеров.
- Сценарии 15/16 (супернет) реализуются **после** мёржа `origin/fix/194-supernet-fixtures`.

---

## Раскладка файлов

| Файл | Ответственность |
|---|---|
| `terraform/go.mod`, `go.sum` | границы модуля |
| `proto/buf.gen.terraform.yaml` | второй выход генерации (только message-типы) |
| `terraform/internal/api/**` | порождённые типы, **рукописного нет ничего** |
| `terraform/internal/client/client.go` | единственный производитель `*http.Client` и `*tls.Config`, срок вызова, заголовок идемпотентности |
| `terraform/internal/client/errors.go` | классификация ответа: форма → код → политика |
| `terraform/internal/client/operation.go` | поллер: завершена → нет ошибки → идентификатор |
| `terraform/internal/client/read.go` | многошаговое чтение, четыре случая |
| `terraform/internal/provider/provider.go` | конфигурация, доверие TLS, реестр ресурсов |
| `terraform/internal/provider/network_resource.go` | `kacho_vpc_network` + пара глаголов CIDR |
| `terraform/internal/provider/subnet_resource.go` | `kacho_vpc_subnet` |
| `terraform/cmd/terraform-provider-kacho/main.go` | точка входа плагина |
| `internal/repohygiene/artifactgates/tfprovider_gates_test.go` | гейты изоляции и устаревания (**в модуле продукта**) |
| `.github/workflows/ci.yaml` | джоба второго модуля: пять команд |

---

## Задача 1 — модуль и его изоляция

**Файлы:** создать `terraform/go.mod`, `terraform/doc.go`; создать
`internal/repohygiene/artifactgates/tfprovider_gates_test.go`; изменить `.gitignore`,
`.dockerignore`, `internal/repohygiene/artifactgates/deferredwork.go`.

**Производит:** модуль `github.com/PRO-Robotech/kacho/terraform`; гейт
`TestProviderModuleIsIsolated` с шестью условиями (сц. 27).

- [ ] **Шаг 1.** Написать гейт `TestProviderModuleIsIsolated` в модуле **продукта**, шесть
      условий: (а) `terraform/go.mod` без `require` на продукт; (б) ни один пакет продукта
      не импортирует `terraform/`; (в) корневой `go.sum` без `hashicorp`; (г) порождённые
      файлы под `terraform/` не импортируют `pkg/api`; (д) зеркало — `pkg/api` не
      импортирует `terraform/internal/api`; (е) отслеживаемого `go.work` нет.
      Корень репозитория резолвить `git rev-parse --show-toplevel`, при недоступности git —
      **отказ**, не обход диска.
- [ ] **Шаг 2.** Прогнать: `go test ./internal/repohygiene/artifactgates -run TestProviderModuleIsIsolated`.
      Ожидание: **FAIL** — модуля ещё нет, условие (а) не выполнимо.
- [ ] **Шаг 3.** Создать `terraform/go.mod` (`module github.com/PRO-Robotech/kacho/terraform`,
      `go 1.25`) и `terraform/doc.go` с пакетным комментарием, объясняющим, **почему** модуль
      отдельный (иначе граф зависимостей каждого сервиса).
- [ ] **Шаг 4.** Внести `terraform` в `deferralScanRoots`; добавить `go.work`/`go.work.sum`
      в `.gitignore`; добавить `terraform/` в `.dockerignore`.
- [ ] **Шаг 5.** Прогнать гейт снова — ожидание **PASS**. Затем инъекция: временно добавить
      `require github.com/PRO-Robotech/kacho v0.0.0` в `terraform/go.mod` → гейт **краснеет и
      называет условие**; убрать → зелёный.
- [ ] **Шаг 6.** Коммит: `feat(terraform): отдельный модуль провайдера и гейт его изоляции`.

## Задача 2 — второй выход генерации

**Файлы:** создать `proto/buf.gen.terraform.yaml`; создать `terraform/internal/api/**`
(порождённое); дополнить `tfprovider_gates_test.go` гейтом `TestGeneratedOutputsAreNotStale`.

**Потребляет:** модуль из задачи 1. **Производит:** типы `vpcv1.CreateNetworkRequest`,
`vpcv1.Subnet`, `operationv1.Operation` под префиксом
`github.com/PRO-Robotech/kacho/terraform/internal/api/...`.

- [ ] **Шаг 1.** Написать гейт устаревания: сносит **каждый** выход, регенерирует оба из
      одной ревизии `proto/`, требует чистый `git diff`, печатает число файлов по каждому
      выходу и утверждает **ноль** рукописных файлов под `terraform/internal/api`.
- [ ] **Шаг 2.** Прогнать — ожидание **FAIL** (второго выхода нет).
- [ ] **Шаг 3.** Создать шаблон. Проверенная форма (замер на `buf 1.72.0`):

```yaml
version: v2
managed:
  enabled: true
  disable:
    - path: google
  override:
    - file_option: go_package_prefix
      value: github.com/PRO-Robotech/kacho/terraform/internal/api
plugins:
  - local: protoc-gen-go
    out: ../terraform/internal/api
    opt: paths=source_relative
inputs:
  - directory: .
    paths: [kacho/cloud/vpc/v1, kacho/cloud/operation]
```

- [ ] **Шаг 4.** `cd proto && buf generate --template buf.gen.terraform.yaml`. Проверить
      глазами **один** файл: импорты своих ведут в новый префикс, аннотации Google — в
      `google.golang.org/genproto/...`.
- [ ] **Шаг 5.** Прогнать гейт — **PASS**. Инъекция: изменить комментарий в `.proto` без
      регенерации → **красный** с именем устаревшего выхода.
- [ ] **Шаг 6.** Коммит: `feat(terraform): второй выход генерации — только message-типы`.

## Задача 3 — клиент: транспорт, доверие, идемпотентность

**Файлы:** создать `terraform/internal/client/client.go`, `client_test.go`.

**Производит:** `client.New(cfg Config) (*Client, error)`, где
`Config{Endpoint, Token, CABundle string, Timeout time.Duration}`;
`(*Client).Do(ctx, method, path string, body proto.Message, hdr Headers) (*Response, error)`.

- [ ] **Шаг 1.** Тесты: (а) пустой `Endpoint` → ошибка называет атрибут **и** переменную
      окружения; (б) неизвестный сертификат → отказ, **не** предупреждение; (в) токена нет
      ни в журнале, ни в дампе состояния — на успешном **и** ошибочном пути; (г) заголовок
      идемпотентности детерминирован: два вызова с тем же входом дают тот же ключ, с другим
      телом — другой.
- [ ] **Шаг 2.** Прогнать — **FAIL** (пакета нет).
- [ ] **Шаг 3.** Реализовать. Единственный производитель `*http.Client` и `*tls.Config`;
      срок вызова из конфигурации применяется **всеми** методами; `InsecureSkipVerify`
      отсутствует как идентификатор.
- [ ] **Шаг 4.** Прогнать — **PASS**. Добавить гейт `TestNoInsecureTransportKnob` +
      инъекция: ввести атрибут → красный; `ca_bundle` → молчит.
- [ ] **Шаг 5.** Коммит: `feat(terraform): клиент края — срок вызова, доверие, идемпотентность`.

## Задача 4 — классификация ответа и поллер операции

**Файлы:** создать `terraform/internal/client/errors.go`, `operation.go` + тесты.

**Потребляет:** `client.Do`. **Производит:** `client.Classify(*Response) Outcome`, где
`Outcome` различает `Malformed`, `NotFound`, `Denied`, `Conflict`, `Retryable`,
`Terminal`; `client.AwaitOperation(ctx, opID string) (resourceID string, err error)`.

- [ ] **Шаг 1.** Тесты: (а) `404` с телом-HTML → `Malformed`, **не** `NotFound` (сц. 35);
      (б) код вне перечня (429/500/504) → `Terminal` с дословным статусом, не `Retryable`
      (сц. 36); (в) операция завершена **с** ошибкой и **с** метаданными → идентификатор
      **не** извлекается (сц. 08); (г) парный положительный: успешная операция даёт
      идентификатор; (д) разбор ответа терпим к неизвестному полю (сц. 41).
- [ ] **Шаг 2.** Прогнать — **FAIL**.
- [ ] **Шаг 3.** Реализовать. Порядок в `AwaitOperation` буквальный: завершена → **assert
      отсутствия ошибки** → метаданные → идентификатор. Бюджет по умолчанию 5 минут, пауза
      между опросами реальная, часы инъектируемы.
- [ ] **Шаг 4.** Прогнать — **PASS**.
- [ ] **Шаг 5.** Коммит: `feat(terraform): классификатор ответов и поллер операции`.

## Задача 5 — многошаговое чтение

**Файлы:** создать `terraform/internal/client/read.go` + тесты.

**Производит:** `client.ConfirmAbsence(ctx, projectID, name string) (Verdict, error)` с
`Verdict ∈ {Gone, Present, Denied, Ambiguous}`.

- [ ] **Шаг 1.** Тесты — **четыре** случая сц. 12: (а) по имени пусто, контрольная страница
      проекта непуста → `Gone`; (б) ресурс найден → `Present`; (в) список отвечает отказом →
      `Denied`; (г) контрольная страница пуста целиком → `Ambiguous`. Плюс: курсор не
      исчерпан → `Ambiguous`, а не `Gone`.
- [ ] **Шаг 2.** Прогнать — **FAIL**.
- [ ] **Шаг 3.** Реализовать; текст `Ambiguous` называет обе причины и `terraform state rm`.
- [ ] **Шаг 4.** Гейт `TestStateRemovalHasSingleCallSite` (сц. 39) + инъекция вторым вызовом.
- [ ] **Шаг 5.** Коммит: `feat(terraform): подтверждение отсутствия — четыре исхода`.

## Задача 6 — `kacho_vpc_network`

**Файлы:** создать `terraform/internal/provider/provider.go`, `network_resource.go`,
`network_resource_test.go`, `terraform/cmd/terraform-provider-kacho/main.go`.

**Потребляет:** задачи 3-5. **Производит:** ресурс со схемой: `project_id` (Required,
ForceNew), `name` (Required), `description`/`labels` (Optional),
`ipv4_cidr_blocks`/`ipv6_cidr_blocks` (Optional), `create_default_security_group`
(Optional, ForceNew), `id`/`created_at`/`default_security_group_id`/
`default_route_table_id` (Computed).

- [ ] **Шаг 1.** Тесты на подставном крае: (а) идентификатор в состоянии **до** первого
      обратного чтения (сц. 38); (б) ретрай 403/404 только на первом чтении, 401 не
      ретраится (сц. 13); (в) обновление шлёт **непустую** маску в lowerCamelCase (сц. 20);
      (г) усыновление по имени после потерянного ответа, три ветки (сц. 06).
- [ ] **Шаг 2.** Прогнать — **FAIL**.
- [ ] **Шаг 3.** Реализовать ресурс и точку входа плагина.
- [ ] **Шаг 4.** Гейты `TestUpdateNeverSendsEmptyMask`,
      `TestRequestBodiesAreBuiltFromContractTypes` (AST) + инъекции.
- [ ] **Шаг 5.** Коммит: `feat(terraform): ресурс сети vpc`.

## Задача 7 — пара глаголов для блоков адресов

**Файлы:** изменить `network_resource.go`; тест `network_cidr_verbs_test.go`.

- [ ] **Шаг 1.** Тесты (сц. 37): порядок — **добавление раньше удаления**; каждый глагол
      дожидается своей операции; при отказе второго в состоянии — **применённое**
      (объединение), apply падает, называя обе половины; отката нет.
- [ ] **Шаг 2.** Прогнать — **FAIL**. **Шаг 3.** Реализовать diff набора → два вызова.
- [ ] **Шаг 4.** Прогнать — **PASS**. **Шаг 5.** Коммит: `feat(terraform): блоки адресов сети — глаголами`.

## Задача 8 — `kacho_vpc_subnet`

**Файлы:** создать `subnet_resource.go`, `subnet_resource_test.go`.

**Производит:** схему: `project_id`/`network_id` (Required, ForceNew), ровно один из
`zone_id`/`region_id` (ForceNew), `ipv4_cidr_primary`/`ipv6_cidr_primary` (Optional,
ForceNew), `route_table_id` (**Optional + Computed** — сервер подставляет умолчание),
`name` (Required), `placement_type`/`ipv4_cidr_blocks` (Computed).

- [ ] **Шаг 1.** Тесты: (а) `plan` после `apply` **пуст** без заданного `route_table_id`
      (сц. 24); (б) оба якоря или ни одного → отказ схемы **до** обращения к краю (сц. 25);
      (в) импорт: асимметрия «скаляр + массив» разрешается правилом сравнения (сц. 28).
- [ ] **Шаг 2.** Прогнать — **FAIL**. **Шаг 3.** Реализовать. **Шаг 4.** Прогнать — **PASS**.
- [ ] **Шаг 5.** Коммит: `feat(terraform): ресурс подсети vpc`.

## Задача 9 — контрактная проба, перечислитель гейтов, CI

**Файлы:** создать `terraform/internal/provider/contract_echo_test.go`,
`gates_enumerated_test.go`; изменить `.github/workflows/ci.yaml`,
`.github/scripts/check-pinned-tools.sh`, `polyrepo.md` **и ещё семь документов**.

- [ ] **Шаг 1.** Контрактная проба (сц. 29): перечень атрибутов — **рефлексией по схеме**;
      различать «эхо нуля» от «не применено»; печатать объём (сверено/исключено).
- [ ] **Шаг 2.** Перечислитель `TestEveryGateHasAnInjection` (сц. 33): сам обходит гейты,
      падает на гейте без инъекции, печатает объём.
- [ ] **Шаг 3.** Джоба CI для модуля: **пять** команд — `go build`, `go vet`,
      `golangci-lint run`, `govulncheck`, `gosec`. Пин `terraform` внести в каталог зондов.
- [ ] **Шаг 4.** Обновить `polyrepo.md` (таблица каталогов + §Build-граф) и остальные семь
      документов, где число Go-модулей утверждается; перечень вывести **заново** предикатом
      из DoD п.6, а не цитировать.
- [ ] **Шаг 5.** Коммит: `feat(terraform): контрактная проба, перечислитель гейтов, джоба CI`.

## Задача 10 — приёмочные тесты против стенда (blocked-by)

**Блокируется** мёржем `origin/fix/194-supernet-fixtures` — сценарии 15/16 на текущем
стволе красны by construction, и ослаблять их нельзя.

- [ ] **Шаг 1.** `TestAccKachoVpcNetwork_*` и `TestAccKachoVpcSubnet_*` под `TF_ACC`;
      без переменной — пропуск с **напечатанным числом** пропущенных (сц. 32).
- [ ] **Шаг 2.** Прогон против стенда в production-посадке; записать числа: исполнено,
      упало, пропущено, **ревизия продукта** (DoD п.2-3).
- [ ] **Шаг 3.** Коммит + PR.

---

## Самопроверка плана

- **Покрытие приёмки.** 41 сценарий распределён: 01-07, 27, 34 → задачи 1-3; 08-11, 35, 36,
  41 → задача 4; 12-14, 39 → задача 5; 15-22, 38, 40 → задача 6; 19, 37 → задача 7;
  23-26, 28, 30 → задача 8; 29, 31, 33 → задача 9; 32 + приёмочные → задача 10.
- **Ни одного плейсхолдера:** каждый шаг называет файл, команду и ожидаемый исход.
- **Согласованность имён:** `client.New`, `client.Do`, `client.Classify`,
  `client.AwaitOperation`, `client.ConfirmAbsence` — употребляются одинаково во всех задачах.
- **Порядок:** гейты пишутся **до** предмета в задачах 1, 2, 5, 6; ресурсные задачи
  зависят только от клиента, поэтому 6 и 8 независимы между собой.
