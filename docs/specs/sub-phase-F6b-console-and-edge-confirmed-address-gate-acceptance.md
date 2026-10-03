<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# Sub-phase F6b (консоль и край: дальше входа — только с подтверждённым адресом почты) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью
> (`.claude/rules/change-graph.md` §2 «Вердикт привязан к ОТПЕЧАТКУ, а не к документу»)
> **История review:** только дописывается; прежние строки не редактируются
> — редакция 1 · 2026-09-27 · кругов ревью не было, вердикта нет
> — круг 1 · 2026-09-27 · ⛔ CHANGES_REQUESTED · редакция 1, отпечаток
> `0bfa670190d3f52eedf1dcf4dcd821891e6d38a2068882e2551dbc8cb4eb3361` · блокирующих 3
> (B1-1 SCOPE, B1-2 COVERAGE, B1-3 COVERAGE) · запись
> `docs/specs/reviews/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance/0bfa670190d3f52eedf1dcf4dcd821891e6d38a2068882e2551dbc8cb4eb3361.yaml`
> — редакция 2 · 2026-09-27 · к кругу 2, вердикта на неё нет; что изменилось и почему — §8
> — круг 2 · 2026-09-27 · ⛔ CHANGES_REQUESTED · редакция 2, отпечаток
> `184fa2831ebd238b975787f727702f70631e329962bb838f0ff61016c63fb62f` · блокирующих 3
> (B2-1 PRODUCER, B2-2 FORMAT, B2-3 COVERAGE) · запись
> `docs/specs/reviews/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance/184fa2831ebd238b975787f727702f70631e329962bb838f0ff61016c63fb62f.yaml`
> — редакция 3 · 2026-09-27 · к кругу 3, вердикта на неё нет; что изменилось и почему — §8
> — круг 3 · 2026-09-27 · ✅ APPROVED · редакция 3, отпечаток
> `49bb29defe3a9442d813a6e09d8005bc1dce9c13aa6a7a98ad68e6e139aa76c3` · блокирующих 0, важных 4
> (I3-1 … I3-4) · запись
> `docs/specs/reviews/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance/49bb29defe3a9442d813a6e09d8005bc1dce9c13aa6a7a98ad68e6e139aa76c3.yaml`;
> событие полномочия на этот отпечаток — комментарий `pointpu` в `kacho#2898`, 2026-09-27T18:30:57Z
> — редакция 4 · 2026-09-28 · возврат в приёмку по `kacho#2901` (человек фикстуры наборов и стенда),
> к кругу 4, вердикта на неё нет; одобрение отпечатка `49bb29de…` на неё не переносится; что
> изменилось и почему — §8
> — круг 4 · 2026-09-28 · ⛔ CHANGES_REQUESTED · редакция 4, отпечаток
> `ab019574a5bccf2b20dc23ec525dcc40e6c60d34dff32f3592d66d7b83e30038` · блокирующих 2
> (B4-1 PRODUCER, B4-2 COVERAGE), важных 5 (I4-1 … I4-5) · запись
> `docs/specs/reviews/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance/ab019574a5bccf2b20dc23ec525dcc40e6c60d34dff32f3592d66d7b83e30038.yaml`
> — редакция 5 · 2026-09-28 · к кругу 5, вердикта на неё нет; одобрение отпечатка `49bb29de…` на неё
> не переносится; что изменилось и почему — §8
> — круг 5 · 2026-09-28 · ✅ APPROVED · редакция 5, отпечаток
> `ce81e18aea14a35832a31c768e7f35ec2064f757834418aca93f91738c6ee04a` · блокирующих 0, важных 2
> (I5-1, I5-2 — отданы полосе S4) · запись
> `docs/specs/reviews/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance/ce81e18aea14a35832a31c768e7f35ec2064f757834418aca93f91738c6ee04a.yaml`;
> событие полномочия на этот отпечаток — комментарий `pointpu` в `kacho#2898`, 2026-09-28T16:36:28Z
> — редакция 6 · 2026-09-29 · по гейту цитат `make`, к кругу 6, вердикта на неё нет; одобрение
> отпечатка `ce81e18a…` на неё не переносится; что изменилось и почему — §8
> **Дата:** 2026-09-29
> **Эпик/issue:** `PRO-Robotech/kacho#2898` (волна `#2797`, эпик `#1266`); сторона службы —
> `PRO-Robotech/kaname#456`. Задачи стадий: S1 (край) — `PRO-Robotech/kacho#2900`, S2 (консоль) —
> `PRO-Robotech/kacho#2898`, S3 (набор консоли) — консольная часть `PRO-Robotech/kacho#2901`,
> S4 (посевы наборов newman и стенда) — часть `PRO-Robotech/kacho#2901` о наборах и стенде

- **Дом документа — воркспейс `docs/specs/`, дом приёмки консоли той же линии (F8, §3.3).** Предмет
  кросс-доменный: консоль и край живут в `PRO-Robotech/kacho`, правило о подтверждённости адреса и
  глагол подтверждения — в `PRO-Robotech/kaname`. В дереве платформы своего дома у приёмок нет:
  ведомость `docs/acceptance-ledger.yaml` платформы называет воркспейс их домом прямо
  (`.claude/rules/polyrepo.md` note «У приёмки домов ДВА, и это решение, а не дрейф»).
- **Ревизии измерения — по дому, без дома половина команд ниже даёт пустоту:** платформа
  `PRO-Robotech/kacho@499ad3085fd` для §1.1–§1.10 и `@b7608fe9750` — голова ветки волны `2797` на день
  редакций 4 и 5 (`git ls-remote origin refs/heads/2797` → `b7608fe9750266f5…`) — для §1.11 и §1.13–§1.16 (§1.11 перепрогоняет на ней предикаты §1.1–§1.8); служба
  `PRO-Robotech/kaname@c083ad5bbfa` для §1.4, §1.8, §1.10 и `@c8559057b` — голова ветки волны `366`
  (`git ls-remote origin refs/heads/366` → `c8559057b48e…`) — для §1.12, §1.15 и §1.16; фундамент —
  `corelib v1.10.0-rc.2` (зависимость службы).
- **Приёмка службы — источник решений о глаголе, письме, коде и предъявлении удостоверений.** Это
  `PRO-Robotech/kaname:docs/engineering/acceptance/access-beyond-login-needs-a-verified-address.md`,
  **редакция 3**, отпечаток `f2d1fe852333af5412591a7ef2740d651086c408715e2083f47d3d075a755853`
  (1705 строк), коммит `fb8189dad`; тот же отпечаток даёт `git show origin/366:<путь> | sha256sum`.
  Её круг 3 — APPROVED, одобрение выпущено (запись
  `docs/specs/reviews/access-beyond-login-needs-a-verified-address/f2d1fe85….yaml` в ветке `366`:
  `effective_approval.issued: true`, `ban1_lifted: true`). Её редакции 1 (`32dd2b23…`) и 2
  (`5fb3e84e…`) вернулись кругами 1 и 2 и этим документом больше не читаются. Её предмет вобрал
  прежнюю приёмку подтверждения адреса (Ф6): черновик Ф6 дальше не ведётся (§0.1 приёмки службы).
  Ниже она называется **«приёмка службы»**, её решения — «Р<N> службы», сценарии — `EV-<N>`.
- **Формат:** Given-When-Then, только markdown. Кода здесь нет по построению.
- **Публичный репозиторий:** стволы платформы и службы публичны; документ описывает функцию и
  решение владельца и написан так, чтобы выдерживать публикацию (`.claude/rules/security-disclosure.md`
  §«Публичные артефакты»).

---

## §0 Обзор

**Решение владельца 2026-09-27, дословно:**

> «Делай механику максимально безопасную где вход дальше экрана регистрации или логина доступен
> только после подтверждения почты»

Для консоли и края это значит одно. Учётная запись с неподтверждённым адресом почты видит экраны
регистрации и входа, экран «подтвердите почту» с вводом кода из письма и отправкой нового письма, и
выход — и ничего больше. Ни одна полоса края, выставляющая личность человека, не доводит такую
учётную запись ни до одной службы за пределами этих действий. После подтверждения — обычная консоль
и обычный доступ, без второго ввода пароля.

Правило держится **на каждой полосе личности человека**, а не на одной (§1.8, Р16): полоса сессии —
краем (S1 этой приёмки); полосы базового секрета и токена доступа — службой на выдаче и на
предъявлении (Р5, Р5а и строка Р4в службы), край исполняет её ответ; ещё две полосы личности
человека не выставляют вовсе (предикат §1.8). Консоль (S2) показывает человеку разрешённое и
следующий шаг; набор проб (S3) заводит подтверждённого человека тем же путём, что проходит человек.
Посевы наборов newman и стенда (S4) — тоже: регистрация через край, письмо регистрации у приёмника
писем стенда, код глаголом подтверждения под сессией регистрации; людей наборов заводит только
посев, и случаи наборов берут их у него (Р17). Пути, помечающего адрес
подтверждённым в обход письма, нет ни в одной посадке — ни глаголом, ни ручкой, ни посевом; в
боевой посадке приёмника стенда нет, и его отсутствие обхода не открывает (Р18).
Этот документ — приёмка всех четырёх стадий, и задачам стадий второй приёмки о том же рубеже не
нужно: два документа об одном рубеже расходятся молча — так разошлись до редакции 3 Р3 этого
документа и строка края в §3.2 приёмки службы (§8).

**Решение Р14 приёмки Ф6 этим решением ОТМЕНЕНО** — что именно отменено и что уцелело, §2 Р1.

---

## §1 Перепись производителей — составлена ДО сценариев

Каждое «Тогда» ниже опирается на производителя. Перепись называет, что в дереве уже печатает нужный
ответ, что его не печатает и чем это получено. Дом каждой команды назван строкой над ней; у
каждого отрицательного предиката прогнан контроль в обратную сторону — иначе «ноль» неотличим от
«ноль прочитанного» (`measurement-discipline`).

### §1.1 Край получает подтверждённость адреса на каждом предъявлении сессии — и полоса её не читает

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — строка не-тестового Go края с именем поля
git grep -n 'EmailVerified' 499ad3085fd -- gateway ':!*_test.go'
#   → 4 строки в 3 файлах: адаптер ответа службы (internal/clients/session_revocations_client.go:92),
#     поле порта сессии и его комментарий (internal/middleware/human_session.go:58,59),
#     ответ «кто я» (internal/middleware/session_identity_handler.go:191)
git grep -n 'sess.AssuranceLevel\|sess.EmailVerified' 499ad3085fd -- gateway ':!*_test.go'
#   → полоса сессии читает из того же ответа УРОВЕНЬ (own_session_assurance.go, три строки),
#     а подтверждённость читает только «кто я» (session_identity_handler.go:191)
```

Контроль в обратную сторону — тот же предикат находит чтение поля ответа там, где оно есть: уровень
уверенности полоса читает и по нему решает (пол ступенчатой аутентификации). Подтверждённость
приходит тем же ответом, и решения по ней нет нигде.

### §1.2 Носитель сессии читают ДВЕ точки края, обе на HTTP-поверхности

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — вхождение предиката носителя
git grep -n 'ourSessionCarrierOf(' 499ad3085fd -- gateway ':!*_test.go' | wc -l
#   → 3: объявление (session_carrier_readers.go) и два вызова —
#        полоса сессии (auth_own_session.go) и «кто я» (session_identity_handler.go)
git show 499ad3085fd:gateway/cmd/api-gateway/main.go | grep -c 'authInterceptor.HTTP(inner)'
#   → 1: полоса оборачивает ВЕСЬ HTTP-обработчик края — «кто я», глаголы формы,
#        выход, поток изменений и пересылку к службам
```

Точка, через которую проходит **каждый** HTTP-путь с нашим носителем сессии, одна — полоса сессии.
Это верно для **носителя сессии**, и только для него: прочие полосы личности — §1.8.

### §1.3 Путей без решения по каталогу — четыре плюс глаголы формы; глаголов подтверждения среди них нет

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:gateway/internal/middleware/authz_util.go | grep -n 'case "/healthz"'
#   → 267: "/healthz", "/readyz", "/oauth/logout", "/iam/v1/auth/me" — и IsLoginLanePath
git show 499ad3085fd:gateway/internal/middleware/login_lane_paths.go | grep -c '^	LoginLanePath[A-Za-z]* *= "'   # → 13
git show 499ad3085fd:gateway/internal/middleware/login_lane_paths.go | grep -ci 'verif'                            # → 0
# КОНТРОЛЬ: тот же образец находит соседнюю полосу, которая объявлена
git show 499ad3085fd:gateway/internal/middleware/login_lane_paths.go | grep -ci 'recovery'                         # → 4
```

Решение по каталогу прав тоже стоит не на каждом пути:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — запись каталога
git show 499ad3085fd:gateway/internal/middleware/embed/permission_catalog.json | grep -c '"permission":'                        # → 343
git show 499ad3085fd:gateway/internal/middleware/embed/permission_catalog.json | grep -c '"permission": "\\u003cexempt\\u003e"'  # → 23
```

Освобождения законны и названы правилом (`.claude/rules/security.md` §«AuthN+AuthZ ВЕЗДЕ»);
следствие для этого предмета одно: правило «никакого доступа до подтверждения» выражается не
ответом о праве на пути, а **допуском принципала** — на полосе сессии краем (Р4), у службы — под
каждым вопросом о праве и на её слушателе (Р4 службы).

### §1.4 Служба: глаголов подтверждения в дереве нет, писателя отметки никто не зовёт, чтение сессии берёт отметку живой

```sh
# ДОМ: PRO-Robotech/kaname @ c083ad5bbfa · единица — объявленный путь слушателя формы
git show c083ad5bbfa:internal/handler/loginlanehttp/handler.go | grep -c 'h.mux.HandleFunc'                        # → 13
git show c083ad5bbfa:internal/handler/loginlanehttp/handler.go | grep 'Path[A-Za-z]* *= ' | grep -ci verif        # → 0
git show c083ad5bbfa:internal/handler/loginlanehttp/handler.go | grep 'Path[A-Za-z]* *= ' | grep -ci recovery     # → 2 (контроль)
# единица — вхождение имени в не-тестовом Go
git grep -n 'MarkEmailVerified(' c083ad5bbfa -- '*.go' ':!*_test.go'
#   → 2, оба не вызов: объявление порта (loginmethod/store.go:57) и реализация (login_method_repo.go:240)
git grep -n 'EmailVerification(' c083ad5bbfa -- '*.go' ':!*_test.go'
#   → 3, третье — живой вызов (humansession/login.go:570): предикат вызов находить умеет
git grep -n 'email_verified_at\|emailVerAt != nil' c083ad5bbfa -- internal/repo/kaname/pg/human_session_repo.go
#   → :59 колонка читается в том же запросе, что сессия; :115 признак выставляется из неё
```

Три вывода, на которые опираются сценарии: (1) глагола подтверждения и письма у службы на этой
ревизии **нет** — их заводит приёмка службы (её Р6–Р9, производители П1–П3, П12), и на голове волны
`366` они есть (§1.12); доставку до приёмника стенда — две величины почтовой полосы службы в
чарте зонта, которые заводит S4 (§1.16); (2) отметок подтверждённости на этой
ревизии **ноль по построению** — писателя не зовёт никто, а обратного заполнения не будет (Р13
службы); на голове волны писатель зовётся одним местом — исходом глагола подтверждения (§1.12); (3) ответ службы о сессии берёт отметку
**при каждом вопросе**, а край ответа не кэширует (шапка `gateway/internal/middleware/human_session.go`,
«Кэша НЕТ»). Подтверждение при этом **меняет носитель** той же сессии (Р10 службы), поэтому
«без нового входа» значит «новым носителем из ответа подтверждения, без второго ввода пароля»
(F6b-10).

### §1.5 Консоль: `/verification` отвечает «такого адреса здесь нет», а вход и регистрация уводят на адрес возврата

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:ui-future/shared/src/pages/auth/ceremony-addresses.ts | grep -n '"/verification": { kind'   # → 53: not-served
git grep -n 'leave(returnTo)' 499ad3085fd -- ui-future/shared/src/pages/auth/LoginPage.tsx \
                                             ui-future/shared/src/pages/auth/RegistrationPage.tsx
#   → 3: вход — при живой сессии (:80) и после отправки (:111); регистрация — после отправки (:52)
git grep -n 'safeInternalPath(' 499ad3085fd -- ui-future/shared/src ':!*.test.*'
#   → 3: объявление (lib/redirect.ts:22), разбор двух источников (:54) и ЕДИНСТВЕННЫЙ читатель
#     адреса возврата экранов церемонии — useReturnTo (pages/auth/use-return-to.ts:22)
git grep -n 'emailVerified' 499ad3085fd -- ui-future ':!*.test.*' ':!ui-future/e2e'
#   → читатель ответа один (shared/src/api/login-lane.ts:552); показ — два места
#     (host AccountPanel, AccountSettingsPage); РЕШЕНИЙ по полю — ноль
git show 499ad3085fd:ui-future/shared/src/contexts/AuthContext.tsx | grep -n 'Promise.all'
#   → 87: вопрос о сессии и `GET /iam/v1/me` уходят ВМЕСТЕ, не дожидаясь ответа о сессии
git show 499ad3085fd:ui-future/host/src/components/molecules/HostBreadcrumb/HostBreadcrumb.tsx | grep -n 'listAccounts({'
#   → 113: каркас при монтировании обращается к `/iam/v1/accounts`
```

Решение консоли на отказ платформы одно и живёт в `shared/src/api/refusal-action.ts`: действий в
закрытом перечне **пять** (`fresh-form-token` · `step-up-freshness` · `step-up-floor` · `sign-in` ·
`show`), решение — по `ErrorInfo.reason`, а не по домену и не по прозе; читателей с поверхностью
`platform` — **два** (`host/src/utils/api-client.ts:56`, `shared/src/api/client.ts:139`;
`git grep -n '"platform",\?$' 499ad3085fd -- ui-future/host/src ui-future/shared/src ':!*.test.*'`).
Срок `Retry-After` консоль уже читает одним местом и своего не выдумывает
(`shared/src/api/login-lane.ts:208–214`).

### §1.6 Набор браузерных проб заводит человека регистрацией — и ни одна проба не подтверждает адрес

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — файл пробы
git ls-tree -r --name-only 499ad3085fd -- ui-future/e2e/specs | grep -c '\.spec\.ts$'        # → 27
git grep -l -E 'registerAndSignIn\(|tenantWithProject\(|[^A-Za-z]register\(page' 499ad3085fd \
  -- ui-future/e2e/specs ':!ui-future/e2e/specs/fixtures.ts' | wc -l                        # → 24
git grep -n 'seedHuman(' 499ad3085fd -- ui-future/e2e/specs ':!ui-future/e2e/specs/ceremony-seed.ts' | wc -l   # → 3 (в двух файлах)
# КОНТРОЛЬ: предикат находит заведомого потребителя
git grep -c -E 'registerAndSignIn\(|tenantWithProject\(|[^A-Za-z]register\(page' 499ad3085fd -- ui-future/e2e/specs/modules.spec.ts  # → 2
```

**24 из 27** файлов проб стоят на фикстуре регистрации. В день, когда край начнёт отвергать
неподтверждённую сессию, все они упадут **одним текстом** по причине, не относящейся к их предмету
(`.claude/rules/e2e-flow.md` §11 «Каскад от общей фикстуры»). Поэтому фикстура — часть этой
под-фазы (S3), а не соседняя уборка. Тот же каскад есть на уровне Go: дублёры порта сессии в пробах
края построены без признака (DoD п. 2).

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — строка пробы края
git grep -n 'HumanSession{' 499ad3085fd -- 'gateway/*_test.go' | wc -l      # → 29 (в 11 файлах)
git grep -n 'EmailVerified:' 499ad3085fd -- 'gateway/*_test.go' | wc -l     # → 6 (в 6 файлах)
```

### §1.7 Приёмник писем на стенде есть; прогон консоли его не читает

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git ls-tree -r --name-only 499ad3085fd -- deploy/helm/umbrella/templates/mail-receiver.yaml   # → 1: приёмник с чтением доставленного по HTTP
git show 499ad3085fd:.github/workflows/console-e2e.yml | grep -ci 'mail'                      # → 0
# КОНТРОЛЬ: тот же образец по файлу, где приёмник объявлен, находит его
git show 499ad3085fd:deploy/helm/umbrella/templates/mail-receiver.yaml | grep -ci 'mail'      # → 35
```

Приёмник поднимается в ядре каждого шарда (`deploy/E2E-SHARDS.md` §4.1). Шага, дающего прогону
консоли прочитать письмо, нет — это **условие, которое заводит S3** (F6b-34).

### §1.8 Полосы края, выставляющие личность: пять, и у каждой назван держатель правила

Правило владельца — об **учётной записи**, поэтому перепись идёт по полосам, а не по носителю
сессии. Единица — полоса аутентификации края, то есть место, где из предъявленного удостоверения
возникает принципал.

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — вызов полосы в обработчике HTTP края
git show 499ad3085fd:gateway/internal/middleware/auth.go | grep -n -E 'a\.try[A-Za-z]+\(w, r'
#   → 4: :991 сессия · :1001 базовый секрет · :1004 предъявитель · :1007 общий ключ подписи
# нативная поверхность — та же цепочка, отдельными входами
git show 499ad3085fd:gateway/cmd/api-gateway/main.go | grep -n 'authInterceptor\.\(Unary\|Stream\)()'
#   → 2: :940, :945
git show 499ad3085fd:gateway/internal/middleware/auth.go \
  | grep -n -E 'principalFromVerifiedPeer\(a\.mtlsDomain|bearer := extractBearer\(ctx\)|a\.basicLane\.Owns\(bearer\)'
#   → 3: :407 сертификат пира · :414 предъявитель · :443 базовый секрет
# КОНТРОЛЬ: перечень полос HTTP держит гейт самого края — полоса, провязанная и не названная, — находка
git grep -n 'func TestHTTPHeaderNamesEveryIdentityLaneItWires' 499ad3085fd -- gateway          # → 1
```

Чью личность выставляет каждая полоса и где её отвергают:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:gateway/internal/middleware/auth.go | sed -n 771,790p | grep -c 'return "service_account"'
#   → 1: сертификат пира даёт ТОЛЬКО служебную учётную запись (прочие ветки — «не принципал»)
git show 499ad3085fd:gateway/internal/middleware/auth.go | grep -n 'pType = verifiedClaim(vt, "kaname_principal_type")'
#   → 730: вид принципала предъявителя берётся из утверждения токена — человек в нём возможен
git show 499ad3085fd:gateway/internal/middleware/auth.go | grep -n 'a.revocationCheck('
#   → 2: :516 нативная · :1163 HTTP — вопрос о живости токена на каждом предъявлении
#     (по HTTP — вне путей без записи каталога, §1.3; на нативной — на каждом методе)
```

Какой вопрос край задаёт о токене, выбирает **запись издателя**, которой проверена подпись, — не
настройка процесса и не адрес:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:gateway/internal/middleware/auth_revocation.go | grep -n 'if vt.ReadRevocation {'
#   → 195: токен, помеченный записью, спрашивается у НАШЕГО авторитета отзыва
git show 499ad3085fd:gateway/internal/config/tokenissuers.go | grep -n 'b.ReadRevocation = true'
#   → 247: пометку ставит запись нашего издателя (platformIssuer), и только она
git show 499ad3085fd:gateway/cmd/api-gateway/main.go \
  | grep -n -E 'WithRevocationCheck\(|NewIntrospectionCache\(|WithPlatformRevocationCheck\('
#   → :380 полоса ЗАПИСИ отзыва (по идентификатору токена) — для прочих принятых записей;
#     :405, :418 полоса НАШЕГО авторитета — сверка через кэш края
git grep -n 'revocationUrl:' 499ad3085fd -- deploy/helm
#   → 8 строк в 4 профилях зонта, каждая — …:9097/internal/tokens/introspect
git show 499ad3085fd:gateway/internal/clients/session_revocations_client.go | grep -n 'a.client.IsRevoked('
#   → 152: вопрос полосы записи (`InternalSessionRevocationsService.IsRevoked`, только `token_jti`)
```

На стендах токен человека к полосе записи не приходит — принят ровно один издатель, наш:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — строка объявления в профиле зонта
git grep -n -E '^\s+(issuers|platformIssuer):' 499ad3085fd -- 'deploy/helm/umbrella/values*.yaml'
#   → 16 строк в 4 профилях (dev, dev-prod, prod, fe3455-prod); в каждом — две пары (край и
#     реестр), и каждое `issuers` — один элемент, равный `platformIssuer` того же блока
git show 499ad3085fd:gateway/deploy/values.yaml | grep -n -E '^  (issuers|platformIssuer): ""'
#   → 393, 406: умолчание чарта края пусто
git show 499ad3085fd:gateway/internal/config/tokenissuers.go | grep -n 'declares no issuer element'
#   → 205: пустой перечень принятых издателей — отказ старта, а не «принимаем любого»
```

Окно, в котором край держит вердикт сверки, — **5 с**, и оно названо здесь потому, что оно же
окно правила на этой полосе:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:gateway/internal/config/config.go | grep -n 'KACHO_INTROSPECTION_CACHE_TTL_SECONDS'
#   → 538: ручка окна кэша сверки, умолчание загрузчика 5
git grep -n 'INTROSPECTION_CACHE' 499ad3085fd -- deploy gateway/deploy | wc -l              # → 0
# КОНТРОЛЬ: тот же предикат по соседней ручке той же полосы находит её — эмиссию в чарте
# края (templates/deployment.yaml) и пробу инъекции рядом с ним
git grep -n 'KACHO_API_GATEWAY_PLATFORM_TOKEN_REVOCATION_URL' 499ad3085fd -- deploy gateway/deploy | wc -l   # → 6
git show 499ad3085fd:gateway/internal/middleware/introspection_cache.go | grep -n -E 'Negative caching|if untilExp < ttl'
#   → :18 кэшируется и «не действует»; :384 окно — меньшее из 5 с и остатка срока токена
```

Чарт края величину окна не задаёт, поэтому на каждом стенде оно — умолчание загрузчика: вердикт
сверки, и «действует», и «не действует», край держит не дольше **min(5 с, остаток срока токена)**.

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd
git show 499ad3085fd:gateway/internal/middleware/basic_credential_lane.go | grep -n 'l.authority.Resolve('
#   → 217: базовый секрет разрешает служба; положительный вердикт край держит окном полосы (5 с, :33)
git show 499ad3085fd:gateway/cmd/api-gateway/authz_validation.go | grep -n 'if cfg.DevSecretSet'
#   → 72: край с заданным общим ключом подписи отказывается стартовать под ЛЮБОЙ пометкой окружения
```

И у службы — где решаются выдача и предъявление её удостоверений:

```sh
# ДОМ: PRO-Robotech/kaname @ c083ad5bbfa · единица — не-тестовый файл, импортирующий правило
git grep -l 'internal/revocationpolicy"' c083ad5bbfa -- '*.go' ':!*_test.go' | wc -l
#   → 6: правило ВЫДАЧИ — токен-эндпоинт, сборка ответа токена, три файла хука, полоса базового секрета
git grep -l 'internal/tokenrevocation"' c083ad5bbfa -- '*.go' ':!*_test.go' | wc -l
#   → 4: правило ПРЕДЪЯВЛЕНИЯ токена — сверка края (handler/tokenintrospecthttp), читатель
#     предъявленного на публичном слушателе (presentedcred), ответ об отзыве
#     (api/session_revocations), гейт одного читателя правила (internal/check)
git show c083ad5bbfa:internal/handler/tokenintrospecthttp/handler.go | grep -n 'IntrospectPath *='
#   → 57: `/internal/tokens/introspect` — тот самый адрес, что назван краю профилями (выше)
git grep -l 'internal/revocationpolicy"' c083ad5bbfa -- internal/handler/tokenintrospecthttp internal/presentedcred | wc -l
#   → 0: на поверхностях предъявления правило выдачи не спрашивается — поэтому Р5а службы
# ДОМ: corelib v1.10.0-rc.2 (зависимость службы, go.mod:8)
#   tokenpolicy/policy.go:146 — MaxTokenTTL = 30 * time.Minute: потолок срока любого токена доступа
```

Отсюда перепись и решение по каждой полосе — Р16.

### §1.9 Решения приёмки службы, на которые опирается эта редакция

Приёмка службы одобрена на редакции 3 (шапка); её решения здесь **не принимаются заново**, а
называются как производители. Правка любого из них её следующей редакцией — находка обеих, и эта
приёмка правится тем же кругом (§6 п. 1). Эта редакция сверена с редакцией 3 по каждому решению,
текстом, диффом `26758cccf..fb8189dad` (добавлено 268 строк, снято 40): изменены Р2 (строка обмена
кода и оборота токена обновления церемонии), Р4в (таблица тринадцати методов вне круга; в ней двери
базового секрета), Р5 (две строки полос церемонии и клетка `token-owner-unverified`), Р5а (третья
поверхность предъявления), Р11 п. 4 (состояние «приглашение снято и не повторено»), Р13 (семейства
выдачи церемонии) и первая строка её §3.2 (окно кэша решений края); добавлено Р5б. Глаголы
подтверждения, их тела и виды формы, значение отказа Р3, таблица отказов Р6, решения Р1, Р7–Р10,
Р12, Р14, Р15 и сценарии EV-01, EV-02, EV-20, EV-21, EV-23, EV-26, EV-36, EV-37, EV-39, EV-40,
EV-50, EV-65…EV-68, EV-73, EV-75, EV-76, на которые ссылается этот документ, **не менялись**:
снятые строки диффа их не касаются (в них — шапка и обзор, перепись правила выдачи, текст Р4в и
Р5, конец Р11 п. 4, §3.1 п. 3, строка края её §3.2, близнецы EV-60 и EV-62, счёт сценариев,
инварианты, DoD и порядок работ службы).

| решение службы (редакция 3) | что оно даёт здесь |
|---|---|
| Р2 — перечень доступного в положении подтверждения; в нём методы внутреннего слушателя, которые край зовёт от лица человека, — по таблице Р4в; предъявление нашего токена человека — «недействителен» (Р5а); церемония авторизации клиента — отказ протокола (Р5); обмен кода и оборот токена обновления церемонии — `400 invalid_grant` (Р5б) | тот же перечень, что Р5 и Р6 этой приёмки; восстановление доступа службой не закрыто (сессии не требует), край закрывает его только при предъявленном носителе неподтверждённой сессии (Р5); «кто я» и выход края на отвергаемые методы не опираются (§1.10); координаты церемонии край ретранслирует, и отвечает на них служба (Р5, §1.11) |
| Р3 — одно значение отказа на полосе формы и на обоих слушателях: `403` / `PERMISSION_DENIED` · `7` · `email address is not verified` · `EMAIL_NOT_VERIFIED`, домен отказов службы | значение отказа края Р3 и Р3а — **то же**; на нативной поверхности — его форма gRPC |
| Р4а — вопрос о праве неподтверждённого человека: `allowed = false`, `deny_reasons = ["email_not_verified"]` на любом объекте, до вычисления отношения (EV-50) | вход отказа Р3а края (F6b-45) |
| Р4в — круг края на внутреннем слушателе: `Revoke` о самом принципале доступен, прочие методы круга — отказ Р3; вне круга двери базового секрета `ResolveBasicCredential` и `CheckBasicCredentialLive` судит правило выдачи, причина `owner-unverified` (строка 483 редакции 3) | выход края доступен; методы, которые зовёт «кто я», в круг не входят (§1.10); перепрос живости базового секрета решён службой — этой строкой и её деревом (§1.9); сценарий перепроса — заказ §3.2 |
| Р5 — удостоверения человека токенов не получают: токен-эндпоинт — `401 {"error":"invalid_client"}`, клетка `owner-unverified` (EV-65); полоса базового секрета — `UNAUTHENTICATED`, `credential refused`, причина `owner-unverified`; авторизация церемонии — перенаправление с `error=access_denied`, без `code` (EV-67) | держатель Л2 на выдаче и на предъявлении, Л3 — на выдаче (Р16); исход обмена личного токена человека фикстуры, не прошедшего подтверждение (F6b-49); навигацию церемонии край ретранслирует (Р5) |
| Р5а — сверка `POST /internal/tokens/introspect` отвечает на наш токен человека с неподтверждённым адресом `200 {"active": false}` по **текущей** отметке; окно кэша у спрашивающего — его величина (EV-68) | держатель Л3 **на предъявлении** (Р16, F6b-35); окно края — 5 с (§1.8); реестр — второй спрашивающий (§3.2) |
| Р5б — обмен кода и оборот токена обновления церемонии (`POST /iam/v1/token`) о неподтверждённом владельце: `400 {"error":"invalid_grant"}`, пары нет, семейство сохранено; «спросить не смогли» — `503 {"error":"temporarily_unavailable"}` (EV-77, EV-78) | ответ службы на ретранслированную краем запись обмена (Р5); значения Р3 на ней край не произносит |
| Р6 — оба глагола подтверждения **под сессией человека**, адреса в теле нет; тела `{csrfToken}` и `{code, csrfToken}`; виды формы `verify-email` и `verify-email-confirm`; успех предъявления — `200` с `session.emailVerified: true` и **новым носителем**; отказы — таблица Р6, в том числе исход предъявления `400` · `9` · `invite is no longer valid; ask an account administrator to invite again` · `INVITE_NOT_VALID` | тела обращений консоли (Р6, Р9) и посевов (Р17); исходы экрана Р9, строка `INVITE_NOT_VALID` — F6b-44; оба глагола читают носитель, поэтому на крае `relayWhenUnanswered = false` (Р5) |
| Р7 — код: 10 знаков, срок, однократен, последний жив, предел попыток **на код** (пятое неподошедшее тратит код), привязан к человеку | отказа по частоте у предъявления нет: исход — `401` (Р9); код чужого человека — `401` (F6b-29) |
| Р8 — письмо несёт код, его срок и **адрес экрана подтверждения консоли; кода в адресе нет** | ссылки-предъявителя нет; экран — ввод кода руками (Р8, Р9); посев берёт код из тела письма (Р17) |
| Р9 — письмо регистрации ставится **той же транзакцией**, что заводит человека; интервал между письмами и суточное число, `429` / `8` с `Retry-After`; пять ручек без умолчаний | производитель первого письма и для консоли (Р15), и для посевов (Р17); вход письма не шлёт (EV-02); ни одна из пяти ручек рубеж не снимает (Р18) |
| Р10 — успешное предъявление: отметка, новый носитель, **прочие сессии человека сняты**; при негодном приглашении — отказ исхода целиком | «подтвердил в другом месте» — эта сессия снята (F6b-30); посев берёт новый носитель из ответа (Р17) |
| Р11 п. 4 — подтверждение при негодном (истёкшем или снятом) приглашении: отказ `INVITE_NOT_VALID`, код не применён и попытки не тратит, отметки нет; выход — повторное приглашение распорядителем (EV-73, EV-75, EV-76) | экран не уводит, не называет код неверным и не считает попытки; выход человека — «Выйти» (F6b-44) |
| Р11 п. 5 — путь хука поставщика (`UpsertFromIdentity`) нашей отметки не несёт и приглашение не активирует; читатель сессии поставщика на крае снят (`kacho#2792`) | человек фикстуры хуком поставщика не заводится (Р17) |
| Р13 — посадка в записи людей не пишет ничего; «обходного пути у рубежа нет намеренно» | Р18: обхода нет ни в одной посадке, и отсутствие приёмника стенда его не открывает |
| Р15 — уже подтверждённый на глаголах подтверждения — `400` / `9` `EMAIL_ALREADY_VERIFIED` | ветвь «уже подтверждён» (F6b-42) |
| §3.2, строка о фикстурах сквозных наборов и посеве стенда — носитель `kacho#2901`, «глаголом, с кодом из приёмника писем стенда» | стадия S4 этого документа (Р17, F6b-46 … F6b-56) |

**Расхождения со строками приёмки службы о крае — названы, а не замолчаны.** Край — предмет этого
документа (S1, `kacho#2900`), и строка §3.2 приёмки службы описывает его как потребителя; где она
расходится с деревом края или с этим документом, правка — её строкой (§6 п. 1):

1. «край читает `Paths()` службы пином» — у края **своё** объявление записей ретрансляции, и проба
   сверяет его записи формы с перечнем службы дословно, а не читает модуль службы (шапка
   `gateway/internal/middleware/login_lane_paths.go` и `loginLaneWant` в его пробе: «перечень выписан
   здесь ДОСЛОВНО, а не прочитан из модуля службы»). Так остаётся и здесь: сверка 15 записей формы с
   15 путями слушателя формы службы — F6b-11; три записи церемонии ретранслируются на другой
   слушатель службы и в эту сверку не входят (§1.11);
2. «отказ Р3 на путях платформы … всё, кроме «кто я» и путей полосы формы» — перечень прохода края
   точнее, Р5: он пропускает ещё выход `/oauth/logout`, пробы здоровья и три координаты церемонии и
   **строже** на девяти глаголах формы, которые край отвергает сам, не дожидаясь службы;
3. отображение `deny_reasons` в `reason` — **совпадает** с этим документом с редакции 3 (Р3а); окно
   кэша решений края, названное её строкой, названо и здесь (Р3а, I3-1).

**Заказы §3.2 редакции 3 этого документа — у производителей в дереве службы.** Текстом приёмки
службы названо одно из трёх; два значения несёт только дерево, и держит их на нашей стороне стенд:

```sh
# ДОМ: PRO-Robotech/kaname · единица — строка документа
D=docs/engineering/acceptance/access-beyond-login-needs-a-verified-address.md
git show fb8189dad:$D | grep -c -F '/verification'               # → 0: значения адреса экрана в тексте нет
git show fb8189dad:$D | grep -n -F '| `POST /iam/v1/auth/verify-email` | `{ "csrfToken" }`'
#   → 628: успех — `200`, тело `{}`, без `Set-Cookie`; заголовка срока в строке нет
git show fb8189dad:$D | grep -c -F 'CheckBasicCredentialLive'    # → 1: строка 483, решение Р4в
# КОНТРОЛЬ: тот же образец находит решение, которое редакция 3 несёт
git show fb8189dad:$D | grep -c -F 'INVITE_NOT_VALID'            # → 8
# ДОМ: PRO-Robotech/kaname @ c8559057b (голова ветки волны 366) · единица — строка не-тестового Go
git show c8559057b:internal/clients/invite_mail.go | grep -n -E 'VerificationScreenPath = "/verification"|Path: VerificationScreenPath'
#   → 93, 622: адрес экрана — происхождение консоли и путь `/verification`, без параметров и фрагмента
git show c8559057b:internal/handler/loginlanehttp/handler.go | grep -n 'w.Header().Set("Retry-After"'
#   → 915 — успех запроса письма; 1010 — отказ по частоте
git show c8559057b:internal/repo/kaname/pg/basic_credential_repo.go | grep -n 'return r.ownerAdmission(qctx, owner)'
#   → 355: перепрос живости базового секрета судит правило выдачи о владельце
```

Отсюда: адрес экрана в письме и `Retry-After` на успехе держат F6b-28 и F6b-19 на стенде — значение
у службы есть в дереве, а не в приёмке, и расхождение дерева службы с этими сценариями — находка
обеих; перепрос живости решён строкой Р4в службы и её деревом, а сценария на него у службы нет —
заказ сценария остаётся (§3.2).

### §1.10 «Кто я» и выход края на методы, которые служба теперь отвергает, не опираются

Р2 службы получила строку о методах внутреннего слушателя, которые край зовёт от лица человека:
из девятнадцати доступно одно — снятие собственного удостоверения. Перечень прохода края (Р5)
держится, только если ни «кто я», ни выход не зовут ни одного из остальных восемнадцати:

```sh
# ДОМ: PRO-Robotech/kacho @ 499ad3085fd · единица — вызов порта службы в обработчике
git show 499ad3085fd:gateway/internal/middleware/session_identity_handler.go \
  | grep -n -E 'ResolveHumanSession\(|SessionCutoffOf\(|IsSystemAdmin\('
#   → 4: :57 объявление порта и три вызова — :157 разбор сессии · :181 вопрос об
#     администраторе · :209 отсечка
git grep -n -E '\.(Resolve|SessionCutoffOf)\(ctx' 499ad3085fd -- gateway/internal/clients ':!*_test.go'
#   → session_revocations_client.go:74 `InternalHumanSessionService.Resolve`, :176 `SessionCutoffOf`
git show 499ad3085fd:gateway/internal/clients/iam_subject_client.go | grep -n -E 'c.stub.Check\(|NewInternalIAMServiceClient\(conn\)'
#   → :82, :153: вопрос об администраторе — `InternalIAMService.Check`
git show 499ad3085fd:gateway/internal/handler/logout_handler.go | grep -n -E 'UserId: *caller.Subject|h.revocations.Revoke\('
#   → :176, :181: выход `/oauth/logout` зовёт `Revoke` о САМОМ вызывающем
# ДОМ: PRO-Robotech/kaname @ c083ad5bbfa · единица — строка метода в перечне круга
git show c083ad5bbfa:internal/authzguard/caller_policy.go \
  | awk '/^func GatewayFrontedInternalRPCs/,/^}/' > circle.txt
grep -c '"/kaname' circle.txt                                                              # → 19
grep -c -E 'InternalHumanSessionService|SessionCutoffOf|InternalIAMService/Check"' circle.txt # → 0
# КОНТРОЛЬ: тот же образец находит метод той же службы, который в круге есть
grep -c 'InternalIAMService/ForceLogout"' circle.txt                                       # → 1
grep -c 'InternalSessionRevocationsService/Revoke"' circle.txt                             # → 1
```

Вывод: «кто я» зовёт три метода вне круга (разбор сессии, отсечка, вопрос об администраторе — его
для неподтверждённой сессии Р10 не задаёт вовсе); выход зовёт единственный метод круга, доступный в
положении подтверждения, — `Revoke` о себе (Р4в службы). Ни одна строка перечня Р5 не опирается на
метод, который служба отвергнет. На головах волн (`b7608fe9750`, `c8559057b`) те же предикаты дают
те же 4, 2 и 19.

### §1.11 Голова волны края: предикаты §1.1–§1.8 перепрогнаны, в объявлении — три записи церемонии

Волна `2797` ушла вперёд от `499ad3085fd`, и числа §1.1–§1.8 перепрогнаны на её голове тем же
предикатом:

```sh
# ДОМ: PRO-Robotech/kacho · единица — та же, что в разделе предиката
for R in 499ad3085fd b7608fe9750; do
  git grep -n 'EmailVerified' $R -- gateway ':!*_test.go' | wc -l                                  # §1.1: 4 → 4
  git grep -n 'ourSessionCarrierOf(' $R -- gateway ':!*_test.go' | wc -l                           # §1.2: 3 → 3
  git show $R:gateway/internal/middleware/login_lane_paths.go | grep -c '^	LoginLanePath[A-Za-z]* *= "'   # §1.3: 13 → 13
  git show $R:gateway/internal/middleware/login_lane_paths.go | grep -c '^	{Verb: "'                      # записей: 13 → 16
  git show $R:gateway/internal/middleware/login_lane_paths.go | grep -c '^	CeremonyPath[A-Za-z]* *= "'    # 0 → 3
  git show $R:gateway/internal/middleware/embed/permission_catalog.json | grep -c '"permission":'   # §1.3: 343 → 349
  git show $R:gateway/internal/middleware/embed/permission_catalog.json | grep -c '"permission": "\\u003cexempt\\u003e"'  # 23 → 25
  git show $R:gateway/internal/middleware/auth.go | grep -c -E 'a\.try[A-Za-z]+\(w, r'              # §1.8: 4 → 4
  git show $R:gateway/internal/config/tokenissuers.go | grep -c 'b.ReadRevocation = true'          # §1.8: 1 → 1
  git grep -n -E '^\s+(issuers|platformIssuer):' $R -- 'deploy/helm/umbrella/values*.yaml' | wc -l # §1.8: 16 → 16
  git grep -n 'HumanSession{' $R -- 'gateway/*_test.go' | wc -l                                    # §1.6: 29 → 31
done
```

Изменились четыре числа, и на предмет этого документа влияет одно — записи объявления. Каталог
вырос записями, не относящимися к рубежу: рубеж стоит **до** решения по каталогу (Р3), и число
записей на него не влияет. Построений дублёра сессии в пробах края стало 31 — каскад DoD п. 2
закрывается по тому же правилу, на любом их числе.

**Три новые записи — координаты церемонии авторизации** (`kacho#2817`, `kacho#2721`):

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750
git show b7608fe9750:gateway/internal/middleware/login_lane_paths.go | grep -n -E '^	\{Verb: "(authorize|token|discovery)"'
#   → 3: `/iam/v1/authorize`, `/iam/v1/token`, `/.well-known/oauth-authorization-server`;
#     цель — слушатель выдачи службы, `relayWhenUnanswered: true` у всех трёх; у обмена кода
#     ретранслятор оставляет удостоверение клиента базовой схемой
git show b7608fe9750:gateway/internal/middleware/authz_util.go | grep -n 'return IsLoginLanePath(path)'
#   → 272: запись объявления — путь без решения по каталогу (§1.3), в том числе все три
git show b7608fe9750:gateway/internal/middleware/auth_own_session.go | grep -n -E 'formVerb := IsLoginLanePath\(route\)|if formVerb \{'
#   → :80, :99: полоса сессии на записи объявления исполняется; «сессии нет» — ретранслируется
# КОНТРОЛЬ: на ревизии, которую читали §1.1–§1.10, записей церемонии нет
git grep -n -E '"/iam/v1/(authorize|token)(\?|")' 499ad3085fd -- gateway ':!*_test.go' | wc -l     # → 0
git grep -n -E '"/iam/v1/(authorize|token)(\?|")' b7608fe9750 -- gateway ':!*_test.go' | wc -l     # → 2
```

Отсюда следствие для Р5. Полоса сессии исполняется на **каждой** записи объявления (шапка
объявления: членство «НЕ снимает полосу сессии»), поэтому рубеж S1, поставленный по нулевому
решению, ответил бы на навигацию церемонии неподтверждённой сессией отказом Р3 — там, где служба
отвечает протоколом (перенаправление с `error=access_denied`, EV-67). Редакция 3 назвала это строкой
§3.2 с предикатом возврата «появлением маршрута края на этот путь»; маршрут появился, и решение
переезжает в Р5.

### §1.12 Голова волны службы: глагол подтверждения есть, писатель отметки зовётся одним местом

```sh
# ДОМ: PRO-Robotech/kaname @ c8559057b · единица — объявленный путь слушателя формы
git show c8559057b:internal/handler/loginlanehttp/handler.go | grep -c 'h.mux.HandleFunc'                  # → 15
git show c8559057b:internal/handler/loginlanehttp/handler.go | grep 'Path[A-Za-z]* *= ' | grep -ci verif   # → 3: два пути и объявление их положения
# единица — вызов писателя отметки в не-тестовом Go
git grep -n '\.MarkEmailVerified(' c8559057b -- '*.go' ':!*_test.go'
#   → 1: исход глагола подтверждения (api/humansession/verification.go:461)
git grep -n 'MarkEmailVerified(' c8559057b -- '*.go' ':!*_test.go' | wc -l
#   → 5: сверх вызова — объявления двух портов и две реализации; порт `loginmethod` вызова не имеет
git grep -n -E 'email_verified_at[[:space:]]*(=|:=)' c8559057b -- 'internal/migrations/*.sql'
#   → 1: `NEW.email_verified_at := NULL` — механизм базы отметку только снимает
git grep -n -i 'email_verified' c8559057b -- '*.py' '*.sh' '*.yml' '*.yaml' ':!docs/**'   # → 0: посевы и конвейеры отметку не пишут
# КОНТРОЛЬ: соседний метод того же порта предикат находит с вызовом
git grep -n '\.EmailVerification(' c8559057b -- '*.go' ':!*_test.go' | wc -l                 # → 1 (humansession/login.go:573)
```

Стенды самой службы уже заводят человека **тем путём, что человек**: регистрация полосой формы,
код из письма регистрации у приёмника писем стенда, предъявление под сессией регистрации
(`tests/authz-fixtures/seed_own_stand.py`, `seed_login_lane.py`, приёмник
`.github/scripts/stand-mailbox.py`; «Отметку в базу посев не пишет» — шапка `seed_login_lane.py`).
Одно отличие названо, и оно не здесь: посев входа службы при отсутствии письма регистрации **просит**
письмо (`POST /iam/v1/auth/verify-email`). Посевы платформы письма не просят (Р17) — это решение
этого документа о своих посевах, а не находка о посеве службы.

### §1.13 Посевы платформы заводят людей хуком поставщика — девять мест, и ни одно не может подтвердить адрес

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750 · единица — место заведения человека
git grep -n -E 'upsert_user\(' b7608fe9750 -- tests | grep -v 'def upsert_user' | wc -l
#   → 8: tests/authz-fixtures/prodseed_matrix.py — 7 (владельцы аккаунтов A и B, субъекты выдач
#     NOB, INV, PA1, неприкосновенный субъект, субъект личного токена), prodseed_network.py — 1
git grep -n 'users:upsertFromIdentity"' b7608fe9750 -- gateway/tests/newman/cases | wc -l
#   → 1: cluster_admin.py, шаг CLUSTER-ADMIN-SEED-TARGET-USER — цель выдачи администратора облака
git grep -n 'auth/register' b7608fe9750 -- tests gateway/tests | wc -l                  # → 0
# КОНТРОЛЬ: тот же образец находит посев консоли, который регистрирует
git grep -n 'auth/register' b7608fe9750 -- ui-future/e2e/specs/ceremony-seed.ts | wc -l   # → 1
git grep -n 'prodseed_network' b7608fe9750 -- ':!tests/authz-fixtures/prodseed_network.py' | wc -l
#   → 3, все — комментарии: вызывающего у prodseed_network.py нет
```

Личный токен человека — единственный предъявитель-человек наборов:

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750
git show b7608fe9750:tests/authz-fixtures/prodseed_matrix.py | grep -n -E 'usr_utok = upsert_user|tok_user_platform = user_platform_token|"jwtUserTokenPlatformIssuer": tok_user_platform'
#   → :763, :770, :779: человек заведён хуком, токен выпущен администратором стенда и обменян у нашего издателя
git grep -n 'auth="jwtUserTokenPlatformIssuer"' b7608fe9750 -- gateway/tests/newman/cases   # → authn_edge.py:716 — читатель слота
```

Приёмник писем посевы наборов не читают, отметку не пишут, и рецептов стенда, заводящих человека,
нет:

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750
git show b7608fe9750:.github/workflows/e2e-newman.yml | grep -ci 'mail'                                # → 0
git grep -n -i 'mailpit\|/api/v1/messages' b7608fe9750 -- tests/authz-fixtures deploy/scripts/newman-parallel.sh | wc -l   # → 0
# обход — шесть каталогов гейта F6b-52 (§1.14); каталога `e2e/` в дереве нет, и в обходе его нет
git grep -n -i -E 'email_verified_at|MarkEmailVerified|UPDATE[^;]*users' b7608fe9750 \
  -- tests gateway/tests 'services/*/tests/**' ui-future/e2e deploy .github ':!*.md' | wc -l   # → 0
# КОНТРОЛЬ: тот же обход находит запись посева в хранилище службы — она есть, и она о другом
git grep -n -E 'INSERT INTO kaname\.|UPDATE kaname\.|DELETE FROM kaname\.' b7608fe9750 \
  -- tests gateway/tests 'services/*/tests/**' ui-future/e2e deploy .github ':!*.md'           # → 1: prodseed_matrix.py:375, fga_outbox
git grep -n -E 'auth/register|upsertFromIdentity|UpsertFromIdentity' b7608fe9750 -- deploy .github ':!*.md' | wc -l   # → 2, оба — комментарии
# приглашений посевы и случаи не шлют · единица — строка с адресом глагола приглашения
git grep -n -E 'users:invite|UserService/Invite' b7608fe9750 -- tests gateway/tests 'services/*/tests/**' ':!*.md' | wc -l   # → 0
# КОНТРОЛЬ: тот же образец находит глагол там, где он объявлен, — запись каталога прав края
git grep -n -E 'users:invite|UserService/Invite' b7608fe9750 -- gateway/internal/middleware/embed/permission_catalog.json | wc -l   # → 1
#   (в `tests/authz-fixtures` слово invite есть только в именах служебной учётной записи
#    `svaInviteeId` / `jwtInvitee` — это субъект выдачи, а не приглашение)
# приёмник по профилям
git grep -n -A1 '^mailpit:' b7608fe9750 -- 'deploy/helm/umbrella/values*.yaml' | grep 'enabled:'
#   → values.dev.yaml: true · values.own-stand.yaml: true · values.yaml (умолчание): false;
#     прочие профили, в том числе values.prod.yaml, блока не объявляют
```

Три вывода, на которые опираются сценарии S4:

1. **Человек, заведённый хуком поставщика, подтвердить адрес не может никогда.** Способа входа у него
   нет — сессии он не получает, а глагол подтверждения требует сессии (Р6 службы); код
   восстановления чеканится только подтверждённому адресу (Р2 службы). Его выдачи не действуют
   (Р4а службы), его личный токен не обменивается (`401 invalid_client`, EV-65 а). Читатель сессии
   поставщика на крае снят (`kacho#2792`; Р11 п. 5 службы) — человек продукта так не появляется.
   Значит девять мест заведения — не «пройдут подтверждение позже», а вид человека, которого у
   продукта нет; после посадки рубежа наборы, опирающиеся на права и видимость этих людей,
   упадут по причине, не относящейся к их предмету, — тот же каскад, что §1.6 для консоли.
2. **Производитель письма и приёмник на стенде наборов есть:** регистрация ставит письмо той же
   транзакцией (Р9 службы), стенд наборов поднимается `make -C deploy dev-up` (`values.dev-prod.yaml` поверх
   `values.dev.yaml`, где приёмник объявлен), и ни один шард его не снимает
   (`deploy/mail_receiver_core_test.go`). Не хватает читателя и двух величин почтовой полосы
   службы на стенде — якоря сертификата приёмника и адреса входа консоли (§1.16); их заводит S4
   (F6b-53, F6b-56).
3. **Обхода в дереве нет ни у одной стороны:** у службы отметку пишет один вызов — исход глагола
   подтверждения (§1.12); в дереве платформы записей отметки ноль. Это состояние, которое S4
   **закрепляет** гейтом, а не создаёт (Р18, F6b-52).

### §1.14 Красный гейта дерева до кода: единица — строка с адресом, находок шесть, каталогов шесть

Ожидаемый вывод гейта F6b-52 выводится отсюда, а не выписывается в сценарии по памяти. Единица
осмотра — отслеживаемый текстовый файл; единица находки — **строка файла, несущая адрес**.

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750 · обход — шесть каталогов, каждый существует
for d in tests gateway/tests 'services/*/tests/**' ui-future/e2e deploy .github; do
  git grep -I -l -e '' b7608fe9750 -- "$d" | wc -l
done
#   → 27 · 10 · 263 · 63 · 390 · 54
git ls-tree -r --name-only b7608fe9750 -- e2e | wc -l          # → 0; на 499ad3085fd и origin/main — тоже 0
# КОНТРОЛЬ образца каталога: без `/**` образец не совпадает ни с одним файлом, и обход молчал бы
git grep -I -l -e '' b7608fe9750 -- 'services/*/tests' | wc -l  # → 0
```

Каталога `e2e/` в дереве платформы нет ни на одной из ревизий, поэтому в обходе его нет: обход
судит только существующие каталоги, и каждый из шести с нулём осмотренных — отказ гейта.

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750 · единица — строка, несущая адрес хука поставщика
P='InternalUserService/UpsertFromIdentity|users:upsertFromIdentity'
git grep -n -E "$P" b7608fe9750 -- tests gateway/tests 'services/*/tests/**' ui-future/e2e deploy .github
#   → 6 строк в 4 файлах:
#     tests/authz-fixtures/prodseed_matrix.py:191          — адрес вызова посева (одна функция на семь мест)
#     tests/authz-fixtures/prodseed_network.py:77          — адрес вызова посева
#     gateway/tests/newman/cases/cluster_admin.py:322      — путь шага случая
#     gateway/tests/newman/collections/cluster_admin.postman_collection.json:538, :546, :579
#       — адрес запроса, сегмент пути и строка сценария перед запросом, которая задаёт адрес,
#         по которому запрос уходит на самом деле (`pm.request.url = …`)
#   по каталогам: tests 2 · gateway/tests 4 · services/*/tests 0 · ui-future/e2e 0 · deploy 0 · .github 0
# КОНТРОЛЬ в обратную сторону: имя метода прозой (через точку) — не адрес, и находкой не считается
git grep -n -E 'InternalUserService\.UpsertFromIdentity' b7608fe9750 \
  -- tests gateway/tests 'services/*/tests/**' ui-future/e2e deploy .github | wc -l   # → 6, ни одна не в перечне выше
```

**Почему единица — строка, а не обращение.** Обращений к хуку четыре — по одному на объявление
запроса (функция посева, посев сети, шаг случая, запрос собранной коллекции), и на этой единице
строка сценария `:579` пропадает внутри «одного запроса коллекции». Гейт, который решал бы,
какая из трёх строк запроса «исполняемая», а какая «декоративная», сам стал бы распознавателем,
который молчит (`.claude/rules/testing-verdict.md` п. 14). Поэтому находка — **любая** строка с
адресом, где бы она ни стояла; до кода их **шесть**.

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750 · единица — строка источника случая набора newman с адресом регистрации
git grep -n 'auth/register' b7608fe9750 -- gateway/tests/newman 'services/*/tests/newman/**' | wc -l   # → 0
git grep -n 'auth/register' b7608fe9750 -- tests/authz-fixtures | wc -l                               # → 0: посев сегодня не регистрирует
# КОНТРОЛЬ: тот же образец находит строку регистрации посева консоли
git grep -n 'auth/register' b7608fe9750 -- ui-future/e2e/specs/ceremony-seed.ts                      # → :60
```

Итог, на который опирается F6b-52: находок до кода — **шесть**, все о хуке поставщика; записей
отметки вне службы — ноль (§1.13); строк регистрации в случаях наборов — ноль.

### §1.15 Идентификаторы человека после регистрации посев берёт с поверхностей края

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750
git show b7608fe9750:tests/authz-fixtures/prodseed_matrix.py \
  | grep -n -E '^def db_lookup|WHERE u.external_id|SELECT 1 FROM kaname.users'
#   → 199: ожидание строки человека чтением хранилища; 206, 213: аккаунт ищется по `external_id` = адрес
git grep -n -E '[^_a-z]db_lookup\(' b7608fe9750 -- 'tests/authz-fixtures/*.py' | grep -v -e 'def db_lookup' -e 'empty after'
#   → 4 вызова: prodseed_matrix.py:577, :578, :764 · prodseed_network.py:152 (у посева сети своя
#     копия поиска, :86)
git show b7608fe9750:gateway/internal/middleware/session_identity_handler.go \
  | grep -n -E '"id": +subj.ID|"emailVerified": +sess.EmailVerified'
#   → 173, 191: «кто я» отдаёт идентификатор человека и его положение одним ответом
# ДОМ: PRO-Robotech/kaname @ c8559057b
git show c8559057b:internal/apps/kaname/api/registration/register.go | grep -n 'ExternalID: domain.NewOwnLaneSubject()'   # → 218
git show c8559057b:internal/apps/kaname/api/user/mirror_tx.go | grep -n -E 'AccountName\("personal-cloud-|ProjectName\("default"\)'  # → 201, 212
git show c8559057b:proto/kaname/cloud/iam/v1/account.proto | grep -n 'string owner_user_id = 5'                          # → 45
```

Регистрация заводит внешнюю идентичность **своей полосы**, а не адрес: поиск аккаунта по
`external_id` = адрес после неё не найдёт ничего. Личный аккаунт и проект `default` она заводит
тем же построением, что хук, поэтому «Дано» F6b-48 строится; откуда посев берёт их идентификаторы
— Р17.

### §1.16 Почтовая полоса службы на стенде ведёт к приёмнику — без якоря его сертификата и без адреса входа

```sh
# ДОМ: PRO-Robotech/kacho @ b7608fe9750 · профиль стенда наборов и консоли (оба конвейера — `make -C deploy dev-up`)
git show b7608fe9750:deploy/helm/umbrella/values.dev.yaml \
  | grep -n -E "connectionURI: 'smtp://\{\{ .Release.Name \}\}-mailpit:1025/'|appBaseURL:"
#   → 58 происхождение консоли стенда (`global.kacho.identity.appBaseURL`), 122 узел полосы — приёмник стенда
git show b7608fe9750:deploy/helm/umbrella/charts/kaname/templates/configmap.yaml \
  | grep -n -E '\$mailNode := |^    invite-mail:|relay: \{\{ \$mailHost'
#   → 591, 602, 603: блок `invite-mail` службы выводится из того же узла `global.kacho.identity.smtp`
git grep -n -E 'ca-bundle-file|login-url' b7608fe9750 -- deploy/helm/umbrella/charts/kaname | wc -l            # → 0
git grep -n -i 'mailpit' b7608fe9750 -- deploy/helm/umbrella/charts/kaname/templates/deployment.yaml | wc -l    # → 0
# КОНТРОЛЬ: якорь того же приёмника стенд уже монтирует — процессу поставщика (блок `kratos`)
git show b7608fe9750:deploy/helm/umbrella/values.dev.yaml | grep -n -E 'SSL_CERT_FILE$|secretName: kacho-mailpit-tls'   # → 1065, 1088
# ДОМ: PRO-Robotech/kaname @ c8559057b
git show c8559057b:internal/repo/kaname/pg/invite_mail_outbox/outbox.go | grep -n 'EventVerificationSend, payload'   # → 171: та же очередь
git show c8559057b:internal/clients/invite_mail.go | grep -n 'case EventVerificationMailSend'                       # → 591, 826: тот же отправитель
git show c8559057b:cmd/kaname/invite_mail_wiring.go | grep -n -F 'if cfg.CABundleFile != ""'                         # → 202: без величины — системные корни
git show c8559057b:internal/clients/invite_mail.go | grep -n 'func verificationScreenAddress'                       # → 617: без адреса входа — письмо без адреса экрана
# КОНТРОЛЬ: собственный чарт службы обе величины выпускает, и её стенд якорь задаёт
git show c8559057b:deploy/templates/configmap.yaml | grep -n -E 'ca-bundle-file:|login-url:'                         # → 635, 638
git show c8559057b:.github/scripts/stand-chart.sh | grep -n 'caBundleFile:'                                           # → 706
```

Вывод перемерен против редакции 4, и он **другой**. Письмо подтверждения идёт той же очередью и
тем же отправителем, что приглашение, а узел полосы на стенде — приёмник стенда: производитель
доставки на стенде — не `kacho#1773`. Но копия чарта службы в зонте не выпускает двух величин,
которые собственный чарт службы выпускает: **якорь сертификата узла** — без него сертификат
приёмника, выпущенный внутренним удостоверяющим стенда, проверяется по системным корням, в которых
такого якоря нет (`values.dev.yaml:1040`, та же причина у процесса поставщика), и соединение
отвергается; и **адрес входа** — без него письмо не несёт адреса экрана, и F6b-28 судит ноль
адресов. Это вывод по объявлению и по коду; на поднятом стенде он не прогонялся.
Обе величины — предмет стенда, как пять ручек подтверждения; их заводит S4 (`kacho#2901`), держит
F6b-56, а приход письма на стенде — F6b-34, F6b-53 и сценарии с письмом.

---

## §2 Решения — ратифицировать явно, ревьюер проверяет каждое

Номер **Р14** в этом документе не занят намеренно: так нельзя спутать решение этого документа с
отменённым Р14 приёмки Ф6.

### Р1. Решение владельца вносится дословно; Р14 приёмки Ф6 ОТМЕНЕНО

Решение — §0, дословно; оно не переоткрывается.

**Что отменено.** Р14 приёмки Ф6 («отказ на действии идёт ОТДЕЛЬНОЙ приёмкой; фаза закрывается ДВУМЯ
документами; сперва производитель отметки, потом отказ, и между ними промежуток, в котором рубежа
нет вовсе») отменено в обеих своих частях:

- **предмет** больше не «действия, требующие подтверждённого адреса», отбираемые по одному, — а
  **всё** за пределами закрытого перечня (Р5, Р6). Отбора по действию нет;
- **промежуток без рубежа** больше не допустим: рубеж и производитель отметки садятся **одной
  волной** (`#2797` платформы вместе с волной `366` службы), и стенда, где рубеж есть, а глагола
  подтверждения нет, не бывает (§6, п. 0).

Приёмка службы записала ту же отмену у себя (её §0.1, строка «Р14», и её Р14) и вобрала предмет Ф6;
второго места, утверждающего Р14 действующим, в линии не остаётся, когда приёмка службы одобрена
(§6 п. 1).

**Что уцелело — и это не противоречие, а физика.** Довод Р14 «рубеж без производителя переселяет
тупик на обычную работу» верен и сегодня: рубеж без глагола подтверждения и письма закрыл бы
консоль **каждому**. Решение владельца снимает не довод, а вывод из него: вместо «рубеж позже» —
«рубеж вместе». Порядок посадки поэтому остаётся обязательным (§6, п. 0), но разнесения по двум
документам и двум посадкам больше нет.

**Цена — названа, и она не ноль.** Отметок сегодня ноль по построению (§1.4), обратного заполнения
не будет (Р13 службы). Значит в день посадки **каждый** существующий человек на каждом стенде проходит
подтверждение сам и до того видит только экран «подтвердите почту»; письма регистрации у него не
было, и первое письмо он просит кнопкой (Р15). Стенд, на котором письмо до человека не доходит,
закрыт для людей целиком. Ручки «выключить рубеж» не заводится (Р11).

### Р2. Кто что держит — у каждой точки свой вопрос

| точка | её вопрос | чем держится |
|---|---|---|
| **служба** (`kaname#456`) | что учётной записи с неподтверждённым адресом можно **в самой службе**: её глаголы, каждый вопрос о праве, выдача ролей, приглашение, посев первого администратора, форма сессии, письмо, выдача и предъявление её удостоверений | её приёмкой и её пробами; заказ §3.2 |
| **край** (эта приёмка, S1, `kacho#2900`) | куда носитель такой **сессии** проходит: к любому пути платформы — нет; к «кто я», выходу, здоровью, шести глаголам формы и трём координатам церемонии — да (на координатах отвечает служба, Р5); ответы службы о прочих удостоверениях и о праве край исполняет | полосой сессии: она единственная видит и носитель сессии, и каждый путь (§1.2); прочие полосы — Р16; ответ службы на вопрос о праве — Р3а |
| **консоль** (эта приёмка, S2) | что человеку **показать** и куда его **не звать** | маршрутизатором и экраном подтверждения |

**Консоль рубежом не является** — рубеж на крае и у службы. Сдержанность консоли (не звать API за
пределами перечня) нужна человеку: без неё он видел бы каркас, собранный из отказов. Но и она
проверяема и утверждается пробами (Р6).

**На полосе сессии решают двое, и расхождение выходит отказом.** Край решает о пути, служба — о своих
глаголах и о каждом праве. Край строже — служба запроса не видит; служба строже — отказывает она. На
этой полосе поэтому второй проверки «совпадают ли они» не заводится. **На полосах базового секрета и
предъявителя** край пути не судит: там держатель — служба на выдаче и на предъявлении, а край
исполняет её ответ своим отказом полосы (Р16), а её ответ на вопрос о праве — значением Р3 (Р3а).
Довод «край спрашивает о каждом пути» действует ровно там, где край спрашивает, и шире не
применяется.

### Р3. Отказ края — ОДНО абсолютное значение на любом пути, и это значение службы

| что | значение |
|---|---|
| HTTP | **403** |
| `code` (`google.rpc.Status`) | **7** |
| `message` | `email address is not verified` — фиксированный текст, тот же, что у отказа службы (Р3 службы) |
| `details` | один `google.rpc.ErrorInfo`: `reason` = **`EMAIL_NOT_VERIFIED`**, `domain` = **`iam.kaname.cloud`**, без `metadata` |
| `WWW-Authenticate` | **нет** — это не вызов на аутентификацию |
| носитель | **цел**: `Set-Cookie` в ответе нет — сессия нужна экрану подтверждения |
| пересылка | запрос **не уходит** ни к решению по каталогу прав, ни к службе |

**Почему значение службы, а не своё.** Причина одна, и её владелец — служба: она произносит тот же
отказ на своих глаголах и на своём слушателе (Р3 службы). Два значения одной причины у двух производителей разошлись бы молча, а
консоль решает по `reason` (§1.5) — второе имя причины стало бы вторым решением. Домен —
`refusaldomain.For(refusaldomain.ServiceIAM)` службы: `Compose` собирает `<служба>.<суффикс>`
(`PRO-Robotech/kaname@c083ad5bbfa:internal/refusaldomain/refusaldomain.go`, `ProductSuffix` =
`kaname.cloud`, `ServiceIAM` = `iam`). Он **отличается** от домена отказа края по каталогу прав
(`kaname.cloud.iam.v1`, `gateway/internal/middleware/permission_denied_response.go:93`), и это
названо, а не случайно: отказ по каталогу — решение края, отказ адреса — решение службы, которое край
произносит раньше неё.

**Значение одинаково на любом пути, побайтово.** Существует ли ресурс, чей он, правилен ли формат
идентификатора — отказ не зависит ни от чего из этого, потому что стоит **до** решения по каталогу
и до скрытия существования. Отказ не может стать оракулом того, чего он не читал.

**Почему 403, а не 401.** Человек аутентифицирован, и его сессия цела; ему не хватает не личности,
а подтверждения. `401` консоль читает как «сессии нет» и уводит на вход (§1.5) — это увело бы
человека с живой сессией в круг «вход → экран подтверждения».

### Р3а. Отказ решения с причиной службы `email_not_verified` край произносит значением Р3

Решение по каталогу прав край спрашивает у службы, и о неподтверждённом человеке служба отвечает
«нет» с причиной `email_not_verified` на любом объекте, до вычисления отношения (Р4а службы, EV-50).
Такой ответ край произносит **значением Р3**, а не своим отказом по каталогу (`AUTHZ_DENIED`) и не
`404` скрытия существования:

- на HTTP — таблица Р3; на нативной поверхности — та же причина в форме gRPC, как её произносит
  служба на своих слушателях: `PERMISSION_DENIED`, `email address is not verified`, тот же
  `ErrorInfo` (Р3 службы);
- **раньше скрытия существования:** причина говорит о вызывающем, а не об объекте, и служба
  отвечает ею на любой объект — поэтому ответ одинаков для существующего и несуществующего объекта
  и оракулом не становится (F6b-45);
- причина узнаётся по **точному значению** в перечне `deny_reasons`; любая иная — прежний отказ по
  каталогу, побайтово как до этой под-фазы;
- к следующему звену запрос не уходит; клетка Р12 не меняется: её растит рубеж полосы сессии, а
  этот отказ произнесён решением.

**Откуда у этого отказа вход — названо.** Рубеж Р4 стоит раньше решения, поэтому на полосе сессии
вопрос о праве неподтверждённого человека до службы доходит лишь тогда, когда отметку сняли между
разбором сессии и вопросом о праве одного запроса. На полосах Л2 и Л3 вход — окно края (5 с, §1.8,
Р16): вердикт «действует», полученный до снятия отметки, край держит до конца окна, а о праве служба
отвечает по текущей отметке — **на промахе кэша решений края**. Этот кэш — третье окно, и оно
названо: он хранит только «разрешено», срок — `KACHO_API_GATEWAY_AUTHZ_CACHE_TTL_SECONDS`
(`gateway/internal/config/config.go:629` @ `b7608fe9750`, умолчание загрузчика 5 с; чарт края
выпускает ручку только заданной, `gateway/deploy/templates/deployment.yaml:357`, и ни один профиль
зонта её не задаёт), сбрасывается потоком смены субъекта, который питают выдачи и членства, а
снятием отметки — нет. Решение «разрешено», записанное до снятия отметки, отвечает без вопроса к
службе до своего срока: на этом окне у Р3а входа нет, а граница окна та же — не дольше 5 с. Снимает
отметку механизм базы на смене адреса (Р1 службы); глагола смены адреса в дереве нет (§3.2), поэтому
сегодня вход строится дублёром ответа службы на уровне пробы края. Отказ произносится одним значением на всех входах, потому что консоль решает по
`reason` (§1.5): второе значение одной причины стало бы вторым решением. Так же решают строка края
в §3.2 приёмки службы и задача стадии `kacho#2900`.

### Р4. Порядок в полосе сессии: сессия → отсечка → АДРЕС → пол уровня → личность

Рубеж адреса стоит в полосе сессии края после решения о годности носителя и отсечки и **до** пола
уверенности и выставления личности (`gateway/internal/middleware/auth_own_session.go`, между
проверкой отсечки и `ownSessionAssurance`):

- носитель негоден, снят или отсечён — прежний отказ **F4d-22** (`401`, `session ended; sign in again`,
  носитель гасится): годность сессии решается раньше её свойств (F6b-07);
- служба не ответила о сессии — прежний отказ **F4d-23**: «адрес неизвестен» проходом не
  бывает (F6b-09);
- адрес не подтверждён, путь вне перечня Р5 — отказ Р3; вызова на повышение уровня **нет** (F6b-08):
  человек без подтверждения повышать уровень не должен — ему нечего получать.

Отсутствующее в ответе службы значение подтверждённости есть **«не подтверждён»** (`bool` провода
без значения равен `false`) — то есть умолчание здесь закрывает, а не открывает.

### Р5. Перечень прохода — ОДНО объявление, и в нём у каждой записи своё решение

Неподтверждённая сессия проходит ровно туда:

1. **пути без записи каталога, не являющиеся записями объявления** — `/iam/v1/auth/me`,
   `/oauth/logout`, `/healthz`, `/readyz` (тот же перечень `isPublicHTTPPath`, §1.3; второго не
   заводится);
2. **записи объявления, несущие решение «доступна до подтверждения».** Объявление остаётся единственным
   (`login_lane_paths.go`), и у записи появляется решение «доступна до подтверждения адреса» —
   рядом с уже существующими `relayWhenUnanswered` и `carriesClientBasic`. **Нулевое значение —
   отказ:** запись, дописанная без решения, до подтверждения недоступна.

Записей в объявлении становится **18** (на голове волны их 16, §1.11): к тринадцати глаголам формы
добавляются `POST /iam/v1/auth/verify-email` и `POST /iam/v1/auth/verify-email/confirm` (имена
ратифицированы владельцем для Ф6 и сохранены Р6 службы), и остаются три координаты церемонии.
Доступных до подтверждения — **девять**: шесть глаголов формы (`csrf` · `login` · `logout` ·
`register` · `verify-email` · `verify-email/confirm`) и три координаты церемонии (`authorize` ·
`token` · `discovery`). Остальные **девять** глаголов формы (смена пароля, два глагола
восстановления, шесть глаголов второго фактора и повышения) для неподтверждённой сессии край
отвергает значением Р3. Без носителя сессии рубеж не действует вовсе: анонимный вызов судится как
прежде.

**Координаты церемонии — доступны до подтверждения, и отвечает на них служба.** Довод не в
удобстве: на каждой из трёх служба уже держит правило и отвечает **протоколом** — навигация
неподтверждённой сессией получает перенаправление с `error=access_denied` без `code` (Р5 службы,
EV-67), обмен кода и оборот токена обновления о неподтверждённом владельце — `400
{"error":"invalid_grant"}` без пары (Р5б службы, EV-77, EV-78), документ обнаружения публичен и не
читает ничего. Отказ Р3 края ответил бы там JSON-телом, которого клиент протокола не ждёт: строже не
стало бы — служба не выдаёт ни кода, ни пары, — а протокол сломался бы. Ответ службы край
**ретранслирует как есть** и значения Р3 на этих записях не произносит (F6b-04). Так же решила
строка §3.2 редакции 3 на день появления маршрута; маршрут появился (§1.11), и решение стоит здесь.

**Оба глагола подтверждения носитель ЧИТАЮТ** (Р6 службы: «под сессией человека»), поэтому их
запись несёт `relayWhenUnanswered = false`: при службе, не ответившей о сессии, край отвечает
F4d-23, а не ретранслирует (F6b-11). «Сессии нет» при носителе на них ретранслируется, как на
каждом глаголе формы, — исход судит служба (`401` / `16`, EV-21, EV-39).

**Восстановление доступа — край строже службы, намеренно.** Служба глаголы восстановления в положении
подтверждения не закрывает: сессии они не требуют (Р2 службы). Край отвергает их **только** при
предъявленном носителе неподтверждённой сессии; анонимный вызов идёт как прежде. Консоль к ним с такой
сессией не зовёт (Р7 уводит `/recovery` на экран подтверждения), а код восстановления служба чеканит
только подтверждённому адресу — строгость края ничего не отнимает у человека и не заводит второго
правила о восстановлении.

### Р6. Что консоль вправе звать до подтверждения — закрытый перечень, и он же предикат проб

«Обращение к API» — запись переписи обращений страницы (`ceremonyCensus`,
`ui-future/e2e/specs/fixtures.ts`) вида «запрос», чей путь отвечает `^/[a-z-]+/v1(/|$)`,
`^/operations(/|$)` или `^/oauth/`. Для учётной записи с неподтверждённым адресом множество таких
обращений обязано лежать в перечне:

| метод | путь | тело (Р6 службы) |
|---|---|---|
| `GET` | `/iam/v1/auth/me` | — |
| `GET` | `/iam/v1/auth/csrf` (любой `?form=`) | — |
| `POST` | `/iam/v1/auth/login` · `/iam/v1/auth/register` · `/iam/v1/auth/logout` | как сегодня |
| `POST` | `/iam/v1/auth/verify-email` | `{"csrfToken"}` — признак вида `verify-email`; адреса в теле нет |
| `POST` | `/iam/v1/auth/verify-email/confirm` | `{"code","csrfToken"}` — признак вида `verify-email-confirm` |

Всё сверх перечня — находка пробы, и проба печатает лишнее обращение целиком.

### Р7. Каркас открывается только на «подтверждён»; «не подтверждён» и «неизвестно» — свои экраны

Страж консоли стоит **над каркасом и над каждым адресом церемонии, кроме четырёх разрешённых**
(`/login`, `/registration`, `/logout`, `/verification`): значит, и `/settings` (в каркасе), и
`/recovery` (вне его) для неподтверждённой сессии ведут на экран подтверждения. Край о сессии он
спрашивает один раз на загрузку документа. Решает по ответу края, и только по нему:

| ответ края | что показывает консоль |
|---|---|
| сессия есть, `emailVerified === true` | каркас, как сегодня |
| сессия есть, `emailVerified === false` | переход на `/verification?returnTo=<адрес>` |
| сессия есть, но подтверждённость **не названа** (`session` нет либо поля нет) | названная страница «Не удалось узнать, подтверждён ли адрес: край не назвал это в ответе о сессии» с кнопками «Проверить снова» и «Выйти» |
| край не ответил по существу (`unknown`) | названная страница с текстом `UNKNOWN_SESSION_TEXT` (`shared/src/api/login-lane.ts:608`) и теми же двумя кнопками |
| сессии нет | как сегодня — поведение анонимного вызова этой под-фазой не меняется |

Во всех состояниях, кроме первого, **обращений сверх перечня Р6 нет**: каркас не монтируется, и его
чтения (§1.5) не выпускаются. Ни одно из этих состояний не говорит «вы вышли» и не уводит на вход:
«спросить не удалось» — не «сессии нет» (так уже решено в дереве, `host/src/utils/session.ts`).
Меняется одно: на первой загрузке документа неизвестное состояние каркаса не открывает — рубеж
закрывающий.

`/iam/v1/me` консоль зовёт **только** в первом состоянии: контекст личности монтируется внутри
каркаса, и параллельного вопроса о правах до ответа о сессии больше нет.

**Сам `/verification` решает по тому же ответу.** Сессии нет — документ уходит на `/login` без
адреса возврата (после входа решит страж). Сессия подтверждена — документ уходит на адрес возврата
(`useReturnTo`, Р8): подтверждать нечего.

### Р8. Экран подтверждения — `/verification`, вне каркаса

Адрес `/verification` из «такого адреса здесь нет» становится экраном церемонии вне каркаса (как вход
и регистрация): у человека без подтверждения нет ни проекта, ни разделов, и рейл обещал бы
недоступное. Адрес с возвратом собирается **одной** функцией рядом с `loginAddress` — тем же именем
параметра `returnTo`. Читает адрес возврата экран **только** через `useReturnTo`
(`shared/src/pages/auth/use-return-to.ts`, §1.5): своё происхождение, иначе корень консоли, —
держатель предиката `safeInternalPath` один, и новый читатель его не заводит заново (F6b-36).

**Вид экрана:**

- заголовок «Подтвердите адрес почты»;
- текст «Чтобы продолжить работу в консоли, подтвердите адрес <адрес>: введите код из письма,
  отправленного на этот адрес.» — `<адрес>` берётся из ответа края о сессии (`user.email`), а не из
  ввода;
- строка «Письмо с кодом приходит после регистрации. Если письма нет или код не подходит,
  отправьте новое.» — верна и для зарегистрировавшегося, и для человека, заведённого до дня посадки
  (Р15);
- поле «Код из письма» и кнопка «Подтвердить» — `POST /iam/v1/auth/verify-email/confirm`; значение
  поля уходит как введено: своего суждения о содержимом кода консоль не выносит, приведение делает
  служба (Р7 службы);
- кнопка «Отправить новое письмо» — `POST /iam/v1/auth/verify-email`; успех — «Письмо с новым
  кодом отправлено на <адрес>. Прежний код больше не действует.»;
- **отсчёт до следующей отправки берётся только у службы**: из `Retry-After` ответа — и на успехе,
  и на отказе по частоте. Пока отсчёт идёт, кнопка закрыта, и закрыта отправка клавишей ввода;
  текст — «Отправить новое письмо можно через <N> с». Ответ без `Retry-After` отсчёта **не**
  получает: своего правила о частоте у консоли нет, и число, выбранное консолью, разошлось бы со
  службой молча. Довод за сам отсчёт — безопасность, а не удобство: письма на адрес ограничены
  промежутком, и человек видит, когда можно снова, вместо того чтобы бить в отказ;
- кнопка «Выйти» — единственный выход консоли (`useLogout`, `shared/src/pages/auth/use-logout.ts`).

**Кнопки «Продолжить» нет.** Подтверждение в другом месте снимает эту сессию (Р10 службы): вопросу
«подтвердили ли меня» нечего найти, кроме «сессии нет». Этот исход экран узнаёт на следующем же
обращении и уводит на вход (F6b-30).

**При открытии экран не шлёт ничего, кроме вопроса о сессии и признака формы** (F6b-18): письмо —
действие человека или регистрации, а не следствие открытия адреса.

Экран по канону консоли (`.claude/rules/ui.md`); отказ службы показывается дословно, как на прочих
экранах церемонии.

### Р9. Исходы двух глаголов на экране — по одному действию на исход

Кода в адресе письма **нет** (Р8 службы): письмо несёт код, его срок и адрес экрана — ровно
`<происхождение консоли>/verification`, без параметров и без фрагмента (производитель — дерево службы, §1.9; значение держит F6b-28). Открытие адреса
из письма поэтому не меняет ничего — подтверждает только введённый код под сессией того же человека
(F6b-28).

**Предъявление кода** (`POST /iam/v1/auth/verify-email/confirm`):

| ответ | что делает экран | сценарий |
|---|---|---|
| `200`, `session.emailVerified: true`, новый носитель в `Set-Cookie` | документ уходит на адрес возврата (`useReturnTo`) **новой загрузкой**; дальше решает страж Р7 | F6b-23, F6b-36, F6b-40 |
| `401` / `16`, сессия жива (код неверен, истёк, вытеснен, истрачен, чужой) | текст службы дословно и строка «Проверьте код или отправьте новое письмо.»; адрес не меняется | F6b-24, F6b-29, F6b-39 |
| `401` / `16`, а «кто я» после него — «сессии нет» | документ уходит на `/login` | F6b-30 |
| `400` / `9`, `EMAIL_ALREADY_VERIFIED` | документ уходит на адрес возврата: подтверждать нечего | F6b-42 |
| `400` / `9`, `INVITE_NOT_VALID` (приглашение истекло или снято, Р11 п. 4 службы) | текст службы дословно, без строки «Проверьте код…» — код тут ни при чём; адрес не меняется; поле и кнопки открыты; выход человека — «Выйти», выход из положения — повторное приглашение распорядителем | F6b-44 |
| `403` / `7`, `FORM_TOKEN_REJECTED` | добывается **один** свежий признак вида `verify-email-confirm`; само обращение не повторяется, повторяет человек | F6b-38 |
| `400` / `3` (`code: required`), `503` / `14`, ответа нет | текст дословно (при отсутствии ответа — `UNKNOWN_SESSION_TEXT`); ничего не повторяется само | F6b-43 |
| после `200` край не ответил о сессии по существу | страница стража «неизвестно» (Р7); второго предъявления нет | F6b-37 |

**Строку выбирает `reason`, а не код:** два исхода `400` / `9` различаются только им (Р6 службы), и
консоль решает по `ErrorInfo.reason` тем же решением на отказ, что всюду (§1.5). Причина, которой
таблица не называет, — действие «показать»: текст дословно, адрес не меняется, ничего не
повторяется (F6b-44, контроль).

**На `401` любого из двух глаголов экран один раз спрашивает «кто я»:** служба отвечает одним и тем
же `401` и на неподошедший код, и на снятую сессию (Р6 службы), и различить две строки таблицы можно
только ответом края о сессии. Второго обращения к глаголу этот вопрос не выпускает.

**Отказа по частоте у предъявления нет по построению:** предел — на код (Р7 службы, EV-36), пятое
неподошедшее тратит код, и дальше исход — тот же `401`. Консоль попыток не считает и своей блокировки
не заводит (F6b-39). **Ветвь «в браузере вошёл другой человек»** решена у службы: код принадлежит
человеку, и код одного в сессии другого — `401` (Р7 службы, EV-37); ни одна из двух записей не
подтверждается (F6b-29).

**Запрос нового письма** (`POST /iam/v1/auth/verify-email`):

| ответ | что делает экран | сценарий |
|---|---|---|
| `200`, тело `{}`, `Retry-After: N` | «Письмо с новым кодом отправлено…», отсчёт N | F6b-19 |
| `200` без `Retry-After` | тот же текст, отсчёта нет, кнопка открыта | F6b-20 |
| `429` / `8`, `TOO_MANY_ATTEMPTS`, `Retry-After: N` | текст службы дословно, отсчёт N, кнопка закрыта | F6b-21 |
| `400` / `9`, `EMAIL_ALREADY_VERIFIED` | документ уходит на адрес возврата | F6b-42 |
| `401` / `16`, а «кто я» — «сессии нет» | документ уходит на `/login` | F6b-30 |
| `403` / `7`, `FORM_TOKEN_REJECTED` | один свежий признак вида `verify-email`, повторяет человек | F6b-38 |
| `503` / `14`, ответа нет | текст дословно; ничего не повторяется само | F6b-43 |

### Р10. «Кто я» у неподтверждённой сессии не называет прав и о правах не спрашивает

Ответ края `GET /iam/v1/auth/me` для сессии с неподтверждённым адресом несёт человека и сессию, как
сегодня, с `session.emailVerified: false`, и **`permissions: []` без вопроса о системном
администраторе**. Довод: служба до подтверждения ни одной выдачи не исполняет (Р4 службы), и
спрашивать её о выдаче — выпускать вопрос, ответ на который известен; а консоль, получившая
`["*","admin"]`, нарисовала бы администраторские разделы тому, кому их нельзя.

### Р11. Ручки «выключить рубеж» нет

Рубеж не имеет ни ручки развёртывания, ни режима посадки, ни исключения для стенда. Ручка,
снимающая рубеж, была бы способом его снять, а боевая посадка на каждом стенде обязательна (ban #16).
Стенду для проб нужно одно — письмо, доходящее до приёмника (§1.7), и оно в ядре каждого шарда.

### Р12. Наблюдаемость: у отказа края своя клетка

Отказ Р3 считается своей клеткой накопителя полосы сессии (`SessionLaneSnapshot`, рядом с
`CutoffDenied` · `NoSession` · `Unavailable`) и выходит на диагностическую поверхность тем же
коллектором. Клетка существует с нулём до первого отказа; проход подтверждённой сессии её не
меняет.

### Р13. Фикстура набора заводит ПОДТВЕРЖДЁННОГО человека; неподтверждённого — отдельный посев

Посевов «Дано» два, и они различаются **ровно одним фактом** — предъявлен ли код:

| посев | как строится |
|---|---|
| **П-н** — неподтверждённый | существующий `seedHuman` (`ui-future/e2e/specs/ceremony-seed.ts`): регистрация глаголом службы своим контекстом запросов; носитель у посева. Регистрация ставит письмо (Р9 службы), но код не предъявлен, и отметки нет (Р6 службы) |
| **П-п** — подтверждённый | П-н, затем посевом: письмо на адрес П-н, принятое приёмником писем стенда **после** регистрации, прочитано; `POST /iam/v1/auth/verify-email/confirm` с его кодом тем же носителем; посев берёт **новый** носитель из `Set-Cookie` ответа; шаг утверждает свой исход ответом `GET /iam/v1/auth/me` новым носителем → `emailVerified: true` |

Фикстура регистрации набора (`register` в `fixtures.ts`) доводит человека до **П-п** через экраны
консоли — тем путём, что проходит человек (F6b-40): регистрация → экран подтверждения → письмо,
принятое приёмником **после регистрации и без единого нажатия** → код в поле → «Подтвердить».
Перепись фикстуры не содержит `POST /iam/v1/auth/verify-email`: фикстура не может сделать зелёным
продукт, в котором первое письмо не уходит (`gate-authoring` §«фикстура не снисходительнее
продукта»). Письмо не пришло в срок — фикстура падает текстом «условие не создано: письмо
подтверждения не дошло до приёмника», и прогон классифицирует это как **«не выполнилось»**, а не как
красное (`.claude/rules/e2e-flow.md` §1). Каскад §1.6 закрывается одним местом, а не двадцатью
четырьмя.

Код значения берётся **из письма**, а не из хранилища и не из строки очереди: проба судит продукт
через те поверхности, которые есть у человека.

**Срок, который создаёт служба, проба не выдумывает.** Где «Дано» требует истёкшего промежутка между
письмами (F6b-19), посев спрашивает `POST /iam/v1/auth/verify-email`, получает `429` с
`Retry-After: N` и ждёт **ровно N**, названное службой; своего числа проба не несёт. Величина — та,
что объявлена профилем стенда для ручки промежутка службы (Р9 службы).

### Р15. Первое письмо ставит РЕГИСТРАЦИЯ у службы; консоль писем сама не шлёт

Производитель первого письма — **служба при регистрации**: письмо ставится той же транзакцией, что
заводит человека (Р9 службы, EV-01), и «зарегистрирован» влечёт «письмо поставлено». Вход письма не
шлёт (EV-02).

- **Консоль письма не шлёт ни при открытии экрана, ни после регистрации** (F6b-12, F6b-18): второй
  производитель одного письма разошёлся бы с первым по промежутку, и открытие адреса стало бы
  действием.
- **Человек, заведённый до дня посадки**, письма регистрации не получал: его первое письмо — нажатие
  «Отправить новое письмо» (F6b-19). Текст экрана поэтому говорит «приходит после регистрации…
  если письма нет — отправьте новое», а не «перейдите по ссылке из письма», и верен в обоих случаях.
- **Следствие для промежутка названо:** письмо регистрации открывает промежуток, поэтому «Отправить
  новое письмо» сразу после регистрации — `429` со сроком службы, а не `200` (F6b-21).

### Р16. Полосы личности человека: держатель правила — у каждой

Перепись §1.8 и решение по каждой полосе:

| полоса | поверхность | чью личность выставляет | держатель правила | удостоверения, выданные до дня посадки |
|---|---|---|---|---|
| **Л1** сессия (`tryOwnSession`) | HTTP | человека | **край** — рубеж Р4 (S1); служба — на своих глаголах и под каждым вопросом о праве (Р2, Р4 службы) | служба отвечает о сессии по текущей отметке на каждом вопросе, кэша у края нет (§1.4): со дня посадки каждая живая сессия в положении подтверждения |
| **Л2** базовый секрет (`tryBasicCredential`; `a.basicLane` нативной) | HTTP и нативная | человека либо машины — вид называет ответ службы | **служба на предъявлении**: разрешение секрета отказывает, если владелец — человек с неподтверждённым адресом (Р5 службы); тот же вердикт — на перепросе живости на открытом соединении (строка Р4в службы и её дерево, §1.9; сценария у службы нет — §3.2). Край исполняет ответ своим единым отказом полосы | служба спрашивается на каждом предъявлении; положительный вердикт край держит не дольше окна полосы (5 с) |
| **Л3** предъявитель, токен доступа (`tryBearerJWT`; `extractBearer` нативной) | HTTP и нативная | человека, когда вид принципала в утверждении токена — человек (персональный токен `UserTokenService`), либо машины | **служба на выдаче** — отказ (Р5 службы); **служба на предъявлении** — сверка `POST /internal/tokens/introspect`, которую край задаёт о токене нашей записи издателя на каждом предъявлении обеих поверхностей (§1.8), отвечает `{"active": false}`, если владелец — человек с неподтверждённым адресом, по **текущей** отметке (Р5а службы, EV-68). Край исполняет ответ своим отказом полосы: по HTTP — `401` с текстом `token revoked`, на нативной — `UNAUTHENTICATED` с единым текстом неудачи подлинности предъявителя `authentication failed` (F6b-35). Вердикт сверки — и «действует», и «не действует» — край держит не дольше окна кэша: min(5 с, остаток срока токена) (§1.8) | срок любого токена — не больше 30 мин (`MaxTokenTTL`); сверка отвечает по текущей отметке со дня посадки службы и о них (Р13 службы) |
| **Л4** общий ключ подписи (`tryDevSecretJWT`) | HTTP | — | **полосы нет ни на одном стенде**: край с заданным ключом отказывается стартовать под любой пометкой окружения (§1.8, `authz_validation.go:72`) | — |
| **Л5** сертификат пира | нативная | только служебной учётной записи (§1.8) | правило не касается: личности человека полоса не выставляет | — |

**Полоса записи отзыва на стендах не получает ни одного токена.** Вопрос о токене
выбирает запись издателя (§1.8): токен нашей записи спрашивается у сверки, токен любой иной
принятой записи — у записи отзыва по идентификатору (`IsRevoked`). Каждый профиль зонта принимает
ровно одного издателя — нашего, а пустой перечень — отказ старта (§1.8), поэтому к записи отзыва не
приходит ни один токен, и держатель правила ей не нужен. Установка, принявшая вторую запись
издателя, — строка §3.2 с предикатом возврата.

**Пути без записи каталога по HTTP сверки не задают** (`auth.go:1162`, §1.3) — это четыре пути
без записи и **все** записи объявления, а не только перечень Р5, — и личность предъявителя на них
прав не даёт: «кто я» отвечает только по носителю сессии, предъявителю — анонимом
(`session_identity_handler.go`, `Me`); выход снимает собственное удостоверение (§1.10); глаголы
формы судит служба по сессии, координаты церемонии — по сессии и по удостоверению клиента, а
предъявитель на них ретранслятором снимается (шапка `login_lane_paths.go`).

**Почему на Л2 и Л3 держатель — служба, а не край.** Край на этих полосах не знает отметки и узнать
её может только вопросом к службе — а вопрос на каждом предъявлении у него уже есть (разрешение
секрета, сверка токена). Держатель, спрашиваемый на каждом предъявлении, закрывает и выдачу, и
удостоверения, выданные до посадки, и открытые соединения, — ровно класс «контроль на выдаче, но не на
предъявлении» (`.claude/rules/security-hardening.md`). Второй вопрос края о той же отметке был бы
вторым местом об одном предмете.

**Почему «не действует», а не отдельный отказ «подтвердите почту» на Л2 и Л3.** На этих полосах в
положении подтверждения не доступно **ничего** из перечня Р2 службы: экран, письмо и выход — действия
сессии. Полный отказ полосы её существующим значением точен; своё значение край завёл бы без
потребителя. Р3а — другой момент, а не исключение: там предъявление уже прошло (окно кэша), и
отказывает решение о праве; его край произносит значением службы, а не своим.

**После подтверждения** ответ «не действует» пропадает на следующем вопросе края к службе: он
выводится из текущей отметки, а не из записанного отзыва, — удостоверения начинают действовать без
повторной выдачи (Р13 службы). На Л3 это — не позже окна кэша сверки (5 с): отрицательный вердикт
окно тоже держит (§1.8); на Л2 — на следующем разрешении секрета: кэш полосы хранит только
принятое удостоверение (`basic_credential_lane.go:115`).

**Потоки, открытые до посадки,** закрываются перекатом края той же волны: рубеж S1 выкатывается на
стенд не раньше службы (§6 п. 0), и после переката каждое соединение открыто заново под новым
правилом. Кэши края — вердиктов сверки, базового секрета и решений — живут в памяти процесса и тем
же перекатом начинаются пустыми: вердикта, полученного до посадки службы, край после переката не
держит.

### Р17. Человек фикстуры наборов и стенда заводится тем путём, что человек

Посевы наборов newman (`tests/authz-fixtures/`) и посевы стенда делают ровно то, что делает
человек, — и ничего сверх; случаи наборов людей не заводят вовсе (правило ниже):

| шаг | что делает посев | чем утверждает исход |
|---|---|---|
| 1. заведение | `GET /iam/v1/auth/csrf?form=register`, затем `POST /iam/v1/auth/register` с адресом и паролем — на **внешнем** слушателе края, тем путём, что консоль; носитель сессии регистрации — у посева; момент ответа T0 печатается | `200`, носитель в `Set-Cookie`, `session.emailVerified: false` |
| 2. письмо | читает у приёмника писем стенда письмо на этот адрес, принятое **после** T0, и берёт код из его тела | письмо ровно одно; код — 10 знаков алфавита (Р7 службы) |
| 3. подтверждение | `GET /iam/v1/auth/csrf?form=verify-email-confirm` и `POST /iam/v1/auth/verify-email/confirm` с телом `{"code","csrfToken"}` носителем регистрации | `200`, `session.emailVerified: true`, новый носитель в `Set-Cookie` (Р10 службы) |
| 4. утверждение | `GET /iam/v1/auth/me` новым носителем | `session.emailVerified: true`; идентификатор человека — `user.id` этого ответа |

Правила, без которых путь перестаёт быть путём человека:

- **Письма посев не просит.** `POST /iam/v1/auth/verify-email` в его переписи нет: первое письмо
  ставит регистрация той же транзакцией (Р9 службы), и фикстура, просящая письмо, сделала бы
  зелёным продукт, в котором первое письмо не уходит (`gate-authoring` §«фикстура не снисходительнее
  продукта»; то же правило у фикстуры консоли, Р13). Письма нет в срок — посев останавливается
  текстом «условие не создано: письмо подтверждения не дошло до приёмника» с адресом и T0, и
  прогон относит наборы к **«не выполнилось»**, а не к красным (`.claude/rules/e2e-flow.md` §1).
  Служба на своём стенде письмо в этом случае просит (§1.12) — это её посев и её решение.
- **Отказ продукта на шаге, где посев предъявил всё, чего требует контракт, — находка, а не
  «условие не создано»:** регистрация, ответившая не `200` на годный вход, и предъявление кода из
  письма, ответившее не `200`, — вердикт о дереве.
- **Хуком поставщика человек фикстуры не заводится.** Такой человек подтвердить адрес не может
  никогда (§1.13, вывод 1) — это вид, которого у продукта нет. Девять мест §1.13 переходят на
  регистрацию; `prodseed_network.py` без вызывающего переходит либо снимается — третьего исхода нет.
- **Людей заводит только посев; случай набора человека не заводит.** Человек, заведённый шагом
  случая, появлялся бы после переписи людей посева (F6b-51) и не держался бы ничем: случай на
  такой цели зелен при любом её положении. Поэтому место заведения — одно, посев, и перепись
  полна по построению. Случаю, которому нужен свежий человек, его заводит посев видом Ф-п и
  отдаёт слотами окружения: цель выдачи администратора облака — `clusterTargetUserId` и
  `clusterTargetEmail`; шаг `CLUSTER-ADMIN-SEED-TARGET-USER` из `cluster_admin.py` снимается
  (F6b-55). Строка источника случая набора с адресом регистрации или хука — находка гейта (F6b-52).
- **Видов человека фикстуры два, и вид объявлен у места заведения.** **Ф-п** — подтверждённый,
  шаги 1–4; это вид по умолчанию. **Ф-н** — неподтверждённый: шаги 1 и 2 без шага 3; заводится
  только пробой посева, которая утверждает положение подтверждения (F6b-47, F6b-49), и отличается
  от Ф-п ровно предъявлением кода. Третьего вида нет.
- **Идентификаторы — тоже с поверхностей края.** Человек — `user.id` ответа «кто я» (шаг 4; у Ф-н
  — тот же вопрос носителем регистрации); его аккаунт — запись `GET /iam/v1/accounts`, чей
  `ownerUserId` равен этому идентификатору; проект — `GET /iam/v1/projects` с `accountId` этого
  аккаунта и `filter` `name="default"`. У Ф-п спрашивает его носитель B2; у Ф-н — администратор
  стенда, потому что носитель Ф-н получает отказ Р3. Поиск по `external_id` = адрес в хранилище
  службы (`db_lookup`) и ожидание строки человека чтением хранилища снимаются: после регистрации
  внешняя идентичность — субъект своей полосы, а не адрес (§1.15), а ответ «кто я» о человеке
  сам доказывает, что его запись есть.
- **Личный токен человека выпускается после подтверждения**: выпуск клиента администратором
  стенда и обмен подписанного утверждения у нашего издателя — как сегодня (§1.13), субъект — Ф-п.
- **Значения берутся с поверхностей человека:** код — из письма, положение и идентификаторы — из
  ответов края; ни одно не читается из хранилища или очереди службы (§7 инв. 7).
- **Приглашённых людей посевы не заводят** (§1.13, предикат с контролем: строк с адресом глагола
  приглашения в посевах и случаях наборов — ноль).
  Посев, который заведёт приглашённого, идёт путём приглашённого: приглашение распорядителем →
  регистрация приглашённым адресом → письмо → код, и активация — исходом подтверждения (Р10 п. 5,
  Р11 службы).

Чтение приёмника — единственная поверхность посева, которой у человека нет: её место у человека
занимает его почтовый ящик. Она читает то, что служба уже сдала почтовому узлу, и ничего не пишет
службе.

### Р18. Обхода письма нет ни в одной посадке — и отсутствие приёмника его не открывает

1. **Ни глагола, ни ручки, ни посева, ни миграции, помечающих адрес подтверждённым иначе, чем
   предъявлением кода из письма под сессией того же человека.** У службы писатель отметки зовётся
   ровно одним местом — исходом глагола подтверждения; миграции отметку только снимают (§1.12). В
   дереве платформы — посевах, случаях наборов, рецептах стенда, конвейерах, пробах консоли —
   записей отметки ноль (§1.13). Это состояние S4 **закрепляет** гейтом (F6b-52): строка с адресом
   хука поставщика, запись отметки вне службы и строка регистрации в источнике случая набора (Р17)
   — находки дерева платформы; у службы —
   заказ гейта единственного вызывающего писателя (§3.2).
2. **Ни одна из ручек не снимает рубеж.** Ручки «выключить рубеж» нет (Р11); пять ручек
   подтверждения службы задают срок кода, попытки, промежуток, число писем и окно (Р9 службы), и
   шестого ключа с приставкой `verification-` в блоке `authn.login` службы нет (F6b-54).
3. **Приёмник писем стенда поднимается только профилем, который его объявил** (`mailpit.enabled`:
   `values.dev.yaml` и `values.own-stand.yaml`; умолчание `values.yaml` — нет; §1.13), и в боевой посадке его нет —
   там почтовая полоса ведёт во внешний ретранслятор (шапка `templates/mail-receiver.yaml`).
   **Отсутствие приёмника обхода не открывает:** рубеж на месте, и человек остаётся в положении
   подтверждения, пока письмо до него не дойдёт — установка без доставки закрыта для людей, а не
   открыта (Р1 «Цена», Р13 службы: «обходного пути у рубежа нет намеренно»). Посев наборов в боевой
   посадке не исполняется вовсе: первичного удостоверения стенда боевой слой не чеканит («Боевой
   слой чеканку НЕ включает» — `deploy/helm/umbrella/values.own-stand.yaml`, блок чеканки), и людей
   боевой посадки заводят сами люди.

---

## §3 Объём и границы

### §3.1 В объёме

1. **Край (S1, `kacho#2900`):** рубеж адреса в полосе сессии (Р2–Р5), значение отказа (Р3),
   отказ решения с причиной службы тем же значением (Р3а), порядок (Р4), перечень прохода одним
   объявлением, два новых глагола и решение о трёх координатах церемонии (Р5), ответ «кто я» (Р10),
   клетка (Р12), исполнение ответа службы на полосах Л2 и Л3 обеими поверхностями (Р16, F6b-35).
2. **Консоль (S2, `kacho#2898`):** страж над каркасом (Р7), экран `/verification` (Р8) и исходы двух
   глаголов (Р9), новое действие на отказ `EMAIL_NOT_VERIFIED` у обоих читателей поверхности
   `platform` (§1.5), уход после входа и регистрации через стража, а не прямо на адрес возврата.
3. **Набор консоли (S3, консольная часть `kacho#2901`):** посевы П-н и П-п (Р13), фикстура
   регистрации, условие «приёмник писем читается прогоном» (F6b-34), новая проба
   `ui-future/e2e/specs/address-confirmation.spec.ts`.
4. **Посевы наборов newman и стенда (S4, часть `kacho#2901` о наборах и стенде):** человек фикстуры
   заводится регистрацией через край и подтверждается письмом регистрации (Р17) — девять мест §1.13;
   виды Ф-п и Ф-н; идентификаторы человека, аккаунта и проекта — с поверхностей края (§1.15); цель
   случая `cluster_admin` заводит посев и отдаёт слотами (F6b-55); личный токен человека — после
   подтверждения; условие «приёмник писем читается посевом наборов» (F6b-53); гейт дерева платформы
   «людей заводит только посев и только регистрацией, отметка — не вне службы» (Р17, Р18, F6b-52);
   проба рендера боевой посадки (F6b-54); почтовая полоса службы на стенде — якорь сертификата
   приёмника и адрес входа консоли (§1.16, F6b-56).

### §3.2 Вне объёма — с носителем и предикатом возврата по каждой строке

| что | почему не здесь | носитель | чем вернётся |
|---|---|---|---|
| правило службы: её глаголы, вопросы о праве, выдача ролей, приглашение, посев первого администратора облака, форма сессии (регистрация и вход неподтверждённого выдают сессию, ответ о ней — `found = true` с признаком) | предмет службы (Р2) | `PRO-Robotech/kaname#456` | её одобренной приёмкой; условие одобрения этой — §6 п. 1 |
| **значение отказа** Р3 службы — то же, что Р3 здесь, побайтово | значение выбрано службой, край его повторяет | `kaname#456` | её приёмкой; расхождение — находка обеих |
| глагол подтверждения, код, письмо регистрации той же транзакцией, виды формы `verify-email` и `verify-email-confirm` | предмет службы | `kaname#456` (Р6–Р10, Р15 службы) | её пробами (EV-01, EV-20…EV-42) |
| **адрес в письме** — ровно `<происхождение консоли>/verification`, без параметров и фрагмента, тем же источником настройки установки, что адрес входа в письмах службы (`LoginURL`, `internal/clients/invite_mail.go`) | адреса консоли знает консоль; письмо пишет служба | `kaname#456` — производитель **есть** в дереве службы (`invite_mail.go:93, 622` @ `c8559057b`, §1.9); текстом приёмки службы значение не названо | держит F6b-28 на стенде; расхождение дерева службы с F6b-28 — находка обеих |
| **успех запроса письма несёт `Retry-After`** — промежуток до следующего разрешённого письма этому человеку | без срока консоль отсчёта не покажет (Р8), а своего не выдумает | `kaname#456` — производитель **есть** в дереве службы (`loginlanehttp/handler.go:915` @ `c8559057b`, §1.9); строка Р6 службы заголовка не называет | держит F6b-19 на стенде; F6b-20 держит поведение консоли без заголовка |
| **Л3: сверка `POST /internal/tokens/introspect`** отвечает `{"active": false}` на токен, чей владелец — человек с неподтверждённым адресом, по текущей отметке | правило предъявления токена — у службы (`internal/tokenrevocation`, §1.8) | `kaname#456` — **решено** её Р5а (редакция 3) | её сценарием-парой EV-68 «отметка снята → `active: false`», «отметка на месте → `active: true`»; до её посадки F6b-35 держит краевую половину дублёром |
| **реестр — второй спрашивающий ту же сверку** о токене нашей записи издателя (`services/registry/cmd/kacho-registry/tokenverifier.go:48` @ `b7608fe9750`; второй блок издателей в каждом профиле, §1.8) | правило держится по построению: Р5а службы отвечает по отметке, кто бы ни спросил, а о праве судит Р4а службы | держатель — Р5а и Р4а службы (`kaname#456`) | ничем сверх: окно — кэш сверки реестра, его величина, объявленная у реестра; появлением у реестра своего решения о человеке — тем же изменением сюда |
| **полоса записи отзыва** (`IsRevoked` по идентификатору) — токены прочих принятых записей издателя | на каждом стенде принят ровно наш издатель, пустой перечень — отказ старта (§1.8): токен человека к этой полосе не приходит; о праве неподтверждённого человека служба отвечает «нет» под каждым вопросом, через какую бы полосу он ни пришёл (Р4а службы) | — | появлением во всяком профиле второй принятой записи издателя: правило о подтверждённости входит в эту полосу тем же изменением — заказом службе той же отметки на вопросе записи либо отказом края принять вид принципала «человек» от записи, которая не наша |
| **Л2: перепрос живости базового секрета на открытом соединении** (`CheckBasicCredentialLive`) судит ту же отметку, что разрешение секрета | правило — у службы; **решено** строкой Р4в «вне круга» редакции 3 (строка 483) и её деревом (`basic_credential_repo.go:355` @ `c8559057b`) | **заказ сценария** `kaname#456` (`status:test`) | её сценарием на перепросе: «владелец не подтверждён → отказ `owner-unverified`», близнец — «подтверждён → живо» |
| **гейт службы: писатель отметки зовётся одним местом** | сегодня вызывающий один — исход глагола подтверждения (§1.12), но держит это только перепись §1.12 этого документа: DoD службы судит перечни путей, дверей и полос выдачи, а вызывающих писателя отметки не судит | **заказ** `kaname#456` (`status:test`) | её гейтом: вызов писателя отметки вне исхода глагола подтверждения — находка с координатой, законный вызов молчит, пустой обход — отказ гейта |
| доставка письма **в установке продукта** — через внешний ретранслятор (шаги 6–7 порядка работ приёмки ID-MAIL-1) | предмет почтовой полосы; на стенде письмо подтверждения идёт той же очередью и тем же отправителем, что приглашение, к приёмнику стенда (§1.16), и стенд п. 0 §6 этой задачи **не ждёт** — редакция 4 утверждала обратное, перемерено | `PRO-Robotech/kacho#1773` (P3, `blocked`, линия уведомлений) | её посадкой и её приёмкой; условием п. 0 §6 не является. Недостающее на стенде — якорь сертификата приёмника и адрес входа консоли у почтовой полосы службы — заводит S4 (`kacho#2901`, F6b-56), а не эта строка |
| **пять ручек подтверждения службы** в чарте службы внутри зонта и в профилях стенда | предмет стенда; без них служба не стартует (Р9 службы) | `PRO-Robotech/kacho#2901` | подъёмом стенда с пятью ручками; до того стенд п. 0 §6 не существует |
| **посев стенда, заводящий человека с правами администратора облака** | сегодня рецептов стенда, заводящих человека, ноль (§1.13); выдачу администратора облака на адрес посева служба делает только подтверждённому (Р12 службы) | `PRO-Robotech/kacho#2878` (P2) | её приёмкой: человек заводится путём Р17, выдача — согласователем службы на первом проходе после подтверждения; обхода Р18 её посадка не заводит |
| экран восстановления доступа | под-фаза S3 приёмки F8 | приёмка F8 | её собственной приёмкой |
| смена адреса почты | глагола смены адреса нет | — | появлением глагола: снятие отметки при смене держит база (Р1 службы), консоль ответит по F6b-25, край — рубежом Р4 и отказом Р3а (F6b-45), полосы Л2 и Л3 — решением Р5а службы и заказами выше; глагол смены адреса питает поток смены субъекта, сбрасывающий кэш решений края (Р3а), — условие его приёмки |
| **нативная поверхность края** | на ней три полосы (§1.8): Л2 и Л3 — держатель служба (Р16), Л5 личности человека не выставляет; полосы сессии на ней нет по построению — носителя сессии она не читает (§1.2) | — | появлением читателя носителя сессии на нативной поверхности: рубеж Р4 входит туда тем же изменением |
| служебные учётные записи | у них нет адреса и нет сессии человека; их права от подтверждённости адреса завёдшего человека не зависят (Р4 службы), а выпуск новых ключей неподтверждённым человеком закрыт у службы (Р4б и Р5 службы) | — | ничем: предмета нет |
| модули консоли, поднятые отдельно от каркаса (федерация разработки) | не посадка, а режим разработчика | — | ничем |

### §3.3 Затронутые сценарии соседней приёмки F8

Приёмка F8 (`docs/specs/sub-phase-F8-console-identity-ceremony-screens-acceptance.md`, DRAFT,
редакция 3, отпечаток `42b4230012ff99d03a32aaaf0467181dbd780a72427a94b1a7d373c2ebd9afcf`) в ствол
воркспейса **не внесена**: её записи кругов 1–2 лежат на ветке воркспейса
`tooling-docfresh-recognition-boundary` (коммиты `a1598318`, `04b82520`), а сам документ — вне
дерева. Ссылка на неё поэтому ведёт на предмет и отпечаток, а не на объект ствола; ни один
близнец этой приёмки на её сценарии не опирается (§8, I1-8).

Решение владельца сильнее редакции F8, и эти сценарии обязаны быть переписаны её автором — здесь они
не переизлагаются, а называются:

| сценарий F8 | что меняется |
|---|---|
| F8-03 | `/verification` — экран (Р8), а не «такого адреса здесь нет»; сценарий на названную страницу остаётся за `/recovery` |
| F8-04, F8-11, F8-13 | «Дано» — посев **П-п**; для П-н — F6b-13, F6b-17 |
| F8-14 | регистрация уводит на экран подтверждения (F6b-12), а не на панель |
| F8-17 | действие «подтвердить адрес» **есть** — экран Р8; признак на экране регистрации остаётся из ответа глагола |
| F8-20, F8-21 | фикстура регистрации включает подтверждение (Р13, F6b-32) |
| F8-23 … F8-36 | «Дано» — посев **П-п**: экран параметров учётной записи и повышение уровня неподтверждённому недоступны (Р5, Р7) |

F8-39 (на экране входа нет пути на подтверждение адреса) этим документом **не меняется**: экран входа
ссылки на подтверждение не получает — на экран подтверждения человека приводит страж после входа.

### §3.4 Что делает сценарий неисполнимым — и это не красное

Сценарии с посевом **П-п**, **Ф-п**, **Ф-н** или с письмом требуют производителей вне этой
приёмки: глагола подтверждения и письма регистрации (приёмка службы; в дереве службы на голове волны
они есть, §1.12), ретрансляции глаголов подтверждения краем (S1), почтовой полосы службы на
стенде (якорь сертификата приёмника и адрес входа, F6b-56, §1.16) и чтения приёмника прогоном
(F6b-34 — консоли, F6b-53 — посева наборов). Пока любого нет, такой сценарий —
**«не выполнилось»** с названным условием, а не красный (`.claude/rules/e2e-flow.md` §1). Сценарии
S1 с дублёром порта сессии, сценарии S2 уровня компонента и сценарии S4 без стенда (F6b-50 —
самопроверка посева с дублёрами, F6b-52 — гейт дерева, F6b-54 и F6b-56 — рендер) от них не зависят и
краснеют до кода уже сейчас (§6, пп. 2, 3, 5, 9). Цена Р13 названа: F6b-19 ждёт срок, названный
службой, — столько, сколько профиль стенда объявил промежутком.

---

## §4 Сценарии

Преамбула ко всем сценариям:

- **«Дано» строится посевом** Р13 либо, для сценариев уровня края и компонента, **дублёром порта**
  на один вопрос, не снисходительнее настоящей службы: дублёр сессии отвечает теми же тремя исходами
  пары `(found, err)`, что порт `HumanSessionReader`, и полем подтверждённости; дублёр транспорта
  консоли отвечает телами и заголовками, объявленными Р6 и Р9 службы, и никакими иными.
- **«Перепись» — `ceremonyCensus`** (Р6); «обращение к API» и перечень — Р6.
- **Имя пробы начинается с ID сценария.**
- «Путь платформы» в сценариях S1 — каждый из четырёх: `GET /iam/v1/projects`,
  `POST /vpc/v1/networks`, `GET /iam/v1/me`, `GET /subscription/v1/events`.
- «Отказ Р3» — ответ с телом `{"code":7,"message":"email address is not verified","details":[ErrorInfo reason=EMAIL_NOT_VERIFIED, domain=iam.kaname.cloud]}`, статусом `403`, без `WWW-Authenticate` и без `Set-Cookie`.
- «Письмо П-н» — письмо на адрес П-н, принятое приёмником стенда после его регистрации.
- **Ф-п** и **Ф-н** — люди посева наборов (Р17): Ф-п заведён шагами 1–4 Р17, Ф-н — шагами 1–2;
  «перепись посева» — журнал обращений посева к краю и к поверхности чтения приёмника, который посев
  печатает сам, с числом записей.

### S1 — край

**ID:** F6b-01 — **неподтверждённая сессия на пути платформы получает отказ Р3, и запрос дальше края не уходит** (близнец F6b-02, различие — `EmailVerified`)

**Given** дублёр порта сессии отвечает на носитель `found = true`, `EmailVerified = false`, отсечки нет
**And** дублёр следующего звена считает дошедшие до него запросы
**When** клиент с этим носителем обращается к каждому пути платформы
**Then** каждый ответ — отказ Р3
**And** дублёр следующего звена насчитал **ноль** запросов
**And** клетка Р12 выросла на число обращений, остальные клетки полосы не изменились

**ID:** F6b-02 — **подтверждённая сессия на тех же путях проходит дальше** (близнец F6b-01, различие — `EmailVerified`)

**Given** условия F6b-01, но дублёр порта сессии отвечает `EmailVerified = true`
**When** клиент с этим носителем обращается к каждому пути платформы
**Then** ни один ответ не несёт `reason` `EMAIL_NOT_VERIFIED`
**And** дублёр следующего звена насчитал по одному запросу на путь
**And** клетка Р12 не изменилась

**ID:** F6b-03 — **отказ побайтово одинаков, что бы ни стояло в пути** (близнец F6b-02, различие — `EmailVerified`)

**Given** условия F6b-01; уровень — проба края с дублёрами, без настоящего сервера
**When** клиент обращается к `GET /vpc/v1/networks/<id существующей сети>`, к `GET /vpc/v1/networks/<id сети, которой нет>` и к `GET /vpc/v1/networks/не-идентификатор`
**Then** три ответа совпадают побайтово — статус, тело и заголовки, кроме заголовка идентификатора запроса и заголовка `Date`
**And** у подтверждённого близнеца (условия F6b-02) те же три обращения уходят к следующему звену, и отказ Р3 не встречается ни в одном

**ID:** F6b-04 — **перечень прохода: неподтверждённая сессия доходит до шести глаголов, трёх координат церемонии и четырёх путей без записи каталога**

**Given** условия F6b-01
**And** дублёр слушателя выдачи службы отвечает на навигацию церемонии `302` с `Location`, несущим `error=access_denied` и не несущим `code`, на обмен — `400` с телом `{"error":"invalid_grant"}`, на документ обнаружения — `200` (так служба отвечает неподтверждённому, Р5 и Р5б службы, EV-67, EV-77)
**When** клиент с этим носителем обращается к `GET /iam/v1/auth/me`, `POST /oauth/logout`, `GET /healthz`, `GET /readyz`, к шести глаголам формы Р5 (`csrf`, `login`, `logout`, `register`, `verify-email`, `verify-email/confirm`) и к трём координатам церемонии (`GET /iam/v1/authorize` с годными параметрами, `POST /iam/v1/token`, `GET /.well-known/oauth-authorization-server`)
**Then** ни один ответ не несёт `reason` `EMAIL_NOT_VERIFIED`
**And** каждый глагол формы ретранслирован слушателю формы, каждая координата церемонии — слушателю выдачи (дублёры ретрансляции насчитали по одному обращению на запись)
**And** ответы на три координаты церемонии — ответы дублёра выдачи побайтово: `302` с `error=access_denied`, `400 {"error":"invalid_grant"}`, `200`
**And** обращение с тем же носителем к каждому из девяти остальных глаголов формы получает отказ Р3 и службе не ретранслируется
**And** у близнеца — те же девять глаголов **без носителя** — каждый ретранслирован службе: рубеж без носителя сессии не действует

**ID:** F6b-05 — **«кто я» неподтверждённой сессии: человек есть, прав нет, и о правах не спрашивали** (близнец F6b-06, различие — `EmailVerified`)

**Given** условия F6b-01
**And** дублёр вопроса о системном администраторе отвечает «да» и считает вопросы
**When** клиент с этим носителем обращается к `GET /iam/v1/auth/me`
**Then** ответ `200`, `user.id` — субъект сессии, `session.emailVerified` = `false`
**And** `user.permissions` = `[]`
**And** дублёр вопроса о системном администраторе насчитал **ноль** вопросов

**ID:** F6b-06 — **«кто я» подтверждённой сессии называет права, как сегодня** (близнец F6b-05, различие — `EmailVerified`)

**Given** условия F6b-05, но дублёр порта сессии отвечает `EmailVerified = true`
**When** клиент обращается к `GET /iam/v1/auth/me`
**Then** `session.emailVerified` = `true`, `user.permissions` = `["*","admin"]`
**And** дублёр вопроса о системном администраторе насчитал **один** вопрос

**ID:** F6b-07 — **годность сессии решается раньше адреса** (близнец F6b-01, различие — отсечка)

**Given** условия F6b-01
**And** отсечка субъекта не раньше момента аутентификации сессии
**When** клиент с этим носителем обращается к `GET /iam/v1/projects`
**Then** ответ — отказ F4d-22: `401`, текст `session ended; sign in again`, носитель гасится
**And** клетка отсечки выросла на один, клетка Р12 не изменилась

**ID:** F6b-08 — **адрес решается раньше пола уровня: вызова на повышение нет**

**Given** условия F6b-01
**And** путь, к которому обращаются, несёт в каталоге прав пол уровня выше уровня сессии
**When** клиент с этим носителем обращается к этому пути
**Then** ответ — отказ Р3, и заголовка `WWW-Authenticate` с `error="insufficient_user_authentication"` нет
**And** у подтверждённого близнеца того же уровня (условия F6b-02) тот же путь отвечает `401` с этим вызовом

**ID:** F6b-09 — **служба не ответила о сессии: отказ F4d-23, прохода «адрес неизвестен» нет** (близнец F6b-01, различие — ответила ли служба)

**Given** дублёр порта сессии на носитель отвечает ошибкой «не ответила»
**When** клиент с этим носителем обращается к `GET /iam/v1/projects`
**Then** ответ — отказ F4d-23 (`401`, тот же текст, носитель цел), как до этой под-фазы
**And** дублёр следующего звена насчитал ноль запросов

**ID:** F6b-10 — **подтверждение действует без нового входа — новым носителем из ответа подтверждения** (близнец — то же обращение до подтверждения)

**Given** стенд боевой посадки; посевом заведён П-н, его носитель B1 у контекста посева
**And** обращение носителем B1 к `GET /iam/v1/projects` получило отказ Р3
**When** посев предъявляет код письма П-н (`POST /iam/v1/auth/verify-email/confirm` носителем B1) и получает `200` с носителем B2 в `Set-Cookie`
**And** повторяет обращение к `GET /iam/v1/projects` носителем B2
**Then** ответ не несёт `reason` `EMAIL_NOT_VERIFIED`
**And** между двумя обращениями посев не вызывал `POST /iam/v1/auth/login`
**And** обращение прежним носителем B1 — отказ F4d-22: прежний носитель больше не годен (Р10 службы)

**ID:** F6b-11 — **глаголы подтверждения ретранслируются краем и носитель читают**

**Given** объявление записей ретрансляции края
**When** клиент обращается к `POST /iam/v1/auth/verify-email` и к `POST /iam/v1/auth/verify-email/confirm` — (а) с носителем неподтверждённой сессии; (б) без носителя; (в) с носителем при службе, не ответившей о сессии
**Then** в (а) и (б) обращение ретранслировано службе, и ответ — ответ дублёра службы
**And** в (в) ответ — отказ F4d-23 края, и службе обращение не ретранслировано: глагол читает носитель (Р5)
**And** у близнеца — глагола `register` в случае (в) — обращение ретранслировано: регистрация носителя не читает
**And** объявление несёт **18** записей: **15** записей с целью «слушатель формы» совпадают с перечнем, который служба объявляет у своего слушателя формы, дословно, и **3** записи церемонии несут цель «слушатель выдачи»; записи без решения «доступна до подтверждения» среди 18 нет — каждая объявила решение явно

**ID:** F6b-35 — **удостоверение, которому служба отказывает на предъявлении, дальше края не уходит — на обеих поверхностях** (близнец — служба отвечает «действует»)

**Given** уровень — проба края с дублёрами, без настоящего сервера; дублёр следующего звена считает дошедшие до него запросы
**And** Л2: дублёр авторитета базового секрета отвечает на разрешение отказом аутентификации (так служба ответит владельцу-человеку с неподтверждённым адресом, Р5 службы)
**And** Л3: предъявляется токен, подпись которого проверена **записью нашего издателя** (пометка чтения отзыва, §1.8), вид принципала в утверждении — «человек»; дублёр **сверки нашего авторитета** (порт полосы нашего авторитета, `WithPlatformRevocationCheck`) отвечает «не действует» — так сверка ответит `{"active": false}` по Р5а службы; дублёр полосы записи отзыва считает вопросы
**When** клиент предъявляет каждое из двух удостоверений на `GET /iam/v1/projects` по HTTP и на соответствующий метод нативной поверхности
**Then** Л2 по HTTP — `401`, тело `{"code":16,"message":"credential refused"}`, заголовок `WWW-Authenticate: Bearer error="invalid_token", error_description="credential refused"`; Л2 на нативной — `UNAUTHENTICATED`, текст `credential refused`: у базового секрета один текст на обеих поверхностях
**And** Л3 по HTTP — `401`, тело `{"code":16,"message":"token revoked"}`, заголовок `WWW-Authenticate: Bearer error="invalid_token", error_description="token revoked"`; Л3 на нативной — `UNAUTHENTICATED`, текст `authentication failed` — тот же единый текст, что у всякой неудачи подлинности предъявителя на этой поверхности, а не текст отзыва
**And** дублёр следующего звена насчитал **ноль** запросов; дублёр полосы записи отзыва — **ноль** вопросов: о токене нашей записи край спрашивает только сверку
**And** у близнеца — дублёры отвечают «секрет годен» и «действует» — каждое обращение дошло до следующего звена, по одному
**And** поведение края существует до кода, сценарий держит его как опору Р16: существующие пробы края того же предмета зелёные на `499ad3085fd` — `TestF1b09_OurTokenRevocationIsAskedOfOurAuthorityAndFailsClosed` (о нашем токене спрашивается наш авторитет) и `TestF1b12_AuthNRefusalsAreIndistinguishableOnTheNativeSurface` («неудач проверки подлинности предъявлено 5, различимых сообщений 1»)
**And** опоры держат выбор полосы и единство текста, но **не тексты отзыва**: `TestF1b09_…` утверждает для отозванного только коды, а среди пяти неудач `TestF1b12_…` отзыва нет — тексты Л3 держит сам этот сценарий. Сквозной пробы обеих половин после посадки не построить: неподтверждённый человек нашего токена не получает (Р5 службы, EV-65 а; F6b-49), а снять отметку у подтверждённого, получившего токен, нечем — глагола смены адреса нет (§3.2). Сходимость половин держит общий ответ сверки `{"active": false}` — тот же, что у отозванного токена, и край исполняет его одной ветвью

**ID:** F6b-45 — **отказ решения с причиной службы `email_not_verified` — значение Р3, одинаковое для любого объекта** (близнец — та же полоса, причина `no path`)

**Given** уровень — проба края с дублёрами; дублёр следующего звена считает дошедшие до него запросы
**And** дублёр решения по каталогу прав отвечает на **каждый** вопрос `allowed = false`, `deny_reasons = ["email_not_verified"]` — так служба отвечает о неподтверждённом человеке на любой объект (Р4а службы, EV-50)
**And** уровень уверенности обоих удостоверений не ниже пола каждого из путей ниже: сценарий судит отказ решения, а не пол уровня
**And** личность предъявлена по очереди двумя полосами: (а) носитель сессии, дублёр порта сессии отвечает `found = true`, `EmailVerified = true` — отметку сняли между разбором сессии и вопросом о праве (Р3а); (б) токен записи нашего издателя с видом принципала «человек», дублёр сверки отвечает «действует» — вердикт в пределах окна кэша края (Р16)
**When** клиент обращается по HTTP к `POST /vpc/v1/networks` с `projectId` посеянного проекта (запись каталога спрашивает отношение на проекте), к `GET /vpc/v1/networks/<id существующей сети>` и к `GET /vpc/v1/networks/<id сети, которой нет>` — чтению, чей отказ край по каталогу произносит `404` скрытия существования; для (б) — и к тем же методам нативной поверхности
**Then** по HTTP каждый ответ — отказ Р3; в пределах каждого из случаев (а), (б) три ответа совпадают побайтово — статус, тело и заголовки, кроме заголовка идентификатора запроса и `Date`
**And** на нативной — `PERMISSION_DENIED`, текст `email address is not verified`, `ErrorInfo` с `reason` `EMAIL_NOT_VERIFIED` и `domain` `iam.kaname.cloud`
**And** дублёр следующего звена насчитал **ноль** запросов; клетка Р12 не изменилась
**And** у близнеца — дублёр решения отвечает `deny_reasons = ["no path"]` — ответы как до этой под-фазы: `403` с `reason` `AUTHZ_DENIED` на `POST /vpc/v1/networks` и `404` на обоих чтениях сети; отказа Р3 нет ни в одном
**And** пути, чей список край не судит, а сужает служба (запись каталога `scope_filtered`, например `GET /iam/v1/projects`), в этот сценарий не входят: вопроса о праве на них край не задаёт, и входа у Р3а там нет

### S2 — консоль

**ID:** F6b-12 — **регистрация ведёт на экран подтверждения, а не в консоль, и письма консоль не шлёт** (близнеца по регистрации нет **по построению**: регистрация отметки не ставит, Р6 службы; различие «подтверждён ли адрес» строится на входе — F6b-13 против F6b-14)

**Given** стенд боевой посадки; адрес `e2e-<метка>@kacho.local` в службе не заведён
**When** браузер открывает `/registration?returnTo=/dashboard`, заполняет адрес и пароль и отправляет форму
**Then** адрес страницы стал `/verification?returnTo=%2Fdashboard`
**And** на экране — заголовок «Подтвердите адрес почты» и адрес `e2e-<метка>@kacho.local`
**And** обращения к API в переписи лежат в перечне Р6; `GET /iam/v1/me`, `GET /iam/v1/accounts` и `POST /iam/v1/auth/verify-email` среди них нет

**ID:** F6b-13 — **вход неподтверждённого ведёт на экран подтверждения с адресом возврата** (близнец F6b-14, различие — отметка)

**Given** стенд боевой посадки; посевом заведён П-н (носитель у посева, не у браузера)
**When** браузер открывает `/login?returnTo=/settings`, вводит адрес и пароль П-н и отправляет форму
**Then** адрес страницы стал `/verification?returnTo=%2Fsettings`
**And** обращения к API в переписи лежат в перечне Р6
**And** рейла каркаса на экране нет

**ID:** F6b-14 — **вход подтверждённого ведёт на адрес возврата, в обычную консоль** (близнец F6b-13, различие — отметка)

**Given** условия F6b-13, но посевом заведён П-п
**When** браузер проходит тот же вход с тем же адресом возврата
**Then** адрес страницы стал `/settings`, каркас с рейлом отрисован
**And** перепись содержит обращение каркаса `GET /iam/v1/accounts` (§1.5) — то самое, которого у F6b-13 нет

**ID:** F6b-15 — **любой адрес консоли у неподтверждённой сессии ведёт на экран подтверждения** (близнец F6b-16, различие — отметка)

**Given** стенд боевой посадки; посевом заведён П-н, носитель перенесён в браузер (`transferSession`)
**When** браузер открывает каждый адрес из перечня: `/`, `/dashboard`, `/projects/<id>/vpc/networks`, `/projects/<id>/compute`, `/iam/`, `/system/`, `/settings`, `/recovery`, `/такого-адреса-нет` (`<id>` — любой идентификатор проекта: страж решает раньше, чем каркас его прочтёт)
**Then** для каждого адрес страницы стал `/verification?returnTo=<этот адрес в процентной кодировке>`, кроме `/` — для него `returnTo` отсутствует
**And** на экране — заголовок «Подтвердите адрес почты»
**And** обращения к API в переписи по каждому адресу лежат в перечне Р6

**ID:** F6b-16 — **подтверждённая сессия на тех же адресах получает то же, что до этой под-фазы** (близнец F6b-15, различие — отметка)

**Given** условия F6b-15, но посевом заведён П-п
**When** браузер открывает каждый адрес того же перечня
**Then** ни один не приводит на `/verification`
**And** адреса каркаса отрисованы в каркасе; `/recovery` отвечает названной страницей «такого адреса здесь нет»; `/такого-адреса-нет` уводит на `/dashboard`

**ID:** F6b-17 — **экран входа при живой неподтверждённой сессии формы не показывает и ведёт на экран подтверждения** (близнец — тот же экран при живой подтверждённой сессии, различие — отметка)

**Given** условия F6b-15
**When** браузер открывает `/login?returnTo=/dashboard`
**Then** формы входа на экране нет
**And** адрес страницы стал `/verification?returnTo=%2Fdashboard`
**And** у близнеца — условия F6b-16 (П-п) — формы входа нет, и адрес страницы стал `/dashboard`

**ID:** F6b-18 — **вид экрана подтверждения и его обращения при открытии**

**Given** условия F6b-15
**When** браузер открывает `/verification`
**Then** на экране: заголовок «Подтвердите адрес почты»; текст «Чтобы продолжить работу в консоли, подтвердите адрес <адрес П-н>: введите код из письма, отправленного на этот адрес.»; строка «Письмо с кодом приходит после регистрации. Если письма нет или код не подходит, отправьте новое.»; поле «Код из письма»; кнопки «Подтвердить», «Отправить новое письмо», «Выйти»
**And** рейла, разделов и переключателя проекта на экране нет; кнопки «Продолжить» нет
**And** обращения к API в переписи лежат в множестве {`GET /iam/v1/auth/me`, `GET /iam/v1/auth/csrf`}, и `GET /iam/v1/auth/me` среди них есть — ни одного `POST`

**ID:** F6b-19 — **новое письмо после промежутка: запрос, текст, отсчёт из ответа службы, прежний код вытеснен**

**Given** условия F6b-15; приёмник писем стенда читается прогоном (F6b-34); письмо П-н с кодом K1 прочитано
**And** посев своим контекстом спросил `POST /iam/v1/auth/verify-email`, получил `429` с `Retry-After: N` и выждал ровно N (Р13). Исход этой пробы посева **утверждается**: ответ, отличный от `429` с `Retry-After`, — «условие не создано: проба промежутка получила <статус и тело>», и сценарий относится к «не выполнилось», а не к красным (`200` сам поставил бы письмо и открыл новый промежуток — Дано было бы не тем)
**When** человек нажимает «Отправить новое письмо»
**Then** перепись содержит `GET /iam/v1/auth/csrf?form=verify-email` и `POST /iam/v1/auth/verify-email` с телом `{"csrfToken":…}` без поля `email`; ответ `200`, тело `{}`, заголовок `Retry-After: M`, M ≥ 1 (производитель заголовка — дерево службы, §1.9)
**And** на экране — «Письмо с новым кодом отправлено на <адрес П-н>. Прежний код больше не действует.» и «Отправить новое письмо можно через M с»
**And** кнопка закрыта, и нажатие клавиши ввода второго `POST /iam/v1/auth/verify-email` не выпускает — это утверждается переписью сразу после нажатия, без ожидания M
**And** у приёмника есть письмо на адрес П-н, принятое после нажатия, с кодом K2 ≠ K1; K1, введённый в поле, даёт отказ `401` (F6b-24), K2 не вводится — его предъявление держит F6b-23

**ID:** F6b-20 — **ответ без `Retry-After` отсчёта не получает** (близнец F6b-19, различие — заголовок в ответе)

**Given** экран подтверждения собран с дублёром транспорта, отвечающим на `POST /iam/v1/auth/verify-email` `200` с телом `{}` без заголовка `Retry-After`
**When** человек нажимает «Отправить новое письмо»
**Then** на экране «Письмо с новым кодом отправлено на <адрес>. Прежний код больше не действует.», текста отсчёта нет
**And** кнопка открыта сразу

**ID:** F6b-21 — **новое письмо сразу после регистрации: отказ по частоте, текст службы дословно и её срок** (близнец F6b-19, различие — истёк ли промежуток после письма регистрации)

**Given** условия F6b-15, П-н заведён только что: промежуток, открытый письмом регистрации (Р15), не истёк
**And** это утверждается, а не предполагается: посев печатает момент T0 ответа своей регистрации, проба — момент T1 нажатия, и T1 − T0 меньше промежутка, объявленного профилем стенда для ручки промежутка службы (`authn.login.verification-resend-interval`, профиль — `kacho#2901`). Иначе — «условие не создано: промежуток истёк до нажатия» с обоими моментами, и сценарий относится к «не выполнилось», а не к красным
**When** человек нажимает «Отправить новое письмо»
**Then** ответ `429`, `code` `8`, `reason` `TOO_MANY_ATTEMPTS`, с `Retry-After: N`, N ≥ 1
**And** на экране — `message` ответа дословно и «Отправить новое письмо можно через N с»; кнопка закрыта
**And** текста «Письмо с новым кодом отправлено» на экране нет, и нового письма на адрес П-н у приёмника нет

**ID:** F6b-22 — **выход с экрана подтверждения**

**Given** условия F6b-15
**When** человек нажимает «Выйти»
**Then** перепись содержит `GET /iam/v1/auth/csrf?form=logout` и `POST /iam/v1/auth/logout`
**And** печенья сессии у браузера нет, адрес страницы — экран входа
**And** открытие `/dashboard` после этого идёт как у анонимного вызова до этой под-фазы; открытие `/verification` уводит на `/login` (Р7)

**ID:** F6b-23 — **код из письма, введённый на экране, ведёт на адрес возврата в обычную консоль**

**Given** условия F6b-15; браузер на `/verification?returnTo=%2Fdashboard`; письмо П-н прочитано
**When** человек вводит код письма и нажимает «Подтвердить»
**Then** перепись содержит `GET /iam/v1/auth/csrf?form=verify-email-confirm` и `POST /iam/v1/auth/verify-email/confirm` с телом `{"code":"<код письма>","csrfToken":…}`; ответ `200`, `session.emailVerified: true`, в `Set-Cookie` — новый носитель
**And** адрес страницы стал `/dashboard`, каркас отрисован; новый `GET /iam/v1/auth/me` в переписи несёт `emailVerified: true`
**And** формы входа между нажатием и каркасом не было

**ID:** F6b-24 — **неверный код оставляет на экране, текст службы дословно** (близнец F6b-23, различие — значение кода)

**Given** условия F6b-23, но в поле введено значение той же длины и алфавита, которого служба не выдавала
**When** человек нажимает «Подтвердить»
**Then** ответ `401`, `code` `16`; на экране — `message` ответа дословно и «Проверьте код или отправьте новое письмо.»
**And** адрес страницы не изменился; после ответа в переписи — один новый `GET /iam/v1/auth/me`, и сессия в нём есть
**And** последующее открытие `/dashboard` ведёт на экран подтверждения

**ID:** F6b-25 — **отказ края `EMAIL_NOT_VERIFIED` на обращении платформы ведёт на экран подтверждения** (близнец F6b-26, различие — `reason`)

**Given** стенд боевой посадки; посевом заведён второй человек П-н, и обращение его носителем к `GET /iam/v1/projects` получило отказ Р3 — **байты этого ответа сняты с настоящего края** и сохранены
**And** посевом заведён П-п, носитель в браузере; открыт `/projects/<id>/vpc/networks`
**And** ответ на ближайшее чтение списка сетей подменён снятыми байтами — подменяется ровно одно обращение
**When** страница выпускает это чтение
**Then** адрес страницы стал `/verification?returnTo=%2Fprojects%2F<id>%2Fvpc%2Fnetworks`
**And** после перехода обращений к API сверх перечня Р6 нет
**And** это же действие выбирают оба читателя поверхности `platform` (§1.5) — проба уровня компонента на каждом

**ID:** F6b-26 — **отказ края по каталогу прав на той же странице никуда не уводит** (близнец F6b-25, различие — `reason`)

**Given** условия F6b-25, но подменяющие байты сняты с настоящего отказа края по каталогу прав: носитель П-п, мутация в проекте другого посеянного арендатора (`403`, `reason` `AUTHZ_DENIED`)
**When** страница выпускает это чтение
**Then** адрес страницы не изменился, отказ показан на странице
**And** перехода на `/verification` нет

**ID:** F6b-27 — **письмо открыто там, где сессии нет: вход, затем код, затем консоль**

**Given** стенд боевой посадки; посевом заведён П-н, его носитель B1 у посева; письмо П-н прочитано, адрес экрана взят из письма
**And** у браузера нет печенья сессии
**When** браузер открывает адрес экрана из письма
**Then** адрес страницы стал `/login`; `POST` в переписи нет
**When** человек входит адресом и паролем П-н
**Then** адрес страницы — `/verification`, экран подтверждения
**When** человек вводит код письма и нажимает «Подтвердить»
**Then** ответ `200`; адрес страницы — корень консоли в каркасе
**And** обращение посева прежним носителем B1 к `GET /iam/v1/projects` — отказ F4d-22: прочие сессии человека сняты подтверждением (Р10 службы)

**ID:** F6b-28 — **адрес из письма кода не несёт, и его открытие ничего не подтверждает** (близнец F6b-27, различие — введён ли код)

**Given** условия F6b-27
**When** приёмник отдаёт тело письма П-н
**Then** каждый адрес в теле письма равен `<происхождение консоли>/verification` — без `?` и без `#` (число адресов печатается и не ноль)
**When** браузер открывает этот адрес, человек входит адресом и паролем П-н и кода не вводит
**Then** `POST /iam/v1/auth/verify-email/confirm` в переписи нет
**And** адрес страницы — `/verification`; открытие `/dashboard` ведёт на экран подтверждения

**ID:** F6b-29 — **код другого человека в сессии этого браузера не подтверждает никого** (близнец F6b-23, различие — чей код)

**Given** стенд боевой посадки; посевом заведены П-н1 и П-н2; носитель П-н2 перенесён в браузер; письмо П-н1 прочитано
**When** браузер на `/verification`, человек вводит код из письма П-н1 и нажимает «Подтвердить»
**Then** ответ `401`, `code` `16`; на экране — `message` ответа дословно; адрес страницы не изменился
**And** `GET /iam/v1/auth/me` браузера несёт `user.email` П-н2 и `emailVerified: false`
**And** обращение носителем посева П-н1 к `GET /iam/v1/projects` — отказ Р3: адрес П-н1 не подтверждён
**And** у близнеца — код из письма П-н2 в том же браузере — ответ `200` и каркас (F6b-23)

**ID:** F6b-30 — **сессия снята подтверждением в другом месте: экран уводит на вход** (близнец F6b-24, различие — жива ли сессия)

**Given** стенд боевой посадки; посевом заведён П-н (сессия S1, носитель у посева); браузер вошёл адресом и паролем П-н (сессия S2) и стоит на `/verification`
**And** посев предъявил код письма П-н в S1 и получил `200`: S2 снята (Р10 службы)
**When** в браузере человек — (а) вводит любой код и нажимает «Подтвердить»; (б) нажимает «Отправить новое письмо»
**Then** в обоих случаях ответ глагола `401`, `code` `16`; следующий `GET /iam/v1/auth/me` — «сессии нет»
**And** адрес страницы стал `/login`
**And** вход адресом и паролем П-н ведёт в каркас, экрана подтверждения нет

**ID:** F6b-31 — **неизвестная подтверждённость каркаса не открывает** (близнец — ответ с `emailVerified: true`)

**Given** страж консоли собран с дублёром транспорта; ответ `GET /iam/v1/auth/me` — человек без объекта `session` (случай «а»), человек с `session` без поля `emailVerified` (случай «б»), ответ не `2xx` (случай «в»)
**When** консоль открывает `/dashboard`
**Then** в случаях «а» и «б» — страница с текстом «Не удалось узнать, подтверждён ли адрес: край не назвал это в ответе о сессии»; в случае «в» — страница с текстом `UNKNOWN_SESSION_TEXT`; во всех трёх — кнопки «Проверить снова» и «Выйти»
**And** ни в одном случае дублёр не получил обращений сверх перечня Р6, и перехода на экран входа нет
**And** у близнеца — ответ с `session.emailVerified: true` — каркас отрисован, и дублёр получил обращение каркаса `GET /iam/v1/accounts`

**ID:** F6b-36 — **адрес возврата чужого происхождения на `/verification` отвергнут: после подтверждения — корень консоли** (близнец F6b-23, различие — значение `returnTo`)

**Given** условия F6b-23, но браузер на `/verification?returnTo=<значение>`, и значение принимает по очереди каждое из четырёх (для каждого — свой посев П-н):
  - `https://evil.example/dashboard` — абсолютный адрес чужой власти
  - `//evil.example/dashboard` — протокол-относительный
  - `/\evil.example/dashboard` — с обратной косой, которую браузер нормализует в двойную
  - `javascript:alert(1)` — схема не из `http`/`https`
**When** человек вводит код письма и нажимает «Подтвердить»
**Then** на каждом из четырёх ответ `200`, и документ ушёл на корень консоли, а не на присланный адрес
**And** происхождение страницы после перехода равно происхождению консоли
**And** у близнеца `returnTo=/dashboard` (F6b-23) документ уходит именно туда — отрицание не тождественно

**ID:** F6b-37 — **после подтверждения край не ответил о сессии: страница «неизвестно», второго предъявления нет** (близнец — край ответил «подтверждён»)

**Given** экран подтверждения и страж собраны с дублёром транспорта; `POST /iam/v1/auth/verify-email/confirm` отвечает `200` с `session.emailVerified: true`; следующий `GET /iam/v1/auth/me` отвечает не `2xx`
**When** человек нажимает «Подтвердить»
**Then** документ ушёл на адрес возврата, и на нём — страница стража с текстом `UNKNOWN_SESSION_TEXT` и кнопками «Проверить снова» и «Выйти»; перехода на экран входа нет
**And** дублёр получил ровно **один** `POST /iam/v1/auth/verify-email/confirm`
**When** дублёр начинает отвечать на `GET /iam/v1/auth/me` сессией с `emailVerified: true`, и человек нажимает «Проверить снова»
**Then** каркас отрисован; новых `POST` дублёр не получил
**And** у близнеца — первый же `GET /iam/v1/auth/me` отвечает `emailVerified: true` — каркас отрисован без страницы «неизвестно»

**ID:** F6b-38 — **отвергнутый признак формы: один свежий признак, повторяет человек** (близнец — признак принят с первого нажатия)

**Given** экран подтверждения собран с дублёром транспорта; первое обращение каждого глагола отвечает `403`, `code` `7`, `reason` `FORM_TOKEN_REJECTED`, второе — успехом
**When** человек нажимает (а) «Подтвердить» с кодом; (б) «Отправить новое письмо»
**Then** после отказа дублёр получил ровно **один** новый `GET /iam/v1/auth/csrf` вида (а) `verify-email-confirm`, (б) `verify-email`, и ни одного повторного `POST` без нового нажатия
**When** человек нажимает ту же кнопку снова
**Then** второй `POST` несёт новый признак; исход — (а) уход на адрес возврата, (б) текст об отправленном письме
**And** у близнеца — первое обращение отвечает успехом — исход наступает после первого нажатия, лишнего `GET /iam/v1/auth/csrf` нет

**ID:** F6b-39 — **консоль попыток не считает и своей блокировки не заводит** (близнец — верный код с первой попытки)

**Given** экран подтверждения собран с дублёром транспорта; `POST /iam/v1/auth/verify-email/confirm` шесть раз подряд отвечает `401`, `code` `16`, `authentication failed` (так служба отвечает и на код, истраченный пределом попыток, — Р7 службы), а `GET /iam/v1/auth/me` — живой неподтверждённой сессией
**When** человек шесть раз вводит код и нажимает «Подтвердить»
**Then** дублёр получил ровно шесть `POST`, по одному на нажатие, и после каждого — один `GET /iam/v1/auth/me`; после каждого — текст службы дословно и «Проверьте код или отправьте новое письмо.»
**And** кнопка «Подтвердить» и поле открыты после шестого ответа; текста о числе оставшихся попыток на экране нет
**And** у близнеца — первый ответ `200` — документ уходит на адрес возврата после первого нажатия

**ID:** F6b-40 — **главный путь: регистрация → письмо без нажатия → код → обычная консоль**

**Given** стенд боевой посадки; приёмник писем читается прогоном (F6b-34); адрес `e2e-<метка>@kacho.local` в службе не заведён
**When** браузер открывает `/registration?returnTo=/dashboard` и регистрируется этим адресом
**Then** адрес страницы — `/verification?returnTo=%2Fdashboard`
**And** у приёмника — **ровно одно** письмо на этот адрес, принятое после регистрации, с кодом из 10 знаков, и в переписи браузера нет `POST /iam/v1/auth/verify-email`: первое письмо поставила регистрация (Р15)
**When** человек вводит код этого письма и нажимает «Подтвердить»
**Then** адрес страницы — `/dashboard`, каркас отрисован; `GET /iam/v1/auth/me` несёт `emailVerified: true`
**And** пароль второй раз не вводился

**ID:** F6b-41 — **отвергнутая регистрация письма не ставит** (близнец F6b-40, различие — исход регистрации)

**Given** условия F6b-40
**When** браузер отправляет форму регистрации этим адресом с паролем, не отвечающим правилу службы, — отказ `400`, `code` `3`, поле `password`
**And** затем отправляет ту же форму с годным паролем
**Then** у приёмника на этот адрес — **ровно одно** письмо, и принято оно после второй, успешной регистрации
**And** адрес страницы после второй отправки — `/verification?returnTo=%2Fdashboard`

**ID:** F6b-42 — **адрес уже подтверждён: экран уводит на адрес возврата** (близнец F6b-24, различие — `reason` ответа)

**Given** экран подтверждения на `/verification?returnTo=%2Fdashboard` собран с дублёром транспорта; ответ глагола — `400`, `code` `9`, `reason` `EMAIL_ALREADY_VERIFIED` (так отвечает служба, когда адрес подтвердили, например, в другой вкладке того же браузера, — Р15 службы)
**When** человек нажимает (а) «Подтвердить» с кодом; (б) «Отправить новое письмо»
**Then** в обоих случаях документ ушёл на `/dashboard`
**And** у близнеца — ответ `401`, `code` `16` (F6b-24) — адрес страницы не изменился

**ID:** F6b-43 — **прочие отказы показываются дословно, и ничего не повторяется само** (близнец — успех того же обращения)

**Given** экран подтверждения собран с дублёром транспорта
**When** человек нажимает «Подтвердить», а ответ — (а) `400`, `code` `3`, `code: required` при пустом поле; (б) `503`, `code` `14`, `request not performed; try again later`; (в) ответа нет — соединение оборвано; и то же для «Отправить новое письмо» в случаях (б) и (в)
**Then** в (а) обращение ушло с пустым `code` — консоль своей проверки поля не делает — и на экране текст службы `code: required` дословно (привязать его к полю машинно нечем: `details` у этого отказа пуст, Р6 службы); в (б) — текст службы дословно; в (в) — `UNKNOWN_SESSION_TEXT`
**And** ни в одном случае дублёр не получил второго `POST` без нового нажатия; адрес страницы не изменился
**And** у близнеца — ответ `200` — исход Р9 наступает после первого нажатия

**ID:** F6b-44 — **негодное приглашение: текст службы дословно, адрес не меняется, выход — «Выйти»** (близнец F6b-42, различие — `reason` ответа)

**Given** экран подтверждения на `/verification?returnTo=%2Fdashboard` собран с дублёром транспорта; `POST /iam/v1/auth/verify-email/confirm` отвечает `400`, `code` `9`, `message` `invite is no longer valid; ask an account administrator to invite again`, `ErrorInfo` с `reason` `INVITE_NOT_VALID` — так служба отвечает приглашённому, чьё приглашение истекло или снято, когда код подошёл (Р6, Р11 п. 4 службы; EV-73, EV-75)
**When** человек вводит код и нажимает «Подтвердить»
**Then** на экране — `message` ответа дословно; строки «Проверьте код или отправьте новое письмо.» нет
**And** адрес страницы не изменился; дублёр не получил ни второго `POST` без нового нажатия, ни `GET /iam/v1/auth/me` после ответа — вопрос «кто я» экран задаёт только на `401` (Р9)
**And** поле, «Подтвердить», «Отправить новое письмо» и «Выйти» открыты; текста о числе попыток нет
**When** человек нажимает «Выйти»
**Then** дублёр получил `GET /iam/v1/auth/csrf?form=logout` и `POST /iam/v1/auth/logout` — тот же выход, что F6b-22
**And** у близнеца — тот же ответ `400` / `9` с `reason` `EMAIL_ALREADY_VERIFIED` (F6b-42) — документ ушёл на `/dashboard`
**And** контроль решения по `reason`: ответ `400` / `9` с `reason`, которого таблица Р9 не называет, — текст дословно, адрес не изменился, второго `POST` нет (действие «показать», §1.5)

### S3 — набор

**ID:** F6b-32 — **фикстура регистрации набора отдаёт человека с подтверждённым адресом тем же путём, что F6b-40**

**Given** стенд боевой посадки; приёмник писем читается прогоном (F6b-34)
**When** фикстура `register` заводит человека
**Then** её перепись содержит `POST /iam/v1/auth/register`, переход документа на `/verification` и `POST /iam/v1/auth/verify-email/confirm` с кодом письма, принятого после регистрации
**And** её перепись **не** содержит `POST /iam/v1/auth/verify-email`
**And** по её завершении ответ `GET /iam/v1/auth/me` браузера несёт `emailVerified: true`
**And** если письмо не дошло до приёмника в срок, фикстура падает текстом «условие не создано: письмо подтверждения не дошло до приёмника», и прогон относит пробу к «не выполнилось», а не к красным

**ID:** F6b-33 — **посев П-н оставляет адрес неподтверждённым** (близнец F6b-32, различие — предъявлен ли код)

**Given** стенд боевой посадки
**When** посев `seedHuman` заводит человека
**Then** ответ `GET /iam/v1/auth/me` с носителем посева несёт `emailVerified: false`
**And** обращение этим носителем к `GET /iam/v1/projects` получает отказ Р3

**ID:** F6b-34 — **условие «приёмник писем читается прогоном» создаётся шагом и проверяется до проб** (близнец — шаг не исполнен)

**Given** прогон консоли на поднятом стенде
**When** исполняется предусловие чтения приёмника
**Then** оно печатает адрес поверхности чтения и число прочитанных писем, и исход «условие создано»
**And** у близнеца — поверхность не отвечает — предусловие печатает «условие не создано: приёмник писем не читается» с адресом, и каждая проба, которой оно нужно, получает «не выполнилось» с тем же текстом, а не красное

### S4 — посевы наборов newman и стенда

**ID:** F6b-46 — **посев наборов заводит человека регистрацией через край и подтверждает адрес письмом регистрации** (близнец F6b-47, различие — предъявлен ли код)

**Given** стенд боевой посадки, поднятый рецептом наборов (`make -C deploy dev-up`, §1.13); приёмник писем читается посевом (F6b-53)
**And** адрес `prodseed-<вид>-<метка прогона>@example.com` в службе не заведён
**When** посев заводит человека вида Ф-п
**Then** перепись посева содержит по порядку: `GET /iam/v1/auth/csrf?form=register`; `POST /iam/v1/auth/register` → `200`, носитель B1 в `Set-Cookie`, `session.emailVerified: false`; чтение приёмника; `GET /iam/v1/auth/csrf?form=verify-email-confirm` носителем B1; `POST /iam/v1/auth/verify-email/confirm` носителем B1 с телом `{"code":"<код письма>","csrfToken":…}` → `200`, `session.emailVerified: true`, носитель B2 в `Set-Cookie`; `GET /iam/v1/auth/me` носителем B2 → `session.emailVerified: true`
**And** у приёмника на этот адрес — **ровно одно** письмо, принятое после ответа регистрации, и предъявленный код — код из его тела
**And** в переписи посева нет `POST /iam/v1/auth/verify-email`; перепись видит обращения к краю и к поверхности чтения приёмника, и только их — отсутствие обращения к хуку поставщика и записи отметки в посеве держит не она, а гейт дерева F6b-52
**And** обращение носителем B2 к `GET /iam/v1/projects` не несёт `reason` `EMAIL_NOT_VERIFIED`
**And** идентификатор человека в выходе посева равен `user.id` ответа «кто я» носителем B2, а идентификатор его аккаунта — записи `GET /iam/v1/accounts` носителем B2, чей `ownerUserId` равен ему (Р17)

**ID:** F6b-47 — **Ф-н: тот же посев без предъявления кода оставляет адрес неподтверждённым** (близнец F6b-46, различие — предъявлен ли код)

**Given** условия F6b-46
**When** посев заводит человека вида Ф-н — те же обращения по чтение приёмника включительно, без предъявления кода
**Then** `GET /iam/v1/auth/me` носителем B1 → `session.emailVerified: false`
**And** обращение носителем B1 к `GET /iam/v1/projects` — отказ Р3
**And** у приёмника на этот адрес — ровно одно письмо, принятое после ответа регистрации: Ф-н отличается от Ф-п только тем, что код не предъявлен

**ID:** F6b-48 — **личный токен подтверждённого человека выдаётся и принимается краем** (близнец F6b-49, различие — предъявлен ли код)

**Given** условия F6b-46; посевом заведён Ф-п H и, как сегодня у субъекта личного токена, получил роль администратора своего аккаунта (§1.13)
**When** посев выпускает H личный токен — выпуск клиента администратором стенда и обмен подписанного утверждения клиента у нашего издателя (`POST /iam/v1/token`)
**Then** обмен — `200`, в теле — токен доступа
**And** предъявление этого токена краю на `GET /iam/v1/accounts` — `200`, а не отказ полосы предъявителя
**And** слот окружения `jwtUserTokenPlatformIssuer` несёт этот токен, а `userTokenPlatformUserId` — идентификатор H

**ID:** F6b-49 — **владелец личного токена не подтверждён: обмен отвергнут, токена нет** (близнец F6b-48, различие — предъявлен ли код)

**Given** условия F6b-48, но H заведён видом Ф-н
**When** посев выпускает H личный токен тем же путём
**Then** выпуск клиента администратором стенда проходит, а обмен утверждения — `401`, тело `{"error":"invalid_client"}`, токена доступа нет (Р5 службы, EV-65 а)
**And** это исход сценария, а не посева наборов: субъект личного токена в посеве наборов — всегда Ф-п (Р17), и сценарий исполняется своей пробой посева на том же стенде

**ID:** F6b-50 — **письма нет в срок — посев останавливается «условием не создано» и письма сам не просит** (близнец F6b-46, различие — дошло ли письмо)

**Given** уровень — самопроверка посева без стенда: дублёр края отвечает на регистрацию `200` с носителем и `session.emailVerified: false` и считает обращения; дублёр поверхности чтения приёмника отвечает по случаю
**And** случаи: (а) письмо на этот адрес с кодом, принятое после ответа регистрации, есть; (б) письма на этот адрес нет до конца ожидания; (в) письмо есть, а дублёр края на предъявление кода отвечает `401`, `code` `16`
**When** посев заводит человека вида Ф-п
**Then** в (б) посев завершается исходом «условие не создано: письмо подтверждения не дошло до приёмника» с адресом и моментом T0; дублёр края не получил ни `POST /iam/v1/auth/verify-email`, ни `POST /iam/v1/auth/verify-email/confirm`; прогон относит наборы к «не выполнилось»
**And** в (в) посев завершается **находкой** — продукт отказал на коде из письма — с адресом и ответом края, а не «условием не создано»
**And** у близнеца (а) дублёр края получил ровно одно предъявление, и код в нём — код из письма дублёра приёмника

**ID:** F6b-51 — **перепись людей посева: каждый заведён регистрацией и объявлен видом, каждый Ф-п подтверждён** (близнец — инъекция Ф-п без шага подтверждения)

**Given** стенд F6b-46; посев наборов завершился
**When** посев печатает перепись людей
**Then** она называет число заведённых людей N, из них Ф-п — M и Ф-н — U; N = M + U, N ≠ 0; у каждого — адрес, вид и ответ «кто я» после заведения: `emailVerified: true` у каждого Ф-п и `false` у каждого Ф-н
**And** у каждого человека перепись называет место заведения — файл и строку посева — и слоты окружения, которыми он отдан наборам; цель случая `cluster_admin` в ней — Ф-п со слотами `clusterTargetUserId` и `clusterTargetEmail` (F6b-55); места заведения вне посева нет по построению (Р17), и держит это гейт F6b-52
**And** у близнеца — посев, у одного Ф-п которого шаг 3 Р17 вынут, — посев завершается находкой с адресом этого человека: «объявлен Ф-п, `emailVerified: false`», и наборы не начинаются

**ID:** F6b-52 — **гейт дерева платформы: людей наборов заводит только посев и только регистрацией, отметка — не вне службы** (близнец — строка регистрации в посеве, законное место заведения)

**Given** дерево платформы; обход — шесть каталогов, каждый существует на голове волны (§1.14): `tests/`, `gateway/tests/`, `services/*/tests/`, `ui-future/e2e/`, `deploy/`, `.github/`
**And** единица осмотра — отслеживаемый текстовый файл; единица находки — **строка файла** (§1.14)
**When** исполняется гейт
**Then** он печатает число осмотренных файлов по каждому из шести каталогов; каталог обхода с нулём осмотренных — отказ гейта, а не зелёное
**And** находка — строка любого из трёх видов, с файлом и номером строки: (1) строка, несущая адрес хука поставщика в одной из двух форм — `InternalUserService/UpsertFromIdentity` или `users:upsertFromIdentity`, — где бы в обходе она ни стояла: объявление адреса, сегмент пути и строка сценария, задающая адрес запроса перед отправкой, — находки наравне; (2) строка вне дерева службы, пишущая колонку отметки (`email_verified_at`) либо зовущая её писателя (`MarkEmailVerified`); (3) строка источника случая набора newman (`gateway/tests/newman/`, `services/*/tests/newman/`), несущая адрес регистрации `/iam/v1/auth/register`
**And** на голове волны до кода гейт красный, и его вывод — вывод §1.14: осмотрено файлов 27 · 10 · 263 · 63 · 390 · 54; находок **шесть**, все вида (1), в четырёх файлах — `tests/authz-fixtures/prodseed_matrix.py:191`, `tests/authz-fixtures/prodseed_network.py:77`, `gateway/tests/newman/cases/cluster_admin.py:322`, `gateway/tests/newman/collections/cluster_admin.postman_collection.json:538`, `:546`, `:579`; по каталогам — `tests/` 2, `gateway/tests/` 4, прочие четыре 0; находок видов (2) и (3) — ноль
**And** у близнеца — строка с адресом регистрации в посеве `tests/authz-fixtures/` — находки нет; инъекции строк, взятых из дерева `@b7608fe9750`, дают находку с координатой места инъекции: строки `prodseed_matrix.py:191` в посев — вид (1); строки `cluster_admin.postman_collection.json:579` в коллекцию — вид (1); строки `ceremony-seed.ts:60` (адрес регистрации) в случай `cluster_admin.py` — вид (3); строки, пишущей колонку отметки, в посев — вид (2)

**ID:** F6b-53 — **условие «приёмник писем читается посевом наборов» создаётся шагом и проверяется до посева людей** (близнец — поверхность не отвечает)

**Given** прогон наборов newman на поднятом стенде (`deploy/scripts/newman-parallel.sh`, конвейер `.github/workflows/e2e-newman.yml`)
**When** исполняется предусловие чтения приёмника посевом
**Then** оно печатает адрес поверхности чтения и число прочитанных писем, и исход «условие создано»
**And** у близнеца — адрес поверхности чтения заменён адресом без слушателя — предусловие печатает «условие не создано: приёмник писем не читается» с адресом, посев людей не начинается, и наборы получают «не выполнилось» с тем же текстом, а не красное

**ID:** F6b-54 — **боевая посадка не несёт приёмника стенда, и пять ручек подтверждения рубежа не снимают** (близнец — рендер стенда наборов, различие — профиль)

**Given** зонт платформы, отрисованный (а) боевым профилем `values.prod.yaml`; (б) профилем стенда наборов `values.dev.yaml` + `values.dev-prod.yaml`
**When** рендер
**Then** в (а) объектов шаблона приёмника писем (`templates/mail-receiver.yaml`: Certificate, Service и Deployment) нет; в (б) Deployment `<релиз>-mailpit` — ровно один, и Service с тем же именем — ровно один
**And** в обоих рендерах ключей с приставкой `verification-` в блоке `authn.login` настройки службы — **ровно пять**: `verification-code-ttl`, `verification-code-attempts`, `verification-resend-interval`, `verification-resend-limit`, `verification-resend-window`, с величинами профиля продукта 30m · 5 · 60s · 5 · 24h; шестого ключа с этой приставкой нет — каждая из пяти задаёт величину рубежа, ни одна его не снимает (Р9 службы, Р11, Р18)
**And** проба печатает число осмотренных ключей блока по каждому рендеру; ноль осмотренных — отказ пробы

**ID:** F6b-55 — **случай `cluster_admin` берёт цель выдачи у посева и человека сам не заводит** (близнец — слота посева нет)

**Given** стенд F6b-46; посев наборов завёл цель выдачи администратора облака видом Ф-п и отдал её слотами окружения `clusterTargetUserId` и `clusterTargetEmail`; перепись F6b-51 называет её с видом Ф-п и `emailVerified: true`
**When** исполняется набор `cluster_admin`
**Then** перепись обращений набора не содержит ни адреса хука поставщика, ни адреса регистрации: шага `CLUSTER-ADMIN-SEED-TARGET-USER` в нём нет
**And** выдача, повторная выдача, снятие и оба чтения перечня администраторов адресуют человека `clusterTargetUserId`; запись перечня после выдачи — ровно одна, и её адрес почты равен `clusterTargetEmail`; исходы шагов — те, что случай утверждает сегодня (снятие до выдачи — `404`, повторная выдача оставляет одну запись, после снятия записи нет), и текст каждого — дословно тот же
**And** у близнеца — слота `clusterTargetUserId` в окружении нет — каждый шаг, которому нужна цель, завершается меткой «условие не создано» с именем слота и не исполняется; вердиктный гейт наборов (`tests/newman/scripts/assert-suites-green.sh`) относит набор к «не выполнилось», а не к красным и не к зелёным, и человека набор не заводит

**ID:** F6b-56 — **почтовая полоса службы на стенде проверяет приёмник якорем его же секрета и несёт адрес входа консоли** (близнец — боевой профиль, различие — профиль)

**Given** зонт платформы, отрисованный (а) боевым профилем `values.prod.yaml`; (б) профилем стенда наборов и консоли `values.dev.yaml` + `values.dev-prod.yaml`
**When** рендер
**Then** в (б) блок `invite-mail` настройки службы несёт `relay` — узел приёмника стенда (`<релиз>-mailpit:1025`), `ca-bundle-file` — путь, по которому рабочему объекту службы смонтирован ключ `ca.crt` секрета сертификата приёмника (`kacho-mailpit-tls`), и `login-url` — абсолютный адрес, чьё происхождение равно `global.kacho.identity.appBaseURL` профиля
**And** в (б) рабочий объект службы монтирует из этого секрета ровно один ключ — `ca.crt`; закрытого ключа приёмника у него нет
**And** в (а) приёмника нет (F6b-54), и у рабочего объекта службы нет тома из секрета `kacho-mailpit-tls`, а у блока `invite-mail`, если он есть, — `ca-bundle-file`, указывающего на такой том
**And** проба печатает число осмотренных ключей блока `invite-mail` по каждому рендеру; в (б) ноль осмотренных — отказ пробы
**And** на голове волны до кода проба красная: в (б) `ca-bundle-file` и `login-url` у службы нет, тома из секрета приёмника нет (§1.16)

---

## §5 Сценарий → производитель

| ID сценария | что производит «Тогда» | координата в дереве | чем измерено |
|---|---|---|---|
| F6b-01 … F6b-09 | рубеж адреса в полосе сессии, значение Р3, порядок Р4, клетка Р12, «кто я» Р10 | **заводится:** `gateway/internal/middleware/auth_own_session.go` (рубеж), `session_identity_handler.go` (Р10), `human_session.go` (клетка); проба — новая `gateway/internal/middleware/own_session_address_gate_test.go` с дублёрами порта сессии, следующего звена и вопроса об администраторе | `go test ./gateway/internal/middleware/...` — красный до кода: рубежа нет (§1.1) |
| F6b-04, F6b-11 | единое объявление записей с решением «доступна до подтверждения» у каждой из 18, два новых пути формы, `relayWhenUnanswered = false` у обоих; три координаты церемонии — «доступна», ответ службы ретранслируется как есть | **заводится:** решение в `gateway/internal/middleware/login_lane_paths.go`; **существует** ретрансляция по тому же объявлению — формы и выдачи (`login_lane_paths.go:251–253` @ `b7608fe9750`, §1.11) | та же проба + `login_lane_paths_test.go`; сверка 15 записей формы с 15 путями службы; красная до кода: решения нет ни у одной записи |
| F6b-10, F6b-11 (ответ службы) | глаголы подтверждения, новый носитель, живое чтение отметки | **существует** в дереве службы на голове волны `366` (§1.12: 15 путей слушателя формы, `loginlanehttp/handler.go:901, 921` @ `c8559057b`); чтение отметки — `PRO-Robotech/kaname:internal/repo/kaname/pg/human_session_repo.go:59,115`; отсутствие кэша у края — шапка `gateway/internal/middleware/human_session.go` | новая проба `ui-future/e2e/specs/address-confirmation.spec.ts` на стенде; «не выполнилось» до ретрансляции краем (S1) |
| F6b-35 | исполнение краем ответа службы на полосах Л2 и Л3 обеими поверхностями; тексты отказа каждой поверхности | **существует:** `gateway/internal/middleware/auth.go` (Л2 — :451 нативная, :1035 HTTP, текст `basicCredentialRefusalText`; Л3 — :516, :522 нативная с `authFailedMsg`, :1163, :1167 HTTP с `revocationDenyDescription`), выбор вопроса записью издателя (`auth_revocation.go:195`, `config/tokenissuers.go:247`), сверка через кэш (`cmd/api-gateway/main.go:405–418`); ответы службы — Р5 и Р5а службы (EV-66, EV-68), перепрос секрета — строка Р4в службы и `basic_credential_repo.go:355` (§1.9), сценарий — заказ §3.2 | `go test ./gateway/internal/e2e/ -run 'TestF1b09_OurTokenRevocationIsAskedOfOurAuthorityAndFailsClosed\|TestF1b12_AuthNRefusalsAreIndistinguishableOnTheNativeSurface' -count=1 -v` @ `499ad3085fd` → PASS обе (опора сценария; сам сценарий — новая проба края с дублёрами обеих полос) |
| F6b-45 | отказ решения с причиной `email_not_verified` значением Р3 на обеих поверхностях, раньше скрытия существования | **заводится:** `gateway/internal/middleware/authz.go` (исход решения по перечню `deny_reasons`, до `denyDecision`), `permission_denied_response.go` (форма gRPC); значение — то же, что у рубежа (Р3); вход — Р4а службы (EV-50) | та же проба края, что F6b-01 … F6b-09: красная до кода — сегодня такой ответ даёт `AUTHZ_DENIED` и `404` |
| F6b-12 … F6b-18, F6b-22 | страж над каркасом (Р7), экран `/verification` (Р8), уход входа и регистрации через стража | **заводится:** `ui-future/host/src/App.tsx` (страж), `ui-future/shared/src/pages/auth/ceremony-addresses.ts` (`/verification` — экран; сборка адреса с возвратом), новый экран в `ui-future/shared/src/pages/auth/`; `LoginPage.tsx`, `RegistrationPage.tsx` | `address-confirmation.spec.ts` на стенде; компонентные пробы экрана и стража в `ui-future/shared` и `ui-future/host` |
| F6b-19, F6b-21 (ответ службы, письмо, `Retry-After`) | глагол запроса письма, промежуток, `Retry-After` на успехе и на отказе | **существует** в дереве службы (`loginlanehttp/handler.go:901, 915, 1010` @ `c8559057b`, §1.9); заголовка на успехе текст приёмки службы не называет — значение держит этот сценарий; доставка на стенде — почтовая полоса службы (F6b-56, §1.16) | `address-confirmation.spec.ts`; «не выполнилось» до ретрансляции краем и доставки |
| F6b-19 … F6b-21 (экран) | отсчёт только из `Retry-After`, закрытие кнопки и клавиши ввода | **заводится:** экран подтверждения | компонентная проба экрана (F6b-20 — только она: ответа без заголовка на стенде после заказа §3.2 не будет) |
| F6b-23, F6b-24, F6b-29, F6b-30, F6b-36 | предъявление кода с экрана и исходы Р9; адрес возврата через `useReturnTo` | **заводится:** экран подтверждения; **существует** `useReturnTo` / `safeInternalPath` (`ui-future/shared/src/pages/auth/use-return-to.ts`, `ui-future/shared/src/lib/redirect.ts`); ответы глагола — `kaname#456` (Р6, Р7, Р10 службы) | `address-confirmation.spec.ts` |
| F6b-25, F6b-26 | новое действие `confirm-address` в решении на отказ и оба читателя поверхности `platform` | **заводится:** `ui-future/shared/src/api/refusal-action.ts`, `ui-future/shared/src/api/lane-reasons.ts`, `ui-future/host/src/utils/api-client.ts`, `ui-future/shared/src/api/client.ts` | `refusal-action.test.ts` (действие по причине, неизвестная причина — «показать»); `address-confirmation.spec.ts` с байтами, снятыми с края в «Дано» самого сценария |
| F6b-27, F6b-28 | уход `/verification` без сессии на вход (Р7); адрес письма без кода | **заводится:** экран подтверждения; адрес в письме **существует** в дереве службы (`invite_mail.go:93, 622` @ `c8559057b`; текстом приёмки службы не назван, §3.2), письмо — `kaname#456` Р8; адрес входа у почтовой полосы службы на стенде — F6b-56 (§1.16) | `address-confirmation.spec.ts`; тело письма — с приёмника |
| F6b-31, F6b-37 | состояния стража Р7, в том числе после подтверждения | **заводится:** страж | компонентная проба стража с дублёром транспорта |
| F6b-38, F6b-39, F6b-42, F6b-43, F6b-44 | исходы Р9 уровня экрана, в том числе решение по `reason` на `400` / `9` | **заводится:** экран подтверждения; **существует** действие `fresh-form-token` и действие «показать» на неназванную причину (`refusal-action.ts`), `UNKNOWN_SESSION_TEXT` (`login-lane.ts:608`); значения `EMAIL_ALREADY_VERIFIED` и `INVITE_NOT_VALID` — Р6, Р11 п. 4, Р15 службы (EV-40, EV-73, EV-75) | компонентная проба экрана с дублёром транспорта |
| F6b-40, F6b-41 | письмо регистрации той же транзакцией; отказ регистрации письма не ставит | **существует** в дереве службы: вид письма `verification` (`internal/check/mail_send_paths.go:112` @ `c8559057b`), постановка в очередь транзакцией вызывающего (`invite_mail_outbox/outbox.go:171`); Р9 службы, EV-01; доставка на стенде — F6b-56 (§1.16); экран — заводится | `address-confirmation.spec.ts`; счёт писем — с приёмника |
| F6b-32, F6b-33 | посевы П-н и П-п, фикстура `register` | **существует** `seedHuman` (`ui-future/e2e/specs/ceremony-seed.ts`); **заводится** П-п и подтверждение в `register` (`ui-future/e2e/specs/fixtures.ts`) | весь набор: 24 файла проб на фикстуре (§1.6) |
| F6b-34 | чтение приёмника прогоном | **существует** приёмник (`deploy/helm/umbrella/templates/mail-receiver.yaml`); **заводится** шаг в `.github/workflows/console-e2e.yml` и предусловие в `ui-future/e2e/preconditions/` | исход предусловия в журнале прогона; инъекция «поверхность не отвечает» |
| F6b-46, F6b-47, F6b-51 | человек посева наборов по Р17 — виды Ф-п и Ф-н, перепись людей посева, идентификаторы с поверхностей края | **заводится:** заведение человека регистрацией, чтение приёмника и предъявление кода в `tests/authz-fixtures/` вместо восьми вызовов `upsert_user` (§1.13) и вместо шага `CLUSTER-ADMIN-SEED-TARGET-USER` (его цель заводит посев, F6b-55); идентификаторы человека, аккаунта и проекта — ответами края вместо `db_lookup` и ожидания строки чтением хранилища (§1.15); перепись людей со слотами — в выходе посева; **существует** регистрация и её ретрансляция краем (`login_lane_paths.go`, запись `register`), глагол подтверждения у службы (§1.12), приёмник на стенде наборов (§1.13) | прогон наборов на стенде, журнал посева; «не выполнилось» до ретрансляции глаголов подтверждения краем (S1) |
| F6b-48, F6b-49 | личный токен человека посева: выдаётся Ф-п, не обменивается у Ф-н | **существует** выпуск и обмен (`tests/authz-fixtures/mint_rs256.py`, `user_platform_token`; `prodseed_matrix.py:763–779` @ `b7608fe9750`) и отказ обмена о неподтверждённом владельце у службы (клетка `owner-unverified`, `internal/clientassertion/verifier.go:173` @ `c8559057b`; Р5 службы, EV-65); **заводится** субъект — Ф-п вместо человека хука поставщика, и проба посева на стенде для F6b-49 | прогон наборов: слот `jwtUserTokenPlatformIssuer` и его читатель `authn_edge.py:716`; проба F6b-49 на стенде |
| F6b-50 | исходы посева: «условие не создано» при письме, не дошедшем в срок; находка при отказе на коде из письма | **заводится:** самопроверка посева с дублёрами края и поверхности чтения приёмника в `tests/authz-fixtures/` (рядом с существующими самопроверками посева, `deploy/scripts/run-gate-self-tests.sh`) | самопроверка без стенда; красная до кода: посева с чтением приёмника нет |
| F6b-52 | гейт дерева платформы по Р17 и Р18 — три вида находки, единица — строка | **заводится:** гейт в `internal/repohygiene/` (обход шести каталогов со счётом осмотренных файлов, три вида находки, инъекции строками из дерева); ожидаемый вывод до кода — перепись §1.14 | `go test ./internal/repohygiene/ -run <имя гейта>`; красный до кода — шесть находок в четырёх файлах на `b7608fe9750` (§1.14) |
| F6b-53 | чтение приёмника посевом наборов | **существует** приёмник на стенде наборов (`values.dev.yaml:171–172` @ `b7608fe9750`); **заводится** предусловие посева и шаг конвейера `.github/workflows/e2e-newman.yml` / `deploy/scripts/newman-parallel.sh` | исход предусловия в журнале прогона; инъекция «поверхность не отвечает» |
| F6b-54 | рендер боевой посадки без приёмника и с пятью ручками | **существует** выключенный по умолчанию приёмник (`values.yaml:329–330` @ `b7608fe9750`) и гейт его присутствия на шардах (`deploy/mail_receiver_core_test.go`); **заводится** пять ручек в чарте службы и профилях — `kacho#2901` (§3.2) — и проба рендера двух профилей в `deploy/` | `go test ./deploy/ -run <имя пробы>`; красная до кода: пяти ручек на голове волны нет (`git grep -n 'verification-code-ttl' b7608fe9750 -- deploy \| wc -l` → 0) |
| F6b-55 | цель случая `cluster_admin` — человек посева по слотам; «условие не создано» без слота | **заводится:** цель в `tests/authz-fixtures/` видом Ф-п и слоты `clusterTargetUserId`, `clusterTargetEmail` в выходе посева (рядом со слотами `fixtures`, `prodseed_matrix.py:772` @ `b7608fe9750`); снятие шага `CLUSTER-ADMIN-SEED-TARGET-USER` из `gateway/tests/newman/cases/cluster_admin.py` и пересборка коллекции; **существует** метка «условие не создано» и её различение вердиктным гейтом (`tests/newman/scripts/assert-suites-green.sh`, `precondition_outcome_test.py`) | прогон набора на стенде; близнец — прогон без слота |
| F6b-56 | почтовая полоса службы на стенде: якорь сертификата приёмника и адрес входа | **существует** узел полосы из `global.kacho.identity.smtp` (`charts/kaname/templates/configmap.yaml:591–603` @ `b7608fe9750`), та же очередь и тот же отправитель письма подтверждения у службы (§1.16), `ca-bundle-file` и `login-url` в собственном чарте службы (`deploy/templates/configmap.yaml:635, 638` @ `c8559057b`); **заводится** выпуск обеих величин копией чарта службы в зонте, монтирование ключа `ca.crt` секрета приёмника и величины профиля стенда — `kacho#2901` — и проба рендера двух профилей в `deploy/` | `go test ./deploy/ -run <имя пробы>`; красная до кода: `git grep -n -E 'ca-bundle-file\|login-url' b7608fe9750 -- deploy/helm/umbrella/charts/kaname \| wc -l` → 0 |

---

## §6 Definition of Done

0. **Порядок посадки (условие, без которого стадии не садятся).** Рубеж края (S1) выкатывается
   только на стенд, где уже живы глагол подтверждения, письмо регистрации и ответы предъявления
   службы: волна `#2797` собирается вместе с волной `366` службы, несущей `kaname#456`. Пройдено —
   сводный прогон волны на одном стенде содержит зелёные F6b-10, F6b-40, F6b-46 и F6b-48, стенд
   поднят с пятью ручками подтверждения службы и с почтовой полосой службы, проверяющей приёмник
   стенда его якорем и несущей адрес входа консоли (`kacho#2901`, §3.2, F6b-56), а посев наборов
   newman доводит каждого своего человека до вида, объявленного Р17 (F6b-51, S4); не пройдено —
   рубеж есть на стенде без глагола (F6b-10 «не выполнилось» по причине «глагола нет») либо посев
   наборов заводит человека, не прошедшего подтверждение там, где объявлен Ф-п. Доставка письма в
   установке продукта (`kacho#1773`, P3) условием этого пункта не является: на стенде письмо идёт
   той же очередью и тем же отправителем к приёмнику стенда (§1.16, §3.2).
1. **Приёмка:** этот документ получил вердикт на свой отпечаток до первой строки кода (ban #1) —
   одобрение редакции 3 (`49bb29de…`) на редакции 4 и 5 не переносится, и код, начатый по нему,
   судится по новому одобрению в той части, которую изменили редакции 4 и 5 (§8). Приёмка службы (`kaname#456`)
   одобрена на редакции 3 (`f2d1fe85…`) и несёт: значение отказа Р3 этого документа побайтово;
   решения, названные §1.9, — в их числе ответ сверки `{"active": false}` на предъявлении (Р5а),
   исходы полос церемонии (Р5, Р5б), исход `INVITE_NOT_VALID` (Р6, Р11 п. 4) и вердикт перепроса
   базового секрета (строка Р4в); виды формы `verify-email` и `verify-email-confirm`; строку отмены
   Р14 Ф6 (её §0.1). Адрес `/verification` в письме и `Retry-After` на успехе запроса письма текстом
   приёмки службы не названы, а деревом службы произведены (§1.9): их значения держат F6b-28 и
   F6b-19, и отдельного условия п. 1 они больше не несут. Расхождения строки края её §3.2 с этим
   документом названы §1.9 и правятся её строкой. Решение службы, изменённое её следующей редакцией,
   — правка этого документа тем же кругом.
2. **S1 — край:** `own_session_address_gate_test.go` и дополнение `login_lane_paths_test.go`
   **красные до кода** с выводом, показанным в запросе на слияние, и зелёные после; F6b-01 … F6b-09,
   F6b-11, F6b-45 исполнены; F6b-35 исполнен и зелёный и до кода, и после — он держит существующее
   поведение края, на которое опирается Р16, и «красного до кода» у него нет законно; его опоры
   `TestF1b09_…` и `TestF1b12_…` остаются зелёными. Записей объявления — 18 (формы 15, церемонии 3),
   доступных до подтверждения — 9 (формы 6, церемонии 3); клетка Р12 видна на
   диагностической поверхности с нулём до первого отказа. **Каскад уровня Go назван и закрыт
   законно:** дублёры порта сессии прочих проб края (§1.6 — 29 построений на `499ad3085fd`, 31 на
   голове волны, §1.11; правило то же на любом их числе) получают
   `EmailVerified: true` с причиной в тексте пробы («проба о другом предмете; рубеж адреса держит
   own_session_address_gate_test.go»), а не ослабление рубежа.
3. **S2 — консоль:** компонентные пробы стража (F6b-31, F6b-37), экрана (F6b-18 … F6b-21, F6b-38,
   F6b-39, F6b-42, F6b-43, F6b-44) и решения на отказ (F6b-25, F6b-26) красные до кода и зелёные после;
   `/verification` в `CEREMONY_ROUTING` — экран; адрес с возвратом собирается одной функцией, читается
   только через `useReturnTo`; README `ui-future/shared/src/pages/auth/README.md` и шапка
   `ceremony-addresses.ts` перестают говорить, что `/verification` «ждёт доставки письма».
4. **S3 — набор (консольная часть `kacho#2901`):** П-п и подтверждение в фикстуре `register`; предусловие F6b-34 и шаг прогона;
   `address-confirmation.spec.ts` несёт F6b-10, F6b-12 … F6b-19, F6b-21 … F6b-30, F6b-32, F6b-33,
   F6b-36, F6b-40, F6b-41 (имя каждого теста начинается с ID). Весь набор консоли на стенде п. 0 —
   тот же вердикт трижды подряд.
5. **Красный до кода на стенде:** проба F6b-15 на стенде ствола волны без правки — красная (консоль
   открывает каркас неподтверждённому) — вывод показан до первой строки кода консоли.
6. **Перепись Р6** прогоняется в каждом сценарии S2 с неподтверждённой сессией и печатает число
   осмотренных обращений: «лишних ноль» при нуле осмотренных — находка, а не успех.
7. **Сценарии F8 §3.3** переписаны автором F8 либо названы там снятыми этим документом; до того
   этот пункт не пройден.
8. **Записки:** trail задачи и записки ресурсов края и консоли, которых касается правка, — тем же
   изменением, что код.
9. **S4 — посевы наборов и стенда (часть `kacho#2901` о наборах и стенде):** девять мест заведения
   человека §1.13 переведены на Р17 (`prodseed_network.py` без вызывающего — переведён либо снят);
   цель случая `cluster_admin` заводит посев и отдаёт слотами, шага заведения в случае нет (F6b-55);
   идентификаторы человека, аккаунта и проекта посев берёт ответами края (§1.15);
   F6b-50 (самопроверка), F6b-52 (гейт; до кода — вывод §1.14: шесть находок в четырёх файлах),
   F6b-54 и F6b-56 (рендер) **красные до кода** с выводом, показанным в запросе на слияние, и зелёные
   после; F6b-46 … F6b-49, F6b-51, F6b-53, F6b-55 исполнены на стенде п. 0 и зелёные, либо «не
   выполнилось» с названным условием §3.4 — не красные и не зелёные; перепись людей посева (F6b-51)
   печатает N, M, U, и N ≠ 0; README `tests/authz-fixtures/README.md` перестаёт
   описывать заведение людей хуком поставщика; новой коллекции newman S4 не заводит, а если заведёт —
   со строкой ведомости производителя.

---

## §7 Инварианты — для ревьюера

1. Для учётной записи с неподтверждённым адресом **ни одна полоса края**, выставляющая личность
   человека, не доводит запрос дальше края за пределами перечня Р5 — у каждой полосы назван держатель
   (Р16), и у полосы сессии это утверждено парой близнецов на каждом уровне (F6b-01/02, F6b-15/16), у
   полос базового секрета и предъявителя — F6b-35 на крае и решениями службы Р5, Р5а и строкой Р4в
   о перепросе секрета (сценарий перепроса — заказ §3.2); полоса записи отзыва на стендах токенов не
   получает (§1.8).
2. Отказ Р3 **один**: одно значение, одна причина, у края и у службы побайтово — и на рубеже полосы
   сессии, и на отказе решения с причиной службы (Р3а, F6b-45); консоль отвечает на него одним
   действием у обоих читателей `platform`.
3. Ни одно умолчание не открывает: отсутствующая подтверждённость у края — «не подтверждён» (Р4);
   у консоли — страница «не удалось узнать» (Р7); глагол без решения — недоступен (Р5); ответ без
   `Retry-After` — без выдуманного срока (Р8).
4. Открытие адреса из письма не меняет ничего; подтверждает только код, введённый под сессией того же
   человека (Р9, F6b-28, F6b-29).
5. Первое письмо у одного производителя — регистрации службы; консоль писем не шлёт ни при открытии,
   ни после регистрации, и фикстура набора этим не пользуется (Р15, F6b-12, F6b-32, F6b-40).
6. Отрицательный кейс меняет ровно один факт против близнеца (`.claude/rules/change-graph.md` §6);
   близнец назван в заголовке каждого отрицательного сценария либо в его последнем «И», и все
   близнецы — сценарии этого документа.
7. Ни одно значение для проб не берётся из хранилища или очереди: код — из письма у приёмника,
   байты отказа — с настоящего края, срок — из `Retry-After` службы, положение и идентификаторы
   человека посева — из ответов края (Р13, Р17, F6b-25, F6b-46).
8. Человек фикстуры — любой: консоли, наборов, стенда — появляется только тем путём, что человек
   продукта: регистрацией и письмом регистрации; видов у него два, Ф-п и Ф-н (П-п и П-н у консоли),
   и каждый отличается от своего близнеца ровно предъявлением кода (Р13, Р17, F6b-32/33, F6b-46/47).
   Людей наборов заводит только посев, случаи наборов берут их слотами, и перепись людей посева
   поэтому полна по построению (Р17, F6b-51, F6b-52, F6b-55).
9. Обхода письма нет ни в одной посадке: писатель отметки у службы зовётся одним местом, в дереве
   платформы записей отметки нет, приёмник есть только у профилей стенда, и его отсутствие оставляет
   людей в положении подтверждения, а не открывает им путь (Р18, F6b-52, F6b-54).

---

## §8 Что изменилось — и почему

### Редакция 6 (по гейту цитат `make`)

**Почему.** Задание конвейера воркспейса «quoted make commands run from the monorepo root»
(`scripts/check-doc-commands.py`) отвечает кодом 1 на трёх цитатах этого документа: цель `dev-up`
была процитирована без каталога, такая команда исполняется из корня монорепо, а там этой цели нет —
она объявлена в `deploy/Makefile`. Скопированная из документа, команда не выполнилась бы.

**Что изменено — только форма команды, смысл ни одной строки не менялся.** Три цитаты — §1.13
вывод 2, шапка блока §1.16 и Given F6b-46 — записаны `make -C deploy dev-up`, той же формой, что
у спеки развёртывания (`03-deployment-and-operations.md`). Сценариев — 56, переписанных и снятых
нет; решения, перепись и §5 не тронуты. Важные круга 5 (I5-1, I5-2) отданы полосе S4 записью круга
и в документ не вносились.

### Редакция 5 (по кругу 4)

**Роды круга 4 повторяют роды прошлых кругов** — PRODUCER был у круга 2, COVERAGE у кругов 1 и 2.
Поэтому изменена форма решения, а не формулировка:

| замечание | прежняя форма | новая форма |
|---|---|---|
| **B4-1 PRODUCER** — число находок гейта до кода названо неверно, в обходе каталог, которого нет | ожидаемый красный выписан в сценарии перечнем, единица находки не названа | ожидаемый вывод — перепись §1.14 **до** сценария: единица осмотра (текстовый файл) и единица находки (строка) названы, число по каждому из шести каталогов, контроль в обе стороны. Находок шесть в четырёх файлах, в их числе строка сценария `:579`, задающая адрес, по которому запрос уходит; почему единица — строка, а не обращение (их четыре), сказано там же. `e2e/` из обхода снят: каталога нет ни на одной ревизии, а каталог обхода с нулём осмотренных — отказ гейта. Предикаты §1.13 переведены на тот же обход; DoD п. 9 и строка §5 — тем же изменением |
| **B4-2 COVERAGE** — человек, которого заводит случай `cluster_admin`, не держится ничем | места заведения перечислялись, и каждому искался свой держатель | место заведения **одно** — посев (Р17, выбран исход (а) рецензента): случай человека не заводит, цель выдачи администратора облака заводит посев видом Ф-п и отдаёт слотами `clusterTargetUserId`, `clusterTargetEmail`. Перепись F6b-51 полна по построению; замыкание держит третий вид находки гейта F6b-52 — адрес регистрации в источнике случая набора; сам случай — новый F6b-55 с близнецом «слота нет». Строка §5 и DoD п. 9 — по нему |

**Важные круга 4:**

- I4-1 — отрицательное «И» F6b-46 заменено: перепись посева видит только край и приёмник, а
  отсутствие обращения к хуку и записи отметки держит гейт F6b-52;
- I4-2 — перемерено (§1.16), и вывод редакции 4 неверен в обе стороны. Письмо подтверждения идёт
  той же очередью и тем же отправителем, что приглашение, к приёмнику стенда — стенд задачу
  `kacho#1773` не ждёт. Но почтовой полосе службы в зонте не хватает якоря сертификата приёмника и
  адреса входа консоли: без первого соединение с приёмником отвергается, без второго письмо не
  несёт адреса экрана. Обе величины — S4 (`kacho#2901`), держит новый F6b-56; строка §3.2, §3.4,
  §1.4, §1.13 вывод 2, DoD п. 0 и строки §5 переписаны от этого;
- I4-3 — F6b-54 (б) называет вид объектов: Deployment и Service `<релиз>-mailpit`, по одному;
- I4-4 — предикат глагола приглашения с контролем — в §1.13, и Р17 ссылается на него;
- I4-5 — §1.15 и правило Р17 «идентификаторы — с поверхностей края»: человек — ответ «кто я»,
  аккаунт — по `ownerUserId`, проект — `default`; поиск по адресу в хранилище службы снят;
  F6b-46 утверждает идентификаторы последним «И».

**Сценариев — 56** (F6b-01 … F6b-56), стадий — 4: добавлены F6b-55 и F6b-56; переписаны F6b-46,
F6b-51, F6b-52, F6b-54; снятых нет, ни один ID не переиспользован.

### Редакция 4 (возврат по `kacho#2901`)

**Почему возвращена.** Полоса стенда и наборов `kacho#2901` упёрлась: ни одна приёмка не описывала,
как человек посева наборов newman и стенда получает подтверждённый адрес, — а заводится он хуком
поставщика, без способа входа, тогда как глагол подтверждения требует сессии. Посылка перемерена
первым шагом: одобренные приёмки воркспейса, называющие посевы наборов (`prodseed`,
`authz-fixtures`), глагола подтверждения не называют ни одна (`git grep -l -E 'prodseed|authz-fixtures'
origin/main -- 'docs/specs/*acceptance*.md'` → 9 документов, строк с `verify-email` в них — 0);
редакция 3 этого документа и приёмка службы отдавали предмет задаче `kacho#2901` строкой §3.2, а
задача требует одобренной приёмки. Посылка подтверждена.

**Решение, по которому написан предмет.** Решение владельца 2026-09-27 (§0) и решение диспетчера по
его полномочию: путь фикстуры — честный и тот же, что у человека (письмо уходит в приёмник стенда,
посев читает письмо и подтверждает адрес глаголом подтверждения); ни глагола, ни ручки, ни посева,
помечающих адрес подтверждённым в обход письма, нет ни в одной посадке; в боевой посадке приёмника
стенда нет, и его отсутствие обхода не открывает. Оно внесено как Р17 и Р18; сценарии — стадия S4.

**Что добавлено:** перепись §1.11 (голова волны края), §1.12 (голова волны службы), §1.13 (девять
мест заведения человека хуком поставщика, чтения приёмника посевом нет, записей отметки нет);
решения Р17, Р18; стадия S4 — F6b-46 … F6b-54, у каждого «Тогда» производитель в §5, у каждого
отрицания близнец в заголовке; §3.1 п. 4, DoD п. 9, инварианты 8 и 9.

**Сверка с приёмкой службы — редакция 3, одобрена.** Шапка и §1.9 перепривязаны к `f2d1fe85…`;
глаголы подтверждения, тела, виды формы, значение отказа Р3 и таблица отказов Р6 — те же, что в
редакции 2, текстом. Изменённые решения службы (Р2, Р4в, Р5, Р5а, Р5б, Р11 п. 4, Р13, её §3.2)
разнесены по строкам §1.9. Три заказа §3.2 редакции 3 этого документа нашли производителей в дереве
службы (§1.9): значения адреса экрана и `Retry-After` на успехе держат F6b-28 и F6b-19, перепрос
живости секрета решён строкой Р4в службы; сценарий перепроса и гейт писателя отметки остаются
заказами службе (§3.2); DoD п. 1 переписан от этого.

**Предикат возврата строки §3.2 сработал — решение переехало в Р5.** Редакция 3 держала церемонию
авторизации строкой «вне объёма» с предикатом «появлением маршрута края на этот путь». На голове
волны край ретранслирует три координаты церемонии (§1.11), и рубеж S1 по нулевому решению ответил бы
на них отказом Р3 там, где служба отвечает протоколом. Поэтому: Р5 — записей 18, доступных до
подтверждения девять, ответ службы на координатах церемонии ретранслируется как есть; F6b-04 и
F6b-11 переписаны; строка §3.2 о церемонии снята, а не оставлена второй.

**Важные круга 3:** I3-1 — окно кэша решений края названо в Р3а и в строке §3.2 о смене адреса;
I3-2 — строка §3.2 о реестре, втором спрашивающем сверку; I3-3 — абзац Р16 о путях без сверки
назван полностью (четыре пути и все записи объявления), тексты нативной поверхности — «неудачи
подлинности предъявителя» (Л3 в Р16, F6b-35); I3-4 — последнее «И» F6b-35: опоры не держат тексты
отзыва, сквозной пробы не построить, сходимость держит общий ответ сверки.

**Сценариев — 54** (F6b-01 … F6b-54), стадий — 4: добавлены F6b-46 … F6b-54; переписаны F6b-04,
F6b-11, F6b-35; снятых нет, ни один ID не переиспользован.

### Редакция 3 (по кругу 2)

**Блокирующие круга 2:**

| замечание | что сделано |
|---|---|
| **B2-1 PRODUCER** — держатель Л3 на предъявлении назван не тем вопросом края | вопрос о токене выбирает запись издателя, и о токене нашей записи край спрашивает сверку `/internal/tokens/introspect` через свой кэш; это названо переписью §1.8 (`auth_revocation.go:195`, `tokenissuers.go:247`, `main.go:380, 405–418`, восемь адресов сверки в профилях), окно кэша — 5 с, min с остатком срока токена, чарт края его не задаёт (предикат с контролем). Держатель Л3 на предъявлении — Р5а службы (строка Л3 Р16, §1.9, §3.2, DoD п. 1); «Дано» F6b-35 — токен записи нашего издателя и дублёр сверки нашего авторитета, дублёр полосы записи обязан насчитать ноль. Полоса записи на стендах пуста — предикатом (каждый профиль принимает ровно нашего издателя, пустой перечень — отказ старта); установка со второй записью — строка §3.2 с предикатом возврата |
| **B2-2 FORMAT** — текст нативной поверхности в F6b-35 | тексты утверждаются по каждой полосе и поверхности отдельно: Л3 по HTTP — `401` `token revoked`, на нативной — `UNAUTHENTICATED` `authentication failed`; Л2 — `credential refused` на обеих. Опоры измерены прогоном `TestF1b09_…` и `TestF1b12_…` @ `499ad3085fd` — PASS обе |
| **B2-3 COVERAGE** — источник решений сменился | шапка и §1.9 перепривязаны к редакции 2 приёмки службы (`26758cccf`, `5fb3e84e…`), сверка по каждому решению названа; строка Р9 и сценарий F6b-44 на `400` / `9` `INVITE_NOT_VALID` (текст дословно, адрес не меняется, выход — «Выйти»; близнец F6b-42, различие — `reason`), решение строки — по `reason`; новая строка Р2 службы сверена с перечнем Р5 края — §1.10: «кто я» зовёт три метода вне круга, выход — `Revoke` о себе, доступный по Р4в службы; Р5а — держатель Л3 (B2-1) |

**Сверх замечаний, по той же сверке с редакцией 2 службы.** Строка края в §3.2 приёмки службы и
задача стадии `kacho#2900` требуют, чтобы край произносил отказ решения с причиной
`email_not_verified` тем же значением; редакция 2 этого документа это отвергала («без
производителя входа»). Вход у такого отказа есть — окна кэша края на Л2 и Л3 и снятие отметки
между двумя вопросами одного запроса (Р3а), — и два документа линии об одном рубеже не должны
называть разные значения. Поэтому добавлены Р3а и F6b-45 (близнец — причина `no path`), а
утверждение «отображения не заводится» снято. Два других расхождения со строкой края приёмки
службы — «край читает `Paths()` пином» и краткий перечень прохода — названы в §1.9 и остаются
правкой её строки; у края своё объявление глаголов, сверяемое дословно.

**Задачи стадий названы.** Край — `kacho#2900`, набор консоли — консольная часть `kacho#2901`
(шапка, §3.1); строка наборов newman от лица человека получила носителя (`kacho#2901`, I2-1), с ней
в §3.2 названы ручки подтверждения службы в чарте зонта и посев стенда.

**Важные круга 2:** I2-1 — носитель `kacho#2901` (§3.2, DoD п. 0); I2-2 — F6b-19 утверждает исход
пробы промежутка, F6b-21 — моменты T0 и T1 против промежутка профиля, иначе «условие не создано»;
I2-3 — F6b-43 (а) утверждает текст службы на экране, без привязки к полю; I2-4 — церемония
`GET /iam/v1/authorize` — строка §3.2 с предикатом (край путь не ведёт, → 0) и предикатом возврата.

**Сценариев — 45** (F6b-01 … F6b-45): добавлены F6b-44 и F6b-45; переписаны F6b-19, F6b-21, F6b-35,
F6b-43; снятых нет.

### Редакция 2 (по кругу 1)

**Блокирующие круга 1:**

| замечание | что сделано |
|---|---|
| **B1-1 SCOPE** — правило об учётной записи держалось на одной полосе | перепись полос §1.8 (HTTP — 4, нативная — 3, всего пять различных полос); держатель по каждой — Р16: Л1 край, Л2 и Л3 служба на выдаче и на предъявлении (заказы §3.2, DoD п. 1), Л4 не существует ни на одном стенде (предикат), Л5 личности человека не выставляет (предикат); удостоверения, выданные до дня посадки, — последний столбец Р16; строка §3.2 о нативной поверхности переписана от учётной записи; F6b-35 держит краевую половину Л2 и Л3 |
| **B1-2 COVERAGE** — у первого письма не было производителя | производитель — регистрация у службы той же транзакцией (Р15, Р9 службы); главный путь — F6b-40 с близнецом F6b-41; фикстура Р13 и F6b-32 больше не нажимают отправку, и их перепись этого обращения не содержит; «Дано» F6b-19 и F6b-21 перестроены под промежуток, открытый регистрацией; текст экрана верен и для людей, заведённых до дня посадки |
| **B1-3 COVERAGE** — ветви экрана без сценария | чужой адрес возврата на `/verification` — F6b-36 (близнец F6b-23); каждая строка таблиц Р9 несёт сценарий. Ветвь «другой человек» решена у службы привязкой кода к человеку и держится F6b-29; «край не ответил» после подтверждения — F6b-37; отвергнутый признак формы — F6b-38; отказа по частоте у предъявления нет по построению (предел — на код), консольная сторона — F6b-39 |

**Сверка с приёмкой службы (редакция 1).** Приёмка службы решила глагол иначе, чем решала Ф6, на
которую опиралась редакция 1 этого документа, и её владелец истины — служба. Поэтому сняты: ссылка
с кодом во фрагменте и подтверждение без сессии (было Р9, F6b-27 … F6b-30 редакции 1) — кода в адресе
письма нет, подтверждают под сессией; поле `email` в телах обоих глаголов; ретрансляция глаголов
подтверждения при неответившей службе (F6b-11 — теперь F4d-23); кнопка «Продолжить» и сценарии
F6b-23/F6b-24 в прежнем смысле — подтверждение снимает прочие сессии, и ID отданы исходам ввода кода;
значение отказа Р3 — теперь значение службы (текст и домен). ID сценариев редакции 1 сохранены, и
ни один не переиспользован под несвязанный предмет: F6b-23, F6b-24, F6b-27 … F6b-30 сохраняют предмет
«исход подтверждения», изменилась форма глагола.

**Важные круга 1:** I1-1 — цена названа в §3.2 и DoD п. 0, решение о приоритете — маршрут; I1-2 —
виды формы названы Р6 службы (§1.9, DoD п. 1); I1-3 — форма сессии неподтверждённого названа в §3.2
и решена Р2 службы (EV-01, EV-02); I1-4 — каскад уровня Go — §1.6 и DoD п. 2; I1-5 — единица §1.1
исправлена (4 строки в 3 файлах); I1-6 — F6b-03 называет уровень и оба исключения; I1-7 — отмена Р14
записана приёмкой службы, требование — DoD п. 1; I1-8 — близнецы F6b-17 и F6b-22 теперь свои (у
F6b-22 близнеца нет: сценарий положительный).

**Ссылки редакции 1 на «условия C6, C10–C13 приёмки F8» заменены координатами дерева:** в тексте
приёмки F8 (отпечаток `42b42300…`) таких обозначений нет; утверждения, которые они несли, держит
дерево консоли (`use-return-to.ts`, `login-lane.ts`, `use-logout.ts`, `host/src/utils/session.ts`).
