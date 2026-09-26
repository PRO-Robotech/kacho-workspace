# Архив: security.md

Снято 2026-09-20. Норма живёт в `.claude/rules/security.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.
Также остался нормой (искл. а — повелительная форма) `sec-internal-trusted-assumption-banned`,
хотя опись сводила его к «слить с другой»: «Internal = trusted, mTLS достаточно» —
**запрещённое допущение**, а прохибиция — норма независимо от класса описи.

## sec-parts-table (класс D — не норма, навигация)

«## Части этого правила» — таблица трёх файлов правила (`security.md`,
`security-hardening.md`, `security-disclosure.md`) с перечнем предмета каждого.
Навигацию между файлами правил не дублировать в тексте нормы; предмет остальных
файлов см. их собственные frontmatter `description`.

## sec-empty-circle-semantics (класс D — довод к норме `sec-forwarder-allowlist-nonempty`)

Норма-предложение «Пустой список — это «не сужаем», а НЕ «запрещаем» (non-negotiable).»
осталась в корпусе буквально (адресуется извне из `subscription.md`). Здесь — довод:
сверка отправителя со списком (`grpcsrv.principalIsTrusted`) осмысленна только если
список непуст; на пустом она пропускает всех. Замер 2026-07-27: класс нашёлся в
четырёх сервисах, и дважды комментарий рядом утверждал обратное («не принимается
ни от кого»).

## sec-tls-does-not-narrow (класс D — довод)

«Слоем ниже это не закрывается: TLS доказывает, что пир предъявил сертификат нашего
CA, и ничего не говорит о том, за кого ему позволено говорить; сетевой слой этого
вопроса тоже не решает.» Вывод (сужение обязано быть явным) — норма
`sec-forwarder-allowlist-nonempty` в корпусе.

## sec-tool-names-stay (класс D — решение 2026-08-02 о СВОЁМ тексте, не норма кода)

«Почему имена средства в этом пункте остаются» — разбор, почему `WithTrustedForwarders`,
`CertIdentityExtract`→`TrustedPrincipalExtract`, `principalIsTrusted` не выхолащиваются:
без имени средства часть (б) нормы «сужение непустым списком» неисполнима — негде
проверить, что сужение есть. Уходит только привязка к прежней дыре (какой сервис был
открыт) — запрещённая сборка «координата + условие + следствие», симметрично
`sec-coordinate-really-unique` ниже. Замер ревизии `6e627cda`: безусловное извлечение
личности — 0 мест; trust-aware пара — во всех семи сервисах.

## sec-retroactive-authz-fix (класс D — слить с другой)

«Это строже, чем ban #6 (про поверхность методов) — здесь про обязательность authN+authZ
на КАЖДОМ запросе обоих листенеров. Применяется ретроактивно: любой существующий
листенер без authz-Check на internal — приоритетный security-фикс.» Норма (сам
инвариант) — рядные строки корпуса; здесь только ретроактивность как довод.

## sec-internal-admin-inventory (класс D — не норма, перечень)

«Текущие Internal admin-ресурсы (kacho-only, нет на external): `AddressPool`
(`/vpc/v1/addressPools`, kacho-vpc); `Region`/`Zone` — админ-CRUD через
`InternalRegionService`/`InternalZoneService` (:9091, kacho-geo).» Перечень стареет
быстрее правила; норма «Admin-ресурс — только Internal» — в корпусе (`sec-ban6-internal-not-on-external`).

## sec-issuance-two-presentation-kinds (класс D — не норма, описание)

Внешне досягаемая поверхность выдачи iam несёт «два вида предъявления»: подпись ключом
служебной учётки (docker-токен) и подписанное утверждение клиента, сверяемое открытым
ключом из реестра (client-credentials). Второй выпускает наш подписант. Нормы из этого
блока (один слушатель, путь не резолвится на других слушателях, побайтово одинаковые
отказы, четыре величины с boot-guard) — в корпусе как отдельные строки.

## sec-why-these-four (класс D — довод, ссылка на решение)

«Почему именно ЭТИ четыре, а не шесть из §3 п. 11 приёмки» — приёмка судит проверку
ПРЕДЪЯВЛЕННОГО утверждения (адресат, издатель, алгоритмы, длительность, допуск часов,
потолок тела), здесь — величины СВОЕЙ выдачи. Решение `PRO-Robotech/kaname#112`,
перечень назван одинаково в правиле, приёмке и страже.

## sec-nonzero-default-means-dead-guard (класс D — слить с `sec-no-silent-default-for-guarded-knob`)

«Умолчание, отличное от нулевого, — признак того, что страж по этой величине мёртв.»
Замер 2026-09-16: на стволе `kaname` умолчания `token-ttl`/`body-ceiling` ненулевые
(предикат: `git -C kaname grep -n 'token-ttl\|body-ceiling' origin/main --
internal/apps/kaname/config/defaults.go`), на ветке `batch-security-and-data` обнулены.
Общая норма (запрет молчаливого умолчания в загрузчике) — строка корпуса
`sec-no-silent-default-for-guarded-knob`, её `red:`-поле и есть этот признак.

## sec-compute-geo-routes-gone (класс D — не норма, фиксация факта дерева)

«Здесь стояли compute-маршруты каталога размещения — их нет, и владелец другой»
(хук свежести документации 2026-08-04): в `proto/kacho/cloud/compute/v1/` нет ни
region-, ни zone-контракта, Geography — в **geo** (KAC-эпик #82). Мёртвый адрес не
воспроизводится координатой намеренно.

## sec-infra-why-defense-in-depth (класс D — довод)

«Зачем: defense-in-depth — даже скомпрометированный публичный API не должен раскрыть
физическую топологию/placement (разведка для lateral movement; tenant A не должен
вывести «мой и чужой инстанс на одном железе»).» Норма (две проекции, только Internal*)
— в корпусе.

## sec-no-single-carrier-package (класс D — замер 2026-08-04, не норма)

«Единого пакета-носителя НЕТ» — каталога с этим именем нет ни у одного из семи сервисов,
носитель у каждого свой (страж прав / транспортный слой / use-case). Правило требует
свойства (личность вызывающего доезжает до use-case), оно выполняется; общего имени
у свойства в дереве нет. Заведут носитель — имя вернётся вместе с ним.

## sec-authz-gate-is-check (класс D — слить с другой, именование)

«Per-RPC authz-gate: `InternalIAMService.Check`; caller-identity сервисы читают из
метаданных запроса, а право прислать эти метаданные сужается списком законных
отправителей» — именование механизма, норма сужения — `sec-forwarder-allowlist-nonempty`
и соседние строки корпуса.

## sec-dev-full-access-abolished (класс D — явный редирект на другой раздел)

«dev-режим, в котором неаутентифицированный запрос получает полный доступ, упраздняется
(нарушает инвариант выше)» — текст сам указывает: «Норма целиком — §«Production-mode —
ОБЯЗАТЕЛЕН ВЕЗДЕ» ниже.» В корпусе — весь блок строк под этим заголовком.

## sec-list-visibility-incident (класс D — инцидент-довод к строкам `sec-page-then-check`/`sec-time-budget-per-request`/`sec-pagetoken-may-encode-closed-row`)

Выведено из дефекта видимости 2026-07-25: перечисление разрешённых объектов имело
жёсткий серверный предел без продолжения; ресурсы сверх предела становились владельцу
невидимы навсегда при живых правах (мутации работали — прямая проверка); предел общий
на тип, не по-арендаторный; детектор усечения был всегда ложным (сравнивал длину с
собственной обрезкой) — класс «форма проверки без содержания».

## sec-real-authn-comes-with-iam (класс D — статус интеграции, не норма)

«Реальный AuthN (validated JWT/IAM-token) — приходит с интеграцией IAM; downstream API
(`tenant.TenantFromCtx`, `AssertProjectOwnership`) не меняется.» Статус интеграции,
не поведенческое требование к новому коду.

## sec-coordinate-really-unique + sec-remeasure-the-assertion (класс C — процесс правки корпуса, не норма кода)

«Этот абзац произвёл ТРИ ложные координаты подряд» — имя проверки приписывали то vpc,
то geo, то локальной функции geo, которая через сутки исчезла как дубликат общего
дескриптора. Норма отсюда (о ТЕКСТЕ правила, не о коде): координату пишут в правило
только когда она одна на весь класс; перечень «у кого где лежит» стареет быстрее всего
подвижного из семи и владельца не имеет. И перемеряется утверждение, а не опровержение:
«функции нет у vpc» не доказывает, что она есть у geo — вторая координата была ложной
именно так.

## sec-geo-had-no-guard (класс D — историческая иллюстрация к `sec-posture-judged-by-common-descriptor`)

«У geo стража не было вовсе до задачи продукта #1380: он объявлял `AUTH_MODE`,
`DB_SSLMODE` (умолчание `disable`) и обе ручки круга отправителей, не читал ни одну,
а самоотчёт о посадке создавал видимость контроля.» Сегодня — гейт
`TestServiceDeclaringPostureKnobsHasABootGuard`; норма (сервис обязан нести стража и
звать его) — строка корпуса.

## sec-posture-gate-live-process-incident (класс D — инцидент-довод к строкам `sec-chart-config-checksum`/`sec-gate-reads-process-and-db`/`sec-ready-is-not-posture`/`sec-gate-proven-on-reproduced-defect`)

Ложный зелёный 2026-07-25: `make dev-prod-up` вышел с кодом 0 и напечатал
«production-posture stand is UP and READY», пока один сервис на этом же стенде работал
в dev-посадке с незашифрованным соединением к БД — видно из `pg_stat_ssl`, но не гейту.
Механика: ручки приходили через `envFrom: configMapRef` (читаются один раз при старте),
правка ConfigMap не меняет шаблон пода ⇒ под не перекатывается ⇒ boot-guard не сработал,
потому что старта не было. Молчали оба гейта: `assert-rollout-ready` видел Ready-под,
`assert-production-posture` читал ConfigMap вместо процесса, `envFrom` был ему невидим.

## sec-posture-regression-assertions — код отказа и держатель выправлены 2026-09-23 (класс D — замер)

Было «anonymous⇒403, forged HS256⇒403», держатель — только `assert-production-posture.sh`.
Замер @kacho 1d42a6728bf: край отвечает `Unauthenticated` (HTTP 401) и без Bearer
(`gateway/internal/middleware/auth.go:474`), и на HS256 в production (шапка того же файла,
:12-13); строк `anonymous`, `HS256`, `403` в скрипте нет — он держит `pg_stat_ssl` (раздел B).
Утверждение края — newman (`testing-newman.md#qa-access`, решение владельца 2026-09-23).
Держатель края — не долг (замер 2026-09-23 @kacho 1d42a6728bf): `gateway/tests/newman/cases/authn_edge.py`,
`IBT-10-ANONYMOUS-REJECTED` (:272) и `IBT-10-HS256-FORGED-REJECTED` (:320), утверждение `eql(401)` (:186);
оба id в `collections/authn_edge.postman_collection.json`; гонит их шаг «newman — суиты шарда, строго
по одной (+ live-отчёт)» (`e2e-newman.yml:825-834`, `newman-shard-run.sh`), судит шаг «гейт — newman
зелёный (api-gateway)» (`:910-915`, `assert-suites-green.sh`), шард по `deploy/e2e-shards.json`.

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**sec-posture-regression-assertions** — прежняя редакция:

sec-posture-regression-assertions · утверждать pg_stat_ssl=true на всех PG; на крае anonymous⇒401, forged HS256⇒401 (не 200) — newman, testing-newman.md#qa-access · deploy/scripts/assert-production-posture.sh (pg_stat_ssl); край — gateway/tests/newman/cases/authn_edge.py (IBT-10-ANONYMOUS-REJECTED, IBT-10-HS256-FORGED-REJECTED) · red: зелёный без этих трёх утверждений

(второй проход того же сжатия)

**sec-posture-regression-assertions** — прежняя редакция:

sec-posture-regression-assertions · утверждать pg_stat_ssl=true на всех PG; на крае anonymous ⇒ 401, forged HS256 ⇒ 401 (не 200) — newman, testing-newman.md#qa-access · deploy/scripts/assert-production-posture.sh (pg_stat_ssl); край — gateway/tests/newman/cases/authn_edge.py (IBT-10-ANONYMOUS-REJECTED, IBT-10-HS256-FORGED-REJECTED) · red: зелёный без этих трёх утверждений

(второй проход того же сжатия)

**абзац** — прежняя редакция:

## Production-mode — ОБЯЗАТЕЛЕН ВЕЗДЕ, включая dev/локальный стенд (выведено из production-mode валидации 2026-07-21)

**sec-internal-trusted-assumption-banned** — прежняя редакция:

sec-internal-trusted-assumption-banned · не считать internal-периметр доверенным: «internal = trusted, mTLS достаточно» — запрещённое допущение (defense-in-depth против lateral movement) · ЗАВЕСТИ · red: код снимает Check на internal, ссылаясь на «доверенный периметр»
