---
title: newman — гейт, known-RED и загрязнение фикстур
category: packages
repo: kacho
layer: ci
status: stable
tags: [packages, architecture, cross-service, kacho-iam]
verified_against: "координаты записки (гейт-скрипт, выходы прогона) сверены с деревом продукта 1653387b (2026-08-06); числа падений и разбор корней — история прогонов 2026-07, по дереву не переподтверждались"
---

# newman: гейт и почему он краснеет

Вердикт по e2e выносит **не exit-код newman**, а `services/iam/tests/newman/scripts/assert-suites-green.sh`.
Скрипт ОДИН (живёт в iam) и применяется к каждому сервису **с его cwd** — он глобит
`collections/` + `out/` относительно pwd. Так же было в polyrepo; при переезде в монорепу
вызов потерялся, и гейтом стал голый exit newman → краснели кейсы RED-by-design.

## Дефекты гейта (оба чинились 2026-07-16)

> [!danger] Вычитание из РАЗНЫХ популяций прятало падения
> `fails` = `.run.stats.assertions.failed` (только AssertionError), а `known_red`
> считался по всему `.run.failures[]` — там ещё JSONError/script-ошибки. Разница давала
> **запас поглощения** (замер: nlb 9 vs 6, channel-equiv 8 vs 6, invite-grant 3 vs 2), а
> клэмп `fails<0 → 0` глушил перекос молча.
>
> Не теория: `rbac-subject-channel-equivalence` был зелёным ТОЛЬКО из-за перекоса —
> whitelist там нацелен на шаги `*-gone` (они дают JSONError), а настоящие AssertionError
> сидели в **других** шагах: `nonmember-denied` ×2 (не-член не получил отказ),
> `user-not-inherits` ×2 (юзер унаследовал гранты SA). Тесты изоляции падали при зелёном
> гейте. Лечится `select(.error.name=="AssertionError")` в known_red.

**Мёртвый комментарий** про `neg-v_delete-denied`/`neg-v_update-denied`: этих шагов в
`cases/` нет (grep → 0), в whitelist они не входят (doc-truthfulness).

## ОКОНЧАТЕЛЬНЫЙ root-cause (multiagent triage 2026-07-16) — TEST-FIXTURE, не продукт/регресс

96 записей label-revoke на чистом kind → **один test-fixture корень, доказано**:
каскад `editor from account` на типе `project` **осознанно удалён** коммитом `f869c8e`
«[rbac-2026 Contract-A] flat index (#122)» (Point Pu, 2026-06-24) **внутри polyrepo** —
модели monorepo↔polyrepo **байт-идентичны** (кроме license-header). Под Contract-A владелец
материализуется **reconciler'ом** (per-object forward-materialization owner `*.*` ARM_ANCHOR
на Create, см. `services/iam/.../api/project/create.go:33-38,168-178` +
`docs/architecture/owner-role-content-access-cascade.md`), НЕ FGA-каскадом.

- **Root A — МИСДИАГНОЗ, ОПРОВЕРГНУТ эмпирикой (qa-агент, прямое FGA :check-зондирование).**
  Гипотеза «swap `jwtAccountAdminA`→`jwtProjectAdminA1`» НЕВЕРНА. На корректно засеянном стенде
  `jwtAccountAdminA` **имеет** `editor@project:A1` (create→200) И `editor@vpc_network` (update→200);
  `jwtProjectAdminA1` имеет `editor@project`, но **НЕ** `editor@vpc_network` — его PATCH даёт 403
  даже на своей сети (**network-editor привязан к account, не к project**). Swap на PA1 ломает
  update-путь (+46 падений). Наблюдавшийся ранее `create-net-n1 → 403` в out/*.json был
  **транзиентным seed-propagation-lag'ом** на непрогретом FGA, НЕ реальным багом. Оригинальная
  идентичность (всё `jwtAccountAdminA`) — правильная для deployed flat-модели. Root A применять НЕ надо.
- **Root B (~51, ЕДИНСТВЕННЫЙ реальный корень label-revoke) — применён (commit 42c3632).**
  `POST /iam/v1/internal/iam:check` бил в external :18080 (public cmux) → `404 page not found` →
  JSONError в test_script. **Фикс test-only:** file-local `_internal_url_override(path)` (зеркало
  `iam-internal-only-check.py`) как `pre_script` на каждый Check-probe → перенаправляет на
  `{{internalBaseUrl}}` :18081 (cluster-internal REST, инъектится `newman-e2e.sh --env-var
  internalBaseUrl=http://localhost:18081`). Применён к label-revoke-vpc/compute +
  rbac-subject-channel-equivalence + iam-authz-grant-check-propagation. RED→GREEN: compute **9→0
  полностью**, vpc **31 JSONError→0** (+3-4 флапа async-revoke-convergence — load-induced, свежий
  стенд сходится; POLL_CAP=30 vs fga_outbox-drain-lag на загруженном стенде).
- **Residual (product-decisions, не Stages 1-2):** (1) operations-worker + fga-register-drainer
  похоже НЕ запущены на umbrella clean-kind (Operation'ы AccessBinding/IssueSAKey `done:false`) —
  реальный **deploy-gap**; (2) anon Operations.Get/Cancel: 401 (authN-first) vs 404 (hide-existence) —
  контрактный вопрос; (3) owner-tuple: синхронно-at-op-done или eventually-consistent (poll-backoff).

Stages 1-2 (Root B+A) → оба label-revoke набора зелёные. Прежние заметки ниже (step-up NO-OP,
пагинация) — верны, но это уже про residual-наборы, не про доминирующий корень.

## Корень остаточной красноты — загрязнение фикстур, НЕ баг продукта

На кластере с нуля (26/26 Running) остаётся **68** падений в 8 наборах. Первое звено:

```
IAM-ACB-CR-CRUD-OK :: poll-op
  code 6 ALREADY_EXISTS: "these permissions are already granted to <NOB> on account:acc…"
```

Это **правильное** поведение продукта (UNIQUE → AlreadyExists). Неверен тест: он ждёт
чистый лист для ресурса, **не привязанного к `runId`** (binding NOB на fixture-аккаунте A).
Create не прошёл → `get-confirms` 404 → каскад.

`setup.sh` про это знает (шаг «4b KAC-132: clean up stale NOB bindings»), но чистит
**один раз перед** прогоном, а загрязнение возникает **во время**: коллекции идут по
списку (`authz-deny` → … → `iam-access-binding`), ранняя создаёт binding, поздняя на него
натыкается. KAC-132 лечит симптом.

**Почему per-case pre-clean не спасает.** У `IAM-ACB-CR-CRUD-OK` есть свой pre-clean, но
он зовёт `ListBySubject` — read, авторизованный **не** под тем субъектом, под которым
чистят: вызывающий получает 403, скрипт `if(code===200)` его не ловит, дубль не удаляется
и «очистка прошла» рапортуется. Правильный путь — `ListByScope(resourceType=account)`,
где account-admin действительно viewer своего scope. В polyrepo этот pre-clean был тот же
и так же не работал — RESULTS.md звал это «occasionally flake». Направление фикса и где он
застрял — kacho#6.

> [!warning] Отказ, разобранный как пустой результат — тот же класс, что ниже про 403
> Оба дефекта этого файла (`delete_binding_if_exists` и этот pre-clean) — одна ошибка:
> **код ответа не проверялся, разбирали только тело**. Отказ приходит валидным JSON'ом,
> `.get(..., [])` даёт пустой список, и «удалено 0» неотличимо от «удалять было нечего».
> Очистка, которая не может пожаловаться, не работает никогда — и молчит об этом.
> Проверяй HTTP-код, а не только парсинг тела.

> [!note] Полоса авторизации `ListBySubject` с тех пор изменилась
> Прежние координаты каталога для этого RPC устарели и здесь намеренно не приводятся:
> RPC переведён на **`scope_filtered`** (авторизация на уровне данных — сервис отвечает
> строками, на которые у вызывающего есть право, вместо одного вопроса про кластерный
> объект). Причина ровно та, что описана в `security.md`
> §«Отношение, выполнимое подстановочным знаком»: у метода, который перечисляет выдачи
> по идентификаторам, названным **вызывающим**, единого объекта для per-RPC Check нет,
> поэтому «один вопрос» либо не сужает ничего, либо отвечает не про тот объект.
> Актуальную полосу читай в proto, не отсюда.

Масштаб: `listBySubject` в pre-clean/setup — **7 кейсов**, не везде это pre-clean (местами
тест контракта, 403 ожидаем). Каждый требует разбора. Полный зелёный — крупная
fixture-переработка, не один заход.

> [!danger] step-up на dev-стенде — NO-OP (моя гипотеза опровергнута экспериментом)
> В `authn.mode=dev` acr step-up gate **НЕ энфорсится**: `jwtAccountAdminA` (без acr) и
> `jwtAccountAdminAStepUp` (acr=2) дают ИДЕНТИЧНЫЕ ответы на DELETE/PATCH/GET (проверено
> curl'ом). 403 на мутациях — это FGA **object-authz** (`lacks relation v_delete/v_update`),
> одинаковый для обоих токенов, а НЕ acr-gate. Массовый flip на step-up = no-op (только
> шумит diff). Мои прогоны «40→28 через step-up» были иллюзией загаженного стенда.

**Настоящие fixture-баги (test-only, найдены qa-агентом, ЦЕННЫ):**
1. **pre-clean cross-user 403.** `:listBySubject?subjectId=userNOBId` под токеном OWNER'а →
   403 (owner ≠ subject) → дубль не найден → `create` ALREADY_EXISTS → phantom crudAcbId →
   каскад. Фикс: авторизованный `:listByScope` + фильтр `subjectId===userNOBId`.
2. **Пагинация.** `:listByScope`/`ListByAccount` пагинируются по 50; scope засорён >50
   биндингами прошлых прогонов → целевой дубль на 2-й странице. Фикс: `&pageSize=1000`.
3. **Status-фильтр.** Искали `status==='ACTIVE'`, API отдаёт `STATUS_UNSPECIFIED`. Фикс: принять оба.

> [!danger] ОПРОВЕРГНУТО измерением: чистый стенд НЕ даёт зелёный (2026-07-16, свежий kind)
> Прежняя гипотеза «сойдётся ТОЛЬКО на чистом стенде» **неверна**. Прогон на реально
> свежем kind (`make dev-down` = `kind delete cluster` → `dev-up`, 26/26 Running) через
> сам гейт `assert-suites-green.sh` дал **96 падений в 8 наборах** (после known-RED skip):
> `label-revoke-vpc 40 · label-revoke-compute 16 · iam-access-binding 18 · rbac-visibility-set 10 ·
> iam-read-authz-vget 4 · rbac-subject-channel-equivalence 4 · iam-authz-grant-check-propagation 3 · iam-user 1`.
> Загрязнение стенда — НЕ причина (стенд пересоздан). Классификация корней (evidence из out/*.json):
> - **каскад от `create → 403`** (label-revoke-vpc/compute, большинство): actor без grant на create →
>   403 → `{{_op}}` не проставлен → `poll` шлёт литерал `{{_op}}` (`invalid operation id`) + `GET /…/{{id}}`
>   с литералом в пути → grpc-gateway `404 page not found` (JSONError). Один каскад = одно 403. FGA-grant/пропагация;
> - **authz-контракт**: anon → 401, тест ждёт 404 (anti-leak) / 403 (iam-authz-grant-check-propagation);
> - **visibility/listauthz**: list-only видит detail (200 вместо 404-hide); non-member видит 1 юзера вместо 0;
> - **teardown-order**: `teardown-binding` → `code:7 PreconditionFailure`; `teardown-*-gone` → 404.
>
> Вывод (жёсткий, на свежем kind): green — крупная многонаборная работа (FGA-grant-пропагация в фикстурах +
> authz-контрактные ожидания + teardown-порядок), НЕ «чистый стенд» и НЕ один заход. CI тоже поднимает
> свежий kind → на CI гейт красный по тем же 96. `RESET_FGA`/re-up краснотy не снимают.

> [!danger] Автоматическое применение step-up РЕГРЕССИРУЕТ — только ручной разбор
> Замеры на iam-access-binding: базовый pre-clean-фикс 40→28. Массовая замена всех
> мутаций (26 шагов) на step-up → **34**. Замена «в non-deny кейсах» (25 шагов) → **46**
> (total assertions упал 390→289 — `setNextRequest`-цепочки порвались, кейсы пропущены).
> Даже специализированный `qa-test-engineer` агент со всем контекстом → **47**.
> Причина: каждый шаг взаимодействует с соседними через `setNextRequest`, а step-up
> меняет не только acr-проход, но и семантику (deny-тест 403→200, existence-hide 404→200).
> Различать success-мутацию / deny-тест / chain-звено можно ТОЛЬКО читая test_script и
> id кейса поштучно, прогоняя после КАЖДОЙ правки и сверяя, что total assertions не упал.
> Это ~28 шагов в одном наборе × 8 наборов, прогон 3-4 мин каждый — дни работы, kacho#6.

> [!warning] 403 парсится как пустой список
> `delete_binding_if_exists` звал УДАЛЁННЫЙ роут `:listByResource` (RPC переименован в
> `ListByScope`, wire-имя снято) → 403 приходил **валидным** JSON'ом, `.get('accessBindings', [])`
> давал пустой список → «удалено 0» и отчёт об успехе. Очистка не работала никогда.
> Проверяй HTTP-код, а не только парсинг тела. См. [[../rpc/iam-access-binding-service]].

## Гочи прогона (стоили часов отладки)

> [!danger] Не держи ручной `kubectl port-forward` во время `newman-e2e.sh`
> Скрипт сам поднимает port-forward на :18080/:18081/:19091. Висящий ручной форвард
> (напр. для отладочного curl) занимает порт → `setup.sh` не достучится до
> iam-internal :19091 → `FATAL: user AAA resolved to an empty id`. Прогон падает на
> setup, out/*.json НЕ обновляется. Перед прогоном: `pkill -f 'port-forward svc'`.

> [!warning] Single-collection прогон пишет ТОЛЬКО cli, не out/*.json
> `newman-e2e.sh iam <collection>` запускает newman с `--reporters cli` — JSON-отчёт в
> out/ НЕ пишется, там остаётся файл от последнего ПОЛНОГО прогона (`run.sh`). Парсить
> результат надо из **cli-лога** (`│ assertions │ … │`, `inside "IAM-…"`), а не из
> out/*.json — иначе анализируешь устаревший отчёт (реальная потеря: час на «фикс не
> применяется», хотя out/ был просто старый).

> [!note] Почему выходы прогона здесь БЕЗ обратных кавычек (сверено 1653387b, 2026-08-06)
> Каталог этих файлов закрыт от учёта (`services/iam/tests/newman/.gitignore`), значит
> координатой дерева они не являются **по построению** и не станут ею никогда. В обратных
> кавычках такая строка читается как утверждение «в дереве есть этот файл» и вечно висит
> находкой хука свежести. Ровно тот класс, который сам этот файл разбирает про мёртвый
> комментарий и про удалённый роут: имя, пережившее свой предмет. Постоянный адрес выходов
> один — шапка `services/iam/tests/newman/scripts/run.sh`, где они перечислены.

> [!danger] Fresh dev-up → ПЕРЕИЗВЛЕКИ mTLS client-cert перед reseed/geo-seed (stale-cert блокер)
> `prodseed_matrix.py`/geo-seed бьют iam-internal :9091 по **mTLS** (`/tmp/iam-mtls/client.crt`
> +`.key`, grpcurl `UpsertFromIdentity`). После `dev-down→up` cert-manager **регенерит
> internal-CA** → cert со СТАРОГО стенда signed старой CA → :9091 отвергает (SPIFFE/CA-mismatch)
> → `UpsertFromIdentity` **виснет на dial-deadline** → 0 users → `db_lookup(...) empty after
> retries` → пустой matrix → весь прогон washed. Это **персистентный** блокер (НЕ transient
> provisioning-EC — bounded-retry просто пере-виснет, каждый раз новый email). Фикс —
> переизвлечь cert из живого секрета ПЕРЕД reseed:
> ```
> kubectl -n kacho get secret api-gateway-client-tls -o jsonpath='{.data.tls\.crt}'|base64 -d >/tmp/iam-mtls/client.crt
> kubectl -n kacho get secret api-gateway-client-tls -o jsonpath='{.data.tls\.key}'|base64 -d >/tmp/iam-mtls/client.key
> ```
> `prodrun.sh` делает это автоматически перед reseed (commit 4c54c67). #67-adjacent (тот же класс
> «fresh dev-up обнуляет/протухает фикстур-предпосылку»: geo-каталог пуст, mTLS-cert протух).

## Что вычитается корректно (RED-by-design, каждый с тикетом)

- `SEC-C-A-*` — fga-proxy Register/Unregister: internal-only :9091 **без** `google.api.http`
  → REST-хендлера нет вовсе, как black-box неисполнимы; покрыты `fgaproxy_test.go` (#111).
- `T31-LBLREVOKE-NLB-*` — infra-RED: EXTERNAL listener требует zone_id, которого env не
  провиженит (#217).
- `iam-invite-grant-fga` T-E4 — product-gap: `CreateRoleRequest` без `project_id` (#212).
- `*-gone` — poll-хвост eventual-consistency (#257).

Связано: [[kacho-ci-runners]], [[kacho-ci-determinism]], [[../rpc/iam-access-binding-service]].

#packages #architecture #cross-service #kacho-iam
