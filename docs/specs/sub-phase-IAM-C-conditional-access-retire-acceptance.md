# Sub-phase IAM-C (ретайр условного доступа) — Acceptance

> Статус: DRAFT (круг 4 — финальная доводка: исходы открытых пунктов + сверка механизмов по коду)
> Дата: 2026-07-27
> Ревьюер: acceptance-reviewer · круг 1 — `CHANGES_REQUESTED`, 5 блокирующих + 11 фактических
> закрыты (сводка — §10); круг 2 — `CHANGES_REQUESTED`, 4 блокирующих + 2 фактических
> закрыты (сводка — §11); круг 4 — 3 ложных механизма и 6 несуществующих артефактов
> исправлены по коду, каждый открытый пункт получил исход (§12)
> Эпик/тикет: задача #74 («ретайрить условный доступ целиком или доводить») — решение принято,
> этот документ её закрывает. Кросс-слойно внутри монорепо `project/kacho`
> База проверки фактов: `project/kacho` @ `b892cd8` (ветка `base/redesign` = `redesign/integration`);
> круг 1 сверялся с `2e54f0e` — все перепроверенные в круге 2 факты сошлись на обоих
> Затронуто: `proto/kacho/cloud/iam/v1` · `pkg/api` (regen) · `pkg/ids` · `services/iam` · `gateway` · `deploy/helm/umbrella` · `services/iam/tests/newman` · vault
> Источники (нормативно, не дублируются в тело — ссылки):
> - `.claude/rules/00-kacho-core.md` ban #1 (acceptance-first), #11 (без тех-долга), #12 (TDD), #14 (production-complete), #15 (адресация по id)
> - `.claude/rules/api-conventions.md` §«Error-format», §«update_mask discipline», §«Форма ресурса»
> - `.claude/rules/data-integrity.md` §«Within-service инварианты», §«Authz-материализация owner-доступа»
> - `.claude/rules/security.md` §«AuthN+AuthZ ВЕЗДЕ», §«Авторизация живёт в МОДЕЛИ», §«Три уровня супер-доступа», §«Production-mode обязателен ВЕЗДЕ»
> - `.claude/rules/architecture.md` §«LEAN: без vestigial-кода», §«Doc-truthfulness»
> - `.claude/rules/testing.md` §«Regression-lock … на уровне ОБСЕРВАБЛА», §«Newman e2e — eventual-consistency дисциплина»
> - vault: `[[resources/iam-condition]]`, `[[resources/iam-access-binding-condition]]`,
>   `[[rpc/iam-conditions-service]]`, `[[resources/iam-access-binding]]`,
>   `[[checks-with-form-but-no-substance]]`

---

## 0. Обзор

Условный доступ (Conditions / ABAC-overlay поверх ReBAC) снимается **целиком**: публичный
ресурс `Condition` вместе с его сервисом, поля условия на привязке прав, связующая таблица,
все шесть условий и тип `iam_condition` в модели прав, записи каталога разрешений, мёртвая
доставка guardrail-политик. Решение принято владельцем: **ретайрим, не доводим.**

Основание — не «фича сырая», а **фича никогда не была соединена**: два независимых дизайна
(«переиспользуемое выражение» и «предикат на привязке») жили в разных таблицах, разных
пространствах идентификаторов и ни разу не встретились в коде; вычислитель — сопоставление
подстрок, а не язык выражений; за всю историю стенда — ноль строк. Доведение означало бы
проектировать фичу заново, поэтому объём снятия и объём доведения совпадают, а снятие вдобавок
убирает поверхность, которая **вводит администратора в заблуждение** (отказ вычислителя
подаётся клиенту как «вычислено, доступ не разрешён» — неотличимо от настоящего решения).

Замена на настоящий язык выражений — **отдельная фича с собственным acceptance** (§8).

---

## 1. Проверка оснований по коду

Каждое основание проверено по дереву `project/kacho` @ `2e54f0e` (круг 1) и перепроверено
@ `b892cd8` (круг 2) — расхождений между снимками нет. **Все шесть подтверждены.**
Ниже — точная механика каждого (она понадобится при снятии) и четыре уточнения/дополнения,
которые меняют объём работ.

### 1.1 Подтверждения

| # | Основание | Подтверждение по коду |
|---|---|---|
| 1 | Привязка прав ОБЪЯВЛЯЕТ поле условия и НЕ ЧИТАЕТ его; обновить нельзя | `CreateAccessBindingRequest.condition_id` (тег 6) и `builtin_condition` (тег 7) объявлены в `access_binding_service.proto`; в `services/iam/internal/apps/kacho/api/access_binding/` **ноль** упоминаний `Condition` вне тестов; `GetConditionId()`/`GetBuiltinCondition()` в проде читаются только внутри `api/conditions` и `api/internal_authorize`, никогда на пути привязки. `UpdateAccessBindingRequest` допускает в маске **только** `deletion_protection` и `labels` |
| 2 | Поле ссылается FK на ДРУГУЮ таблицу и другое пространство id, чем сам ресурс условия | `0001_initial.sql`: `access_bindings_condition_fk FOREIGN KEY (condition_id) REFERENCES access_binding_conditions(id)`, где `access_binding_conditions.id ~ '^cond_[a-z0-9_]{1,40}$'`. Ресурс `Condition` живёт в **другой** таблице `conditions` с `id ~ '^cnd[a-z0-9]{1,17}$'`. Два пространства id, две таблицы |
| 3 | В связующую таблицу нет ни одного прод-INSERT; единственный читатель — счётчик ссылок, структурно всегда ноль | Единственные прод-обращения к `access_binding_conditions`: `SELECT COUNT(*)` в `countConditionReferences` (`conditions_repo.go:165`) и ветка маппинга ошибки в `pgmaperr.go:165`. `INSERT`/`UPDATE`/`DELETE` — только в интеграционных тестах и в forward-cleanup миграции `0013` |
| 4 | Вычисление — сопоставление ПОДСТРОК; произвольное выражение отвергается, и отказ подаётся как «вычислено, доступ не разрешён» | `recogniseExpression` (`conditions_evaluator.go:150`) — цепочка `strings.Contains`; нераспознанное → `ErrUnsupportedExpression`. `ConditionsCRUDService.Evaluate` (`conditions_crud_service.go:620`) **специально** гасит именно этот sentinel и возвращает клиенту `allowed=false` + `trace="free-form expression — delegate to FGA"` **без ошибки** |
| 5 | Из шести условий в модели прав на отношение ссылается одно; ни один писатель не прикрепляет условие к записи | `fga_model.fga` объявляет 6 блоков `condition`; `with`-клауза встречается трижды и всегда с `mfa_fresh`: `cluster#console`, `compute_instance#ssh`, `compute_instance#console`. Прод-конструкторы `authztypes.TupleConditionRef` — только read-path (`openfga_read.go:107`) и приём чужого запроса (`internal_authorize/handler.go:184`); путь привязки не строит его никогда |
| 6 | За всю историю стенда — ноль строк | Установлено владельцем на живом стенде. Кодом подтверждается **структурно**: ни одна миграция не сеет ни строки в `conditions`/`access_binding_conditions`; писателя у связующей таблицы нет вовсе. Тем не менее гейт §5.3 требует **пересчитать** перед удалением (счётчик, не рассуждение) |

### 1.2 Уточнения — механика, которую легко описать неверно

**A. Мост между двумя дизайнами существует, но не там, где кажется.** Миграция `0048`
добавила в связующую таблицу производную колонку `access_binding_conditions.condition_id`
(BEFORE-триггер из `params ->> 'condition_id'`) и настоящий `FK REFERENCES conditions(id)
ON DELETE RESTRICT`. То есть FK **связующая-таблица → ресурс** есть. Не соединены другие
два конца: `access_bindings.condition_id` смотрит в связующую таблицу (`cond_`), а не в
ресурс (`cnd`), и у связующей таблицы нет писателя. `0048` выглядит как «соединительная
ткань» и ею не является — это важно, потому что при снятии её FK/триггер/функцию нужно
дропнуть **до** таблиц, а её защитную роль нельзя приводить как аргумент «фича живая».

**B. Тот же класс шире, чем сформулировано.** `Evaluate` гасит `ErrUnsupportedExpression`
не только из ветки «свободное выражение», но и из ветки `default: "unknown builtin"`. Значит
привязка с устаревшим `BREAK_GLASS_WINDOW`/`JIT_WINDOW` тоже вернулась бы клиенту как
«вычислено, доступ не разрешён», а не как отказ. Это ровно
[[checks-with-form-but-no-substance]]: форма ответа есть, содержания нет.

**C. Перечисление, модель и вычислитель расходятся втроём.** `BuiltinCondition` перечисляет
**7** значений (включая deprecated `BREAK_GLASS_WINDOW = 4`); `fga_model.fga` содержит **6**
блоков (`break_glass_window` нет); вычислитель обрабатывает **5** (`jit_window` и
`break_glass_window` уходят в reject-ветку). Ни одна пара не совпадает. Отдельного действия
не требует — все три уходят целиком, — но это довод против «доведения»: согласовывать нечего,
надо переписывать.

**D. `has_list_endpoint.go` описывает состояние, которого НИКОГДА не было — комментарий
неверен ДВАЖДЫ.** Блок `has_list_endpoint.go:28-31` заявляет, что `ConditionsService.List`
«is NOT registered on the api-gateway external mux … Internal/unregistered → false».
Оба утверждения ложны:

1. **Регистрация есть** — `gateway/internal/restmux/mux.go:612`
   (`RegisterConditionsServiceHandlerFromEndpoint`), добавлена правкой задачи #71;
2. **`false` там никогда не возвращался** — сама map'а `noPublicListEndpoint`
   (`has_list_endpoint.go:45-48`) содержит **ровно одну** запись, `"vpc.addressPool"`.
   Записи `"iam.condition"` в ней нет, а `hasPublicListEndpoint` по умолчанию отдаёт
   `true`. То есть комментарий описывал поведение, которого код не производил, — не
   «устарел после #71», а был ложным с момента написания. Это классический
   [[checks-with-form-but-no-substance]] в доке: следующий контрибьютор «починил бы»
   код под неверный комментарий.

Та же ложная фраза продублирована в `ui-future/shared/src/lib/resourceInstanceFetchers.ts:49`
(«не зарегистрирован на external, has_list_endpoint=false»). Оба комментария уезжают вместе
с поверхностью (§4 S1), но зафиксировать надо именно это: **в наборе не появляется
«починка» — из него удаляется ложное утверждение** (`architecture.md` doc-truthfulness).

### 1.3 Дополнения — что нашлось рядом и меняет объём

**E. `AccessBinding.expires_at` — ЖИВОЙ, ретайру НЕ подлежит.** Комментарий в proto
приписывает его OPA («OPA gates evaluation by `now() < expires_at`»), а OPA-оверлей из кода
удалён. TTL реально энфорсится **другим** механизмом — **периодической подметающей
свёрткой реконсайлера**, а не синхронно на чтении. Точная цепочка (перепроверена в круге 4,
файл и строка — иначе это снова «описание механизма»):

1. `seed/reconcile_worker.go:187` — свёртка зовёт `ListExpiredBindingIDs`;
2. `repo/kacho/pg/reconcile_adapter.go:992-1009` — `SELECT id … WHERE status='ACTIVE'
   AND expires_at IS NOT NULL AND expires_at < now()`;
3. `api/access_binding/reconcile/reconcile.go:~670-700` — `ExpireBinding`: загрузка,
   затем **атомарный CAS** `RevokeExpiredBinding`;
4. `reconcile_adapter.go:979-989` — сам CAS: `UPDATE … SET status='REVOKED',
   revoked_at=now() WHERE id=$1 AND status='ACTIVE'`, `RowsAffected()==1` (ban #10);
   0 строк ⇒ другой путь уже отозвал ⇒ кортежи не трогаются;
5. далее по членам привязки снимаются per-object кортежи (отложенно, `flushDeletes`).

Наблюдаемое следствие для приёмки: **истечение не мгновенно** — оно наступает в такте
свёртки, поэтому регрессия IAM-C-33 формулируется через свёртку, а не через «подождали».
Регрессия на этот механизм **уже существует** и переиспользуется:
`TestC23_ExpiredRulesBinding_EagerRevoke`
(`services/iam/internal/repo/kacho/pg/reconcile_rules_integration_test.go:302`).

Поэтому `expires_at` остаётся, а его proto-комментарий **правится** в этом же
ретайре (иначе после снятия OPA-упоминаний останется ложный след).

**F. Доставка guardrail-политик OPA — мёртвый код шаблонов за навсегда выключенным
флагом (LEAN).** Оверлей `data.kacho.iam.guardrails.deny` из кода удалён
(`authorize_service.go:19`), Go нигде не читает `KACHO_OPA_*`. Шаблоны доставки при этом
в дереве остались, но **ничего не деплоят**: все они обёрнуты в
`{{- if .Values.opaSidecar.enabled }}`, а флаг `false` во **всех** профилях —
`charts/kacho-iam/values.yaml:361`, `umbrella/values.yaml:124`, `values.dev.yaml:1234`;
`values.prod.yaml:825-827` задаёт **другую** ручку (top-level `opaSidecar.networkPolicy.enabled`)
и `opaSidecar.enabled` не включает. Проверено рендером: `helm template
deploy/helm/umbrella/charts/kacho-iam` даёт **ноль** ConfigMap'ов `opa-*` (в выводе только
пустые `# Source:`-заголовки), ноль `envFrom`, ноль `opa-*-checksum`.

> **Правка после ревью круга 1 (замечание принято).** Прежняя редакция этого пункта
> утверждала, что чарт «рендерит два ConfigMap'а, пробрасывает `envFrom` и держит
> `checksum`-аннотацию». Это **фактически неверно** — всё перечисленное за выключенным
> флагом. Утверждение переписано по коду, а не смягчено; следствие для сценария —
> см. переписанный IAM-C-50 (прежняя его редакция была зелёной **до** начала работ, то
> есть являлась «формой без содержания»).

Мёртвая поверхность (полный поимённый список — §4 S5) состоит из **четырёх** классов:

1. **Четыре шаблона за флагом** (ревью назвало три; четвёртый найден при сверке):
   `templates/opa-policies-fallback-configmap.yaml:3`, `templates/opa-bundle-server-configmap.yaml:3`,
   `templates/opa-sidecar-configmap.yaml:3` и `templates/jwks-configmap.yaml:3`. Последний —
   ConfigMap открытого ключа **для проверки подписи OPA-бандла**; его собственная шапка
   уже фиксирует, что «наполнять его НЕКОМУ: JWKS-ротатор удалён, bundle-signing в iam
   отсутствует», то есть он мёртв даже при включённом флаге. Плюс 5 `.rego`-файлов
   в `files/opa-policies/kacho/iam/guardrails/` (среди них `deny_break_glass_too_long.rego`
   и `deny_prod_out_of_hours.rego` — буквально предикаты условного доступа).
2. **Куски `deployment.yaml`** — все за тем же флагом, **кроме метки пода**:
   блок аннотаций-хэшей, блок томов, блок `envFrom`, блок env `KACHO_BUILD_SHA` и блок
   контейнера сайдкара; **и метка пода `kacho.cloud/opa-sidecar: "true"` — БЕЗ флага**,
   она рендерится всегда (видна в выводе `helm template`).
   **Точные границы намеренно НЕ дублируются здесь** — единственный нормативный список
   границ живёт в §4 S5, строка 3 (она предназначена для буквального исполнения). Прежняя
   редакция этого пункта несла **собственный, расходящийся и неверный** набор границ
   (`:67-75` — терял закрывающий `{{- end }}` на `:76` и оставил бы висячий тег;
   `:431-482` — обрывал контейнер сайдкара, который идёт до `:489`), причём §4 S5 по тем же
   двум артефактам называла **третьи** границы. Два расходящихся списка на один артефакт —
   тот же класс, что ретайрится: любой из них выглядит нормативным, оба неверны.
   Дублирование устранено ссылкой (правка круга 2, §11 пункт 4).
3. **Ручки, рендерящиеся БЕЗ флага**: секция `config.authz.opaSidecar` (`values.yaml:261-266`)
   уезжает в `configmap.yaml:135-146` как `authz.opa-sidecar.{url,timeout-ms,fail-mode,read-fail-open}`,
   которые Go не читает вовсе (ноль совпадений `opa-sidecar`/`OpaSidecar` в `services/iam/**.go`).
   Это тот же класс, что §1.3 G, но на другой ручке.
4. **NetworkPolicy, живая в бою**: `umbrella/templates/networkpolicy-authz.yaml:3` читает
   `.Values.opaSidecar.networkPolicy.enabled`, и в проде он `true` (`values.prod.yaml:827`).
   То есть в боевом рендере **реально появляются** политики `opa-bundle-endpoint-ingress`
   (allowlist по метке `kacho.cloud/opa-sidecar=true`) и `opa-sidecar-egress-allowlist` —
   для сайдкара, которого не бывает. Решение по ней — §4 S5, пункт 5 (снимается вместе,
   с сохранением живой части политики).

Это часть той же фичи и снимается вместе с ней (§4, S5).

**G. Ручка чарта для вычислителя условий никогда не читалась.** Чарт рендерит
`authz.conditions.context-cache-ttl-seconds` (из `.Values.config.authz.conditions.contextCacheTtlSeconds`),
а Go читает `conditions.cache-size` / `conditions.cache-ttl-seconds`. Разные ключи — ручка не
подключена ни к чему. Снимается вместе с секцией.

> **Вывод.** Ни одно из шести оснований не опровергнуто. Объём работ расширяется на
> три пункта (E — правка комментария, F — снятие мёртвой доставки OPA **вместе с
> перенацеливанием живого гейта и разбором NetworkPolicy**, G — снятие мёртвой ручки)
> и сужается на ноль.
>
> **Уточнение по кругу 1 ревью.** F после сверки оказался **не тем**, чем был описан:
> не «деплоится и надо выключить», а «мёртвый код за навсегда выключенным флагом».
> Формально это **сужает** технический риск (ничего живого не гасим), но **расширяет**
> объём: рядом обнаружились (а) четвёртый шаблон за тем же флагом, (б) метка пода и
> секция `config.authz.opaSidecar`, рендерящиеся **без** флага, (в) живой в бою
> `networkpolicy-authz.yaml`, который нельзя снять целиком без потери действующего
> контроля изоляции хранилища прав (R12), и (г) гейт `config-rollout-binding-test.sh`,
> включающий эту ручку явным `--set` (R13). Ни один из четырёх пунктов не был виден из
> прежней формулировки.
>
> ⚠️ **Правка круга 4 — пункт (г) назывался «живой CI-гейт», и это неверно.**
> `deploy/tests/helm/config-rollout-binding-test.sh` **не вызывается ниоткуда**: ни из
> одного workflow, ни из одного Makefile. Единственное упоминание за пределами самого
> скрипта — **комментарий** в `deploy/scripts/assert-production-posture.sh:79`. Job
> `helm lint · template (dev + prod)` (`.github/workflows/ci.yaml:273`) исполняет
> `helm lint`, два `helm template`, `.github/scripts/check-volume-mounts.sh` и
> `make -C deploy check-mtls-off-complete` — и **ничего** из `deploy/tests/helm/`. То есть гейт
> сегодня не наблюдает ничего вообще: он не «превратится в форму без содержания после
> снятия ручки», он уже ею является. Это ровно предмет задачи **#81** (третий её пункт:
> «команда гейта не исполняется из корня и не вызывается в CI»). Следствие для R13:
> убрать мёртвый `--set` — **необходимо, но недостаточно**; гейт обязан быть подключён
> к CI в том же PR, иначе IAM-C-53 проверяет скрипт, который никто не запускает.
> Исход и критерий закрытия — §12, строка O-1.

---

## 2. Решения и обоснования

| Решение | Обоснование |
|---|---|
| **R1. Снимаем целиком, без окна устаревания.** Ни `deprecated`-разметки, ни «сначала выключим, потом удалим» | Окно устаревания нужно, чтобы дать потребителям съехать. Потребителей нет (§1, §5.1), строк нет. Оставленная на окно поверхность продолжала бы отвечать «вычислено, доступ не разрешён» — **вводящий в заблуждение** ответ, хуже честного отказа. ban #11 |
| **R2. Файлы proto удаляем, теги тумбстоним.** Теги `AccessBinding` 9/14, `CreateAccessBindingRequest` 6/7, `Tuple` 4 — в `reserved` навсегда; сами файлы `condition.proto`, `conditions_service.proto`, `builtin_condition.proto`, `access_binding_condition.proto` удаляются | Append-only дисциплина тегов — уже действующая конвенция репозитория (`access_binding.proto` держит тумбстоны 15/16/17/18). Тумбстон защищает провод; пустой файл-скелет не защищает ничего и является vestigial-кодом (LEAN) |
| **R3. `buf breaking` — осознанно красный, с точным заявленным набором правил.** Конфиг `buf.yaml` **не** ослабляется | Прецедент зафиксирован: «`buf breaking` would be deliberately red for that coordinated major» (`services/iam/docs/architecture/resource-scoped-access-binding-delta.md`). Ослабление категории `FILE` скрыло бы **посторонние** поломки в этом же PR. Гейт merge — «упало ровно то, что заявлено, и ничего сверх» (§5.4) |
| **R4. Отношения, гейтированные `mfa_fresh` (`cluster#console`, `compute_instance#ssh`, `compute_instance#console`), УДАЛЯЮТСЯ, а не «расконжичиваются»** | Это единственные потребители `mfa_fresh`. Записей каталога у них 0, писателей 0, сидов 0 — они мертвы независимо от условия. Оставить их без условия значит оставить **живо выглядящее** отношение, которое ничего не даёт: тот же класс «форма без содержания». Настоящий step-up остаётся: `required_acr_min` (§8) |
| **R5. Контекст условия на запросе снимается** (`AuthorizeCheckRequest.context` тег 4, `ListObjectsRequest.context` тег 6 → тумбстон; `buildCondContext` / `serverAuthoritativeCondKeys` удаляются) | Без условий в модели контексту не с чем сопоставляться — FGA его игнорирует. Поле запроса, которое молча игнорируется, — тот же класс. **Безопасность при этом не снижается**: `serverAuthoritativeCondKeys` был анти-подделочным фильтром именно этого контекста; когда контекста нет, подделывать нечего. Это утверждение обязано быть проверено сценарием IAM-C-25, а не принято на слово |
| **R6. `expires_at` остаётся; правится только его proto-комментарий** | TTL энфорсится реконсайлером (§1.3 E), а не снимаемой машинерией. Удалить живой TTL под видом «ретайра условного доступа» было бы регрессом безопасности |
| **R7. Схема БД: НОВАЯ миграция на удаление; применённые не редактируются** | Non-negotiable #5. Практическое следствие: `0001` продолжит **создавать** таблицы на свежей БД, а новая миграция — удалять их в конце цепочки. Это нормально и обязано быть проверено (IAM-C-31), иначе «оптимизация» вида «вырежем из 0001» порвёт цепочку на существующих стендах |
| **R8. Дроп-миграция сначала СЧИТАЕТ, потом удаляет.** Непустая таблица → `RAISE EXCEPTION`, миграция не проходит | «Счётчик строк, не рассуждение». Ноль строк установлен на **одном** стенде; миграция поедет и на другие. Обоснование «данных нет, облако не в проде» (`data-integrity.md`) снимает необходимость **переноса**, но не необходимость **проверки** |
| **R9. Down-миграция восстанавливает ПРЕД-ДРОПОВУЮ форму DDL** (пост-`0070` / пост-`0048` / пост-`0013`), а не форму `0001` | Строк нет по определению (R8 это гарантирует), поэтому down/up лосслесс **по данным**. Но «лосслесс» и «обратимо» — разные утверждения: обратимость держится только если down отдаёт схему **в точности той формы, которую увидел бы предыдущий шаг цепочки**. Основание — **два, и они разной природы** (см. разбор в §4 S3): (а) **реальный отказ цепочки** — восстановление формы `0001` уронило бы `goose down` через `0070` на первом же стейтменте `ALTER TABLE kacho_iam.conditions RENAME COLUMN project_id TO folder_id` (`0070:50`): колонки `project_id` не существует ⇒ `42703 undefined_column`; (б) **точная обратность up** — для whitelist'а выражений отказа цепочки **нет вовсе** (Down `0013` начинается с `DROP CONSTRAINT IF EXISTS`, `0013:71-72`, и только потом `ADD`, `:74-84` — откатывается любая форма), поэтому его форма держится исключительно на требовании «down = точный обратный up», проверяемом поэлементным совпадением со снимком схемы. Точный список формы — §4 S3; проверяется IAM-C-34 (снимок схемы) и IAM-C-35 (ещё два шага down). Down-заглушка «ничего не делаем» сделала бы миграцию необратимой без выигрыша |
| **R10. Записи vault не удаляются, а переписываются в retirement-record** | Vault — память о причине. Удалённая записка через полгода = «а почему у нас нет условного доступа?» → кто-то реализует его заново с теми же шестью дефектами. Запись обязана нести: что было, почему не работало, что снято, каким PR, и условие возврата (§7) |
| **R11. Анти-реинтродукция — машинные гейты, не договорённость** | Четыре точных гейта (§6, S6): каталог разрешений, модель прав, каталог id-префиксов, схема БД. Гейт на слово «condition» в тексте запрещён — он шумный и его отключат |

### Что здесь про производительность и безопасность (акцент владельца)

**Производительность.** Снятие строго вычитающее. Выигрыш ровно один — и он **уже,
чем говорилось до круга 4**:

- уходит копирование map'а контекста условия: `buildCondContext`
  (`authorize_service.go:79-92`) аллоцирует новый `map[string]any` размером
  `len(reqContext)+1`, копирует в него весь клиентский контекст, затем удаляет **8**
  серверно-авторитетных ключей (`serverAuthoritativeCondKeys`, `:58-66`) и дописывает
  `current_time`/`acr_value`. Вызывается **ровно из двух мест**: `AuthorizeService.check`
  (`:200` → `:272`, за ним публичные `Check` и `BatchCheck`) и `ListObjects`
  (`:579` → `:596`).

> ⚠️ **Исправлено в круге 4 — прежняя формулировка «на каждый `Check`» была ложной.**
> Per-RPC гейт, который api-gateway дёргает на **каждом** запросе платформы, — это
> `InternalIAMService.Check` (`api/internal_iam/handler.go:271`) → `AuthorizeService.
> CheckRelation` (`authorize_service.go:396`). Эта функция `buildCondContext`
> **не вызывает вовсе**: она строит литерал из одного ключа —
> `condCtx := map[string]any{"current_time": now.Unix()}` (`:414`), и её запрос
> (`CheckRequest`) поля `context` вообще не несёт. Значит настоящая горячая полоса
> энфорсмента **этой аллокации не платит и не платила**, и снятие условного доступа
> её латентность не улучшает. Экономия относится к **публичной** `AuthorizeService.Check`/
> `BatchCheck`/`ListObjects` — RPC, которые зовёт клиент/UI, а не интерсептор шлюза.
> Утверждение «обе горячие полосы» удалено; IAM-C-70 перенацелен на те RPC, где эффект
> действительно возможен (см. сценарий).

**Вне горячего пути** (и потому НЕ входит в перф-приёмку):

- процесс-глобальный LRU распознавания выражений под одним мьютексом
  (`BuiltinEvaluator.mu`, `conditions_evaluator.go:78,151-152`). Прежняя редакция
  относила его к «горячему пути авторизации» — **это неверно**: единственный прод-вызов
  `evaluator.Evaluate` — `conditions_crud_service.go:614`, достижимый только через
  handler `api/conditions/handler.go:140`, то есть через RPC `ConditionsService/Evaluate`.
  На `AuthorizeService.Check` / `ListObjects` он не попадает никогда. Утверждение
  исправлено по коду (замечание ревью принято); мьютекс уходит вместе с вычислителем,
  но выигрышем на авторизации это не является и в базовой линии IAM-C-70 не измеряется.
- модель прав уменьшается на 6 блоков условий, один тип и три отношения — меньше рёбер
  для резолва и меньше тело `WriteAuthorizationModel`. Эффект **ожидается в пределах
  шума** и приёмкой не является: измеряется той же парой замеров, но проходным
  критерием служит только отсутствие регресса.

DoD требует не «стало быстрее», а **отсутствие регресса с явным допуском**: спецификация
инструмента, профиля нагрузки, длительности, числа прогонов и полосы — IAM-C-70.
Улучшение приветствуется, но предметом приёмки не является. С учётом правки выше
**ожидание сдвинуто честно**: измеряется отсутствие регресса на публичной полосе, а не
обещанное ускорение per-RPC энфорсмента, которого не будет.

**Безопасность.** Снимается:
- публичный RPC (`ConditionsService.Evaluate`), принимавший **произвольный
  caller-supplied контекст** на внешнем листенере;
- ответ, в котором **отказ подан как решение** (`allowed=false` вместо ошибки) — прямой
  путь к ложной уверенности администратора, что выражение работает;
- мёртвый MFA-гейт (`mfa_fresh` на `ssh`/`console`), который читается как живое требование
  MFA и им не является;
- два неподключённых пространства id (`cnd`, `cond_`) — меньше поверхности для путаницы
  адресации (ban #15);
- деплоящиеся, но никем не читаемые guardrail-политики и их ConfigMap'ы.

Не снимается ничего из действующих контролей: `required_acr_min`, `expires_at`,
per-RPC `Check`, listauthz, hide-existence, каскад супер-доступа (§8).

---

## 3. Порядок по build-графу

Внутри монорепо `project/kacho` слои не разъезжаются по PR'ам — удаление proto без удаления Go
не компилируется. Поэтому декомпозиция **вертикальная по поверхностям**, а внутри каждой стадии
порядок правок — по графу `proto → gen (pkg/api) → services/iam → gateway → deploy → tests → docs/vault`.

```
S0  доказательство отсутствия потребителей        (без правок кода; гейт на S1..S6)
 └─ S1  публичная поверхность Condition           (proto+gen+iam+gateway+newman+config+chart-knob)
     └─ S2  поля условия на привязке и на кортеже (proto+gen+iam+dto+repo-чтение)
         └─ S3  схема БД                          (новая миграция + repo-колонки + маппинг ошибок)
             └─ S4  модель прав                   (fga_model.fga + configmap regen + authzmap + re-pin)
                 └─ S5  доставка guardrail-политик (chart + разбор NetworkPolicy + перенацел. гейта)
                     └─ S6  память и анти-реинтродукция (vault, docs, CI-гейты)
```

Каждая стадия — самостоятельный green-committable срез: дерево компилируется, все гейты
зелёные (кроме заявленного `buf breaking` на S1/S2/S4), стенд поднимается. Порядок
S2 → S3 обязателен: колонку нельзя дропать, пока Go её читает. Порядок S3 → S4 некритичен
технически, но выбран так, чтобы смена id модели (требующая перекатки сервисов) была
**последней** мутацией стенда.

---

## 4. Что именно удаляется

### S1 — публичная поверхность `Condition`

| Слой | Артефакт |
|---|---|
| proto | `iam/v1/condition.proto`, `iam/v1/conditions_service.proto` (сервис + **6** RPC — `Get`/`List`/`Create`/`Update`/`Delete`/`Evaluate`, `conditions_service.proto:28,40,54,72,92,114` — + 8 message'й + 3 metadata-типа). Шесть согласуется с остальным документом: 6 записей каталога, 6 строк allowlist, 6 REST-маршрутов; прежнее «5» было внутренней несогласованностью |
| gen | `pkg/api/.../condition.pb.go`, `conditions_service.pb.go`, `conditions_service_grpc.pb.go`, `conditions_service.pb.gw.go` |
| iam · domain | `internal/domain/condition.go` |
| iam · repo | `internal/repo/kacho/condition/iface.go`, `internal/repo/kacho/pg/conditions_repo.go` (+ ссылка в `pg/helpers.go`, `repo/kacho/iface.go`) |
| iam · service | `internal/service/conditions_crud_service.go`, `conditions_evaluator.go`, `conditions_audit.go` (3 типа событий аудита `iam.condition.{created,updated,deleted}`) |
| iam · handler | `internal/apps/kacho/api/conditions/` целиком |
| iam · authorize (**LEAN-остаток, найден в круге 2**) | элемент `"evaluate"` из viewer-ветки резолвера глаголов `resolveActionToRelation` (`internal/service/authorize_service.go:824-830`, сам элемент — `:829`). После снятия разрешения `iam.conditions.evaluate` эта ветка становится **мёртвой**: `evaluate` — **единственный** глагол `evaluate` во всём каталоге (`gateway/internal/middleware/embed/permission_catalog.json:1307` и байт-идентичная копия сида; в proto — единственная аннотация `conditions_service.proto:116`). Остальные элементы обеих `case`-строк **остаются**. Симметрично снятию `ssh`/`console` из соседней passthrough-ветки `:835` (§4 S4) — тот же класс, другая ветка |
| iam · wiring | `cmd/kacho-iam/grpc_register.go` (регистрация), `cmd/kacho-iam/wiring.go` (`conditionsHandler`, `buildAuthZServices` ветка) |
| iam · config | `ConditionsConfig`, дефолты `conditions.cache-{size,ttl-seconds}`, env-алиасы `KACHO_IAM_CONDITIONS_CACHE_*`, две проверки в `Config.Validate()` |
| ids | `"cnd"` из `domainStringPrefixes` (`pkg/ids/ids.go`) |
| gateway | 6 строк allowlist, регистрация в `gateway/internal/restmux/mux.go:612`, 6 строк `rest_route_table_gen.go`, 6 записей в **обеих** tracked-копиях `permission_catalog.json`, ложный комментарий-исключение в `services/iam/internal/apps/kacho/api/permission_catalog/has_list_endpoint.go:28-31` (§1.2 D) |
| tests · снимаются | `services/iam/tests/newman/cases/iam-condition.py` (**4** кейса `IAM-CND-*`: `IAM-CND-CR-CRUD-OK` `:52`, `IAM-CND-CR-VAL-UNSCOPED` `:145`, `IAM-CND-UP-CRUD-OK` `:176`, `IAM-CND-LS-AUTHZ-NOBINDINGS-DENY` `:305` — ровно четыре `CASES.append(Case(` в файле; **не 6**, прежняя цифра была ошибочно перенесена из счёта RPC/записей каталога/маршрутов, где 6 верно), `collections/iam-condition.postman_collection.json`, вызов `run_one "iam-condition"` в `services/iam/tests/newman/scripts/run.sh:177` (**не** `tests/newman/run.sh` — такого файла нет) + его комментарий `:173-176`, `internal/fuzz/fuzz_cel_expression_test.go`, `api/conditions/*_test.go`, `pg/conditions_*_integration_test.go`, `service/conditions_*_test.go` |
| tests · **добавляются** | новый набор `services/iam/tests/newman/cases/iam-conditional-retired.py` (кейсы `IAM-CRET-*`, §6.0) + его вызов `run_one "iam-conditional-retired"` в `scripts/run.sh` — иначе набор лежит в `collections/`, не выполняется и даёт фантомный `(no-report)` (тот же класс, что снимаемый) |
| tests · **правятся** (иначе регенерация каталога и снятие типа их уронят) | `gateway/internal/middleware/permission_catalog_test.go` · `gateway/internal/middleware/permission_catalog_acr_invariant_test.go` · `services/iam/internal/apps/kacho/api/permission_catalog/usecase_test.go` · `services/iam/internal/authzmap/fga_types_test.go` · `services/iam/internal/authzmap/super_admin_cascade_test.go:319` (в списке leaf-типов, у которых `super_admin` обязан каскадить от проекта, стоит `iam_condition` — убрать элемент, **не** ослаблять само утверждение: остальные 7 типов продолжают проверяться) |
| chart | секция `config.authz.conditions` в `charts/kacho-iam/values.yaml:259-260` и её рендер в `templates/configmap.yaml:115-122` (мёртвая ручка, §1.3 G) |
| ui | ложный комментарий в `ui-future/shared/src/lib/resourceInstanceFetchers.ts:49` — дословный дубль неверной фразы из `has_list_endpoint.go` (§1.2 D); страницы у ресурса не было |

### S2 — поля условия на привязке и на кортеже

| Слой | Артефакт |
|---|---|
| proto | `AccessBinding.condition_id` (9) и `builtin_condition` (14) → `reserved`; `CreateAccessBindingRequest.condition_id` (6) и `builtin_condition` (7) → `reserved`; `Tuple.condition` (4) → `reserved`; удаляются `message TupleCondition`, `builtin_condition.proto`, `access_binding_condition.proto` |
| iam · domain | `AccessBinding.ConditionID`, тип `AccessBindingConditionID` (`domain/access_binding_condition.go`), whitelist-константы в `domain/constants_extended.go` |
| iam · dto | `toproto/access_binding.go` — заполнение `ConditionId` |
| iam · repo | `condition_id` из списка колонок SELECT/INSERT (`access_binding_repo.go`), сканирование в `ab.ConditionID` |
| iam · authz | `authztypes.ConditionalTuple.Condition`, `authztypes.TupleConditionRef`, `clients/openfga_read.go` (сборка условия при чтении), `clients/openfga_extensions.go` (алиас), `service/fga_tuple_writer.go` (`Condition`, `equalCondition`) |
| iam · handler | `internal_authorize/handler.go` — маппинг `TupleCondition` в обе стороны |
| iam · authorize | `buildCondContext`, `serverAuthoritativeCondKeys`, параметр `condCtx` в порту `Authorizer` и во всех его реализациях; `AuthorizeCheckRequest.context` / `ListObjectsRequest.context` → `reserved` |
| proto · комментарии | `AccessBinding.expires_at` — снять ложную атрибуцию OPA, описать реальный энфорсер (реконсайлер, §1.3 E) |

### S3 — схема БД

Новая миграция `services/iam/internal/migrations/00NN_drop_conditional_access.sql`
(номер = следующий свободный после `0070`; **каталог назван явно** — все ссылки вида
`0001`/`0013`/`0048`/`0070` в этом документе означают файлы **этого** каталога, тесты же
живут отдельно, в `services/iam/internal/repo/kacho/pg/`), порядок стейтментов обязателен:

1. пред-проверка: `SELECT count(*)` по `conditions`, `access_binding_conditions`,
   `access_bindings WHERE condition_id IS NOT NULL` → любой ненулевой ⇒ `RAISE EXCEPTION`
   с текстом, называющим таблицу и число строк;
2. `ALTER TABLE access_bindings DROP CONSTRAINT access_bindings_condition_fk`;
3. `ALTER TABLE access_bindings DROP COLUMN condition_id`;
4. `DROP TRIGGER access_binding_conditions_sync_condition_id_trg` + `DROP FUNCTION
   access_binding_conditions_sync_condition_id()`;
5. `DROP TABLE access_binding_conditions` (уносит `access_binding_conditions_condition_fk`,
   `_binding_fk`, `_pkey`, `_binding_unique` и **ЧЕТЫРЕ** CHECK'а: `_created_by_check`,
   `_expression_whitelist_ck`, `_id_check`, `_params_object_ck`);
6. `DROP TABLE conditions` (уносит `conditions_pkey`, `conditions_project_name_uniq`,
   `idx_conditions_project_status` и **ШЕСТЬ** CHECK'ов: `conditions_description_length`,
   `conditions_expression_length`, `conditions_project_id_not_empty`, `conditions_id_check`,
   `conditions_name_pattern`, `conditions_status_whitelist`).

> **Разбор чисел (обе прежние цифры были неверны; одна из поправок ревью — тоже).**
> - `conditions`: **шесть** CHECK'ов, а не четыре — `0001_initial.sql:373-378` объявляет
>   шесть, `0070:41-43` **подменяет** один из них (`_folder_id_not_empty` →
>   `_project_id_not_empty`), не меняя количества. Замечание ревью верно, принято.
> - `access_binding_conditions`: **четыре** CHECK'а, а не три. Ревью утверждает, что
>   «четвёртый, `_expression_whitelist_ck`, дропнут в `0013:53`» — **это неверно**.
>   `0013_drop_jit_breakglass_condition_whitelist.sql` не дропает ограничение, а
>   **пересоздаёт его суженным**: `:52-53` — `DROP CONSTRAINT IF EXISTS`, а `:55-63`
>   тут же `ADD CONSTRAINT access_binding_conditions_expression_whitelist_ck CHECK
>   (expression = ANY (ARRAY['mfa_fresh','non_expired','source_ip_in_range',
>   'business_hours','device_compliant']))` — 5 значений вместо 7 в `0001:200`.
>   Симметрично в Down (`:71-84`) восстанавливается 7-значный вариант. Ограничение
>   с этим именем **живо на момент дропа**, поэтому CHECK'ов четыре.
>
> **Отдельно — обоснование формы whitelist'а в down (исправлено в круге 2, прежнее было
> выдумано).** Прежняя редакция §4 S3, R9, IAM-C-35 и §10.2 A **четырежды** утверждала, что
> восстановление 7-значного варианта уронило бы `goose down` через `0013` на
> `42710 duplicate_object`. **Это неверно по коду.** Down `0013` устроен так же, как его Up:
> `ALTER TABLE … DROP CONSTRAINT IF EXISTS access_binding_conditions_expression_whitelist_ck`
> (`0013:71-72`) и **только затем** `ADD CONSTRAINT …` (`:74-84`). `DROP … IF EXISTS` снимает
> ограничение **любой** формы (и 5-значное, и 7-значное, и отсутствующее), поэтому последующий
> `ADD` никогда не встречает имя занятым — `42710` в этой цепочке недостижим ни при каком
> состоянии схемы. Требование к down при этом **остаётся в силе**, но по другому основанию:
> down обязан быть **точным обратным** своего up (иначе `goose up → down → up` — не тождество,
> а «похожая» схема), и это проверяется поэлементным совпадением со снимком (IAM-C-34), а не
> отказом БД. Отказ цепочки даёт **только** переименование колонки — `0070:50`, `42703
> undefined_column`; whitelist его не даёт. Обоснование заменено, требование — нет.

**Форма down-миграции — не «структуры на месте», а побайтовое совпадение с пред-дроповым
снимком (уточнение R9, было незадано).** На момент дропа обе таблицы несут **пост-0070 /
пост-0048 / пост-0013** форму, а не форму `0001`:

| Что | Форма `0001` (наивно) | Форма на момент дропа (**правильная для down**) |
|---|---|---|
| колонка scope в `conditions` | `folder_id` (`0001:364`) | **`project_id`** (`0070:35`) |
| UNIQUE-индекс | `conditions_folder_name_uniq` (`0001:1325`) | **`conditions_project_name_uniq`** (`0070:37`) |
| status-индекс | `idx_conditions_folder_status` (`0001:1366`) | **`idx_conditions_project_status`** (`0070:38`) |
| CHECK непустоты scope | `conditions_folder_id_not_empty` (`0001:375`) | **`conditions_project_id_not_empty`** (`0070:43`) |
| whitelist выражений | 7 значений (`0001:200`) | **5 значений** (`0013:55-63`) |
| колонка `access_binding_conditions.condition_id` + FK + триггер + функция | отсутствуют | **присутствуют** (`0048:42,63,79,88-89`) |

Требование к down: **восстановить пред-дроповую форму, а не форму `0001`** — по
явному списку колонок, индексов, ограничений и триггеров, сравнением со снимком схемы,
снятым до применения дропа. Иначе up→down→up (IAM-C-34) всё равно пройдёт — он
проверяет только «структуры есть», — а следующий шаг `goose down` **через `0070`**
упадёт на `ALTER TABLE kacho_iam.conditions RENAME COLUMN project_id TO folder_id`
(`0070:50`): колонки `project_id` не существует, потому что down дроп-миграции
восстановил `folder_id`. Проверяется IAM-C-34 (усилен) и новым IAM-C-35.

Сопутствующее: ветка `access_binding_conditions_condition_fk` в `pg/pgmaperr.go:165` и её
unit-тест; интеграционный тест `migrations_iam_extensions_integration_test.go`,
утверждающий **наличие** `access_bindings.condition_id`, переворачивается в утверждение
**отсутствия**.

Миграции `0001`, `0013`, `0048`, `0070` **не редактируются** (R7).

### S4 — модель прав

| Артефакт | Что |
|---|---|
| `proto/kacho/cloud/iam/v1/fga_model.fga` | 6 блоков `condition {...}`; `type iam_condition` целиком; отношения `cluster#console`, `compute_instance#ssh`, `compute_instance#console` (R4) |
| `deploy/helm/umbrella/charts/openfga-bootstrap/templates/openfga-model-stub-configmap.yaml` | перегенерировать: **`cd deploy && make -C deploy openfga-model-json`** (цель — `deploy/Makefile:452`, генератор — `deploy/scripts/gen-openfga-model-configmap.py`; из корня монорепо цели нет — корневого `Makefile` не существует вовсе). Блоки `model.fga` и `model.json` обязаны сойтись с каноном — гейты **C-1/C-2** в `services/iam/internal/authzmap/fga_model_configmap_identity_test.go` |
| `services/iam/internal/authzmap/fga_types.go` | `"iam_condition"` из `objectTypes`; `"iam.condition" → "iam_condition"` из точечного реестра |
| `services/iam/internal/service/authorize_service.go` | passthrough-ветка `case "ssh", "console", "admin", "editor", "viewer":` (`:835`) — убрать `ssh`/`console`, оставить `admin`/`editor`/`viewer` (после удаления отношений эти два глагола обязаны падать в fail-closed `""`, а не резолвиться в несуществующее отношение). **Второй элемент того же файла — `"evaluate"` из viewer-ветки `:829` — снимается в S1** (см. §4 S1, строка «iam · authorize»); здесь он назван, чтобы обе правки одного файла были видны рядом |
| **НОВЫЙ артефакт** — предполётный гейт условных кортежей (R14) | `services/iam/cmd/kacho-iam/` — подкоманда `authz preflight-model-change`; см. R14 ниже |
| стенд | новый `authorization_model_id`; `KACHO_IAM_OPENFGA_MODEL_ID` перепинить и перекатить сервисы — **один раз, на свободном стенде** |

**R14. Предполётный гейт — подкоманда `kacho-iam`, а не разовый скрипт.** Замечание ревью
принято: IAM-C-43 требовал «предполётный гейт», которому ни одна таблица §4 не назначала
слоя — непонятно было, где он живёт и кто его пишет. Решение:

- **Где живёт:** `services/iam/cmd/kacho-iam/` — подкоманда `authz preflight-model-change`
  (тот же бинарь, отдельный entrypoint, как `cmd/migrator`; `architecture.md` §composition
  root). Не отдельный скрипт в `deploy/`: гейт читает домен прав и обязан ездить вместе
  с сервисом, а не жить рядом с чартами.
- **Механика уже есть, изобретать нечего:** `InternalAuthorizeService.ReadTuples`
  (`proto/kacho/cloud/iam/v1/internal_authorize_service.proto:55`, реализация
  `services/iam/internal/apps/kacho/api/internal_authorize/handler.go:98`) постранична
  (`page_size`/`page_token`), то есть полный обход выразим без новых RPC.
- **Что делает:** постранично обходит **все** кортежи хранилища, считает кортежи с
  непустым `condition`, и при счёте `> 0` — **отказывает до записи модели**, называя
  число. Обход обязан быть доказуемо полным: подкоманда печатает число страниц и общее
  число кортежей (усечённый обход, докладывающий «ноль», — ровно
  [[checks-with-form-but-no-substance]]).
- **Кто зовёт:** процедура смены модели на стенде (шаг перед `WriteAuthorizationModel`),
  и она же — в DoD S4. Гейт **не** является частью старта сервиса: он одноразовый,
  оператору, и не должен блокировать boot.
- **Живёт ли после ретайра:** да. После снятия условий появление условного кортежа —
  признак реинтродукции или ручной записи в обход модели; гейт остаётся дешёвым
  оператором-контролем и переиспользуется при любой следующей смене модели.
- Проверяется IAM-C-43 (искусственно записанный **ровно один** условный кортеж → отказ).

### S5 — доставка guardrail-политик (чарт + разбор NetworkPolicy + перенацеливание гейта)

Все пути — от `project/kacho/`. Перечислено **поимённо**: буквальное исполнение прежней
редакции («убрать блок OPA-ручек в `values.yaml`») сломало бы гейт привязки перекатки и
уронило бы боевой рендер на nil — см. пункты 5 и 6. Порог полноты один и тот же во всех
местах документа: **`grep -rl opaSidecar deploy/helm/` = пусто** (сегодня 13 файлов).

| # | Артефакт | Что делаем |
|---|---|---|
| 1 | `deploy/helm/umbrella/charts/kacho-iam/files/opa-policies/kacho/iam/guardrails/*.rego` (5 файлов: `deny_break_glass_too_long`, `deny_prod_out_of_hours`, `deny_cross_tenant`, `deny_sa_grant_user`, `deny_billing_destructive`) | удалить каталог целиком |
| 2 | `charts/kacho-iam/templates/opa-policies-fallback-configmap.yaml` · `opa-bundle-server-configmap.yaml` · `opa-sidecar-configmap.yaml` · `jwks-configmap.yaml` — **четыре** шаблона, все за `{{- if .Values.opaSidecar.enabled }}` | удалить файлы |
| 3 | `charts/kacho-iam/templates/deployment.yaml` — **шесть блоков** (пять за флагом `opaSidecar.enabled` + метка пода **вне** флага), **границы ниже отдельной таблицей** (по целым блокам, включая направляющий комментарий и закрывающий `{{- end }}`) | удалить шесть блоков целиком; аннотация `kacho.cloud/config-checksum` (`:25`) и `openfga-model-id-rev` (`:29`) **остаются** |
| 4 | `charts/kacho-iam/values.yaml`: блок `opaSidecar:` (`:360-398`, включая `jwks`, `bundle`, `policiesFallback`) **и** блок `config.authz.opaSidecar` (`:261-266`); `charts/kacho-iam/templates/configmap.yaml:125-146` (самодокументация `KACHO_OPA_BUNDLE_*` + рендер `authz.opa-sidecar.*`, которого Go не читает) | удалить. **Не трогать** `values.yaml:56 encKeySecretName: kacho-iam-jwks-enc-key` — это другой ключ (шифрование JWKS-хранилища iam), к OPA отношения не имеет |
| 5 | `umbrella/templates/networkpolicy-authz.yaml` — **живой в бою**, разбирается по политикам, а не сносится | см. решение R12 ниже |
| 6 | `deploy/tests/helm/config-rollout-binding-test.sh:79` (`--set kacho-iam.opaSidecar.enabled=true`) и его утверждение привязки checksum к потребляемым OPA-ConfigMap'ам (`:194-201`) | привести в соответствие — см. R13 |
| 7 | `umbrella/values.yaml:123-186` (блок `kacho-iam.opaSidecar`) · `values.dev.yaml:1233-…` (тот же блок) · top-level `opaSidecar.networkPolicy`: `umbrella/values.yaml:187-195`, `values.dev.yaml:1344-1348`, `values.prod.yaml:824-827`, **`values.fe3455-prod.yaml:148-150`** (боевой профиль Beget — легко упустить, ключ там `false`) | переписать под R12; ни одного осиротевшего ключа `opaSidecar` не остаётся ни в одном профиле |
| 8 | **`charts/kacho-iam/README.md`** — документирует ручку `opaSidecar` как поддерживаемую | привести в соответствие (описать `networkPolicy.authz` вместо снятой ручки). **Найдено в круге 4**: `grep -rl opaSidecar deploy/helm/` даёт **13** файлов, из них после строк 1-7 остаётся ровно этот. Без него порог §5.1 («ноль совпадений по `deploy/helm/`») и порог DoD S5 («ноль по `values*.yaml` + `charts/*/values.yaml`») **расходятся**, и README проваливается в щель между ними — два разных порога на один инвариант, тот же класс, что документ ретайрит |

#### S5, строка 3 — точные границы блоков `deployment.yaml` (единственный нормативный список)

Файл — `deploy/helm/umbrella/charts/kacho-iam/templates/deployment.yaml`, **489 строк**
(последняя строка без завершающего перевода строки, поэтому `wc -l` печатает 488 — при
проверке границ считать по номерам строк, а не по выводу `wc`).

**Правило (введено в круге 2): граница = ЦЕЛЫЙ блок, а не «строки, где встречается `opa`».**
Удаление отдельных строк изнутри `{{- if … }} … {{- end }}` оставляет висячий тег и роняет
рендер; удаление «до последней содержательной строки» оставляет осиротевший `{{- end }}`;
захват строки **после** `{{- end }}` уносит живой соседний ключ. Прежняя редакция ошибалась
всеми тремя способами (см. столбец «Было (неверно)»).

| Блок | **Верная граница** | Что внутри | Было (неверно) — и чем это ломает |
|---|---|---|---|
| метка пода | **`:19-22`** | комментарий `:19-21` + `kacho.cloud/opa-sidecar: "true"` `:22`. **Вне флага** — рендерится всегда | `:22` — оставляет 3 строки комментария об удалённой метке (ложный след, `architecture.md` doc-truthfulness) |
| аннотации-хэши | **`:30-41`** | `{{- if .Values.opaSidecar.enabled }}` `:30`, комментарий `:31-37`, три аннотации `:38-40`, `{{- end }}` `:41` | «`:38`, `:39`, `:40`» — удаляет содержимое, но **оставляет `{{- if }}`/`{{- end }}` пустой парой** и комментарий про три несуществующих ConfigMap'а |
| тома | **`:67-76`** | `{{- if … }}` `:67`, комментарий `:68-69`, `opa-config` `:70-72`, `kacho-iam-jwks` `:73-75`, `{{- end }}` `:76` | §4 S5: `:67-77` — **захватывает `initContainers:` на `:77`** (живая строка, её удаление ломает миграционный init-контейнер). §1.3 F: `:67-75` — **теряет `{{- end }}` на `:76`** ⇒ висячий тег ⇒ рендер падает |
| env `KACHO_BUILD_SHA` | **`:293-298`** | комментарий `:293-294`, `{{- if … }}` `:295`, env `:296-297`, `{{- end }}` `:298` | `:295-298` — оставляет комментарий «OPA bundle server — список knobs…» на `:293-294` |
| `envFrom` | **`:411-418`** | `{{- if … }}` `:411`, комментарий `:412-413`, `envFrom:` `:414-417`, `{{- end }}` `:418` | `:410-418` — **`:410` это `{{- end }}` петли `{{- range $k, $v := .Values.env }}` (`:407-410`)**; его удаление обрывает петлю пользовательских env ⇒ рендер падает |
| контейнер сайдкара | **`:431-489`** | `{{- if … }}` `:431` … `{{- end }}` `:489` (последняя строка файла) | §1.3 F: `:431-482` — обрывает контейнер на середине `securityContext` ⇒ невалидный YAML + осиротевший `{{- end }}` |

**Проверка после удаления (обязательна, в DoD S5):** `helm template
deploy/helm/umbrella/charts/kacho-iam` завершается успешно, и в `deployment.yaml` **ноль**
совпадений `opa` при **сохранённых** `initContainers:`, петле `range … .Values.env` и
валидном YAML вывода. Границы, названные здесь, — единственные нормативные; §1.3 F
собственных границ больше не содержит и ссылается сюда.

**R12. `opaSidecar.networkPolicy` не снимается целиком — он разбирается: одна политика
живая, две мёртвые.** Шаблон `networkpolicy-authz.yaml` эмитит под **одним** `{{- if
.Values.opaSidecar.networkPolicy.enabled }}` (`:3`, закрывается `:200`) **три** политики:

- `openfga-engine-ingress-allowlist` (`:55`) — **ЖИВАЯ и ценная**: ограничивает ingress
  на OpenFGA `:8081`/`:8080` списком «iam + шлюз + backend-поды». К условному доступу
  отношения не имеет, в проде включена (`values.prod.yaml:827`). Снятие всего блока
  **молча убрало бы действующий контроль изоляции хранилища прав** — регресс безопасности
  под видом ретайра, ровно то, что запрещает R6;
- `opa-bundle-endpoint-ingress` (`:105`) — allowlist по метке `kacho.cloud/opa-sidecar=true`
  на bundle-эндпоинт; **мёртвая** (сайдкара нет, метку носит каждый под iam);
- `opa-sidecar-egress-allowlist` (`:152`) — egress сайдкара; **мёртвая** (селектор ни на
  что не матчит).

Решение: удалить политики 2 и 3, **сохранить** политику 1, **переименовать ручку** из
`opaSidecar.networkPolicy.enabled` в `networkPolicy.authz.enabled` (одноимённость с
ретайренной фичей — тот же класс «ложного следа», что и комментарий `expires_at`, §1.3 E),
значения профилей сохранить как есть (dev `false`, prod `true`). Проверяется IAM-C-52.

**R13. Гейт `config-rollout-binding-test.sh` не ослабляется, а перенацеливается —
и подключается к CI.** Скрипт
заводился под инцидент «`envFrom` без `checksum/config`» (kacho-storage, 2026-07-25) и
рендерит третий профиль **специально с включёнными** сайдкарами
(`--set vpc.opa.enabled=true --set compute.opa.enabled=true --set kacho-iam.opaSidecar.enabled=true`,
`:75-81`), потому что «проверять надо конфигурацию, которую чарт СПОСОБЕН выдать, а не
только ту, что включена сегодня» (его собственный комментарий, `:70-74`). После снятия
ручки `kacho-iam.opaSidecar.enabled` этот `--set` станет no-op'ом на несуществующем ключе —
**helm такое не диагностирует**, гейт останется зелёным и превратится в форму без
содержания. Поэтому: `--set kacho-iam.opaSidecar.enabled=true` из третьего рендера убрать
(`vpc.opa.enabled` / `compute.opa.enabled` **остаются** — те сайдкары не в этом scope),
а инвариант «каждый потребляемый ConfigMap имеет свою content-аннотацию» обязан
продолжать проверяться для оставшихся потребителей iam. Проверяется IAM-C-53.

> ⚠️ **Обязательная вторая половина R13 (круг 4).** Сказанное выше исходило из того, что
> гейт живой. **Он не живой**: скрипт не вызывается ни одним workflow и ни одним
> Makefile (§1.3 F). Поэтому «убрать `--set`» само по себе ничего не восстанавливает —
> оно правит текст скрипта, который никто не исполняет. R13 считается выполненным только
> когда сделано **и то, и другое**: (1) мёртвый `--set` убран, (2) скрипт **подключён к
> CI** отдельным шагом job'а `helm lint · template (dev + prod)` — по образцу уже
> подключённых там `.github/scripts/check-volume-mounts.sh` и `make -C deploy check-mtls-off-complete`
> (`.github/workflows/ci.yaml:330-336`). Без (2) IAM-C-53 проверял бы скрипт, который в CI
> не запускается, — то есть был бы экземпляром ровно того класса, ради которого скрипт
> писали. Это предмет задачи **#81**; исход и критерий — §12, строка O-1.

> **Out-of-scope, вынесено явно.** `vpc.opa.*` / `compute.opa.*` — сайдкары **других**
> чартов, живущие за собственными флагами. Их судьба этим документом не решается и
> отдельной под-фазой здесь не заводится: они не являются поверхностью условного доступа
> iam. Если они окажутся тем же мёртвым классом — это предмет отдельного acceptance
> с собственным критерием приёмки («рендер с включённым флагом не производит ни одного
> объекта, который читал бы код»), не этого.

### S6 — память и анти-реинтродукция

`obsidian/kacho/resources/iam-condition.md`, `resources/iam-access-binding-condition.md`,
`rpc/iam-conditions-service.md` → retirement-record (§7); новый
`KAC/IAM-C-conditional-access-retire.md`; `services/iam/docs/components/09-conditions.md` →
короткая записка о снятии со ссылкой на этот документ; секция про Conditions в
`services/iam/docs-site/docs/architecture/authz.mdx`; четыре CI-гейта (§6, S6).

---

## 5. Как доказывается, что потребителей не осталось

Доказательство — не рассуждение, а набор проверок с ожидаемым результатом. Все входят в DoD.

### 5.1 Инвентарь идентификаторов

После S1–S4 каждый из наборов даёт **ноль** совпадений вне удалённых файлов и вне
retirement-записок vault:

- `ConditionsService`, `ConditionID`, `AccessBindingCondition`, `BuiltinCondition`,
  `TupleCondition`, `TupleConditionRef`, `ConditionsEvaluator`, `BuiltinEvaluator`,
  `ErrUnsupportedExpression`, `buildCondContext`, `serverAuthoritativeCondKeys`;
- `iam.conditions.` (пространство разрешений), `iam_condition`, `iam.condition`;
- `access_binding_conditions`, `condition_id`, `parameters_schema`;
- `cnd` в `pkg/ids`, `cond_` в `services/iam`;
- **чарт (S5):** `opaSidecar`, `opa-sidecar`, `KACHO_OPA_`, `opa-policies`,
  `opa-bundle`, `kacho.cloud/opa-` — ноль совпадений по `deploy/helm/` (кроме
  `vpc.opa.*` / `compute.opa.*`, явно вынесенных в §8: инвентарь исключает их
  **поимённо**, а не маской, чтобы исключение было видимым).

**Отдельная, НЕ-масочная проверка (добавлена в круге 2 — маски выше её не ловят).**
Два остатка ретайра выражены **словами общего языка**, а не идентификаторами домена
условий, поэтому ни один набор выше на них не сработает, и они пережили бы гейт
незамеченными:

| Остаток | Точечная проверка | Почему маска не годится |
|---|---|---|
| `"evaluate"` в viewer-ветке резолвера глаголов (`services/iam/internal/service/authorize_service.go:829`) | в `resolveActionToRelation` **отсутствует** строковый литерал `"evaluate"`; параллельно — в обеих tracked-копиях каталога **ноль** разрешений, чей глагол (последний сегмент `permission`) равен `evaluate` | слово `evaluate` встречается в дереве в десятках несвязанных мест (комментарии, чужие домены); маска дала бы шум и была бы отключена |
| `"ssh"` / `"console"` в passthrough-ветке (`:835`) | в `resolveActionToRelation` отсутствуют литералы `"ssh"` и `"console"`; `admin`/`editor`/`viewer` в той же ветке **сохранены** | те же слова живут в UI, доках и чужих сервисах |

Обе проверки формулируются как утверждения **о конкретной функции конкретного файла**
(парсинг Go-AST либо якорный греп по телу функции), а не как поиск по дереву. Их
инъекционная проба — вернуть один литерал обратно ⇒ гейт красный.

> **Что эта проверка НЕ закрывает (круг 4).** Она снимает три конкретных элемента, но не
> **механизм**, из-за которого они там оказались: `resolveActionToRelation`
> (`services/iam/internal/service/authorize_service.go:783`) держит **собственный** словарь
> глаголов, не выводимый из каталога разрешений и с ним не сверяемый. Следующий глагол
> разъедется так же. Это предмет задачи **#75** («внутрисервисная карта зеркалит каталог
> прав; проверено во всех семи сервисах») — исход и критерий в §12, строка O-2. Здешняя
> точечная проверка — не замена той задаче, а локальный якорь на время ретайра.

Инвентарь оформляется как **исполняемый скрипт**, а не как список в PR — иначе он
протухнет. Гоняется по `git ls-files` (untracked build-артефакты и `.claude/worktrees/`
не попадают, §5.2), возвращает ненулевой код при первом же совпадении и проверяется
инъекцией (IAM-C-01).

### 5.2 Компиляция и гейты сборки

**Каждая команда ниже приведена вместе с рабочим каталогом, из которого она реально
исполняется, и с job'ом CI, который её реально наблюдает** (правка круга 4: раньше две
команды были записаны без адреса, а корневого `Makefile` в `project/kacho` **не
существует** — из корня они падают «нет такой цели»).

| Гейт | Команда (и откуда) | Что реально наблюдает в CI |
|---|---|---|
| компиляция | `go build ./...`, `go vet ./...` — из корня | job `build · vet · gofmt · test -race` |
| тесты | `go test ./services/iam/... ./gateway/... -race` **полностью**, без `-short` — из корня | job `build · vet · gofmt · test -race` гоняет `-short`; testcontainers-часть — job `integration (<svc>)`. **Оба** обязаны быть зелёными: `-short` скипает весь S3 |
| каталог разрешений | **`cd gateway && make permission-catalog-check`** (цель — `gateway/Makefile:67`, регенерация — `:49`) | job `permission-catalog · rest-route-table (staleness + copy-drift)`, шаг `permission-catalog staleness + copy-drift`, `working-directory: gateway` (`.github/workflows/ci.yaml:199-201`) |
| таблица REST-маршрутов | **`cd gateway && make rest-route-table-check`** (цель — `gateway/Makefile:94`) — **назван в круге 4**: раньше требование «регенерация не содержит `/iam/v1/conditions`» стояло без команды | тот же job, шаг `rest-route-table staleness`, `working-directory: gateway` (`ci.yaml:208-210`) |
| proto-lint | **`cd proto && buf lint`** | job `buf lint · breaking · generate-diff`, шаг `buf lint`, `working-directory: proto` (`ci.yaml:126-128`) |
| proto-breaking | **`cd proto && buf breaking --against "https://github.com/<repo>.git#branch=main,subdir=proto"`** | тот же job, шаг `buf breaking (vs main)` — **исполняется только на `pull_request`** (`if: github.event_name == 'pull_request'`, `ci.yaml:130-133`). Значит заявленный набор нарушений (§5.4) сверяется **в PR**, а не на push-в-ветку |
| стабы | generate-diff — из корня | тот же job, шаг `generate-diff (стабы в синхроне с .proto)` (`ci.yaml:138`) |
| модель прав | **`cd deploy && make -C deploy openfga-model-json`** + `go test ./services/iam/internal/authzmap/...` | C-1/C-2 (`fga_model_configmap_identity_test.go`), D-1..D-4 / R-1..R-3 (`fga_model_drift_test.go`) — оба в job'е тестов |

Проверяется, что обе **tracked**-копии каталога байт-идентичны и не содержат
`iam.conditions.*`: `gateway/internal/middleware/embed/permission_catalog.json` и
`services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json`.
**Третья копия — `gateway/build/permission_catalog.json` — untracked build-артефакт**
(её нет в `git ls-files`): инвентарь §5.1 обязан её **исключать**, иначе на машине с
прошлым build'ом гейт даст ложное срабатывание на файле, которого нет в репозитории.
Сам инвентарь §5.1 гоняется по tracked-файлам (`git ls-files`), а не по рабочему дереву:
`build/`, `node_modules/`, `.claude/worktrees/` в него не попадают.

### 5.3 Состояние стенда — считаем, не рассуждаем

Снимается **до** применения дроп-миграции и прикладывается к тикету:

- `SELECT count(*) FROM kacho_iam.conditions` = 0;
- `SELECT count(*) FROM kacho_iam.access_binding_conditions` = 0;
- `SELECT count(*) FROM kacho_iam.access_bindings WHERE condition_id IS NOT NULL` = 0;
- полный обход кортежей хранилища прав: число кортежей с непустым условием = 0
  (иначе смена модели сделала бы их невычислимыми — предполётный гейт IAM-C-43).

### 5.4 Заявление ломающего изменения

`buf breaking` сравнивается с `main` и **упадёт осознанно**. В теле PR заявляется точный
ожидаемый набор нарушений (удалённые файлы; удалённые сервис и RPC; удалённые поля с
зарезервированными тегами). Гейт merge: вывод `buf breaking` совпадает с заявленным
**поэлементно** — ни одного лишнего нарушения. Конфигурация `buf.yaml` не трогается (R3).

Наблюдаемые последствия для клиентов, которые обязаны быть описаны в CHANGELOG:

| Клиент | Было | Стало |
|---|---|---|
| REST `/iam/v1/conditions*`, **аутентифицированный** клиент | 200 / Operation | **403** (промах каталога, fail-closed; шлюз не раскрывает существование пути) |
| REST `/iam/v1/conditions*`, **анонимный** клиент | 200 / Operation | **401** в посадке `production-strict` (запрос не доходит до authz), **403** в посадке `production`. Никогда 200, никогда 404 — см. разбор у IAM-C-11 |
| gRPC `ConditionsService/*` на внешнем листенере | проксировался | `NOT_FOUND "unknown method: …"` |
| gRPC `ConditionsService/*` на листенере iam | обслуживался | `UNIMPLEMENTED` |
| REST `POST /iam/v1/accessBindings` с ключом `conditionId` | ключ читался ноль раз | ключ отбрасывается мостом (unknown JSON key), привязка создаётся, в ответе ключа нет |
| gRPC `CreateAccessBinding` с тегом 6/7 | поле не читалось | уходит в unknown fields, игнорируется |

### 5.5 Чёрный ящик

Полный newman зелёный **без** ретайренного набора `iam-condition` (**4** кейса `IAM-CND-*`
удаляются вместе с `run_one "iam-condition"` в `services/iam/tests/newman/scripts/run.sh:177`
и его комментарием `:173-176`), и прогонщик не докладывает `iam-condition(no-report)`
(иначе снятие набора превратится в фантомный красный — класс
[[false-green-suite-not-executed]] наоборот). Взамен появляется **новый** набор
`iam-conditional-retired` (кейсы `IAM-CRET-*`, §6.0), который **тоже** обязан быть добавлен
в `run.sh` — иначе он даст свой собственный фантомный `(no-report)`. Вердикт прогонщика
читается из `assertions.failed`, а не из факта выполнения (`newman-runners-print-green-while-red`).

**Кто именно это наблюдает (адресовано в круге 4 — раньше гейт был назван без пути):**
`services/iam/tests/newman/scripts/assert-suites-green.sh`, запускаемый с **cwd = каталог
набора** (`deploy/scripts/newman-parallel.sh:236,266` делает `cd "$d" && bash "$GATE_SCRIPT"`).
Гейт перебирает `collections/*.postman_collection.json` и для каждой требует
`out/<name>.json`; отсутствие отчёта даёт `"<name>(no-report)"` (`assert-suites-green.sh:62-67`) —
это и есть механизм, ловящий оба фантома. Дополнительно **до** подсчёта утверждений
исполняется `services/iam/tests/newman/scripts/exec-coverage.py` (`:49-59`): каждый лист
коллекции обязан либо выполниться, либо быть статически объяснён. Новый набор
`iam-conditional-retired` обязан пройти **и** его — набор с недостижимыми запросами
провалит гейт до того, как счётчики утверждений станут осмысленными.
`iam-condition` в known-RED whitelist гейта **отсутствует** (проверено), поэтому снятие
набора правок whitelist'а не требует.

Стенд поднимается в production-posture: `make -C deploy dev-prod-up` (`deploy/Makefile:180`) зелёный,
посадка проверяется **у живого процесса** и по `pg_stat_ssl`
(`deploy/scripts/assert-production-posture.sh`), а не по ConfigMap'у.

---

## 6. Сценарии

### 6.0 Трассировка: правило именования и таблица соответствия

`IAM-C-NN` — идентификатор **сценария этого документа**. Он не заменяет и не
переименовывает существующие пространства (`IAM-CND-*` — ретайренные newman-кейсы,
удаляются целиком; `IAM-ACB-*`, `IAM-ACC-*` и прочие остаются как есть).

**Пространств имён ровно два, третьего не заводится** (проверено в круге 4): (1)
идентификатор сценария acceptance-документа — `IAM-C-NN`, по уже принятому в репозитории
образцу `GEO-1-NN`; (2) идентификатор newman-кейса — `IAM-CRET-*`, в схеме, общей с 338
существующими кейсами iam. **Имя Go-теста пространством имён не является** — это имя
функции; связь с документом несёт `IAM-C-NN` в его ведущем doc-комментарии, ровно как в
эталонном наборе geo. Поэтому греп `IAM-C-` по дереву даёт замкнутое множество, сверяемое
с §6.0 в обе стороны.

Связывание — явное, по двум правилам, взятым из уже действующей практики репозитория:

- **Go-тест**: имя по сложившейся схеме `Test<Subject>_<Case>`, а идентификатор сценария —
  в **ведущем doc-комментарии** теста. Ровно так сделано в эталонном redesign-наборе geo:
  `// TestPublicZone_TwoProjection_NoStatusNoInfra — GEO-1-02/33: …`
  (`services/geo/internal/protoconv/protoconv_test.go:28`),
  `// TestInternalRegionHandler_Delete_failedPrecondition — GEO-1-18: …`
  (`services/geo/internal/handler/handler_test.go:113`). Формат комментария —
  `// <ИмяТеста> — IAM-C-NN: <краткое утверждение>`; один тест может нести несколько
  идентификаторов через `/`.
- **Newman-кейс**: `id="IAM-CRET-<VERB>-<KIND>-<OUTCOME>"` — схема совпадает с 338
  существующими кейсами iam (`IAM-ACB-RD-LS-PAGESIZE-OVER-NEG`,
  `IAM-ACC-GT-NEG-ID-MALFORMED`, …); `CRET` = conditional-access retire, новый
  resource-сегмент, не пересекающийся с ретайренным `CND`. Кейсы живут в новом наборе
  `services/iam/tests/newman/cases/iam-conditional-retired.py` и в `run.sh`
  вызываются через `run_one "iam-conditional-retired"` — иначе прогонщик доложит
  `(no-report)` фантомным красным (тот же класс, что снимаемый `iam-condition`, §5.5).
- **Стендовая процедура** (сценарий без кода-артефакта) помечена в таблице явно; её
  артефакт — приложение к тикету (числа/вывод), а не файл в репозитории. Такой сценарий
  **не** засчитывается как «покрыт тестом» и в общем счёте RED→GREEN не участвует.

Таблица двусторонняя: каждая строка называет **и** сценарий, **и** артефакт. Строка без
артефакта обязана быть помечена «стендовая процедура» — «нет артефакта, потому что не
придумали» не является допустимым состоянием.

**Правка круга 4 — колонка «где живёт» проверена на существование пофайлово.** Каждый путь
помечен: `[есть]` — файл существует сегодня и правится/дополняется; `[новый]` — файла нет,
он создаётся этим ретайром. Раньше шесть строк указывали на несуществующие или на
многоточечные пути (`gateway/internal/…/router_test.go`), то есть «трассировка» вела в
никуда — тот же класс, что документ ретайрит.

| ID | Артефакт (Go-тест / newman case-id / процедура) | Где живёт |
|---|---|---|
| IAM-C-01 | `TestRetireInventory_NoResidualIdentifiers` + сам исполняемый гейт | `deploy/tests/helm/` **[есть, каталог]** — файл гейта **[новый]**; вызывается из CI (job `helm lint · template (dev + prod)`, новым шагом — см. §12 O-1) |
| IAM-C-02 | **стендовая процедура** (три счётчика §5.3) | приложение к тикету |
| IAM-C-03 | **стендовая процедура** (постраничный обход `InternalAuthorizeService.ReadTuples`) | приложение к тикету; механика **[есть]** — `proto/kacho/cloud/iam/v1/internal_authorize_service.proto:55`, `services/iam/internal/apps/kacho/api/internal_authorize/handler.go:98` |
| IAM-C-10 | `IAM-CRET-GT-RETIRED-DENY`, `IAM-CRET-LS-RETIRED-DENY`, `IAM-CRET-CR-RETIRED-DENY`, `IAM-CRET-UP-RETIRED-DENY`, `IAM-CRET-DL-RETIRED-DENY`, `IAM-CRET-EV-RETIRED-DENY` | `services/iam/tests/newman/cases/iam-conditional-retired.py` **[новый]** |
| IAM-C-11 | `IAM-CRET-LS-RETIRED-ANON-DENY` | там же **[новый]** |
| IAM-C-12 | `TestShimProxy_ConditionsService_UnknownMethod` | `gateway/internal/proxy/shimproxy_bufconn_test.go` **[есть]** — дополняется кейсом. Механизм отказа **[есть]**: `gateway/internal/proxy/shimproxy.go:53` возвращает `status.Errorf(codes.NotFound, "unknown method: %s", method)` для всего, чего нет в allowlist |
| IAM-C-13 | `TestIAMGRPC_ConditionsService_Unimplemented` (**регресс-контроль**, см. пометку у сценария) | `services/iam/cmd/kacho-iam/grpc_register_test.go` **[новый]** |
| IAM-C-14 | `TestPermissionCatalog_NoConditionsNamespace` (обе копии) + `cd gateway && make permission-catalog-check` | `gateway/internal/middleware/permission_catalog_test.go` **[есть]** |
| IAM-C-15 | `TestRESTRouteTable_NoConditionsRoutes` + `cd gateway && make rest-route-table-check` | `gateway/internal/middleware/` (рядом с `rest_route_table_gen.go`) **[есть, каталог]**; тест **[новый]** |
| IAM-C-16 | `TestResourceID_RetiredCndPrefixRejected` | `pkg/validate/validate_test.go` **[есть]** |
| IAM-C-17 | `TestConfig_StaleConditionsEnv_Boots` + `TestConfigValidate_InsecureSslmode_Fatal` (живость guard'а) | `services/iam/internal/apps/kacho/config/config_test.go` **[есть]** |
| IAM-C-18 | **прогон** `deploy/scripts/newman-parallel.sh` **[есть]**, вердикт — `services/iam/tests/newman/scripts/assert-suites-green.sh` **[есть]** (cwd = каталог набора) + предшествующий ему `exec-coverage.py` **[есть]** | артефакт — отчёт прогона (`out/*.json` + вывод блока `GATED`) |
| IAM-C-20 | `IAM-CRET-ACB-GT-NO-CONDITION-KEYS`, `IAM-CRET-ACB-LS-NO-CONDITION-KEYS` | `services/iam/tests/newman/cases/iam-conditional-retired.py` **[новый]** |
| IAM-C-21 | `IAM-CRET-ACB-CR-LEGACY-KEY-IGNORED-OK` | там же **[новый]** |
| IAM-C-22 | `TestCreateAccessBinding_ReservedTags_Ignored` | `services/iam/internal/apps/kacho/api/access_binding/` **[есть, каталог]**; тест **[новый]** |
| IAM-C-23 | `IAM-CRET-ACB-UP-MASK-CONDITIONID-NEG` + `TestUpdateAccessBinding_UnknownMaskField_InvalidArgument` | newman **[новый]** + `api/access_binding/` **[новый тест]** |
| IAM-C-24 | `TestInternalAuthorize_WriteReadTuple_NoCondition` | `services/iam/internal/apps/kacho/api/internal_authorize/` **[есть, каталог]**; тест **[новый]** |
| IAM-C-25 | `TestAuthorizeCheck_RetiredContextKey_NoEffect` + `IAM-CRET-AZ-CHECK-CONTEXT-IGNORED` | Go **[новый]** + newman **[новый]** |
| IAM-C-30 | `TestMigrations_DropConditionalAccess_Idempotent` | `services/iam/internal/repo/kacho/pg/` **[есть, каталог]** — по образцу существующих `migration_00NN_*_integration_test.go`; файл **[новый]** |
| IAM-C-31 | `TestMigrations_FullChain_FreshDB` | там же **[новый]** |
| IAM-C-32 | `TestMigrations_DropRefusesNonEmpty` | там же **[новый]** |
| IAM-C-33 | `TestAccessBindingLifecycle_AfterDrop` (+ concurrent-подтест); **TTL-половина переиспользует существующую** `TestC23_ExpiredRulesBinding_EagerRevoke` | новый тест — там же **[новый]**; TTL — `services/iam/internal/repo/kacho/pg/reconcile_rules_integration_test.go:302` **[есть]** |
| IAM-C-34 | `TestMigrations_DownRestoresPreDropSchemaSnapshot` | там же **[новый]** |
| IAM-C-35 | `TestMigrations_DownThrough0070And0013` | там же **[новый]** |
| IAM-C-40 | **переиспользует два существующих гейта, новый файл не заводится**: C-1/C-2 — `fga_model_configmap_identity_test.go`; D-1..D-4 / R-1..R-3 — `fga_model_drift_test.go` (в т.ч. R-3: закрытый набор expandable-отношений равен модели **в обе стороны**) | `services/iam/internal/authzmap/fga_model_configmap_identity_test.go` **[есть]** и `services/iam/internal/authzmap/fga_model_drift_test.go` **[есть]** — оба дополняются утверждением «ноль блоков `condition`, нет типа `iam_condition`, ноль клауз `with`» |
| IAM-C-41 | `IAM-CRET-ACB-CR-TARGET-IAMCONDITION-NEG` | `services/iam/tests/newman/cases/iam-conditional-retired.py` **[новый]** |
| IAM-C-42 | `TestVerbResolver_SshConsoleEvaluate_FailClosed` (**пара RED→GREEN**) + `IAM-CRET-AZ-EXPAND-SSH-NEG` (**регресс-контроль**, зелёный до работ — см. пометку у сценария) | Go + newman |
| IAM-C-43 | `TestModelApplyPreflight_RefusesConditionalTuples` + сам гейт (см. §4 S4, R14) | `services/iam/cmd/kacho-iam/` **[есть, каталог]**; подкоманда и тест **[новые]** |
| IAM-C-44 | **прогон** матрицы «глагол × роль × область» и матрицы отказов | отчёт прогона, обе линии приложены |
| IAM-C-50 | `TestHelmRender_NoOpaDeliveryArtifacts` + tree-гейт (см. сценарий) | `deploy/tests/helm/` **[есть, каталог]**; скрипт **[новый]**, подключается к CI (§12 O-1) |
| IAM-C-51 | **стендовая процедура** (`cd deploy && make -C deploy dev-prod-up`, внутри — `assert-production-posture`) | приложение к тикету; `deploy/Makefile:180,283`, `deploy/scripts/assert-production-posture.sh` **[есть]** |
| IAM-C-52 | `TestHelmRender_AuthzNetworkPolicy_KeepsOpenfgaAllowlistOnly` | `deploy/tests/helm/` **[есть, каталог]**; скрипт **[новый]**, подключается к CI (§12 O-1) |
| IAM-C-53 | `config-rollout-binding-test.sh` (перенацелен, R13) + инъекция дефекта + **подключение к CI** | `deploy/tests/helm/config-rollout-binding-test.sh` **[есть, но НЕ вызывается ниоткуда]** — см. §1.3 F и §12 O-1 |
| IAM-C-60 | `TestGate_PermissionCatalog_RejectsConditionsNamespace` | `gateway/internal/middleware/permission_catalog_test.go` **[есть]**; утверждение **[новое]** |
| IAM-C-61 | `TestGate_FGAModel_RejectsConditionBlocks` | `services/iam/internal/authzmap/fga_model_drift_test.go` **[есть]**; утверждение **[новое]** |
| IAM-C-62 | `TestGate_IDPrefixes_RejectsCnd` | `pkg/ids/ids_test.go` **[есть]** |
| IAM-C-63 | `TestGate_Schema_RejectsConditionStructures` — **переворот существующего**: `migrations_iam_extensions_integration_test.go:146` сегодня утверждает **наличие** `{"access_bindings","condition_id"}` | `services/iam/internal/repo/kacho/pg/migrations_iam_extensions_integration_test.go` **[есть]** |
| IAM-C-64 | **ревью-чеклист** (записки vault) | проверяется ревьюером PR по §7 |
| IAM-C-70 | **замер** (спецификация — в сценарии) | обе линии числами в тикете; harness — `services/iam/tests/k6/ghz/` **[новый]** по образцу `services/vpc/tests/k6/ghz/in-cluster-job.yaml` **[есть]** |
| IAM-C-71 | `TestAuditOutbox_EventTypeFormatEnforced` + прогон мутаций (**регресс-контроль целиком**, зелёный до работ — см. пометку у сценария; из счёта пар исключён) | Go + отчёт |

**DoD-требование трассировки:** ни один сценарий не остаётся без строки в этой таблице;
каждый Go-тест несёт свой `IAM-C-NN` в ведущем doc-комментарии, каждый newman-кейс —
в `id=`. Проверяется грепом `IAM-C-` по дереву: множество найденных идентификаторов
обязано совпасть с множеством строк таблицы **в обе стороны** (нет сценария без
артефакта; нет артефакта, ссылающегося на несуществующий сценарий).

### S0 — доказательство отсутствия потребителей (правок кода нет)

---

**Сценарий 01: инвентарь потребителей пуст**

**ID:** IAM-C-01

**Given** дерево `project/kacho` после стадий S1–S4
**And** исполняемый инвентарь §5.1 добавлен в репозиторий как гейт

**When** гейт запускается на всём дереве, исключая retirement-записки vault

**Then** по каждому набору идентификаторов — **ноль** совпадений
**And** две **точечные** проверки §5.1 (не масочные) тоже зелёные: в теле
`resolveActionToRelation` (`services/iam/internal/service/authorize_service.go`) нет
литералов `"evaluate"`, `"ssh"`, `"console"`, при этом `"admin"`, `"editor"`, `"viewer"`
и остальные элементы обеих `case`-строк **на месте**; в обеих tracked-копиях каталога
разрешений **ноль** записей с глаголом `evaluate`
**And** гейт возвращает ненулевой код при появлении хотя бы одного (проверяется инъекцией:
временно вернуть одну строку → гейт красный)
**And** инъекция проверена **отдельно для точечной части**: возврат литерала `"evaluate"`
в viewer-ветку обязан сделать гейт красным — иначе точечная проверка сама оказывается
формой без содержания (масочные наборы этот остаток не покрывают by construction, §5.1)

---

**Сценарий 02: на стенде ноль строк — пересчитано, не предположено**

**ID:** IAM-C-02

**Given** стенд с применёнными миграциями до `0070` включительно

**When** выполняются три счётчика §5.3

**Then** каждый возвращает `0`
**And** результат приложен к тикету как артефакт (значения, а не «проверено»)

---

**Сценарий 03: в хранилище прав нет кортежей с условием**

**ID:** IAM-C-03

**Given** тот же стенд

**When** выполняется полный постраничный обход кортежей через `InternalAuthorizeService.ReadTuples`

**Then** число кортежей с непустым `condition` = `0`
**And** число страниц и общее число кортежей зафиксированы (чтобы обход не оказался
усечённым — «форма без содержания»)

---

### S1 — публичная поверхность `Condition`

---

**Сценарий 10: ретайренный REST-путь отвечает отказом, а не данными**

**ID:** IAM-C-10

**Given** шлюз собран после S1
**And** клиент аутентифицирован валидным токеном и является владельцем аккаунта

**When** клиент вызывает `GET /iam/v1/conditions/cnd00000000000000abc`
**And** `GET /iam/v1/conditions?projectId=<свой проект>`
**And** `POST /iam/v1/conditions` с телом `{projectId, name, expression}`
**And** `PATCH /iam/v1/conditions/cnd00000000000000abc`
**And** `DELETE /iam/v1/conditions/cnd00000000000000abc`
**And** `POST /iam/v1/conditions/cnd00000000000000abc:evaluate` с телом `{context:{}}`

**Then** каждый вызов отвечает `403` (промах каталога разрешений, fail-closed)
**And** ни один не отвечает `200` ни при каких значениях полей
**And** тело ответа не содержит ни `cnd`, ни имени сервиса, ни слова `condition`
(отказ не раскрывает, что именно было снято)

---

**Сценарий 11: анонимный вызов ретайренного пути тоже отвергается**

**ID:** IAM-C-11

**Given** тот же шлюз, поднятый в посадке `production-strict` (та, что даёт `make -C deploy dev-prod-up`:
`values.dev-prod.yaml:73` — `authn.mode: production-strict`)
**And** запрос без заголовка `Authorization`

**When** клиент вызывает `GET /iam/v1/conditions?projectId=prj000000000000000a`

**Then** ответ — **`401`** (`WWW-Authenticate: Bearer error="invalid_token", …missing access token"`)
**And** он **не отличим** от ответа на любой другой путь без токена: отказ наступает на
входном рубеже, до того как шлюз вообще узнаёт, известен ли ему метод
**And** ответ **не** `200` и **не** `404` — ретайренный путь не отвечает данными и не
раскрывает, что путь когда-то существовал

**When** тот же вызов выполняется в посадке `production` (без `-strict`) — либо тем же
запросом, но с валидным токеном субъекта без грантов

**Then** ответ — **`403`** (промах каталога, fail-closed), не `401` и не `404`

> **Сценарий переписан в круге 4 — прежняя редакция была ЛОЖНОЙ на том самом стенде,
> который документ предписывает.** Требовалось «`403`, не `401` и не `404`» и объяснялось
> это тем, что «промах каталога не повышается до `UNAUTHENTICATED`». Вторая половина верна
> (`gateway/internal/middleware/authz.go:746-777`: при `!found` возвращается
> `PermissionDenied` **обоим** — и аутентифицированному, и нет, с разными `missReason`), а
> первая — нет: **до authz-фазы анонимный запрос не доходит**. Цепочка HTTP-обработчиков
> (`gateway/cmd/api-gateway/main.go:513-522`) — `authInterceptor` → **DPoP** → authz → …,
> и DPoP в production-strict несёт `RequireForAllRequests` (`main.go:242`:
> `cfg.AuthNMode == AuthModeProductionStrict`), который на пустом `Authorization`
> отвечает `401` немедленно (`dpop_http_middleware.go:189-196`). `/iam/v1/conditions` не
> входит в `isPublicHTTPPath` (`authz_util.go:184-191`), поэтому исключения нет.
> Наблюдаемый инвариант, который **не зависит** от посадки и потому вынесен в оба Then:
> **никогда `200`, никогда `404`, тело не называет снятый ресурс**. Код различается по
> посадке — и это записано, а не замаскировано «толерантным oneOf», который скрыл бы
> реальную разницу между «нет токена» и «нет прав».

---

**Сценарий 12: gRPC-вызов на внешнем листенере отклонён маршрутизатором**

**ID:** IAM-C-12

**Given** внешний gRPC-листенер шлюза после снятия записей allowlist

**When** клиент вызывает `/kacho.cloud.iam.v1.ConditionsService/Get`

**Then** ответ — `NOT_FOUND` с сообщением `"unknown method: /kacho.cloud.iam.v1.ConditionsService/Get"`
**And** ни один backend-коннекшн не открывается (запрос не доходит до iam)

---

**Сценарий 13: gRPC-вызов на собственном листенере iam не обслуживается**

**ID:** IAM-C-13

**Given** процесс `kacho-iam` после снятия регистрации сервиса

**When** вызывается `/kacho.cloud.iam.v1.ConditionsService/Create` напрямую на публичном `:9090`

**Then** ответ — `UNIMPLEMENTED`
**And** в логе нет паники и нет обращения к пулу БД

> **Регресс-контроль (уже верно ДО начала работ), вынесен из основного утверждения.**
> Прежняя редакция требовала «то же на внутреннем `:9091` → `UNIMPLEMENTED`». Это
> **истинно уже сейчас**: `ConditionsService` регистрируется **только** в
> `registerPublicServices` (`services/iam/cmd/kacho-iam/grpc_register.go:51`); в
> `registerInternalServices` (`:73`) его нет и никогда не было. Проверка остаётся в
> наборе, но **явно помечена как регресс-контроль**, а не как доказательство снятия:
> она защищает от «перенесли сервис на internal вместо удаления». Формулировка
> сценария не должна выдавать её за наблюдаемое следствие работы — это ровно тот
> класс «форма без содержания», который документ разбирает в §1.2 B. RED→GREEN для
> этой проверки не предъявляется (она зелёная в обеих точках), и в счёте пар
> «RED → GREEN» стадии S1 она не участвует.

---

**Сценарий 14: каталог разрешений не содержит пространства `iam.conditions.*`**

**ID:** IAM-C-14

**Given** каталог перегенерирован из proto после S1

**When** выполняется `make -C gateway permission-catalog-check`

**Then** обе встроенные копии (сид iam и middleware шлюза) байт-идентичны
**And** ни одна не содержит записи с `permission`, начинающимся на `iam.conditions.`
**And** ни одна не содержит `scope_extractor.object_type = "iam_condition"`
**And** общее число записей уменьшилось ровно на 6

---

**Сценарий 15: таблица REST-маршрутов не знает пути условий**

**ID:** IAM-C-15

**Given** сгенерированная таблица маршрутов после S1

**When** в ней ищутся шаблоны с префиксом `/iam/v1/conditions`

**Then** совпадений `0`
**And** число маршрутов уменьшилось ровно на 6

---

**Сценарий 16: идентификатор ретайренного ресурса больше не валиден**

**ID:** IAM-C-16

**Given** `cnd` снят из каталога префиксов платформы

**When** каноничный валидатор идентификатора вызывается со строкой `cnd00000000000000abc`
**And** со строкой `cnd0`

**Then** оба отвергаются как `INVALID_ARGUMENT` с конвенционным текстом `"invalid <res> id '<X>'"`
**And** идентификаторы всех остальных доменов (`acc`, `prj`, `usr`, `sva`, `grp`, `rol`, `acb`,
`iop`, `uoc`) по-прежнему валидны — регрессия на соседей
**And** пустая строка по-прежнему **пропускается** валидатором (`validate.go:457-459`) —
required-проверка это отдельная ответственность вызывающего, и ретайр её не меняет

> **Мотивировка исправлена по коду (замечание ревью принято).** Прежняя редакция
> называла две строки «верхней и нижней границей прежнего формата» — это неверная
> мотивация: `validate.ResourceID` (`pkg/validate/validate.go:455-474`) длину и алфавит
> **тела** не проверяет вовсе. Она проверяет ровно две вещи: (а) сегмент до первого дефиса
> ∈ `hyphenResourceIDPrefixes`, (б) первые **три** символа ∈ `resourceIDPrefixes` при
> `len(id) >= 3`. Поэтому обе строки отвергаются не потому, что вышли за границу формата,
> а потому, что после снятия `"cnd"` из `domainStringPrefixes` (`pkg/ids/ids.go:245`) их
> трёхсимвольный префикс **перестаёт быть членом каталога платформы**. Утверждения
> сценария от этого не меняются — меняется то, что именно он доказывает: снятие префикса
> из каталога, а не длиновую валидацию, которой нет. Обе строки сохранены как две
> различающиеся по длине пробы того же префикса — это осмысленно (одна короче, другая
> длиннее «обычного» id), но границей формата не является.

---

**Сценарий 17: процесс поднимается при устаревших переменных окружения**

**ID:** IAM-C-17

**Given** конфигурация вычислителя условий снята из `Config` и из `Config.Validate()`
**And** в окружении процесса **остались** `KACHO_IAM_CONDITIONS_CACHE_SIZE=0` и
`KACHO_IAM_CONDITIONS_CACHE_TTL_SECONDS=0` (значения, на которых прежняя валидация делала fatal)

**When** процесс `kacho-iam` стартует в production-mode

**Then** процесс поднимается и проходит readiness
**And** boot-guard production-режима отрабатывает как прежде (проверяется отдельно инъекцией
`sslmode=disable` → отказ старта: гейт остаётся живым, а не «стал зелёным, потому что
перестал выполняться»)

---

**Сценарий 18: полный чёрный ящик зелёный без снятого набора**

**ID:** IAM-C-18

**Given** набор `iam-condition` (**4** кейса `IAM-CND-*` — `IAM-CND-CR-CRUD-OK`,
`IAM-CND-CR-VAL-UNSCOPED`, `IAM-CND-UP-CRUD-OK`, `IAM-CND-LS-AUTHZ-NOBINDINGS-DENY`)
и его коллекция удалены, вызов `run_one "iam-condition"` из `run.sh:177` убран
**And** добавлен новый набор `iam-conditional-retired` (кейсы `IAM-CRET-*`, §6.0) и его
вызов `run_one "iam-conditional-retired"` в `run.sh`

**When** выполняется полный newman по всем сервисам

**Then** прогон зелёный: **0** упавших утверждений
**And** вердикт прочитан из `assertions.failed`, а не из факта выполнения набора
**And** прогонщик **не** докладывает ни `iam-condition(no-report)`, ни
`iam-conditional-retired(no-report)` — оба фантома исключены явно
**And** имени `iam-condition` нет ни в списке выполненных наборов, ни в `collections/`
**And** имя `iam-conditional-retired` есть **и** в `collections/`, **и** в отчёте
(набор, лежащий в `collections/`, но не вызванный из `run.sh`, — ровно тот фантом,
из-за которого этот кейс существует)
**And** итоговое число выполненных наборов **не изменилось**: один снят, один добавлен
(оба числа в отчёте — «уменьшилось на один» было бы неверным ожиданием и уронило бы
кейс ложно)

---

### S2 — поля условия на привязке и на кортеже

---

**Сценарий 20: ответ привязки не несёт полей условия**

**ID:** IAM-C-20

**Given** существующая привязка прав `acb-…` (создана до ретайра)

**When** клиент вызывает `GET /iam/v1/accessBindings/{id}`
**And** `GET /iam/v1/accessBindings?filter=subject="usr-…"`

**Then** в JSON-объекте привязки нет ключей `conditionId` и `builtinCondition`
**And** остальные поля (`id`, `subjects`, `roleId`, `scopeType`, `scopeId`, `status`,
`expiresAt`, `deletionProtection`, `labels`, `target`, `materializedAt`, `createdAt`)
присутствуют и не изменились

---

**Сценарий 21: старый клиент шлёт ключ условия — привязка создаётся без него**

**ID:** IAM-C-21

**Given** клиент, написанный до ретайра

**When** он вызывает `POST /iam/v1/accessBindings` с телом, содержащим, помимо обязательных
полей, `"conditionId": "cond_legacy"` и `"builtinCondition": 4` (deprecated-значение —
граничный случай)

**Then** возвращается `Operation`, полл до `done=true` без `error`
**And** последующий `Get` отдаёт привязку **без** ключей условия
**And** статус ответа — не `400`: мост отбрасывает неизвестный JSON-ключ, и это
задокументированное поведение, а не молчаливая потеря данных (данных за ключом не стояло
никогда)

---

**Сценарий 22: старый gRPC-клиент шлёт зарезервированные теги**

**ID:** IAM-C-22

**Given** клиент, собранный со старыми стабами

**When** он вызывает `CreateAccessBinding`, заполнив теги 6 (`condition_id`) и 7 (`builtin_condition`)

**Then** сервер принимает запрос; теги уходят в unknown fields и игнорируются
**And** созданная привязка идентична созданной без этих тегов (побайтово по полям ответа)
**And** теги 6/7 в схеме помечены `reserved` — повторное использование номера невозможно

---

**Сценарий 23: маска обновления не знает поля условия**

**ID:** IAM-C-23

**Given** существующая привязка

**When** клиент вызывает `PATCH /iam/v1/accessBindings/{id}` с `updateMask=["conditionId"]`

**Then** ответ — `INVALID_ARGUMENT` (неизвестное поле маски)
**And** текст соответствует конвенции неизвестного поля, а **не** тексту про immutable-поле
(поле не «неизменяемое», его больше нет)
**And** `updateMask=["labels"]` и `["deletionProtection"]` продолжают работать — регрессия

---

**Сценарий 24: внутренний кортеж больше не несёт условия**

**ID:** IAM-C-24

**Given** внутренний листенер `:9091` после снятия `TupleCondition`

**When** админ-инструмент вызывает `WriteTuples` с кортежем, у которого заполнен старый тег 4
**And** затем `ReadTuples` по тому же объекту

**Then** запись проходит; условие игнорируется
**And** прочитанный кортеж не содержит поля условия
**And** внутренний листенер по-прежнему требует mTLS и проходит per-RPC `Check`
(инвариант «authN+authZ везде» не ослаблен)

---

**Сценарий 25: снятие контекста условия не открывает подделку**

**ID:** IAM-C-25

**Given** `AuthorizeCheckRequest.context` переведён в тумбстон, `buildCondContext` удалён
**And** субъект `usr-…`, у которого нет права `v_update` на объект `X`

**When** субъект вызывает `POST /iam/v1/authorize:check` для `X` и действия `*.update`,
подложив в тело устаревший ключ `context` со значениями `acr_value="3"`,
`amr_claims=["webauthn"]`, `mfa_at=<now>`, `client_ip="10.0.0.1"`

**Then** ответ — `allowed=false`
**And** решение побитово совпадает с решением на том же запросе **без** ключа `context`
**And** ни одно значение из тела не доходит до хранилища прав (проверяется на уровне
наблюдаемого решения и отсутствия ключа в исходящем запросе к хранилищу)
**And** субъект с настоящим правом `v_update` получает `allowed=true` — регрессия на
положительный путь

---

### S3 — схема БД

---

**Сценарий 30: дроп-миграция применяется и идемпотентна при повторе**

**ID:** IAM-C-30

**Given** БД с применёнными миграциями до `0070` включительно, все три счётчика §5.3 равны нулю

**When** выполняется `goose up`
**And** затем `goose up` повторно

**Then** первый прогон применяет дроп-миграцию
**And** таблиц `conditions` и `access_binding_conditions` нет, колонки
`access_bindings.condition_id` нет, триггера и функции нет
**And** повторный прогон — no-op без ошибок

---

**Сценарий 31: свежая БД проходит всю цепочку**

**ID:** IAM-C-31

**Given** пустая БД

**When** применяется полная цепочка миграций от `0001` до последней

**Then** цепочка проходит целиком: `0001` создаёт таблицы условий, `0013`/`0048`/`0070`
их правят, дроп-миграция их удаляет
**And** итоговая схема совпадает со схемой стенда после сценария 30 (сравнение по списку
таблиц, колонок, индексов и ограничений схемы `kacho_iam`)
**And** ни одна из применённых миграций не отредактирована — проверяется хэшем содержимого
файлов `0001`, `0013`, `0048`, `0070` против базового коммита

---

**Сценарий 32: непустая таблица останавливает миграцию**

**ID:** IAM-C-32

**Given** БД, в которой в `kacho_iam.conditions` вставлена **ровно одна** строка
(нижняя граница непустоты)

**When** выполняется `goose up`

**Then** миграция падает с `RAISE EXCEPTION`
**And** текст ошибки называет таблицу и число строк
**And** ни одна из шести структур не удалена (транзакция откачена целиком)
**And** тот же результат для одной строки в `access_binding_conditions`
**And** тот же результат для одной привязки с непустым `condition_id`

---

**Сценарий 33: жизненный цикл привязки не деградировал**

**ID:** IAM-C-33

**Given** схема после дроп-миграции

**When** выполняется полный цикл: `Create` привязки → полл `Operation` → `Get` → `Update`
(`labels`) → `Revoke` → `Delete`
**And** параллельно из нескольких горутин создаются привязки с одним и тем же
`(subject, role, scope)`

**Then** цикл проходит; коды и тексты ошибок не изменились
**And** уникальность гранта по-прежнему держится на уровне БД: ровно одна транзакция
проходит, остальные получают ожидаемый sentinel
**And** истечение TTL по-прежнему переводит привязку в `REVOKED` — проверяется **тактом
свёртки, а не ожиданием**: привязке ставится `expires_at` в прошлом, затем явно
выполняется шаг реконсайлера (`ListExpiredBindingIDs` → `ExpireBinding`), после чего
`status = 'REVOKED'` и `revoked_at IS NOT NULL`; повторный шаг — no-op (CAS даёт 0 строк)

> **Уточнено в круге 4.** TTL энфорсится **периодической свёрткой**
> (`seed/reconcile_worker.go:187`), а не синхронно, поэтому формулировка «истекла ⇒ REVOKED»
> без указания такта непроверяема (тест либо спал бы, либо был бы флейком). Механизм и его
> точки — §1.3 E. **Регрессия на этот инвариант уже существует и переиспользуется, а не
> пишется заново**: `TestC23_ExpiredRulesBinding_EagerRevoke`
> (`services/iam/internal/repo/kacho/pg/reconcile_rules_integration_test.go:302`). От
> ретайра требуется, чтобы она осталась зелёной после дроп-миграции — это и есть здешняя
> половина сценария; новый TTL-тест не заводится (ban #11).

---

**Сценарий 34: down восстанавливает ПРЕД-ДРОПОВУЮ форму, а не форму `0001`**

**ID:** IAM-C-34

**Given** БД с применёнными миграциями до `0070` включительно
**And** снят машинно-сравнимый снимок схемы `kacho_iam` **до** применения дроп-миграции:
для `conditions` и `access_binding_conditions` — упорядоченные списки колонок с типами и
NOT NULL/DEFAULT, всех индексов с их определениями, всех ограничений (PK/FK/CHECK) с их
именами и текстом выражения, триггеров и функций

**When** применяется дроп-миграция, затем выполняется `goose down` на один шаг
**And** снимок схемы снимается повторно

**Then** повторный снимок **совпадает с исходным поэлементно** (сравнение списков, а не
«таблицы существуют»)
**And** в частности: колонка scope называется `project_id`, а НЕ `folder_id`; индексы —
`conditions_project_name_uniq` и `idx_conditions_project_status`; CHECK непустоты —
`conditions_project_id_not_empty`; whitelist `access_binding_conditions_expression_whitelist_ck`
содержит **ровно 5** значений (`mfa_fresh`, `non_expired`, `source_ip_in_range`,
`business_hours`, `device_compliant`), а не 7; колонка `access_binding_conditions.condition_id`,
её FK `access_binding_conditions_condition_fk`, триггер
`access_binding_conditions_sync_condition_id_trg` и функция
`access_binding_conditions_sync_condition_id()` присутствуют
**And** повторный `goose up` снова их удаляет (цикл up→down→up воспроизводим)
**And** сам этот сценарий проверен инъекцией: down, восстанавливающий форму `0001`
(`folder_id` + `conditions_folder_name_uniq` + 7-значный whitelist), обязан сделать
сценарий **красным** — иначе сравнение не сравнивает

---

**Сценарий 35: цепочка остаётся обратимой ещё на шаг — `goose down` через `0070` и `0013`**

**ID:** IAM-C-35

**Given** БД после сценария 34 (дроп-миграция откачена, форма пред-дроповая)

**When** выполняется `goose down` ещё на два шага — через `0070`, затем через `0013`

**Then** оба шага проходят без ошибок
**And** после `0070` колонка называется `folder_id`, индексы —
`conditions_folder_name_uniq` / `idx_conditions_folder_status`, CHECK —
`conditions_folder_id_not_empty`
**And** после `0013` ограничение `access_binding_conditions_expression_whitelist_ck`
содержит **ровно 7** значений (`mfa_fresh`, `non_expired`, `source_ip_in_range`,
`break_glass_window`, `jit_window`, `business_hours`, `device_compliant`) — то есть шаг
`0013` действительно выполнился и расширил whitelist обратно, а не был пропущен
**And** сценарий проверен инъекцией **того самого** дефекта, ради которого существует:
если down дроп-миграции восстанавливает форму `0001` (`folder_id` вместо `project_id`),
шаг через `0070` обязан упасть на первом же стейтменте
`ALTER TABLE kacho_iam.conditions RENAME COLUMN project_id TO folder_id` (`0070:50`,
`42703 undefined_column`) — красный до отката инъекции, зелёный после

> **Что этот сценарий НЕ доказывает (исправлено в круге 2).** Прежняя редакция утверждала,
> что неверная форма whitelist'а тоже уронила бы цепочку — `0013:74-84` якобы на
> `42710 duplicate_object`. **Это было выдумано**: Down `0013` начинается с
> `DROP CONSTRAINT IF EXISTS` (`0013:71-72`), поэтому `ADD` никогда не встречает занятое имя
> и шаг проходит при **любой** форме whitelist'а. Единственный отказ цепочки даёт
> переименование колонки в `0070`. Форма whitelist'а проверяется не здесь, а поэлементным
> совпадением снимка в IAM-C-34 (down = точный обратный up); здесь она проверяется лишь
> как признак того, что шаг `0013` отработал. Утверждение «упало бы на `42710`» удалено из
> всех четырёх мест, где стояло (R9, §4 S3, этот сценарий, §10.2 A) — см. §11, пункт 1

---

### S4 — модель прав

---

**Сценарий 40: в модели не осталось условий и типа условия**

**ID:** IAM-C-40

**Given** канонический файл модели прав после S4

**When** он парсится, и параллельно парсится сгенерированный ConfigMap

**Then** в каноне нет ни одного блока `condition`
**And** нет типа `iam_condition`
**And** нет ни одной клаузы `with`
**And** гейт побайтового совпадения блока DSL в ConfigMap с каноном зелёный
**And** гейт структурного совпадения преобразованной модели с каноном зелёный (те же типы,
те же имена отношений, тот же — пустой — набор условий)

---

**Сценарий 41: тип условия больше не адресуем как цель гранта**

**ID:** IAM-C-41

**Given** закрытый реестр типов после снятия `iam.condition`

**When** клиент вызывает `POST /iam/v1/accessBindings` с
`target.resources[0] = {type: "iam.condition", id: "cnd00000000000000abc"}`
**And** то же с опечаткой `type: "iam.conditions"`

**Then** оба отвергаются как `INVALID_ARGUMENT` (тип вне закрытого реестра)
**And** цель с любым живым типом (`compute.instance`, `vpc.network`, `iam.accessBinding`)
принимается — регрессия на соседей

---

**Сценарий 42: глаголы удалённых отношений отвергаются, а не резолвятся**

**ID:** IAM-C-42

**Given** отношения `ssh`/`console` удалены из модели и из passthrough-ветки резолвера
глаголов (`authorize_service.go:835`)
**And** глагол `evaluate` снят из viewer-ветки того же резолвера
(`authorize_service.go:824-830`) вместе с разрешением `iam.conditions.evaluate`

**When** внутренний `Check` приходит с действием `compute.instances.ssh`
**And** с действием `compute.instances.console`
**And** с действием `iam.conditions.evaluate`

**Then** каждый отвечает отказом по fail-closed-ветке «глагол не отображён» (резолвер
вернул `""`), а **не** ошибкой хранилища прав про несуществующее отношение и **не**
резолвом в `viewer`
**And** ни один живой глагол (`get`/`list`/`create`/`update`/`delete` и суффиксные
действия — в частности `listaccessbindings`, `batchcheck`, `expandrelations`,
`listsubjects`, `issue`, `revoke`) не затронут: резолвер отдаёт им прежние отношения —
регрессия на соседей по тем же двум `case`-спискам

> **Регресс-контроль (уже верно ДО начала работ), вынесен из основного утверждения —
> правка круга 2.** Прежняя редакция первым Then требовала: «`ExpandAccess` с
> `relation="ssh"`/`"console"` отвечает `INVALID_ARGUMENT`». Это **истинно уже сегодня**:
> `ExpandAccess` валидирует отношение против **закрытого** набора из девяти имён
> `expandableRelations = {v_get, v_list, v_create, v_update, v_delete, viewer, editor,
> admin, member}` (`services/iam/internal/authzmap/fga_types.go:209-222`), и проверка
> `!authzmap.IsExpandableRelation(relation)` → `INVALID_ARGUMENT`
> (`services/iam/internal/apps/kacho/api/access_binding/expand_access.go:117-121`).
> `ssh`/`console` в этом наборе **никогда не было** — набор специально исключает
> domain-specific и внутренние отношения модели (его собственный godoc: «Forwarding an
> arbitrary string into the FGA Read would let a caller probe the model's internal relation
> graph»). Значит newman-кейс `IAM-CRET-AZ-EXPAND-SSH-NEG` зелёный **до единой строки
> правок** и парой RED→GREEN быть не может. Он **остаётся в наборе** как регресс-контроль
> (защищает от «расширили `expandableRelations` при чистке модели»), но **исключён из счёта
> пар** — по тому же правилу, что применено к IAM-C-13. RED-able половина сценария — только
> `Check`-полоса выше: passthrough-ветка `case "ssh", "console", …` (`:835`) сегодня
> резолвит эти глаголы в живые отношения, и до её снятия fail-closed не наступает.

---

**Сценарий 43: предполётный гейт запрещает смену модели при живых условных кортежах**

**ID:** IAM-C-43

**Given** стенд, в хранилище прав которого искусственно записан **ровно один** кортеж
с условием (граница)

**When** запускается процедура применения новой модели

**Then** процедура **отказывает** до записи модели, называя число найденных условных кортежей
**And** действующая модель остаётся прежней
**And** после удаления этого кортежа процедура проходит

---

**Сценарий 44: доступ не изменился ни у кого, кроме снятого**

**ID:** IAM-C-44

**Given** новая модель применена, `KACHO_IAM_OPENFGA_MODEL_ID` перепинен, сервисы перекачены

**When** прогоняется матрица «глагол × роль × область» и матрица отказов на 6 субъектах

**Then** каждый результат совпадает с базовой линией до S4
**And** администратор облака по-прежнему достаёт чужую выдачу каскадом
**And** владелец по-прежнему структурно достаёт свой аккаунт
**And** тенант без выдачи по-прежнему не видит ничего
**And** ни один субъект не получил доступа, которого у него не было

---

### S5 — доставка guardrail-политик

---

**Сценарий 50: артефактов доставки политик нет В ДЕРЕВЕ, и включить их больше нечем**

**ID:** IAM-C-50

> **Сценарий переписан после ревью круга 1.** Прежняя редакция утверждала отсутствие
> объектов в **рендере production-профиля** — и была бы зелёной **до начала работ**:
> `opaSidecar.enabled=false` во всех профилях, поэтому `helm template` уже сегодня даёт
> ноль ConfigMap'ов `opa-*`, ноль `envFrom` и ноль `opa-*-checksum` (§1.3 F). Проверка,
> которая не может упасть, ничего не доказывает — тот самый класс, который этот документ
> ретайрит. Наблюдаемость восстановлена двумя независимыми утверждениями: (1) артефакты
> отсутствуют **в дереве**, (2) рендер с **принудительно включённой** ручкой доказывает,
> что ручки больше нет.

**Given** чарт после S5 (артефакты §4 S5, строки 1-4 и 7, удалены)

**When** выполняется гейт по **дереву** репозитория

**Then** каталога `charts/kacho-iam/files/opa-policies/` не существует (ноль `.rego`-файлов)
**And** не существует ни одного из четырёх шаблонов: `opa-policies-fallback-configmap.yaml`,
`opa-bundle-server-configmap.yaml`, `opa-sidecar-configmap.yaml`, `jwks-configmap.yaml`
**And** в `charts/kacho-iam/templates/deployment.yaml` нет ни одного совпадения `opa`
(ни метки `kacho.cloud/opa-sidecar`, ни трёх аннотаций-хэшей, ни томов, ни `envFrom`,
ни контейнера сайдкара, ни `KACHO_BUILD_SHA`) — удалены **шесть целых блоков** по границам
таблицы §4 S5, а не отдельные строки внутри `{{- if }}`
**And** соседние **живые** конструкции того же файла на месте и рендерятся: ключ
`initContainers:` (шёл сразу за блоком томов), петля `{{- range $k, $v := .Values.env }}`
с её `{{- end }}` (шла сразу перед блоком `envFrom`), аннотации
`kacho.cloud/config-checksum` и `kacho.cloud/openfga-model-id-rev`
**And** `helm template deploy/helm/umbrella/charts/kacho-iam` завершается **успешно** и
даёт **валидный YAML** — ни висячего `{{- if }}`, ни осиротевшего `{{- end }}`, ни
оборванного контейнера (именно так падало бы буквальное исполнение прежних, неверных
границ — см. §4 S5, столбец «Было (неверно)»)
**And** ключ `opaSidecar` не встречается **нигде под `deploy/helm/`**:
`grep -rl opaSidecar deploy/helm/` даёт **0 файлов** против **13** сегодня. В тринадцать
входят пять профилей values (`charts/kacho-iam/values.yaml`, `umbrella/values.yaml`,
`values.dev.yaml`, `values.prod.yaml`, `values.fe3455-prod.yaml` — последний боевой
профиль Beget, `:148-150`, ставит `networkPolicy.enabled: false`; при переименовании ручки
по R12 он правится вместе с остальными), четыре шаблона, `deployment.yaml`,
`configmap.yaml`, `umbrella/templates/networkpolicy-authz.yaml` **и
`charts/kacho-iam/README.md`** — последний найден в круге 4 и прежним, более узким
порогом («ноль по `values*.yaml` + `charts/*/values.yaml`») **не ловился**: два разных
порога на один инвариант — ровно тот класс, который документ ретайрит. Порог теперь один
и тот же в §4 S5, §5.1, здесь и в DoD S5
**And** ключ `authz.opaSidecar` / рендер `authz.opa-sidecar` отсутствует в
`templates/configmap.yaml`

**When** дополнительно выполняется рендер с **принудительной попыткой включить** ручку:
`helm template … --set kacho-iam.opaSidecar.enabled=true --set opaSidecar.networkPolicy.enabled=true`

**Then** рендер проходит успешно (не падает на nil — ручек просто нет, `--set` на
несуществующий ключ безвреден)
**And** в выводе **ноль** объектов с `opa` в имени: ни `opa-policies-fallback`, ни
`opa-bundle-server-config`, ни `opa-sidecar-config`, ни `kacho-iam-jwks`, ни
`opa-bundle-endpoint-ingress`, ни `opa-sidecar-egress-allowlist`
**And** в выводе **ноль** контейнеров с именем `opa` и ноль аннотаций, содержащих
`opa-sidecar-checksum` / `opa-bundle-server-checksum` / `jwks-checksum`

**And** остальные аннотации-хэши конфигурации на месте: у каждого workload'а, потребляющего
ConfigMap, есть своя `checksum`-аннотация (иначе смена настроек перестанет перекатывать
под — известный класс ложного зелёного, `security.md` §«Гейт посадки…»)
**And** гейт проверен инъекцией: возврат любого из четырёх шаблонов в дерево делает его
красным

---

**Сценарий 52: NetworkPolicy сохранила живую политику и потеряла обе мёртвые**

**ID:** IAM-C-52

**Given** `networkpolicy-authz.yaml` после S5 (решение R12): ручка переименована в
`networkPolicy.authz.enabled`, значения профилей сохранены (dev `false`, prod `true`)

**When** выполняется рендер в production-профиле

**Then** политика `openfga-engine-ingress-allowlist` присутствует, и её `spec` не
изменился: тот же podSelector на движок прав, тот же список источников (iam, шлюз,
backend-сервисы), те же порты
**And** политик `opa-bundle-endpoint-ingress` и `opa-sidecar-egress-allowlist` в выводе нет
**And** ни один объект вывода не селектирует по метке `kacho.cloud/opa-sidecar`

**When** тот же рендер выполняется в dev-профиле (ручка `false`)

**Then** ни одной из трёх политик нет — поведение выключенной ручки не изменилось

**And** проверено инъекцией регресса: рендер prod-профиля **без**
`openfga-engine-ingress-allowlist` обязан сделать сценарий красным. Это главный смысл
кейса: наивное «снять весь блок `opaSidecar`» молча убрало бы **действующий** контроль
изоляции хранилища прав, замаскировав регресс безопасности под ретайр (§4 S5, R12)

---

**Сценарий 53: гейт привязки перекатки не ослаблен, а перенацелен**

**ID:** IAM-C-53

**Given** `deploy/tests/helm/config-rollout-binding-test.sh` после правки R13:
`--set kacho-iam.opaSidecar.enabled=true` убран из третьего рендера, а
`--set vpc.opa.enabled=true` и `--set compute.opa.enabled=true` **сохранены**

**And** скрипт **подключён к CI** отдельным шагом job'а `helm lint · template (dev + prod)`
(до этой правки он не вызывался ниоткуда — §1.3 F, R13)

**When** гейт запускается на дереве после S5

**Then** гейт зелёный
**And** он **виден в логе CI-прогона** как отдельный шаг с ненулевым выводом — «шаг есть в
YAML» без строки в логе не засчитывается (иначе подключение проверяется намерением, а не
исходом)
**And** в скрипте нет ни одного `--set` на несуществующий ключ (проверяется отдельно:
для каждого `--set <path>=…` путь резолвится в объединённых values — иначе `helm`
молча примет его и гейт превратится в форму без содержания)

**When** в `charts/kacho-iam/templates/` инъекцией добавляется потребляемый ConfigMap
и `envFrom` на него **без** соответствующей `checksum`-аннотации

**Then** гейт красный с сообщением, называющим workload и число непокрытых ConfigMap'ов
**And** после добавления аннотации — зелёный

> Смысл кейса: гейт заводился под инцидент `envFrom` без `checksum/config`
> (kacho-storage, 2026-07-25) и обязан пережить ретайр **работающим**. Снятие ручки без
> правки скрипта оставило бы `--set kacho-iam.opaSidecar.enabled=true` висеть на
> несуществующем ключе — helm такое не диагностирует, гейт остался бы зелёным и перестал
> бы проверять то, ради чего заведён.

---

**Сценарий 51: стенд поднимается в production-посадке**

**ID:** IAM-C-51

**Given** тот же чарт

**When** выполняется установка релиза в production-профиле и ожидание готовности

**Then** все поды выходят в Ready
**And** посадка подтверждается **у живого процесса** (режим аутентификации, режим TLS к БД,
mTLS) и **со стороны БД** (шифрование соединений), а не чтением ConfigMap'а
**And** boot-guard остаётся живым: инъекция небезопасной настройки роняет старт

---

### S6 — память и анти-реинтродукция

---

**Сценарий 60: возврат разрешений условий роняет сборку**

**ID:** IAM-C-60

**Given** гейт каталога разрешений после ретайра

**When** в каталог вносится запись с `permission`, начинающимся на `iam.conditions.`

**Then** гейт красный с текстом, ссылающимся на этот документ
**And** без такой записи гейт зелёный

---

**Сценарий 61: возврат условий в модель роняет сборку**

**ID:** IAM-C-61

**Given** гейт модели прав

**When** в канонический файл возвращается блок `condition` или тип `iam_condition`

**Then** гейт красный
**And** тот же результат при возврате клаузы `with` в любое отношение

---

**Сценарий 62: возврат префикса ресурса роняет сборку**

**ID:** IAM-C-62

**Given** гейт каталога id-префиксов

**When** в каталог возвращается `cnd`

**Then** гейт красный

---

**Сценарий 63: возврат структур БД роняет сборку**

**ID:** IAM-C-63

**Given** интеграционный гейт схемы

**When** в схему возвращается таблица `conditions`, `access_binding_conditions` или колонка
`access_bindings.condition_id`

**Then** гейт красный
**And** гейт проверен инъекцией реального дефекта (красный до, зелёный после) — сам гейт
не является «формой без содержания»

---

**Сценарий 64: память о причине сохранена**

**ID:** IAM-C-64

**Given** записки vault после S6

**When** ревьюер читает `resources/iam-condition`, `resources/iam-access-binding-condition`,
`rpc/iam-conditions-service`

**Then** каждая — retirement-record: что существовало, шесть причин нерабочести, что снято,
каким PR, дата, и условие возврата
**And** ни одна не удалена
**And** `KAC/IAM-C-conditional-access-retire.md` связывает их и несёт ссылку на этот документ

---

### Сквозные

---

**Сценарий 70: горячий путь авторизации не деградировал — с явным допуском**

**ID:** IAM-C-70

> **Сценарий переписан после ревью круга 1.** Прежняя редакция требовала «p95 не хуже
> базовой линии» без инструмента, профиля, длительности, числа прогонов и полосы
> допуска. p95 шумит: такое утверждение либо всегда истинно, либо ложно по случайности —
> «пройдено/не пройдено» из него не выводится. Ниже — полная спецификация замера.

**Given** стенд, поднятый в production-посадке (`cd deploy && make -C deploy dev-prod-up`), **свободный**
(ни одного параллельного прогона newman/e2e — `shared-stand-single-writer`), с прогретым
процессом (≥60 с после Ready)
**And** инструмент — `ghz`, запускаемый **как in-cluster Job по существующему в репозитории
образцу** `services/vpc/tests/k6/ghz/in-cluster-job.yaml`; артефакт этого сценария —
`services/iam/tests/k6/ghz/` (новый, той же формы). In-cluster, а не port-forward:
port-forward рвётся под нагрузкой (это записано в шапке образца)
**And** профиль: два независимых прогона на RPC — **`AuthorizeService/Check` и
`AuthorizeService/ListObjects`** на публичном листенере iam
(`kacho-iam.kacho.svc.cluster.local:9090`);
закрытая модель, **10 одновременных потоков**, длительность **120 с** на прогон,
фиксированный набор из 200 предсозданных `(subject, object)`-пар, выбираемых по кругу
(чтобы кэш-профиль был одинаков в обеих точках), `--connections 4`

> **Цель замера исправлена в круге 4 (была неверной).** Прежняя редакция мерила
> `InternalAuthorizeService/Check`. Этот RPC — **не тот**, где что-то меняется: его путь
> (`api/internal_iam/handler.go:271` → `AuthorizeService.CheckRelation`,
> `authorize_service.go:396`) **не вызывает** `buildCondContext` и строит одноключевой
> `map[string]any{"current_time": …}` (`:414`); его запрос поля `context` не имеет вовсе.
> Замер на нём измерял бы шум по определению — «форма без содержания» в перф-обёртке.
> Плюс он живёт на internal `:9091` за mTLS, то есть Job'у понадобился бы клиентский
> сертификат ради нулевого эффекта. Аллокацию платят **публичные** `AuthorizeService.Check`
> (`:200` → `:272`) и `ListObjects` (`:579` → `:596`) — на них замер и перенацелен;
> оба доступны Job'у на `:9090` без mTLS-обвязки.
**And** каждая точка замера — **5 повторов** прогона; в сравнении участвует **медиана
p95 по пяти повторам** (одиночный прогон отбрасывается как нерепрезентативный)
**And** базовая линия снята **до S2** на этом же стенде, тем же инструментом, тем же
профилем; сохранены сырые выводы `ghz` всех пяти повторов, а не только сводка

**When** после S4 замер повторяется в точности тем же профилем на том же стенде

**Then** для **каждого** из двух RPC выполняется
`median_p95_after <= median_p95_before * 1.10` (допуск **+10 %**)
**And** дополнительно `median_p50_after <= median_p50_before * 1.10` — p50 устойчивее p95
и ловит систематический сдвиг, который широкая полоса p95 могла бы пропустить
**And** межповторный разброс базовой линии зафиксирован и приложен: если
`(max_p95 - min_p95) / median_p95 > 0.25` по пяти повторам, стенд признаётся слишком
шумным, замер **не засчитывается**, и сценарий перезапускается на успокоившемся стенде
(вместо того чтобы сравнивать шум с шумом)
**And** к тикету приложены **обе линии числами** (p50/p95/p99 × 5 повторов × 2 RPC,
плюс медианы и вычисленное отношение), а не вывод «стало быстрее»
**And** ухудшение сверх допуска — **блокирует merge стадии** и разбирается как регресс,
а не списывается на шум

> Что этим сценарием НЕ проверяется: выигрыш от уменьшения модели прав и снятие
> `BuiltinEvaluator.mu` (последний вообще вне горячего пути — §2). Оба ожидаются в
> пределах шума и предметом приёмки не являются. **И отдельно: не проверяется латентность
> per-RPC энфорсмента шлюза** (`InternalIAMService.Check`) — на ней ретайр не сказывается
> вовсе (§2, врезка), поэтому обещать там улучшение или требовать его отсутствия
> одинаково бессмысленно.

---

**Сценарий 71: аудит не потерял ни одного живого события** — **РЕГРЕСС-КОНТРОЛЬ ЦЕЛИКОМ**

**ID:** IAM-C-71

> **Переклассифицирован в круге 2; из счёта пар RED→GREEN исключён.** Ни одно из трёх
> утверждений сценария **не способно упасть до начала работ**, то есть RED для него не
> существует ни в какой формулировке:
> (а) «каждая мутация по-прежнему оставляет запись аудита» — регрессия на **нетронутых**
> путях (ретайр не касается ни одного эмиттера, кроме `conditions_audit.go`), зелёная и до,
> и после;
> (б) инъекция malformed `event_type` (`'IAM.Condition'`, `'iamcondition'`) отвергается
> ограничением `audit_outbox_event_type_check`, которое **уже существует и работает**
> (`0001_initial.sql:273`: `length ∈ [1,128] AND event_type ~
> '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'`) — обе строки нарушают шаблон (верхний регистр /
> отсутствие точки) и падают на `23514` уже сегодня;
> (в) третье утверждение делегировано в IAM-C-01 и там же засчитывается.
> Круг 2 проверялся: центрального реестра типов событий аудита в коде **нет** (`grep -rln
> 'iam\.condition\.'` по `services/iam`/`gateway` даёт три файла — сам эмиттер, его
> интеграционный тест и **комментарий** в `cmd/kacho-iam/wiring.go:718`), поэтому
> «инвентарь типов сузился на три» как RED-able утверждение построить не на чем: сужается
> не реестр, а множество файлов — а это ровно то, что уже меряет IAM-C-01. Изобретать
> новый реестр ради RED — значит вводить конструкцию под тест (ban #11), поэтому выбран
> честный исход: **сценарий сохранён как регресс-контроль, счёт пар пересчитан**
> (§9: сквозные — **0** пар, сумма **31**, а не 32). По собственному правилу документа
> (см. IAM-C-13) регресс-контроль в счёт пар не записывается.

**Given** три типа события `iam.condition.{created,updated,deleted}`
(`services/iam/internal/service/conditions_audit.go:26,28,30`) сняты вместе с их
единственным эмиттером

**When** прогоняется полный цикл мутаций по всем остальным ресурсам iam

**Then** каждая мутация по-прежнему оставляет свою запись аудита (счёт записей до/после
цикла совпадает с числом мутаций)
**And** ограничение `audit_outbox_event_type_check` живо и **отвергает** запись с
malformed-типом — проверяется инъекцией: прямой `INSERT` с `event_type = 'IAM.Condition'`
(верхний регистр) и с `event_type = 'iamcondition'` (без точки) обязан упасть на `23514`
**And** ни один прод-путь больше не способен эмитить снятые типы — это следует из
инвентаря IAM-C-01 (ноль совпадений `iam.condition.` вне retirement-записок), а не из
содержимого таблицы

> **Третье утверждение переписано после ревью круга 1, но НЕ так, как предложило ревью.**
> Прежняя редакция утверждала «в таблице аудита нет ни одной записи снятых типов (их и не
> было)» — вакуум по собственному признанию, замечание принято. Однако предложенная замена
> («ограничение формата типа события по-прежнему **отвергает снятые типы**») **нереализуема
> и была бы вторым вакуумом**: `audit_outbox_event_type_check` (`0001_initial.sql:273`) —
> это **регулярное выражение формы**, а не whitelist:
> `(length(event_type) BETWEEN 1 AND 128) AND event_type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'`.
> Строка `iam.condition.created` этому выражению **удовлетворяет** (строчные сегменты,
> разделённые точками) и будет принята и до, и после ретайра. Ограничение не может
> «отвергать снятые типы» ни при каких условиях — требовать этого значило бы записать
> в DoD заведомо невыполнимое утверждение.
> Поэтому наблюдаемое разделено на две части, каждая из которых **может упасть**:
> (а) ограничение формата **живо** (доказывается инъекцией malformed-строки — если
> ограничение случайно дропнули вместе с таблицами, `INSERT` пройдёт и сценарий покраснеет);
> (б) отсутствие эмиттера снятых типов доказывается инвентарём кода (IAM-C-01), где это
> утверждение действительно проверяемо. Whitelist-ограничение на типы событий как
> **новая** конструкция в этот ретайр не вводится: это отдельное изменение схемы аудита
> со своей ценой (каждый новый тип события требовал бы миграции), и оно вне scope (§8).

---

## 7. Что остаётся в vault как память о причине

Записки **переписываются**, не удаляются (R10). Обязательный состав каждой:

1. **Статус** — `retired`, дата, ссылка на этот acceptance и на PR.
2. **Что существовало** — ресурс/сервис/таблицы/тип модели/записи каталога, с точными именами
   и идентификаторами, чтобы будущий читатель нашёл их в истории.
3. **Почему не работало** — шесть оснований §1.1 плюс три уточнения §1.2, каждое с точкой в
   коде. Это главная ценность записки: без неё ретайр читается как «передумали».
4. **Что снято и чем это наблюдаемо** — таблица §5.4 (какой код ответа теперь на каком пути).
5. **Условие возврата** — возвращать можно только через новый acceptance, и он обязан начинаться
   с соединительной ткани (кто пишет привязку условия и откуда берётся вычислитель), а не с
   CRUD ресурса. CRUD был написан и протестирован — и остался бесполезен.

Плюс:
- новый трейл `KAC/IAM-C-conditional-access-retire.md` (статус, репозитории, PR, затронутые
  сущности vault, чеклист DoD);
- связка с классовой запиской [[checks-with-form-but-no-substance]] — `Evaluate`, подающий
  отказ как решение, и счётчик ссылок, структурно равный нулю, суть два её экземпляра;
- `[[resources/iam-access-binding]]` — убрать упоминания полей условия, оставив пометку о
  зарезервированных тегах (чтобы никто не переиспользовал номера).

**Записки, которые НЕЛЬЗЯ трогать:** `expires_at` и step-up остаются как есть — они живые (§8).

---

## 8. Out-of-scope

Явно **не** входит в IAM-C. **Каждый пункт ниже имеет исход в §12** — номер заведённой
задачи либо явное «требует отдельной задачи» с критерием; «вынесено и забыто» здесь не
существует по построению.

- **Настоящий язык выражений** (полноценный CEL через компилятор, условия хранилища прав,
  привязка условия к записи выдачи). Это **отдельная фича со своим acceptance**, если владелец
  её захочет. Ретайр не является ни её подготовкой, ни обещанием: возврат начинается с чистого
  проектирования, а не с восстановления снятого.
- **Step-up MFA (`required_acr_min`)** — живой, энфорсится на чувствительных RPC, остаётся без
  изменений. Снятие `mfa_fresh` из модели его не касается: это два независимых механизма, и
  после ретайра step-up остаётся **единственным**, что и убирает нынешнюю двусмысленность.
- **`AccessBinding.expires_at`** — живой TTL, энфорсится реконсайлером (§1.3 E). Правится
  только его proto-комментарий.
- **`deletion_protection`, `labels`, `target`, `subjects`, `materialized_at`** на привязке —
  не затрагиваются.
- **Каскад трёх уровней супер-доступа** и плоская материализация ниже — не затрагиваются;
  из модели уходит только тип `iam_condition`.
- **Перенос данных / бэкфилл** — не требуется (ноль строк, R8 это подтверждает счётчиком).
- **Реформа дренажа, каталога разрешений, hide-existence, listauthz** — соседние поверхности,
  затрагиваются только регенерацией и регрессией.
- **Удаление `resource_version` из `conditions`** — вопрос снимается вместе с таблицей;
  отдельного решения не требует.
- **OPA-сайдкары ДРУГИХ чартов** (`vpc.opa.*`, `compute.opa.*`) — живут за собственными
  флагами в своих чартах и поверхностью условного доступа iam не являются. Их `--set`
  в `config-rollout-binding-test.sh` **сохраняется** (R13). Если они окажутся тем же
  мёртвым классом — это **отдельная под-фаза** со своим acceptance; критерий приёмки для
  неё уже назван: «рендер с принудительно включённым флагом не производит ни одного
  объекта, который читал бы прод-код соответствующего сервиса». Здесь этот вопрос
  не решается и не откладывается «на потом» без адреса — он вынесен с критерием.
- **Whitelist-ограничение на типы событий аудита** (`audit_outbox.event_type` как закрытый
  список вместо регулярного выражения формы, `0001_initial.sql:273`) — **не вводится**.
  Ретайр снимает три типа событий, но не меняет форму ограничения: закрытый список
  потребовал бы миграции на **каждый** новый тип события во всём iam. Это отдельное
  изменение схемы аудита со своей ценой; критерий приёмки для него, если владелец его
  захочет, — «добавление типа события требует миграции, и это осознанный размен».
  Разбор, почему нынешнее ограничение **не способно** отвергать снятые типы, — IAM-C-71.
- **Ретайр `GetJWKSStatus` и остальной мёртвой поверхности JWKS iam** — пересекается с
  этим документом ровно в одной точке: `charts/kacho-iam/templates/jwks-configmap.yaml`
  снимается здесь, потому что он гейтирован **тем же** флагом `opaSidecar.enabled` и
  обслуживает **только** проверку подписи OPA-бандла (§1.3 F, п.1). Остальная JWKS-поверхность
  (контракт `GetJWKSStatus`, ротатор, `values.yaml:56 encKeySecretName`) в этот ретайр
  **не входит**: она ведётся **задачей #47** («Ретайр контракта GetJWKSStatus + мёртвая
  поверхность чарта»). Здесь она явно не трогается, чтобы два потока не столкнулись на
  одном чарте. Граница фиксируется как критерий: этот PR трогает из JWKS-поверхности
  **ровно один** файл — `jwks-configmap.yaml`; всё остальное остаётся #47 (§12, O-4).

---

## 9. DoD

Каждый пункт — **наблюдаемое «пройдено / не пройдено»**: назван прогон, назван набор,
названо «сколько из скольки». Пункт вида «сделано» / «приведено в соответствие» /
«не хуже» без числа и без прогона в этот список не входит по построению.

**Счёт сценариев — всего 40** (`IAM-C-01`…`IAM-C-71`; множество идентификаторов
совпадает со строками таблицы §6.0, 40 = 40). Из них:

- **33 покрыты кодом-артефактом** (Go-тест и/или newman-кейс);
- **7 без кода-артефакта**, каждый помечен в §6.0 и принимается приложенным к тикету
  артефактом с числами: IAM-C-02, IAM-C-03, IAM-C-51 (стендовые процедуры),
  IAM-C-18, IAM-C-44 (прогоны наборов), IAM-C-64 (ревью-чеклист записок vault),
  IAM-C-70 (замер).

**Пар RED→GREEN предъявляется 31**: 33 покрытых кодом **минус два регресс-контроля**,
зелёных и до, и после работ, — для них RED не существует, и записывать их в счёт как
выполненную пару запрещено:

| Исключён из счёта | Почему RED невозможен (проверено по коду в круге 2) |
|---|---|
| **IAM-C-13** | `ConditionsService` регистрируется **только** в `registerPublicServices` (`services/iam/cmd/kacho-iam/grpc_register.go:51`); в `registerInternalServices` (`:73`) его нет и не было ⇒ внутренний `:9091` отвечает `UNIMPLEMENTED` уже сегодня |
| **IAM-C-71** | все три утверждения истинны до работ: аудит нетронутых путей — регрессия; `audit_outbox_event_type_check` (`0001_initial.sql:273`) уже отвергает обе malformed-строки; третье делегировано в IAM-C-01 |

Отдельно: **половина** IAM-C-42 (`IAM-CRET-AZ-EXPAND-SSH-NEG`) — тоже регресс-контроль
(`expandableRelations`, `authzmap/fga_types.go:209-222`, никогда не содержал `ssh`/`console`),
но сам сценарий **остаётся парой** за счёт RED-able половины про `Check` fail-closed, поэтому
на счёт стадии S4 это не влияет.

### Общий (обязателен для каждой стадии)

- [ ] **RED→GREEN предъявлен парой прогонов** по каждому сценарию стадии, покрытому кодом:
      в отчёте — вывод падающего прогона (с причиной падения) и вывод зелёного, а не
      утверждение «тесты написаны первыми». Число пар по стадиям: **S0 — 1, S1 — 7,
      S2 — 6, S3 — 6, S4 — 4, S5 — 3, S6 — 4, сквозные — 0**. Сумма = **31**; совпадение
      суммы с §6.0 (33 покрытых кодом − IAM-C-13 − IAM-C-71) проверяется ревьюером.
      Сквозные дают **0** пар: IAM-C-70 — замер без кода-артефакта, IAM-C-71 —
      регресс-контроль (см. таблицу исключений выше).
- [ ] `go build ./...` — exit 0; `go vet ./...` — exit 0; `golangci-lint run` — 0 issues;
      `govulncheck ./...` — 0 findings.
- [ ] `go test ./services/iam/... ./gateway/... -race` **полностью** (флаг `-short`
      НЕ применяется — он скипает testcontainers-integration и скрыл бы весь S3):
      `ok` по всем пакетам, 0 FAIL, 0 SKIP.
- [ ] Дерево компилируется и стенд поднимается **на каждой** стадии по отдельности
      (green-committable): для каждой стадии зафиксирован `git rev-parse HEAD` + вывод
      `make -C deploy dev-prod-up` до `Ready`.
- [ ] `grep -rnE 'TODO|FIXME|XXX|pm\.test\.skip|t\.Skip' <diff-файлы>` = 0 совпадений;
      ни одного закомментированного утверждения в добавленных тестах.
- [ ] Трассировка сходится в обе стороны: множество `IAM-C-` из грепа по дереву **равно**
      множеству строк таблицы §6.0 (0 сценариев без артефакта, 0 артефактов без сценария).
- [ ] Vault-трейл обновлён; тикет переведён в `Done` с приложенными артефактами.

### S0 (1 пара RED→GREEN; 2 стендовые процедуры)

- [ ] IAM-C-02 (**процедура**): три счётчика §5.3 сняты, к тикету приложены **три числа**,
      каждое `= 0`, вместе с текстом выполненных запросов и меткой времени.
- [ ] IAM-C-03 (**процедура**): обход `ReadTuples` выполнен до исчерпания `page_token`;
      приложены **число страниц**, **общее число кортежей** и **число кортежей с непустым
      `condition` = 0**. Обход без числа страниц не засчитывается (усечённый обход,
      докладывающий ноль, — форма без содержания).
- [ ] IAM-C-01: исполняемый инвентарь §5.1 добавлен, вызывается из CI, гоняется по
      `git ls-files` (untracked `gateway/build/permission_catalog.json` исключён);
      проверен инъекцией — **1 возвращённая строка ⇒ exit ≠ 0**, после отката ⇒ exit 0.
- [ ] IAM-C-01, точечная часть: в теле `resolveActionToRelation` **0** литералов
      `"evaluate"` / `"ssh"` / `"console"` и **3 из 3** сохранённых (`"admin"`,
      `"editor"`, `"viewer"`); в обеих tracked-копиях каталога **0** записей с глаголом
      `evaluate`. Инъекция `"evaluate"` обратно ⇒ гейт красный (проверено отдельным
      прогоном, а не заодно с масочной частью).

### S1 (7 пар RED→GREEN; 1 регресс-контроль без RED; 1 прогон набора)

- [ ] Удалены **все** артефакты таблицы §4 S1 (сверка построчно); `buf lint` — 0 issues;
      generate-diff — пустой.
- [ ] `buf breaking` упал **ровно** заявленным в теле PR набором (§5.4): сравнение
      поэлементное, **0 нарушений сверх заявленных**; `buf.yaml` не изменён (проверено
      `git diff --exit-code buf.yaml`).
- [ ] `cd gateway && make permission-catalog-check` — exit 0; обе tracked-копии
      байт-идентичны (`cmp` = 0); число записей уменьшилось **ровно на 6**
      (`before − after = 6`, оба числа в отчёте).
- [ ] Таблица REST-маршрутов короче **ровно на 6**; `grep '/iam/v1/conditions'
      rest_route_table_gen.go` = 0 совпадений.
- [ ] IAM-C-10, 11, 12, 14, 15, 16, 17 — **7 из 7** зелёные (IAM-C-13 — регресс-контроль,
      зелёный в обеих точках, засчитывается отдельно, RED не предъявляется).
- [ ] IAM-C-18 (**прогон**): полный newman — **0 упавших утверждений**; вердикт прочитан
      из `assertions.failed`, а не из факта выполнения; в отчёте **нет** ни
      `iam-condition(no-report)`, ни `iam-conditional-retired(no-report)`; число
      выполненных наборов **не изменилось** (один снят, один добавлен — оба числа
      в отчёте); новый набор присутствует и в `collections/`, и в отчёте.
- [ ] Процесс поднимается со стоявшими в окружении `KACHO_IAM_CONDITIONS_CACHE_*`
      (readiness достигнут); boot-guard проверен инъекцией `sslmode=disable` →
      **старт отказан**, в логе fatal.

### S2 (6 пар RED→GREEN)

- [ ] Теги `AccessBinding` 9/14, `CreateAccessBindingRequest` 6/7, `Tuple` 4 и контекстные
      теги (`AuthorizeCheckRequest` 4, `ListObjectsRequest` 6) переведены в `reserved` —
      **7 тумбстонов**, номера не переиспользованы (проверено грепом по `.proto`).
- [ ] Комментарий `AccessBinding.expires_at` не содержит слова `OPA` и называет реального
      энфорсера (реконсайлер, §1.3 E).
- [ ] IAM-C-20…25 — **6 из 6** зелёные.
- [ ] IAM-C-25 доказывает отсутствие пути подделки **наблюдаемо**: решение с ключом
      `context` и без него совпадает, и ни одно подложенное значение не появляется в
      исходящем запросе к хранилищу прав (проверено на уровне решения и перехвата запроса,
      а не декларацией R5).

### S3 (6 пар RED→GREEN)

- [ ] Новая миграция добавлена; `0001`/`0013`/`0048`/`0070` не тронуты — sha256 каждого
      из четырёх файлов совпадает с базовым коммитом (**4 из 4**).
- [ ] Пред-проверка на строки реализована и проверена на «**ровно одна** строка» в каждой
      из трёх точек (IAM-C-32): `conditions`, `access_binding_conditions`,
      `access_bindings.condition_id IS NOT NULL` — **3 из 3** дают `RAISE EXCEPTION`.
- [ ] IAM-C-30…35 — **6 из 6** зелёные.
- [ ] IAM-C-34 сравнивает **снимок схемы**, а не наличие таблиц, и проверен инъекцией:
      down, восстанавливающий форму `0001`, делает его красным.
- [ ] IAM-C-35 доводит `goose down` ещё на **два** шага (через `0070` и `0013`) — оба
      без ошибок.
- [ ] Интеграционный тест, утверждавший **наличие** `access_bindings.condition_id`,
      переписан на утверждение **отсутствия** (не удалён).
- [ ] Ветка `access_binding_conditions_condition_fk` в `pgmaperr.go:165` снята вместе с её
      unit-тестом; остальные ветки маппера не затронуты (диф показывает только эту).

### S4 (4 пары RED→GREEN; 1 прогон матрицы)

- [ ] IAM-C-40: оба гейта зелёные — побайтовое совпадение DSL-блока ConfigMap с каноном
      **и** структурное совпадение преобразованной модели; в каноне **0** блоков
      `condition`, **0** клауз `with`, тип `iam_condition` отсутствует.
- [ ] Реестр типов (`authzmap/fga_types.go`) и passthrough-ветка глаголов
      (`authorize_service.go:835`) приведены в соответствие; IAM-C-41, 42 зелёные.
      IAM-C-42 предъявляет **одну** пару RED→GREEN — Go-тест на fail-closed резолвера
      (`Check` с `compute.instances.ssh` / `.console` / `iam.conditions.evaluate`);
      newman-кейс `IAM-CRET-AZ-EXPAND-SSH-NEG` идёт как **регресс-контроль без RED**
      (`expandableRelations`, `authzmap/fga_types.go:209-222`, `ssh`/`console` там
      никогда не было — зелёный до работ).
- [ ] `expandableRelations` **не расширен** ретайром: набор по-прежнему ровно 9 имён
      (`v_get`, `v_list`, `v_create`, `v_update`, `v_delete`, `viewer`, `editor`,
      `admin`, `member`, `authzmap/fga_types.go:209-222`) — **9 из 9**, ноль добавленных.
      Наблюдает это **уже существующий** гейт `fga_model_drift_test.go`, утверждение
      **R-3** («закрытый набор expandable-отношений равен `v_*`/tier/member модели **в обе
      стороны**») — новой проверки не заводится (ban #11); от ретайра требуется, чтобы R-3
      остался зелёным после снятия `ssh`/`console` из модели. Это и есть предмет
      регресс-контроля IAM-C-42.
- [ ] IAM-C-43: предполётный гейт реализован как подкоманда (R14), проверен на «**ровно
      один**» условный кортеж → отказ до записи модели, с числом в сообщении; после
      удаления кортежа — проходит.
- [ ] Новый `authorization_model_id` записан, `KACHO_IAM_OPENFGA_MODEL_ID` перепинен,
      сервисы перекачены **за одно окно** на свободном стенде (зафиксированы старый и
      новый id).
- [ ] IAM-C-44 (**прогон**): матрица «глагол × роль × область» и матрица отказов на 6
      субъектах — **каждая ячейка** совпадает с базовой линией до S4; обе линии приложены
      таблицами, **0 расхождений**; ни один субъект не получил доступа, которого не имел.

### S5 (3 пары RED→GREEN; 1 стендовая процедура)

- [ ] IAM-C-50: гейт по дереву зелёный — **0** `.rego`-файлов, **0** из четырёх шаблонов,
      **0** совпадений `opa` в `deployment.yaml`, и **единый** порог полноты:
      `grep -rl opaSidecar deploy/helm/` = **0 файлов** (сегодня **13**; из них 5 профилей
      values, включая `values.fe3455-prod.yaml`, плюс `charts/kacho-iam/README.md`, который
      прежний, более узкий порог DoD пропускал — §4 S5, строка 8); принудительный рендер
      с `--set …enabled=true` даёт **0** объектов/контейнеров/аннотаций с `opa`.
      Гейт проверен инъекцией.
- [ ] IAM-C-50, границы блоков: из `deployment.yaml` удалены **6 из 6** блоков по
      границам таблицы §4 S5 (метка `:19-22` — вне флага; аннотации `:30-41`, тома
      `:67-76`, env `:293-298`, `envFrom` `:411-418`, контейнер `:431-489` — за флагом);
      `helm template charts/kacho-iam` — **exit 0** и
      вывод проходит `yaml`-парсер; в файле **сохранены** `initContainers:`, петля
      `range … .Values.env` с её `{{- end }}` и обе живые аннотации (**3 из 3**
      сохранённых конструкций присутствуют).
- [ ] IAM-C-52: в prod-рендере политика `openfga-engine-ingress-allowlist` присутствует и
      её `spec` не изменился (диф со старым рендером — пустой по этому объекту); политик
      `opa-bundle-endpoint-ingress` и `opa-sidecar-egress-allowlist` — **0**; в dev-рендере
      политик **0**. Проверено инъекцией: пропажа живой политики делает кейс красным.
- [ ] IAM-C-53: `config-rollout-binding-test.sh` зелёный **после** правки R13; в скрипте
      **0** `--set` на несуществующий ключ (каждый путь резолвится в объединённых values);
      инъекция `envFrom` без `checksum`-аннотации делает гейт красным, добавление
      аннотации — зелёным.
- [ ] IAM-C-53, подключение: скрипт вызывается **шагом CI** в job'е `helm lint · template
      (dev + prod)`, и это подтверждено **строкой в логе прогона**, а не строкой в YAML.
      До этой правки скрипт не вызывался ниоткуда (единственное упоминание — комментарий
      `deploy/scripts/assert-production-posture.sh:79`). Предмет задачи **#81**, §12 O-1.
- [ ] IAM-C-51 (**процедура**): `helm install` в production-профиле выходит в Ready
      (не только `helm template`); посадка подтверждена **у живого процесса**
      (`auth_mode`/`db_sslmode`/mTLS из лога старта) **и** со стороны БД (`pg_stat_ssl`
      = true на всех backend'ах iam); инъекция небезопасной настройки роняет старт.

### S6 (4 пары RED→GREEN; 1 ревью-чеклист)

- [ ] Четыре гейта (IAM-C-60…63) реализованы; **каждый из 4** проверен инъекцией —
      красный до отката инъекции, зелёный после (**4 из 4**).
- [ ] IAM-C-64: три записки vault переписаны в retirement-record, **ни одна не удалена**;
      каждая несёт все **5** обязательных разделов §7; `KAC/IAM-C-conditional-access-retire.md`
      создан и ссылается на этот документ.
- [ ] `services/iam/docs/components/09-conditions.md` и раздел Conditions в
      `docs-site/docs/architecture/authz.mdx` приведены в соответствие; сборка docs-site —
      **0 broken links**.
- [ ] CHANGELOG несёт таблицу §5.4 (**6 строк**, все шесть клиентских путей — REST
      аутентифицированный и REST анонимный считаются раздельно, коды у них разные и
      зависят от посадки).
- [ ] §12 закрыт: **каждая** строка регистра открытых пунктов несёт либо номер задачи,
      либо явное «требует отдельной задачи» + критерий — **0 строк без исхода**.

### Сквозной (0 пар RED→GREEN; 1 замер; 1 регресс-контроль)

- [ ] IAM-C-70: обе линии приложены числами (p50/p95/p99 × **5 повторов** × **2 RPC**);
      выполняется `median_p95_after <= median_p95_before * 1.10` **и**
      `median_p50_after <= median_p50_before * 1.10` для **обоих** RPC;
      межповторный разброс базовой линии `(max−min)/median <= 0.25` (иначе замер
      не засчитан и перезапущен).
- [ ] IAM-C-71 (**регресс-контроль**, пара RED→GREEN не предъявляется): число записей
      аудита после цикла мутаций равно числу мутаций (оба числа в отчёте); инъекция
      malformed `event_type` (`'IAM.Condition'` и `'iamcondition'`) отвергается на
      `23514` — **2 из 2**. Засчитывается как «зелёный до и после», а не как выполненная
      пара; отсутствие эмиттера снятых типов засчитывается в IAM-C-01.
- [ ] Ветка смёржена сразу по зелёному (не копится дольше одного дня), удалена после merge.

---

## 10. Исход замечаний ревью, круг 1

Каждое замечание получило **исход** (правку в тексте либо явный разбор с файлом и
строкой), а не пометку. Ни одно не закрыто смягчением формулировки.

### 10.1 Блокирующие

| # | Замечание | Исход |
|---|---|---|
| 1 | §1.3 F и IAM-C-50: доставка OPA не деплоится, сценарий зелёный до работ | **Принято.** §1.3 F переписан как «мёртвый код шаблонов за навсегда выключенным флагом», утверждения «деплоится / рендерит / пробрасывает / держит» убраны; проверено `helm template` (ноль объектов `opa-*`). IAM-C-50 сделан наблюдаемым **обоими** способами из замечания: отсутствие артефактов **в дереве** (шаблоны/values/файлы/`deployment.yaml`) **и** принудительный рендер `--set …opaSidecar.enabled=true`, требующий, что ручки больше нет |
| 2 | §4 S5 неполон, ломает живой гейт и prod-рендер | **Принято и расширено.** §4 S5 переписан поимённой таблицей из 7 строк: (а) шаблонов **четыре**, не три — четвёртый `jwks-configmap.yaml` найден при сверке, ревью его не называло; (б) добавлены метка пода `:22` (вне флага), тома `:67-77`, аннотации `:38-40`, контейнер `:431-489`, env `:295-298`; (в) `config-rollout-binding-test.sh` получил решение R13 + сценарий IAM-C-53 + пункт DoD; (г) судьба `opaSidecar.networkPolicy` решена явно — R12: политика `openfga-engine-ingress-allowlist` **сохраняется** (живой контроль изоляции хранилища прав, снос был бы регрессом безопасности), две OPA-политики снимаются, ручка переименовывается; сценарий IAM-C-52 |
| 3 | `IAM-C-NN` — третье пространство имён без привязки | **Принято.** Добавлена §6.0: правило именования (Go — ID в ведущем doc-комментарии по образцу geo `protoconv_test.go:28`; newman — `id="IAM-CRET-<VERB>-<KIND>-<OUTCOME>"` по схеме 338 существующих кейсов iam) + **таблица двусторонней трассировки на все 40 сценариев**; 7 сценариев без кода-артефакта помечены явно («стендовая процедура» / «прогон» / «ревью-чеклист»). Трассировка внесена в общий DoD как греп-проверка «множество ID = множество строк таблицы в обе стороны» |
| 4 | Форма down не задана, R9 непроверяем, IAM-C-34 пропустит неверный down | **Принято и усилено.** §4 S3 получил таблицу «форма `0001` vs форма на момент дропа» по 6 позициям; R9 переформулирован как «восстанавливает **пред-дроповую** форму». IAM-C-34 переписан на **сравнение снимков схемы** (колонки/индексы/ограничения/триггеры) + инъекция неверного down. Добавлен **новый IAM-C-35**: `goose down` ещё на два шага, через `0070` **и `0013`**. ⚠️ **Правка круга 2:** обоснование «`0013` даёт вторую поломку — `42710`» было **выдумано** и удалено (`0013:71-72` — `DROP … IF EXISTS` перед `ADD`); отказ цепочки даёт **только** `0070:50` (`42703`), форма whitelist'а держится на поэлементном снимке. См. §11, пункт 1 |
| 5 | Три пункта DoD не наблюдаемы (IAM-C-70, IAM-C-13, IAM-C-71) | **Принято, 2 из 3 — как предложено, 1 — иначе.** (1) IAM-C-70 получил полную спецификацию: `ghz`, 10 потоков, 120 с, 5 повторов, медиана p95, допуск `×1.10` на p50 **и** p95, плюс критерий отбраковки шумного стенда; §2 «Производительность» исправлена — `BuiltinEvaluator.mu` вынесен из горячего пути. ⚠️ **Правка круга 4:** цель замера была указана неверно — `InternalAuthorizeService/Check` `buildCondContext` **не вызывает** (`authorize_service.go:396,414`), эффекта там нет by construction; замер перенацелен на публичные `AuthorizeService/Check` и `/ListObjects`, harness привязан к существующему образцу `services/vpc/tests/k6/ghz/in-cluster-job.yaml`. (2) IAM-C-13 переклассифицирован в явный регресс-контроль, вторая половина вынесена из основного утверждения и исключена из счёта RED→GREEN. (3) IAM-C-71 — вакуум убран, но **не** заменой из замечания: она нереализуема, см. 10.2 |

### 10.2 Где ревьюер ошибся — разбор по коду

Оба пункта перепроверены по дереву; исход — формулировка **по коду**, а не по прежнему
тексту документа и не по замечанию.

> ⚠️ **Частичный отзыв в круге 2.** Пункт **A** был прав в **счёте** (CHECK'ов четыре) и
> **неправ в следствии**: приписанный откату отказ `42710 duplicate_object` в коде
> недостижим. Следствие удалено, счёт сохранён — детали ниже и в §11 пункт 1. Пункт **B**
> подтверждён кругом 2 без изменений.

**A. «Для `access_binding_conditions` „три CHECK'а“ — ВЕРНО (четвёртый,
`_expression_whitelist_ck`, дропнут в `0013:53`)» — неверно. Их ЧЕТЫРЕ.**
`0013_drop_jit_breakglass_condition_whitelist.sql` ограничение **не дропает**, а
**пересоздаёт суженным**: `:52-53` — `DROP CONSTRAINT IF EXISTS`, `:55-63` — тут же
`ADD CONSTRAINT access_binding_conditions_expression_whitelist_ck CHECK (expression = ANY
(ARRAY['mfa_fresh','non_expired','source_ip_in_range','business_hours','device_compliant']))`
(5 значений вместо 7 в `0001:200`); симметрично в Down (`:71-84`). Ограничение с этим
именем **живо на момент дропа**. Прежний текст документа («три») тоже был неверен —
исправлено на четыре.

> ⚠️ **Отзыв части этого пункта (круг 2).** Прежняя редакция добавляла к верному
> счёту неверное следствие: «down обязан восстановить суженный вариант, **иначе `goose
> down` через `0013` упадёт на `42710 duplicate_object`** — это вторая поломка цепочки».
> **Поломки нет.** Down `0013` начинается с `ALTER TABLE … DROP CONSTRAINT IF EXISTS
> access_binding_conditions_expression_whitelist_ck` (`0013:71-72`) и только затем делает
> `ADD CONSTRAINT` (`:74-84`), поэтому имя к моменту `ADD` всегда свободно и `42710`
> недостижим при любой форме whitelist'а. Ревьюер круга 2 прав; правка внесена во все
> четыре места (R9, §4 S3, IAM-C-35, здесь). **Счёт CHECK'ов (четыре) от этого не
> меняется** — он опирается на живость ограничения на момент дропа, а не на поведение
> отката. Требование к форме down тоже сохраняется, но по другому основанию: down = точный
> обратный up, проверяется поэлементным снимком (IAM-C-34). Единственный реальный отказ
> цепочки — `0070:50` (`RENAME COLUMN project_id TO folder_id`, `42703 undefined_column`);
> IAM-C-35 доводит откат на два шага именно ради него плюс подтверждения, что шаг `0013`
> отработал (whitelist снова 7-значный). Это ровно тот класс, который документ ретайрит:
> механизм был описан, а в коде его не было.

**B. Предложенная замена для IAM-C-71 («ограничение формата типа события по-прежнему
отвергает снятые типы») нереализуема — это был бы второй вакуум.**
`audit_outbox_event_type_check` (`0001_initial.sql:273`) — регулярное выражение **формы**,
а не whitelist: `(length BETWEEN 1 AND 128) AND event_type ~
'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'`. Строка `iam.condition.created` ему
**удовлетворяет** (строчные сегменты через точки) и принимается и до, и после ретайра.
Ограничение не может отвергать снятые типы ни при каких условиях. Вакуум устранён иначе,
двумя утверждениями, каждое из которых **способно упасть**: (а) ограничение **живо** —
инъекция malformed `event_type` (`'IAM.Condition'`, `'iamcondition'`) обязана упасть на
`23514` (если ограничение случайно дропнули вместе с таблицами, `INSERT` пройдёт и кейс
покраснеет); (б) отсутствие эмиттера снятых типов доказывается инвентарём кода
(IAM-C-01), где это утверждение проверяемо. Введение whitelist-ограничения как **новой**
конструкции вынесено в §8 с критерием приёмки.

### 10.3 Фактические ошибки документа

| # | Было | Стало |
|---|---|---|
| 1 | §1.3 F: «чарт рендерит два ConfigMap'а, пробрасывает `envFrom`, держит `checksum`» | мёртвый код за навсегда выключенным флагом; проверено рендером |
| 2 | «два ConfigMap'а» / два шаблона | **четыре** шаблона (третий назван ревью, четвёртый `jwks-configmap.yaml` найден при сверке) |
| 3 | §4 S3 шаг 6: «четыре CHECK'а» на `conditions` | **шесть** (`0001:373-378`, один подменён `0070:41-43`); у `access_binding_conditions` — **четыре**, не три (см. 10.2 A) |
| 4 | §4 S1: «сервис + 5 RPC» | **6** RPC (`conditions_service.proto:28,40,54,72,92,114`) — согласуется с 6 записями каталога / 6 маршрутами |
| 5 | §2: `BuiltinEvaluator.mu` на «горячем пути авторизации» | вынесено из горячего пути: единственный вызов `Evaluate` — `conditions_crud_service.go:614` через `api/conditions/handler.go:140`, только RPC `ConditionsService/Evaluate`. Первый пункт (копирование map'а, 8 ключей) подтверждён: `authorize_service.go:58-66,79-92`, вызовы `:272` и `:596` |
| 6 | «`run_one` в `tests/newman/run.sh`» | `services/iam/tests/newman/scripts/run.sh:177` (файла `tests/newman/run.sh` не существует) |
| 7 | §5.2: `make -C gateway permission-catalog-check` без адреса | цель — `gateway/Makefile:67`, запускать из `gateway/`; названы обе tracked-копии; третья копия `gateway/build/permission_catalog.json` объявлена untracked build-артефактом и **исключена** из инвентаря §5.1 |
| 8 | §1.3 D: «комментарий устарел после #71» | комментарий неверен **дважды**: регистрация есть (`restmux/mux.go:612`) **и** записи `iam.condition` в `noPublicListEndpoint` нет вовсе (там только `vpc.addressPool`, `has_list_endpoint.go:45-48`) — то есть `false` там никогда не возвращался. Та же фраза продублирована в `resourceInstanceFetchers.ts:49` |
| 9 | IAM-C-16: «верхняя/нижняя граница прежнего формата» | мотивировка исправлена: `validate.ResourceID` (`validate.go:455-474`) длину/алфавит тела не проверяет вовсе — только членство префикса и `len>=3`; добавлено утверждение про пропуск пустой строки (`:457-459`) |
| 10 | §4 S1 tests: не названы падающие при регенерации артефакты | добавлена строка «tests · правятся» с пятью файлами, включая `super_admin_cascade_test.go:319` (убрать `iam_condition` из списка leaf-типов, **не** ослабляя утверждение) |
| 11 | IAM-C-43 требует гейт, которому §4 не назначает слоя | добавлено **R14**: подкоманда `kacho-iam authz preflight-model-change`, строка в таблице §4 S4, механика — `ReadTuples` (`internal_authorize_service.proto:55`, `handler.go:98`), требование доказуемо полного обхода (число страниц) |

### 10.4 Что расширилось сверх замечаний

Найдено при сверке, ревью этого не называло; каждый пункт получил решение здесь, а не
пометку:

1. **Четвёртый шаблон за флагом** — `jwks-configmap.yaml` (ключ проверки подписи
   OPA-бандла; его собственная шапка уже фиксирует, что наполнять его некому). Снимается
   в S5; граница с отдельным потоком работ по JWKS проведена явно в §8.
2. **Метка пода `kacho.cloud/opa-sidecar: "true"`** (`deployment.yaml:22`) рендерится
   **вне** флага — видна в выводе `helm template` уже сегодня.
3. **Секция `config.authz.opaSidecar`** (`values.yaml:261-266` → `configmap.yaml:135-146`)
   рендерится **вне** флага и Go её не читает — тот же класс, что §1.3 G, на другой ручке.
4. **Пятый профиль values** — `values.fe3455-prod.yaml:148-150` (боевой Beget) несёт
   `opaSidecar.networkPolicy`; ревью называло четыре файла, пропуск оставил бы
   осиротевший ключ в боевом профиле.
5. **Риск потери живого контроля** — наивное снятие блока `opaSidecar` убрало бы
   `openfga-engine-ingress-allowlist` (ограничение ingress на хранилище прав) в проде.
   Закрыто R12 + IAM-C-52 с инъекцией регресса.

---

## 11. Исход замечаний ревью, круг 2

Все проверены по дереву `project/kacho` @ `b892cd8` (ветка `base/redesign`). **Ни одно
замечание не признано неверным** — все шесть подтвердились по файлу и строке. Ни одно не
закрыто смягчением формулировки: там, где документ утверждал несуществующий механизм,
утверждение **удалено**, а требование переобосновано реальным основанием.

### 11.1 Блокирующие

| # | Замечание | Исход | Где смотреть |
|---|---|---|---|
| 1 | **Выдуманный отказ БД `42710`** — `goose down` через `0013` не может им упасть | **Принято полностью.** Проверено: Down `0013` — `ALTER TABLE … DROP CONSTRAINT IF EXISTS access_binding_conditions_expression_whitelist_ck` (`0013:71-72`), затем `ADD CONSTRAINT` (`:74-84`) ⇒ имя к моменту `ADD` всегда свободно ⇒ `42710` недостижим при **любой** форме whitelist'а. Утверждение удалено из **всех четырёх** мест. Требование к down сохранено и переобосновано **двумя реальными основаниями**: (а) единственный отказ цепочки — `0070:50` `RENAME COLUMN project_id TO folder_id` ⇒ `42703 undefined_column`; (б) для whitelist'а отказа нет вовсе, его форма держится на «down = точный обратный up», проверяемом поэлементным снимком. IAM-C-35 переформулирован: инъекция теперь воспроизводит **`0070`-отказ**, а «после `0013` whitelist снова 7-значный» оставлено как признак того, что шаг отработал — не как отказ | R9 · §4 S3 (врезка «Отдельно — обоснование формы whitelist'а») · IAM-C-35 + врезка под ним · §10.1 #4 · §10.2 A (врезка отзыва) |
| 2 | **IAM-C-42, первое Then истинно до работ**, но посчитано парой | **Принято.** Проверено: `expandableRelations` — закрытый набор из **9** имён (`authzmap/fga_types.go:209-222`), `ssh`/`console` в нём никогда не было; отказ даёт `!authzmap.IsExpandableRelation(relation)` → `INVALID_ARGUMENT` (`expand_access.go:117-121`) ⇒ `IAM-CRET-AZ-EXPAND-SSH-NEG` зелёный до единой правки. Сценарий разделён: `ExpandAccess`-половина помечена **регресс-контролем** (по образцу IAM-C-13) и исключена из счёта пар; `Check`-половина (снятие passthrough `case "ssh", "console"`, `authorize_service.go:835`) остаётся RED-able парой, поэтому счёт S4 не меняется. Добавлен DoD-пункт «`expandableRelations` не расширен — 9 из 9» | Сценарий IAM-C-42 + врезка · §6.0 строка IAM-C-42 · DoD S4 |
| 3 | **IAM-C-71 не содержит ни одного RED-able утверждения**, но занимает пару | **Принято, счёт пересчитан.** Проверено все три утверждения: (а) аудит нетронутых путей — регрессия; (б) `audit_outbox_event_type_check` (`0001_initial.sql:273`) уже сегодня отвергает `'IAM.Condition'` и `'iamcondition'`; (в) третье делегировано в IAM-C-01. Дополнительно проверено, **можно ли построить RED-able утверждение**: центрального реестра типов событий аудита в коде **нет** (`iam.condition.` встречается в трёх файлах — эмиттер, его интеграционный тест и **комментарий** `cmd/kacho-iam/wiring.go:718`), поэтому «реестр сузился на три» построить не на чем, а вводить реестр ради теста — ban #11. Выбран честный исход: сценарий **переклассифицирован в регресс-контроль**, арифметика поправлена в **трёх** местах: §9 преамбула (**31**, с таблицей исключений), общий DoD (**сквозные — 0, сумма 31**), заголовок раздела «Сквозной» (**0 пар; 1 замер; 1 регресс-контроль**) + сам пункт DoD IAM-C-71 | Сценарий IAM-C-71 (врезка) · §9 преамбула · общий DoD · «Сквозной» |
| 4 | **§4 S5 даёт диапазоны, захватывающие живые строки**, и противоречит §1.3 F | **Принято и расширено.** Проверено по файлу (489 строк; `wc -l` печатает 488 — нет финального перевода строки). Введено правило «граница = ЦЕЛЫЙ блок» и **единственная нормативная таблица границ** (§4 S5, подраздел «точные границы блоков»): метка `:19-22`, аннотации `:30-41`, тома `:67-76`, env `:293-298`, `envFrom` `:411-418`, контейнер `:431-489`. Исправлены **обе** ошибки замечания и **три сверх него**: тома `:67-77` → `:67-76` (`:77` — живой `initContainers:`), `envFrom` `:410-418` → `:411-418` (`:410` — `{{- end }}` петли `range … .Values.env`, `:407-410`), плюс аннотации `:38,:39,:40` → `:30-41` (иначе остаётся пустая пара `{{- if }}/{{- end }}` и комментарий про три несуществующих ConfigMap'а), env `:295-298` → `:293-298` (осиротевший комментарий), метка `:22` → `:19-22` (осиротевший комментарий). §1.3 F **собственных границ больше не содержит** — там были `:67-75` (терял `{{- end }}` `:76`) и `:431-482` (обрывал контейнер, идущий до `:489`); пункт заменён ссылкой на нормативную таблицу, чтобы двух списков на один артефакт не существовало by construction. IAM-C-50 и DoD S5 получили утверждения о **сохранности соседей** (`initContainers:`, петля env, две живые аннотации) и об успешном рендере валидного YAML | §4 S5 строка 3 + подраздел «точные границы» · §1.3 F п.2 · IAM-C-50 · DoD S5 |

### 11.2 Фактические ошибки

| # | Было | Стало (по коду) |
|---|---|---|
| 1 | «6 кейсов `IAM-CND-*`» (в трёх местах: §4 S1, §5.5, IAM-C-18) | **4** кейса — ровно четыре `CASES.append(Case(` в `services/iam/tests/newman/cases/iam-condition.py` (`:51`, `:144`, `:175`, `:304`) с id `IAM-CND-CR-CRUD-OK` (`:52`), `IAM-CND-CR-VAL-UNSCOPED` (`:145`), `IAM-CND-UP-CRUD-OK` (`:176`), `IAM-CND-LS-AUTHZ-NOBINDINGS-DENY` (`:305`); `IAM-CND` больше нигде в дереве, кроме этого файла и сгенерированной коллекции. Цифра «6» была перенесена из счёта RPC / записей каталога / маршрутов, где она верна. Исправлено во всех трёх местах, id перечислены поимённо |
| 2 | LEAN-остаток `case … "evaluate":` не снимался и инвентарём не ловился | Добавлена строка **«iam · authorize»** в §4 S1 (снять `"evaluate"` из viewer-ветки `resolveActionToRelation`, `authorize_service.go:824-830`, сам элемент `:829`) со ссылкой из §4 S4, где рядом стоит снятие `ssh`/`console` (`:835`). Обоснование мёртвости проверено: `iam.conditions.evaluate` — **единственное** разрешение с этим глаголом (`permission_catalog.json:1307` в **обеих** tracked-копиях; в proto — единственная аннотация `conditions_service.proto:116`). §5.1 получил **не-масочную** проверку (маски по `iam.conditions.`/`iam_condition`/`cnd` слово `evaluate` не покрывают, а маска на само слово шумит и была бы отключена): утверждение о **теле конкретной функции** — нет литералов `"evaluate"`/`"ssh"`/`"console"`, при этом `"admin"`/`"editor"`/`"viewer"` на месте — плюс собственная инъекционная проба. Отражено в IAM-C-01 и в DoD S0. Глагол `evaluate` добавлен третьим входом в IAM-C-42 (fail-closed резолвера) |

### 11.3 Что круг 2 подтвердил без изменений

Ревьюер прогнал по дереву и сошлось точь-в-точь: 6 RPC `ConditionsService`, 6 записей
каталога и 4 `scope_extractor` в обеих копиях, 6 строк allowlist, 6 REST-маршрутов,
регистрация на внешнем mux, двойная ложность комментария `has_list_endpoint.go:28-31`,
дубль фразы в `resourceInstanceFetchers.ts:49`, гашение sentinel в `Evaluate`,
`recogniseExpression` как цепочка `strings.Contains`, 7/6/5 расхождение перечисления,
`type iam_condition` и три `with mfa_fresh`, 8 серверно-авторитетных ключей и
`buildCondContext` на обеих горячих полосах, **шесть** CHECK'ов у `conditions` и
**четыре** у `access_binding_conditions`, форма на момент дропа, мёртвая ручка
`authz.conditions.context-cache-ttl-seconds`, `opaSidecar.enabled=false` во всех пяти
профилях и нулевой рендер `opa-*` при рендерящихся **без** флага метке пода и
`authz.opa-sidecar.*`, три политики под одним `if`, `--set` в
`config-rollout-binding-test.sh:79` при живых `vpc.opa`/`compute.opa`, 403 на промахе
каталога, `NOT_FOUND "unknown method"`, `run_one "iam-condition"` на `scripts/run.sh:177`,
`iam_condition` в списке leaf-типов `super_admin_cascade_test.go:319`, префикс `"cnd"`
(`pkg/ids/ids.go:245`) и семантика `validate.ResourceID` (`validate.go:455-474`, пропуск
пустой строки `:457-459`). Эти утверждения в круге 2 **не правились**.

---

## 12. Регистр открытых пунктов — каждый с исходом (круг 4)

Правило раздела: **ни один пункт вида «осознанно не сделано» / «зафиксировано» /
«расхождение» не остаётся без исхода.** Исход — это либо **номер заведённой задачи**, либо
явная формулировка «**требует отдельной задачи**» с критерием закрытия. Номера не
изобретаются: если пункта нет среди заведённых задач, так и написано.

### 12.1 Пункты, попадающие в уже заведённые задачи

| # | Пункт (и почему он открыт) | Задача | Критерий закрытия — одной фразой |
|---|---|---|---|
| **O-1** | **`deploy/tests/helm/config-rollout-binding-test.sh` не вызывается ни из CI, ни из Makefile** — единственное упоминание вне скрипта — комментарий `deploy/scripts/assert-production-posture.sh:79`; job `helm lint · template (dev + prod)` (`ci.yaml:273`) исполняет lint, два `helm template`, `check-volume-mounts.sh` и `make -C deploy check-mtls-off-complete`, и ничего из `deploy/tests/helm/`. Документ до круга 4 называл его «живым CI-гейтом» (§1.3 F). Тот же класс покрывает и остальные **11** скриптов этого каталога | **#81** (третий пункт: «команда гейта не исполняется из корня и не вызывается в CI») | Скрипт вызывается шагом CI и его вывод **виден в логе прогона**; инъекция `envFrom` без `checksum`-аннотации делает прогон красным, откат инъекции — зелёным |
| **O-2** | **Внутрисервисная карта глаголов расходится с каталогом прав.** `resolveActionToRelation` (`services/iam/internal/service/authorize_service.go:783`) держит собственный словарь: viewer-ветка (`:824-829`) несёт `evaluate`, passthrough-ветка (`:835`) — `ssh`/`console`. Ни у одного из трёх нет пары в каталоге разрешений после ретайра (`evaluate` — единственный такой глагол, `permission_catalog.json:1307`; у `ssh`/`console` записей каталога **ноль уже сегодня**). Ретайр снимает три элемента, но **сам механизм расхождения остаётся**: карта не выводится из каталога и может разъехаться снова на следующем глаголе | **#75** («внутрисервисная карта зеркалит каталог прав; проверено во всех семи сервисах») | Множество глаголов, резолвящихся картой сервиса, выводится из каталога (или сверяется с ним гейтом) во **всех семи** сервисах; расхождение роняет сборку |
| **O-3** | **Гейт `listauthz` покрывает 4 сервиса из 7.** `ci.yaml:226-235` гоняет `make -C services/{compute,nlb,storage,vpc} audit-list-filter`. `iam`, `geo`, `registry` не покрыты — при том что публичные `List` у них есть. Документ опирается на listauthz как на действующий контроль (§2 «Не снимается ничего из действующих контролей»), а для iam этот контроль **не исполняется** | **#75** (та же формулировка «во всех семи сервисах») | `audit-list-filter` (или эквивалент) исполняется в CI для **7 из 7** сервисов; отсутствие цели у сервиса — красный, а не пропуск |
| **O-4** | **Граница с ретайром JWKS-поверхности.** `jwks-configmap.yaml` снимается здесь (он за флагом `opaSidecar.enabled` и обслуживает только подпись OPA-бандла), остальная JWKS-поверхность — нет. Без явной границы два потока столкнутся на одном чарте | **#47** («Ретайр контракта GetJWKSStatus + мёртвая поверхность чарта») | Диф этого PR трогает из JWKS-поверхности **ровно один** файл (`jwks-configmap.yaml`); `GetJWKSStatus`, ротатор и `values.yaml:56 encKeySecretName` в дифе отсутствуют |
| **O-5** | **Решение «ретайрить, а не доводить»** — предмет самой задачи-решения | **#74** («РЕШЕНИЕ ВЛАДЕЛЬЦА: ретайрить условный доступ целиком или доводить») | Задача закрывается ссылкой на APPROVED-версию этого документа и на PR ретайра |

### 12.2 Пункты, для которых задачи НЕТ — требуется завести отдельную

Номера здесь **не проставлены намеренно**: их не существует, и выдумывать их нельзя.
Каждая строка формулирует предмет и критерий так, чтобы задача заводилась без
доисследования.

| # | Пункт | Статус | Критерий закрытия — одной фразой |
|---|---|---|---|
| **N-1** | **OPA-сайдкары чужих чартов** (`vpc.opa.*`, `compute.opa.*`): живут за собственными флагами, их `--set` в `config-rollout-binding-test.sh` сохраняется (R13). Подозрение на тот же мёртвый класс, что снятый здесь, **не проверено** | **требует отдельной задачи** | Рендер соответствующего чарта с **принудительно включённым** флагом не производит ни одного объекта, который читал бы прод-код своего сервиса — либо флаг признан живым и это записано в `docs/architecture/` сервиса |
| **N-2** | **Whitelist-ограничение на типы событий аудита**: `audit_outbox_event_type_check` (`0001_initial.sql:273`) — регулярное выражение **формы**, не закрытый список, поэтому снятые типы `iam.condition.*` оно принимает и после ретайра (разбор — IAM-C-71). Ретайр форму не меняет осознанно | **требует отдельной задачи** | Добавление нового типа события требует миграции — и это записано как осознанный размен; либо решение «оставляем regex» зафиксировано в `docs/architecture/` iam |
| **N-3** | **Настоящий язык выражений** (CEL через компилятор, условия хранилища прав, привязка условия к записи выдачи) — замена снятому. Ретайр не является ни её подготовкой, ни обещанием | **требует отдельной задачи (только по решению владельца)** | Новый acceptance начинается с **соединительной ткани** (кто пишет привязку условия и откуда берётся вычислитель), а не с CRUD ресурса — CRUD уже был написан и протестирован и остался бесполезен |
| **N-4** | **Остальные 11 скриптов `deploy/tests/helm/`** — тот же класс, что O-1: они существуют и, судя по отсутствию вызовов, тоже не подключены. Здесь проверен и адресован **только** `config-rollout-binding-test.sh`; про остальные документ утверждать не вправе | **требует отдельной задачи** | Для **каждого** из 12 скриптов каталога установлено: вызывается из CI (строка в логе прогона) либо удалён как мёртвый — «лежит и не вызывается» не остаётся ни у одного |

### 12.3 Пункты, закрытые внутри этого документа (не переносятся никуда)

Перечислены, чтобы их не приняли за открытые:

- **Ложный комментарий про `ConditionsService.List`** (`has_list_endpoint.go:28-31` и его
  дословный дубль `ui-future/shared/src/lib/resourceInstanceFetchers.ts:49`) — уезжает
  вместе с поверхностью в S1; в набор **не добавляется «починка»**, из него **удаляется
  ложное утверждение** (§1.2 D).
- **Мёртвая ручка `authz.conditions.context-cache-ttl-seconds`** (§1.3 G) — снимается в S1
  вместе с секцией.
- **Расхождение перечисления 7 / модели 6 / вычислителя 5** (§1.2 C) — отдельного действия
  не требует, все три уходят целиком.
- **Расхождение двух списков границ `deployment.yaml`** (§1.3 F п.2 vs §4 S5) — устранено в
  круге 2 сведением к **одной** нормативной таблице (§4 S5, подраздел «точные границы»),
  проверено пофайлово в круге 4: все шесть границ совпали со строками файла.
- **Расхождение двух порогов полноты по `opaSidecar`** (§5.1 «ноль по `deploy/helm/`» vs
  прежний DoD «ноль по `values*.yaml`») — устранено в круге 4 единым порогом
  `grep -rl opaSidecar deploy/helm/` = 0 и добавлением 8-й строки в §4 S5 (README чарта).

### 12.4 Заведённые задачи, встречных пунктов к которым в этом документе НЕТ

Сказано явно, чтобы отсутствие ссылки не читалось как пропуск: **#76** (три дефекта
storage: регион образа, классификация отказа в правах дренажем, необъявленные метрики) и
**#80** (`Snapshot.Create` не валидирует описание и метки синхронно) относятся к домену
**storage** и поверхности условного доступа iam не касаются. Ни одна правка этого
документа их не затрагивает и не заменяет.
