# Архив: testing-newman.md

Снято 2026-09-20. Норма живёт в `.claude/rules/testing-newman.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.
Также остался нормой (искл. а — повелительная форма) `robust-ryw-not-masking`, хотя опись
отнесла абзац, из которого он взят (`n-header`), к классу D: «...newman обязан быть robust
к read-your-writes окну, но НИКОГДА не маскировать реальный дефект» — прямой императив
(«обязан», «никогда не»). Остаток того же абзаца — навигация, ниже в этом архиве.

## n-header (класс D — не норма; императивный хвост абзаца ушёл нормой `robust-ryw-not-masking`)

«Часть правила `.claude/rules/testing.md`. Инварианты, общие всем suite'ам — RYW-retry,
authz-first толерантность негативов, per-service fixture isolation, идемпотентность
прогона, — живут там же, §«e2e-инварианты», и здесь не повторяются.» Навигация и пересказ
eventual-consistency из `api-conventions.md` — предмета нормы не несут.

## poll-cost-and-symptom (класс D — замер и симптом, не норма)

«Цена измерена. Без него петля на 30 итераций покрывает ~0.15s, а не секунды: op завершался
за 3.6s, а кейс сдавался мгновенно (инцидент IAM-USR-INV-CRUD-OK; sweep нашёл 51 такую петлю
в 26 case-файлах iam/registry/nlb).» «Симптом класса: «поллер сдался, хотя async-хвост был
здоров» — выглядит как materialization-лаг сервиса, а на деле проба вообще не ждала.»
Норма (без замера и симптома) — в корпусе как `poll-busywait-before-setnextrequest`.

## parallel-run-and-pointwise-debug (класс C — процесс, гейта нет)

«Параллельный прогон суит и точечный debug. newman-parallel.sh fan-out iam/vpc/compute/nlb
после единого seed → wall-time = max(суита), убирает serial-timeout (суиты независимы при
изоляции). Debug — точечно: newman run collections/<битая>.json + --folder <case>; Go-фикс →
make reload-svc SVC=x (patch без dev-up) → re-run той коллекции.»

## n-meta (класс D — пересказ раздела, не норма)

«Мета: массовая параллелизация большого e2e (65+ коллекций) — инженерная задача пирога
throughput+isolation+idempotency, а не «добавить retry». Retry-обёртки — для истинного
read-your-own-writes EC-окна; не лечат collision/phantom/idempotency (там — fixture-изоляция/
энтропия/preclean-retry). Прод-фиксы (форвард/lock/delete-stale) — TDD+db-review; тест-фиксы
не маскируют.»

## edge-is-newman — поток подписки (класс D — замер; исключение снято 2026-09-23)

Прежняя редакция отдавала тело потока playwright: «ответ-поток newman не дочитывает». Замер
опроверг довод. newman 6.2.2 (конвейер — `newman@6`) против локального SSE (chunked, кадры
`opened` и `event`, служебный кадр раз в 1 с): поток, закрытый сервером через 3 с, — 200,
тело с обоими кадрами, 3 утверждения из 3; незакрывающийся поток — newman не вернулся за 60 с
и при `--timeout-request 8000`. Край kacho закрывает поток сам и чисто: `StreamBudget`
(`KACHO_API_GATEWAY_SUBSCRIPTION_STREAM_BUDGET`, умолчание 90s; чарт
`gateway/deploy/values.yaml` — `streamBudget: 90s`), ветвь `ctx.Done()` в `pump`
(`gateway/internal/subscriptionstream/handler.go`) @kacho 1d42a6728bf; `--timeout-request`
прогонщики kacho не ставят. Итог: тело потока newman читает до закрытия по сроку, консоль
поверх потока — playwright.

## qa-class-label — AUTHN узаконен синонимом правила (класс D — замер; 2026-09-23)

`qa-access` относил 401 к AUTHZ, а держатель 401 на крае помечен AUTHN
(`gateway/tests/newman/cases/authn_edge.py`, 7 списков: 4 отказа 401 и 3 контроля 200).
Решение диспетчера: AUTHN — синоним AUTHZ удостоверения, законен и в новом кейсе. Перепись
@kacho 1d42a6728bf, 60 файлов `*/tests/newman/cases/*.py`; единица — литеральный список
аргумента `classes` по AST (`ast.keyword`, значение `List`): 1070 списков, 1985 элементов —
1981 строковый литерал и 4 условных выражения `"POS" if … else "NEG"`; 7 записей не литералом
(`inner_case.classes`, сложение списков) в счёт не входят. Вне словаря и синонимов 8 меток:
POS 7 (3 литерала и 4 ветви условных), LST 7, AZ 6, FLOW 3, SECD 2, SETUP, CATALOG, OBS по 1 —
их правка в дереве продукта, не здесь. `ALLOW` и `UNAUTH` — операнды сравнения в условии, а не
метки (compute `authz-deny.py:243`, `:271`; storage `authz-catalog.py:113`).

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**edge-is-newman** — прежняя редакция:

edge-is-newman · утверждай поведение края newman-кейсом; край — всё, с чем работает потребитель: gateway kacho и публичные пути kaname, включая ретранслятор `/iam/v1/authorize`, `/iam/v1/token`; HTTP-путь без proto — новый RPC для testing.md#new-rpc-newman-case; поток (`gateway/internal/subscriptionstream`) — тоже: край закрывает его по `streamBudget` (90 s), newman читает тело до закрытия (замер — архив); консоль поверх него — playwright (subscription.md#sub-e2e-observable); Go-проба край не закрывает · ЗАВЕСТИ new-rpc-newman-case · red: путь края покрыт только Go-пробой

**edge-author-black-box** — прежняя редакция:

edge-author-black-box · кейс края пишет тестировщик — `integration-tester` до реализации, `qa-test-engineer` после выкатки и на баг; автор предмета (реализатор, регистратор, чинящий и в аудите, миграция, контракт, профиль края, каркас службы) его заказывает строкой «нужен следующий»; вход — приёмка, контракт, публичная документация, адрес края, провенанс стенда, перечень тронутых методов полными путями, план опыта из них же (testing.md#exp-plan-parallel; пункт — отклонение ответа от контракта), утверждения — тестировщика; код предмета не вход, угол негатива — из контракта; прочитанное — в возврат · вниманием диспетчера: dispatcher.md §3 «Край» · red: ожидание списано с реализации — кейс зелёный на своём дефекте; кейс написан автором предмета

**edge-double-check** — прежняя редакция:

edge-double-check · утверждай обе стороны: исход по приёмке И ответ, равный объявленному интерфейсу, — пара статус и код (e2e-flow.md#assert-status-and-code); ключи тела публичного пути — ровно `json_name` сообщения (публичный mux отдаёт и пустые, `EmitUnpopulated`; внутренний — нет), типы и enum — из контракта, не выписывай; id (api-conventions.md#api-hyphen-prefix), время (api-conventions.md#api-timestamp-truncate), `reason` (api-conventions.md#api-reason-token), текст (api-conventions.md#api-error-tone), драйвера в тексте нет; `content-type`; метод, тип тела и `Accept` вне контракта — исход, вычисленный библиотекой (e2e-flow.md#status-set-computed); эволюцию контракта судит `buf breaking` · ЗАВЕСТИ edge-double-check (сверка тела с дескриптором `buf build proto`) · red: ответ сверен выборочными полями — лишнее, внутреннее или переименованное поле проходит

**edge-composite-chain** — прежняя редакция:

edge-composite-chain · заводи родителей краем по зависимости (сеть → подсеть → адрес), звено утверждает исход операции и захват id (testing-newman.md#fixture-seed-assert-op-error); сноси в обратном и чтением докажи отсутствие остатка, и после отказа посреди цепочки; негативы звена — родитель несуществующий, чужой, удаляемый, в другом проекте или аккаунте (исход по контракту ссылки); удаление родителя с детьми — исход по контракту, без остатка · ЗАВЕСТИ edge-composite-chain (уборка стеком в kacholib; сейчас шаги cleanup руками) · red: снос оставляет сирот; ребро края не пройдено ни одним кейсом (shared-литерал — testing-newman.md#fixture-self-seed-per-case)

**qa-class-label** — прежняя редакция:

qa-class-label · метку `classes` бери из словаря CRUD, VAL, NEG, BVA, IDM, CONC, CONF, STATE, AUTHZ, PAGE, FILTER, SEC (CLASS в `docs/TAXONOMY.md` compute); синонимы `TAXONOMY.md` nlb — IDEM = IDM, AZD = AUTHZ, LSG — PAGE либо FILTER по предмету — перепись сводит, новый кейс пишет словарь; синоним правила AUTHN = AUTHZ удостоверения (401 и его контроль 200) законен и в новом кейсе; метка обязывает к утверждению своего вида: CONF — edge-double-check, VAL — имя поля в отказе, AUTHZ — субъект и исход · ЗАВЕСТИ qa-class-census (validate-cases.py словарь не судит) · red: метка вне словаря и синонимов (POS, AZ) либо без утверждения своего вида — перепись классов ложна

**qa-create** — прежняя редакция:

qa-create · (CRUD, VAL, NEG) минимум и полный набор полей; дубль уникального → ALREADY_EXISTS; нет обязательного → INVALID_ARGUMENT с именем поля; необязательное читается обратно применённым либо отвергнуто с именем поля (api-conventions.md#api-accepted-ignored); свой id клиента — где Create несёт `id` (справочник): форма и дубль, иначе id выдаёт край (api-conventions.md#api-hyphen-prefix); output-only и иной ключ вне контракта не шлётся (TestNewmanCollectionsSendNoUnknownRequestFields); get после операции равен телу, repeated — на ≥3 элементах (api-conventions.md#api-repeated-order) · ЗАВЕСТИ qa-class-census · red: поле принято и проигнорировано

**flow-after-deploy** — прежняя редакция:

flow-after-deploy · после выкатки, тронувшей край, при провенансе «сходится» `qa-test-engineer`: первым smoke — happy каждого тронутого пути, его отказ называет выкатку (e2e-flow.md#cascade-same-text); затем классы свода и хартия: цель, область, срок, объём «пути × классы, запросов N» отдельно от находок (testing.md#census-separate-from-findings), найденное — кейсом либо задачей · вниманием диспетчера: `deploy-engineer` → `qa-test-engineer` · red: выкатка закрыта без прогона тронутого пути; хартия «находок 0» без объёма

**flow-bug-regression** — прежняя редакция:

flow-bug-regression · баг, видимый через край, включая находку аудита, — красный кейс `qa-test-engineer` `# verifies <issue>` до фикса (testing.md#tdd-red-case-links-issue-no-skip, testing.md#known-failing-declared); чинящий его зеленит, не правя; Go RED-lock (testing.md#product-bug-go-fix-not-tolerance) кейса края не заменяет · пометка — tools/knownfailingsubject; наличие кейса — вниманием `landing-reviewer` (landing-reviewer.md:130) · red: фикс влит, кейса-замка края нет

(второй проход того же сжатия)

**edge-internal-consequence** — прежняя редакция:

edge-internal-consequence · внутренний слушатель краем не является; его следствие, видимое через край, утверждай newman, создавая условие средствами потребителя или админ-проекции (`{{internalBaseUrl}}`), иначе — Go integration с причиной в шапке пробы · ЗАВЕСТИ edge-internal-consequence · red: следствие видно через край, проба только Go и без причины

**qa-classes-per-method** — прежняя редакция:

qa-classes-per-method · дай методу края каждый применимый класс свода, неприменимый назови в шапке набора с причиной; позитив — круг create→get→list→update→get→delete→get 404, звено сверяет тело с прежним; техника — скил `testing-product-coach` Часть III · ЗАВЕСТИ qa-class-census (перепись «метод+путь × classes» по `cases/*.py`) · red: метод прожил выкатку с одним happy и одним negative; «кейсов N» без разреза по классам

**qa-list** — прежняя редакция:

qa-list · (PAGE, FILTER) пусто; страницы, в том числе по `pageSize` 1, не пересекаются и покрывают всё, чужого нет; границы и мусорный токен — api-conventions.md#api-pagesize; токен kacho — курсор без привязки (api-conventions.md#api-pagination-cursor): чужой — 200 и только своё, протухший (строка снята) — продолжение без повтора; фильтр верный и кривой; элемент равен get по объявленным полям (api-conventions.md#api-projection-holder) · ЗАВЕСТИ qa-class-census · red: элемент повторён или потерян между страницами

**qa-validation** — прежняя редакция:

qa-validation · (VAL, BVA) классы и границы поля (min−1, min, max, max+1, 0, отрицательное, пусто, переполнение), те же — у вложенного поля и элемента repeated; ловушки края: неверный JSON-тип, формат CIDR, IP, имени, null против отсутствия, неизвестный enum, юникод, пробелы, регистр; недопустимое → INVALID_ARGUMENT с именем поля (api-conventions.md#api-outcome-reject), допустимое — близнец на той же границе; условия — таблицей решений, сочетания полей — попарно · ЗАВЕСТИ qa-class-census · red: граница проверена с одной стороны

**qa-access** — прежняя редакция:

qa-access · (AUTHZ; для 401 и синоним AUTHN — testing-newman.md#qa-class-label) токена нет, он кривой, истёкший, отозванный, чужой аудитории → 401; матрица verb×role×scope (data-integrity.md#authz-edge-matrix); чужой арендатор — security-hardening.md#hard-hide-existence-byte-identical; эскалация через поле тела; Internal краем не отдаётся (00-kacho-core.md#ban06-internal-not-external) · ЗАВЕСТИ qa-class-census · red: отказ проверен одним субъектом

**qa-repeat-race** — прежняя редакция:

qa-repeat-race · (IDM, CONC) повтор мутации — исход по контракту; N параллельных за уникальное имя — ровно один успех, прочие ALREADY_EXISTS; параллельные правки разных полей без версии — обе в get либо проигравшая отвергнута конфликтом (data-integrity.md#db-xmin-occ), молча потерянной нет; правка по версии неприменима, пока версии (etag) в контракте нет, — назови в шапке набора · ЗАВЕСТИ qa-class-census · red: гонка дала два ресурса с одним именем либо потеряла правку

**qa-rate** — прежняя редакция:

qa-rate · (SEC) окно темпа из контракта (kaname: вход, второй фактор; kacho: потолок потоков) — сверх окна 429 с `reason`, `Retry-After` в секундах — где контракт его обещает; после окна проходит · ЗАВЕСТИ qa-class-census · red: окно не отпускает либо обещанного `Retry-After` нет

**flow-red-by-acceptance** — прежняя редакция:

flow-red-by-acceptance · до реализации `integration-tester` пишет по APPROVED приёмке красный кейс на каждый сценарий края, классы — из свода; вход — путь и отпечаток приёмки, ID сценариев, адрес края · `landing-reviewer` на сыром красном (маршрут «Новая фича или RPC» dispatcher.md) · red: кейс края написан после кода и сразу зелёный

**flow-handoff** — прежняя редакция:

flow-handoff · сдавай `cases/*.py` с `classes` и ID сценария либо `# verifies` → validate-cases.py → gen.py; перепись CASES-INDEX; RESULTS «исполнено N из M» (e2e-flow.md#n-of-m-first); новая коллекция kaname — строка PRODUCER_LEDGER; новый набор — e2e-flow.md#new-suite-four-things · validate-cases.py (ci.yaml, обход `services/*`); newman-suite-debt.py (kaname) · red: кейс в дереве, в CASES-INDEX нет; набор вне обхода валидатора — `gateway/tests/newman`

**flow-acceptance** — прежняя редакция:

flow-acceptance · вердикт прогона — `landing-reviewer` по числам; кейс, не падавший ни разу, и правка kacholib или генератора — работа-проверка: `check-verifier` ломает ровно утверждаемое, кейс краснеет с координатой · вниманием диспетчера: dispatcher.md §5 `check-verifier` · red: кейс, не падавший ни разу, принят зелёным

**layer7-ordering-tolerance-negatives** — прежняя редакция:

layer7-ordering-tolerance-negatives · толерируй 400/403/404, never 200; scope-deny пинуй отдельным precond'ом · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: STRICT-403 ложно падает на hide-existence 400

(второй проход того же сжатия)

**edge-double-check** — прежняя редакция:

edge-double-check · утверждай обе стороны: исход по приёмке И ответ, равный объявленному интерфейсу, — статус и код (e2e-flow.md#assert-status-and-code); ключи тела публичного пути — ровно `json_name` сообщения (публичный mux отдаёт и пустые), типы и enum — из контракта; id, время, `reason` и текст — по нормам api-hyphen-prefix, api-timestamp-truncate, api-reason-token, api-error-tone (`api-conventions.md`), драйвера в тексте нет; `content-type`; метод, тип тела и `Accept` вне контракта — исход библиотеки (e2e-flow.md#status-set-computed); эволюцию судит `buf breaking` · ЗАВЕСТИ (сверка тела с дескриптором `buf build proto`) · red: ответ сверен выборочными полями — лишнее, внутреннее или переименованное поле проходит

**edge-author-black-box** — прежняя редакция:

edge-author-black-box · кейс края пишет тестировщик — `integration-tester` до реализации, `qa-test-engineer` после выкатки и на баг; автор предмета (реализатор, регистратор, чинящий, миграция, контракт, профиль края, каркас службы) заказывает его строкой «нужен следующий»; вход — приёмка, контракт, публичная документация, адрес края, провенанс стенда, тронутые методы полными путями, план опыта (testing.md#exp-plan-parallel); код предмета не вход, негатив — из контракта, прочитанное — в возврат · вниманием диспетчера: dispatcher.md §3 «Край» · red: ожидание списано с реализации — кейс зелёный на своём дефекте; кейс написан автором предмета

**edge-composite-chain** — прежняя редакция:

edge-composite-chain · заводи родителей краем по зависимости (сеть → подсеть → адрес), звено утверждает исход операции и захват id (testing-newman.md#fixture-seed-assert-op-error); сноси в обратном порядке и чтением докажи отсутствие остатка, и после отказа посреди цепочки; негативы звена — родитель несуществующий, чужой, удаляемый, в другом проекте или аккаунте; удаление родителя с детьми — исход по контракту, без остатка · ЗАВЕСТИ (уборка стеком в kacholib) · red: снос оставляет сирот; ребро края не пройдено ни одним кейсом

**edge-is-newman** — прежняя редакция:

edge-is-newman · утверждай поведение края newman-кейсом; край — всё, с чем работает потребитель: gateway kacho и публичные пути kaname с ретранслятором `/iam/v1/authorize`, `/iam/v1/token`; HTTP-путь без proto — новый RPC для testing.md#new-rpc-newman-case; поток `gateway/internal/subscriptionstream` — тоже (newman читает тело до закрытия по `streamBudget`, замер — архив), консоль поверх него — playwright (subscription.md#sub-e2e-observable) · ЗАВЕСТИ new-rpc-newman-case · red: путь края покрыт только Go-пробой

**qa-class-label** — прежняя редакция:

qa-class-label · метку `classes` бери из словаря CRUD, VAL, NEG, BVA, IDM, CONC, CONF, STATE, AUTHZ, PAGE, FILTER, SEC (CLASS в `docs/TAXONOMY.md` compute); синонимы nlb (IDEM = IDM, AZD = AUTHZ, LSG — PAGE либо FILTER) сводит перепись, новый кейс пишет словарём; AUTHN = AUTHZ удостоверения (401 и контроль 200) законен; метка обязывает к утверждению своего вида: CONF — edge-double-check, VAL — имя поля в отказе, AUTHZ — субъект и исход · ЗАВЕСТИ qa-class-census (validate-cases.py словарь не судит) · red: метка вне словаря и синонимов (POS, AZ) либо без утверждения своего вида

**qa-create** — прежняя редакция:

qa-create · (CRUD, VAL, NEG) минимум и полный набор полей; дубль уникального → ALREADY_EXISTS; нет обязательного → INVALID_ARGUMENT с именем поля; необязательное читается обратно применённым либо отвергнуто с именем поля (api-conventions.md#api-accepted-ignored); свой id — где Create несёт `id`: форма и дубль; output-only и ключ вне контракта не шлётся (TestNewmanCollectionsSendNoUnknownRequestFields); get после операции равен телу, repeated — на ≥3 элементах (api-conventions.md#api-repeated-order) · ЗАВЕСТИ qa-class-census · red: поле принято и проигнорировано

**qa-list** — прежняя редакция:

qa-list · (PAGE, FILTER) пусто; страницы, в том числе по `pageSize` 1, не пересекаются, покрывают всё, чужого нет; границы и мусорный токен — api-conventions.md#api-pagesize; курсор kacho без привязки (api-conventions.md#api-pagination-cursor): чужой — 200 и только своё, протухший — продолжение без повтора; фильтр верный и кривой; элемент равен get по объявленным полям (api-conventions.md#api-projection-holder) · ЗАВЕСТИ qa-class-census · red: элемент повторён или потерян между страницами

**qa-validation** — прежняя редакция:

qa-validation · (VAL, BVA) классы и границы поля (min−1, min, max, max+1, 0, отрицательное, пусто, переполнение) — и у вложенного поля, и у элемента repeated; ловушки края: JSON-тип, формат CIDR, IP, имени, null против отсутствия, неизвестный enum, юникод, пробелы, регистр; недопустимое → INVALID_ARGUMENT с именем поля (api-conventions.md#api-outcome-reject), допустимое — близнец на той же границе; условия — таблицей решений, сочетания — попарно · ЗАВЕСТИ qa-class-census · red: граница проверена с одной стороны

**qa-access** — прежняя редакция:

qa-access · (AUTHZ; 401 и синоним AUTHN — testing-newman.md#qa-class-label) токена нет, он кривой, истёкший, отозванный, чужой аудитории → 401; матрица verb×role×scope (data-integrity.md#authz-edge-matrix); чужой арендатор — security-hardening.md#hard-hide-existence-byte-identical; эскалация через поле тела; Internal краем не отдаётся (00-kacho-core.md#ban06-internal-not-external) · ЗАВЕСТИ qa-class-census · red: отказ проверен одним субъектом

**qa-repeat-race** — прежняя редакция:

qa-repeat-race · (IDM, CONC) повтор мутации — исход по контракту; N параллельных за уникальное имя — один успех, прочие ALREADY_EXISTS; параллельные правки разных полей без версии — обе в get либо проигравшая отвергнута конфликтом (data-integrity.md#db-xmin-occ); правку по версии, пока etag в контракте нет, назови неприменимой в шапке набора · ЗАВЕСТИ qa-class-census · red: гонка дала два ресурса с одним именем либо потеряла правку

**qa-classes-per-method** — прежняя редакция:

qa-classes-per-method · дай методу края каждый применимый класс свода, неприменимый назови в шапке набора с причиной; позитив — круг create→get→list→update→get→delete→get 404, звено сверяет тело с прежним; техника — `testing-product-coach` Часть III · ЗАВЕСТИ qa-class-census (перепись «метод+путь × classes» по `cases/*.py`) · red: метод прожил выкатку с одним happy и одним negative; «кейсов N» без разреза по классам

**flow-after-deploy** — прежняя редакция:

flow-after-deploy · после выкатки, тронувшей край, при провенансе «сходится» `qa-test-engineer`: первым smoke — happy каждого тронутого пути (отказ называет выкатку, e2e-flow.md#cascade-same-text); затем классы свода и хартия: цель, область, срок, объём «пути × классы, запросов N» отдельно от находок; найденное — кейсом либо задачей · вниманием диспетчера: `deploy-engineer` → `qa-test-engineer` · red: выкатка закрыта без прогона тронутого пути; хартия «находок 0» без объёма

**flow-bug-regression** — прежняя редакция:

flow-bug-regression · баг, видимый через край, включая находку аудита, — красный кейс `qa-test-engineer` `# verifies <issue>` до фикса (testing.md#tdd-red-case-links-issue-no-skip, testing.md#known-failing-declared); чинящий его зеленит, не правя; Go RED-lock (testing.md#product-bug-go-fix-not-tolerance) кейса края не заменяет · пометка — tools/knownfailingsubject; наличие кейса — вниманием `landing-reviewer` · red: фикс влит, кейса-замка края нет

**flow-handoff** — прежняя редакция:

flow-handoff · сдавай `cases/*.py` с `classes` и ID сценария либо `# verifies` → validate-cases.py → gen.py; перепись CASES-INDEX; RESULTS «исполнено N из M» (e2e-flow.md#n-of-m-first); новая коллекция kaname — строка PRODUCER_LEDGER; новый набор — e2e-flow.md#new-suite-four-things · validate-cases.py (ci.yaml, обход `services/*`); newman-suite-debt.py (kaname) · red: кейс в дереве, в CASES-INDEX нет; набор вне обхода валидатора

**flow-flaky-is-defect** — прежняя редакция:

flow-flaky-is-defect · разный исход кейса на одной ревизии и стенде — дефект кейса либо продукта, разбор причины (testing-newman.md#robust-ryw-not-masking); карантин, пропуск одиночного отказа и повтор до зелёного запрещены (testing.md#e2e-no-skip-ever, e2e-flow.md#no-whole-probe-retry); сбой среды — недействителен весь прогон (testing-verdict.md#exhausted-run-is-third-category) · вниманием `landing-reviewer` · red: кейс в карантине либо перезапущен до зелёного

(второй проход того же сжатия)

**qa-update** — прежняя редакция:

qa-update · (STATE, VAL) маска неизвестная, с output-only и с неизменяемым полем — api-conventions.md#api-mask-unknown, api-conventions.md#api-mask-immutable; пустая — полный PATCH (api-conventions.md#api-mask-empty-full-patch); no-op; поле вне маски не тронуто (get после) · ЗАВЕСТИ qa-class-census · red: неизменяемое поле в маске принято

**flow-red-by-acceptance** — прежняя редакция:

flow-red-by-acceptance · до реализации `integration-tester` пишет по APPROVED приёмке красный кейс на каждый сценарий края, классы — из свода; вход — путь и отпечаток приёмки, ID сценариев, адрес края · `landing-reviewer` на сыром красном (маршрут «Новая фича или RPC») · red: кейс края написан после кода и сразу зелёный

(второй проход того же сжатия)

**qa-rate** — прежняя редакция:

qa-rate · (SEC) окно темпа из контракта (kaname: вход, второй фактор; kacho: потолок потоков) — сверх окна 429 с `reason` и `Retry-After` в секундах там, где контракт его обещает; после окна проходит · ЗАВЕСТИ qa-class-census · red: окно не отпускает либо обещанного `Retry-After` нет

(второй проход того же сжатия)

**layer6-retry-create-message-discriminated** — прежняя редакция:

layer6-retry-create-message-discriminated · различай phantom-id и peer-RYW: retry_create_until_present message-discriminated (400/404 + /not found/; валидационные 400 проходят сквозь) · TestPhantomIdGateAttributesPollByOperationVariable · red: retry поверх валидационного 400

(второй проход того же сжатия)

**абзац** — прежняя редакция:

## op-poll с РЕАЛЬНОЙ inter-poll задержкой (выведено из owner-tuple раундов)

**абзац** — прежняя редакция:

## Параллельный newman — слоёная parallel-safety (выведено из e2e-newman стабилизации 2026-07, serial 90мин→parallel ~35мин)

**edge-composite-chain** — прежняя редакция:

edge-composite-chain · заводи родителей краем по зависимости (сеть → подсеть → адрес), звено утверждает исход операции и захват id; сноси в обратном порядке и чтением докажи отсутствие остатка, и после отказа посреди цепочки; негативы звена — родитель несуществующий, чужой, удаляемый, в другом проекте или аккаунте; удаление родителя с детьми — исход по контракту · ЗАВЕСТИ (уборка стеком в kacholib) · red: снос оставляет сирот; ребро края не пройдено ни одним кейсом

**flow-acceptance** — прежняя редакция:

flow-acceptance · вердикт прогона — `landing-reviewer` по числам; новый кейс и правка kacholib или генератора — работа-проверка: `check-verifier` ломает ровно утверждаемое, кейс краснеет с координатой · вниманием диспетчера: dispatcher.md §5 · red: кейс, не падавший ни разу, принят зелёным

**edge-is-newman** — прежняя редакция:

edge-is-newman · утверждай поведение края newman-кейсом; край — всё, с чем работает потребитель: gateway kacho, публичные пути kaname с ретранслятором `/iam/v1/authorize`, `/iam/v1/token` и поток `gateway/internal/subscriptionstream`; HTTP-путь без proto — новый RPC (testing.md#new-rpc-newman-case); консоль — playwright (subscription.md#sub-e2e-observable) · ЗАВЕСТИ new-rpc-newman-case · red: путь края покрыт только Go-пробой
