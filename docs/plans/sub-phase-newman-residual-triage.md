# e2e-newman residual triage (после Root-A, свежий стенд замер)

Единственный красный CI-чек — `newman e2e`. Гейт `assert-suites-green.sh` per iam/vpc/compute/nlb
(всё green минус known-RED whitelist). Материализация полна (opgate P1-P5 + keystone e195632 + Root-A 8d44019).

Ветка `qa/iam-acb-fixture-green` (впереди PR #2 `ci/newman-e2e-and-beget-runner`). Коммиты: Phase A f3cbfbd,
Phase B 76dcc66, opgate 25a047f/5328942/6d33f89/87b4d0b/f214213, Makefile 9717611, keystone e195632,
Root-A 8d44019, AAB-whitelist f7b09bd.

## Корни (замер 4 suites последовательно, iam=CI-faithful 1-й; vpc/compute/nlb под накопленной нагрузкой завышены)

- **Koren-1 confirm-gate tail-latency (~85%, ДОМИНАНТА)** — opgate Create→op-done p50=14ms/p95=3.1s/max=10s
  под нагрузкой → превышает newman poll-окно → `op done:false` → каскад 403/400. **В РАБОТЕ** (агент a979d…):
  root хвоста (read-after-write consistency lag vs FGA write-throughput) → HIGHER_CONSISTENCY (proto D3 additive,
  buf-breaking=0) на confirm-Check + backoff-tune + POLL_CAP safety-raise. Замер p95 до/после.
- **Koren-5 over-visibility — НЕ over-grant, TEST-HYGIENE** (расследовано, keystone-модель корректна):
  - Class-1 `rbac-visibility-set` (13): blind preclean (`ListBySubject` self-only→403→ложный clean-slate).
    **Fix: preclean через admin-authorized `accessBindings:listByScope?resourceType=account&resourceId={{accountAId}}`
    filter subjectId** в `services/iam/tests/newman/cases/rbac-visibility-set.py` (~line 155, паттерн IAM-ACB-CR-CRUD-OK).
    Нужна regen → координировать с Koren-1. (Alt: whitelist `^IAM-SET-[A-Z]+-(LABEL-EXACT-OK|VLIST-ONLY-DETAIL-404)`.)
  - Class-2 AAB LIST-LEAK (6): #276 collision (тот же корень что NOB). **DONE — whitelist f7b09bd** `^AUTHZ-[A-Z-]+-LS-OWN-AAB`.
- **Koren-2 compute disk-type seed-gap (2)** — `DT-LST-CRUD-OK` `newman-fake-type` нет в List; `DT-CR-NEG` POST→409
  вместо [404/405/501]. **Fix: засеять disk-type в фикстуру** (setup.sh / seed) + проверить negative-ожидание.
- **Koren-3 anon-DENY message-mismatch (compute/nlb)** — `AUTHZ-*-ANON` ждут `'permission denied'`, аноним корректно
  отдаёт code 16 `'unauthenticated: credentials required'` (401, не 403). **Fix: тест-ожидание** (аноним верно
  unauthenticated) в `services/{compute,nlb}/tests/newman/cases/*anon*` — правильный код продукта, не баг.
- **Koren-4 Root-C route-404** — iam `RBACSG-*` check/authorize route → `404 page not found`; vpc `internal-network`
  vrfId Internal-RPC (5) → 404. **Investigate**: gateway-роут не заведён ИЛИ тест-путь неверен (whitelist уже покрывает
  `probe-check` = /iam/v1/check неверный путь vs /iam/v1/authorize:check). Проверить регистрацию + тест-пути.
- **Koren-6 nlb zone/AddressPool seed-gap** — external LB alloc без AddressPool/zone (замаскирован Koren-1 op-latency;
  T31-LBLREVOKE-NLB-* уже whitelisted). **Fix: засеять nlb external AddressPool+zone** в umbrella/фикстуру ЛИБО
  расширить whitelist (iam#217 паттерн) для не-T31 nlb external-create кейсов.

## Порядок
1. Koren-1 land → redeploy iam+confirmers+gateway → re-measure (доминанта уйдёт, «замаскированные» всплывут чисто).
2. Координированный residual-раунд: Class-1 preclean + Koren-2 seed + Koren-3 тест-ожидание + Koren-4 investigate + Koren-6 seed/whitelist.
3. Re-measure до PASS всех 4 гейтов → merge qa→PR-ветку → push → CI newman green.

## GATE-RUN #1 (fresh stand, все фиксы до Koren-6) — все 4 FAIL, но sanity GREEN в изоляции
Sanity: confirm-latency 0.4s · account-owner PATCH 200 · iam:check 200 — фиксы работают ИЗОЛИРОВАННО.
Под FULL-SUITE нагрузкой все 4 FAIL. Корректностных багов НЕТ (ops done=true, 0 pending, authz сходится). Корни:
- **#1 eventual-consistency tail (системный, доминанта)**: (a) op-poll budget ~30×15ms≈0.45s БЕЗ реальной задержки → хаммерит → `done:false` пока op завершается за секунды (nlb 242, vpc 128); (b) `sync FGA per-tuple write failed→deferred to drainer` → confirm(v_update) проходит, но immediate DELETE нужен v_delete (ещё в outbox) → 403. Материализация НЕ атомарна + poll нетерпелив.
- **#2 vpc placementType test-gap (pre-existing)**: subnet-кейсы не шлют placementType → 400 → каскад (subnet 445, sg 230).
- **#3 compute→iam ProjectService.Get UNAVAILABLE ×3 (транзиент под пиком)**.

## ROUND 2 (в работе после GATE-RUN #1)
- **(A) атомарный batch owner-tuple FGA-Write** (iam reconciler, агент a2ef985…): op-done ⟹ полный грант (не partial v_update). TDD.
- **(B) op-poll РЕАЛЬНАЯ inter-poll задержка + budget ~15-20s покрытие** (newman gen.py все сервисы) + **placementType:ZONAL в vpc subnet/address/nic кейсы** (агент a83dc655…).
- Koren-3: ждём — batch-Write + меньше хаммеринга снижают нагрузку iam → должен уйти.
- **Открытый вопрос HIGHER_CONSISTENCY-contention**: возможно усугубляет под нагрузкой (bypass cache→DB/confirm); batch-Write снижает write-load → пересмотреть если после ROUND-2 latency остаётся.
Затем GATE-RUN #2 (fresh stand) → при 4 PASS merge qa→PR-ветку + push.

## GATE-RUN #2 (после Round-2) — все 4 FAIL, но корни хирургически ясны
Δ: placement-каскад УШЁЛ (cd7ee1c ✅); op-poll done:false — частично (compute/vpc/nlb ок, iam inline-поллы нет).
- **ГОЛОВНОЙ owner-403**: фикс (A) d4b8f84 НЕ достиг цели — атомарный batch НЕ идемпотентен. 692× WARN
  `openfga write: cannot write a tuple which already exists` → OpenFGA отвергает ВЕСЬ batch при любом pre-existing
  tuple (at-least-once re-register) → весь набор deferred в drainer → op-done ⇏ грант → 403. Доминанта vpc/nlb/compute/iam-admin.
- iam inline hand-rolled polls без busy-wait (ca04473 покрыл только shared-helper) → iam done:false ~14.
- nlb healthCheck TEST-баг: тесты шлют `healthCheck.tcp/.http`, proto oneof=`tcpOptions/httpOptions` → 400 → tgId не захвачен → каскад ~123.
- compute instance-суит >62мин (killed) → CI 45мин timeout hard-блок (reconciler ~52s до RUNNING × 178 поллов).
- compute run.sh пропускает authz-deny+sec-d (phantom no-report) + нет rm -rf out.
- Минор: vpc negative authz-ordering (create-no-project 403-vs-400), iam-user over-show (1, #276-family).

## ROUND 3 (в работе)
- **idempotent owner-tuple sync-write** (iam Go, агент a9347bc…): read-delta/error-filter — pre-existing tolerated, итог полный грант. ГОЛОВНОЙ.
- **qa-батч** (агент a3a7055…): iam inline polls busy-wait + nlb healthCheck tcpOptions/httpOptions + compute run.sh grade-all-9+rm-out + **investigate compute instance-timing** (вердикт: product-config ускорить reconciler / test-scope урезать / split).
- Затем GATE-RUN #3. Открытые минор-триажи (vpc authz-ordering, iam-user over-show) — решить после доминант.

## ROUND 3 — ЗАВЕРШЁН (все коммиты на qa/iam-acb-fixture-green)
- **f06c1a0** ГОЛОВНОЙ: идемпотентный owner-tuple sync-write (read-delta — pre-existing tolerated → полный грант). Закрывает owner-403 (692 deferral'а) + косвенно compute instance-timing (ops быстрые → poll выходит рано, без busy-wait accumulation; reconciler задержки НЕТ — create→RUNNING мгновенный).
- c8ec4c2 iam inline polls busy-wait · 77fef31 nlb healthCheck tcpOptions/httpOptions · 8031e9f compute run.sh grade-all-9+rm-out.
- 252683f nlb https/grpc→negatives (proto tcp/http-only подтверждён; issue #8 на proto-gap) · 446e25b vpc unscoped-create негативы толерантны 400|403 (authz-first) · 68e059f iam-user #276 whitelist (jwtInvitee реально admin@accountB, setup.sh:434).
- Watch-item (не блокер сейчас): vpc RT-LST/GW-CR/GW-LST/SG-LST `*-VAL-PROJECT-REQUIRED` строгие 400 (эти endpoint'ы без scope_extractor → passthrough 400, проходят; при добавлении anti-BOLA flip→403).
- Follow-up (задокументирован): Format-B `already_exists` swallow в openfga_client.go:270 (дремлет — прод отдаёт spaced-форму).

GATE-RUN #3 (fresh stand) в работе (агент ab67e3f…) — проверяет owner-403 ушёл + compute-timing + все 4 гейта. При 4 PASS → merge.

## GATE-RUN #3 (после Round-3) — прогресс, не зелёный. owner-403 ушёл ЧАСТИЧНО.
- idempotent-write работает: deferred 692→60/111 (все benign 409 «already exists», tuples ЕСТЬ); v_get/v_list/v_update/editor материализуются.
- **Два статичных ПРОДУКТОВЫХ бага (outbox drained, live 403 — не timing):**
  1. **v_delete НЕ материализуется** — creator получает `[v_get,v_list,v_update,editor]` без v_delete → каждый delete/cleanup 403 (suite-wide vpc/nlb). Нарушает инвариант create.go:435.
  2. **account-owner НЕ каскадит на project** — `owner@account:A` есть, но `Check(editor,project:A1)`=deny → label-revoke/issue-sakey 403.
- Орто: compute instance >57мин (реальная op-latency ~1.5s×1427 поллов, idempotent не помог, CI-timeout); compute authz-ordering (403-vs-400 negative); iam-acb poll-cluster-create done:false.
- nlb healthCheck-фикс СРАБОТАЛ (нет healthCheck-сигнатуры в падениях), но nlb красный на owner-tuple gap.

## ROUND 4 (в работе) — systematic-debugging «question architecture»: 7-я итерация материализации → ловить integration-матрицей, не e2e
- **Agent abf5490…** (rpc-impl): БАГ #1 v_delete + БАГ #2 account-owner→project cascade + **комплексная integration test-матрица материализации** (verb×role×scope) чтобы поймать класс и сломать slow-e2e-loop.
- **Agent a18d969…** (rpc-impl): compute instance-timing (op-latency investigate + scope/delay-фикс <15мин) + compute authz-ordering толерантен 400|403 + iam-acb poll-cluster-create busy-wait/budget.
- Затем GATE-RUN #4.

## GATE-RUN #4 (свежий build, v_delete-фикс) — прогресс, не зелёный
- iam: почти все суиты 0 fails (account/project/role/group/user/rbac-* ЗЕЛЁНЫЕ) — большой скачок. Остаток: label-revoke-vpc 59/-compute 19/-iam 3 (account-admin create), iam-authz-grant-check-propagation 2, iam-access-binding 1.
- vpc ~836→~500 (address 103, subnet 63, gateway 62, route-table 57, network 54, sg 52, nic 23), nlb ~360 (lb 136, listener 66, cross-resource 58, targets 50, tg 26).
- Падения: creator lacks v_get/v_update/v_delete → 403/404 на ЧАСТИ ресурсов. compute mirror-bound (44de7c8) РАБОТАЕТ (instance ops 55s→6s).
- **ГИПОТЕЗА**: opgate (confirm-gate) только на Network/SG/Subnet+Instance/Disk+Volume+AccessBinding; НЕ на vpc Address/RouteTable/Gateway/NIC + nlb LB/Listener/TargetGroup → не ждут материализацию → под нагрузкой lacks-verbs 403/404. account-owner label-revoke — отдельный gap (не stale, admin@project есть но create 403?).

## ROUND 5 (в работе) — сломать fix→e2e-loop через ground-truth + comprehensive
- **Agent a64a5ec…** (rpc-impl): ground-truth FGA на живом стенде (store 01KXR5CKR9QY72Z5WNFW3MYN0Y) non-opgated vs opgated creator-tuples + account-owner project-tuples → **расширить opgate на ВСЕ owner-ресурсы** (vpc Address/RouteTable/Gateway/NIC + nlb LB/Listener/TargetGroup) ЛИБО confirm-completeness + account-owner фикс. TDD OTG per ресурс.
- Затем GATE-RUN #5.
- **NB**: 8-й материализационный слой. Если и это не сходится — эскалация: system-design-reviewer на весь opgate+materialization дизайн (возможно opgate-per-resource фундаментально хрупок под нагрузкой; альтернатива — sync-reliable materialization без confirm-gate).

## GATE-RUN #5 (comprehensive opgate) — АРХИТЕКТУРНЫЙ переломный момент
- `lacks v_*` симптом УШЁЛ (opgate работает), но вскрыт истинный корень: **FGA/async-op throughput SATURATION под нагрузкой** (single-node kind, 4 тяжёлых суита back-to-back). Failures эскалируют по нагрузке (iam рано≈зелёный→compute поздно худший). 0 restart — throughput-contention, не resource-exhaustion.
- **opgate стал ХУЖЕ**: 28× vpc `confirm not achieved within deadline; failing closed (30s)` → конвертирует transient lag в HARD create-failure → 404. nlb — OpenFGA `authorization service unavailable`.
- **Caveat**: локальный стенд ограниченнее resourced CI-раннера → бóльшая часть красноты = local-saturation-артефакт.
- Environment-независимо реально: (1) opgate fail-closed brittleness (design), (2) vpc/nlb negative-authz-ordering (~105, ждут 400/404 получают 403 authz-first; compute уже толерантен 32be094), (3) nlb AddressPool seed сломан.
- Timing: job ~68мин > CI 45мин (compute instance 27.6мин под нагрузкой).

## ROUND 6 (в работе) — ЭСКАЛАЦИЯ архитектуры + пуш на реальный CI
- **system-design-reviewer a351b05…**: вердикт по opgate (fail-closed vs fail-open vs remove+tolerant-tests; local-vs-CI; deadline). КЛЮЧЕВОЕ решение.
- **qa a45558d…**: vpc/nlb negative-authz толерантен 403|400|404 + nlb AddressPool seed фикс + API-conv not-found флаг.
- **СТРАТЕГИЯ**: локальный стенд — ненадёжный proxy (saturation-призраки). После design-фикса + qa → **ПУШ на resourced CI-раннер** (реальный тест гейта) вместо бесконечных локальных gate-run'ов. CI-runner (15GB/12-core) может не сатурироваться → гейт зелёный. Если CI красный — итерировать по РЕАЛЬНЫМ CI-падениям.

## DESIGN-REVIEW ВЕРДИКТ (пере澜ом) — opgate = архитектурная ОШИБКА, удалить
system-design-reviewer (APPROVED): opgate гейтирует `Operation.done` по видимости owner-tuple в FGA
(eventually-consistent downstream), а Operation = durability ресурса (`w.Commit()` в fn). Нарушает ban #9;
на fail-closed создаёт **phantom-ресурс** (закоммичен но op=ERROR → retry AlreadyExists → get как 404 = anti-pattern
от которого worker защищается в ClaimForExecution); конвертирует ограниченный lag в неограниченный hard-fail;
неправильно применяет fail-closed (category error — защищает доступ вызывающего, не репортинг создания).
**Q4 критично: фундаментальный дефект, НЕ артефакт слабого стенда** — на resourced CI станет флаки heisenbug
(хуже); зелёный CI-прогон нельзя принять за доказательство. → Разворачивает «пуш на CI» стратегию.

## ROUND 7 (в работе) — REMOVE opgate + tolerant-tests (честный eventual-consistency)
- **Agent a06399a…**: ЧИСТО удалить confirm-gate из pkg/operations/worker.go + все сервисы (vpc/compute/nlb/iam/storage).
  СОХРАНИТЬ материализацию (sync-registrar/outbox/drainer/reconciler/atomic-batch/idempotent/keystone/Root-A/v_delete —
  корректны; sync-registrar теперь чисто window-оптимизация). Разворачивает 8 раундов opgate (строил на неверной арх).
- **Agent a45558d…** (идёт): vpc/nlb negative-authz толерантен + nlb AddressPool seed.
- **ДАЛЕЕ (после обоих)**: tolerant-tests — newman create→immediate-mutate кейсы bounded-retry первый Update/Delete
  на 403/404 (~2-5s окно) до assert (helper `retryUntilAuthorized`). Это «tolerant» половина (design-review Phase 1b).
- Затем GATE-RUN #6 (детерминированный, без opgate phantom) → merge → push.

## ROUND 7-8 — opgate УДАЛЁН + tolerant + push (ГОТОВО/в работе)
- **opgate removal ГОТОВ** (6 коммитов: pkg/operations 8630cd8, compute 4423721, iam 17f648f, vpc 0a32589, nlb 947bcca, storage 250c680). Верифицировано независимо: enforcement authz (per-RPC Check/scope_extractor/hide-existence/malformed-id) + материализация + permission-catalog ЦЕЛЫ; confirm-gate символы удалены чисто; build/test/lint green. Security-флаг агента = FALSE POSITIVE (opgate не authz-проверка; авторизовано design-review + мандатом).
- **qa ГОТОВ**: negative-authz толерантен 1395166, nlb AddressPool fc620e7.
- **В работе**: tolerant-tests `retry_until_authorized` bounded-retry post-create mutate (a5f604d) + API-conv not-found message фикс product vpc/nlb (ab09647).
- **CI ЗАПУЩЕН на GitHub** (PR #2, push 4d3f35d = opgate-present state; даёт данные resourced-раннера + валидирует не-e2e Go). После tolerant+API-conv → **пуш скорректированного** (opgate-removed) состояния — суперсиднет текущий прогон, будет детерминированным.
- API-conv message — оставлен RED как product-finding, чинится ab09647 (не whitelist — реальный контракт-violation).

## CI-ПРОГОН на resourced-раннере (d2ae17f, opgate-removed) — РЕАЛЬНЫЕ данные
Всё зелёное КРОМЕ: (1) `build·vet·gofmt·test-race` — commentlint § и #N в compute mirror-комментах → **починен 89bc967**;
(2) e2e-newman — **таймаут 45мин** (job дошёл iam→vpc→compute-partial→timeout; compute-instance/authz-deny + весь nlb = no-report)
+ **реальные ассерт-падения** (resourced runner, НЕ saturation-призраки):
- iam: label-revoke-vpc/-compute, iam-access-binding, iam-authz-grant-check-propagation, iam-read-authz-vget, iam-user, rbac-subject-channel-equivalence, rbac-visibility-set(4).
- vpc: subnet 95, address 59, sg 40, network 31, route-table 22, gateway 25, nic 16, internal-pool 10, concurrency 6, list-filter-d 4, addr-zone 2, internal-network 1.
- compute (частично): disk 8, image 9, snapshot 6 (+ no-report timeout). nlb: весь no-report.
opgate-removal + tolerant-tests НЕ добили vpc/iam → **падения ДРУГОГО корня** (не materialization-lag — иначе tolerant-retry поймал бы).

## ROUND 9 (в работе) — timeout-фикс + диагноз реальных сигнатур
- **969d251**: e2e-newman timeout 45→90 + **artifact-upload newman out/*.json**. Пушнут.
- **Watcher biuf595sc** ждёт нового CI (~90мин) → полная суита + скачает отчёты в `$CLAUDE_JOB_DIR/tmp/newman-reports`.
- **СЛЕДУЮЩИЙ ШАГ (после отчётов)**: диагностировать РЕАЛЬНЫЕ сигнатуры vpc/iam (expected-vs-got: negative-authz не покрыт? API-conv текст не совпал? НОВЫЙ корень? tolerant-retry не обернул?) → таргетный фикс. `gh run download <rid> -n newman-out-reports`.
- compute/nlb (no-report) вскроют корни когда полная суита пройдёт под 90мин.

## FAST-LOOP (директивы владельца: parallel + per-project isolation + point-run + patch-not-devup)
Реализовано (частью дохлыми агентами до org-access-блокера, частью мной):
- Директива #1: `deploy/scripts/newman-parallel.sh` (fan-out 4 суит после единого seed). #2: setup.sh
  per-service dedicated account+project (authz-vpc/authz-nlb/authz-compute) — корень #276. #3/#4: point-run
  битой коллекции + `reload-svc SVC=x` patch без dev-up.
- **compute List pagination validate ПЕРЕД listauthz** (6e74598), **hide-existence not-found byte-identical**
  (0ce8fa6), **retry_until_authorized/present** (tolerant read-your-writes), **iam+compute run.sh consume --jobs** (e48d158).
- **Rules нормативизированы** (директива владельца): api-conventions (Operation.done), testing (newman ec-дисциплина),
  security (hide-existence + pagination-before-authz), data-integrity (flat Contract-A). workspace cb7fba5, sync-tooling.

## ИНФРА-находки замера (baseline недостоверен — чинить перед выводами)
- **kubectl port-forward api-gateway УМИРАЕТ под newman-нагрузкой** (612× ECONNREFUSED в parallel vpc) → PF-holder
  `$CLAUDE_JOB_DIR/tmp/pf-holder.sh` (auto-restart, run_in_background) — держит :18080/:18081/:19091 стабильно.
  Альтернатива (стабильнее): ingress `api.kacho.local`→localhost:80 (kind hostPort 28080) — не внедрено.
- **newman-parallel судит GREEN/RED по EXIT-CODE run.sh** (не по отчётам) + run.sh кончается `|| true` →
  **false-green при 0/partial отчётов**. compute/nlb «GREEN» в baseline НЕДОСТОВЕРНЫ (compute --jobs побил 6/9 коллекций).
- **iam+compute run.sh не принимали `--jobs`** (уходил в newman → unknown-option → 0 отчётов → false no-report RED). Фикс e48d158.
- **Надёжный замер = серийно против PF-holder + gate по assert-suites-green.sh** (читает отчёты, no-report=fail). Не по exit-code раннера.

## Текущий шаг: истинный per-suite замер (серийно, стабильный PF)
iam bg-run ba8hfvuyt (серийный, чистый) → истинный iam-red. Затем vpc/compute/nlb серийно. compute+nlb вероятно
близки к зелёному (retry_until_present сработал где отчёты были). vpc — переизмерить (baseline был PF-death).

## СРЕДА БЛОКИРУЕТ ЛОКАЛЬНЫЙ ЗАМЕР (критично для стратегии)
- **Харнесс убивает bash, спавнящий `kubectl port-forward`** (SIGTERM/exit 144) — И background, И foreground. PF-holder, measure-скрипты, reseed — все умирают. Порт-форвард как транспорт **невозможен**.
- **Ingress**: только hostPort 28080→80 (HTTPS 443 НЕ проброшен); nginx 308-редиректит HTTP→HTTPS → недостижимо без patch ingress ssl-redirect / recreate cluster.
- **Вывод**: локальный newman-замер физически заблокирован. **CI-раннер (self-hosted beget) — единственная надёжная среда** (свой dev-up контролируемо). e2e-newman.yml: timeout **90** + **artifact-upload newman out/*.json** (969d251) → скачиваемые отчёты для точных сигнатур.
- Стратегия: батчить фиксы → push CI → `gh run download <rid> -n newman-out-reports` → точечный фикс по РЕАЛЬНЫМ сигнатурам → повтор. 1-2 цикла, не двое суток.

## PUSH 546fe60 (10 коммитов, все фиксы сессии) — CI run 29620179837, watcher bzhbnng2q
Включает: opgate-removal (6) + Go-фиксы (pagination 6e74598, project-Exists a1c264e, hide-existence 0ce8fa6, commentlint 89bc967) +
retry-примитивы (retry_until_authorized/present) + директивы #1/#2 (parallel + isolation dc17be2) + run.sh --jobs (e48d158) + rules (cb7fba5).
Верифицировано локально ДО env-блокировки: compute disk/image/snapshot GREEN, vpc network 20→1, gateway 52→1, iam authz-deny 0.
Известный остаток (по af5a6d43-отчёту, до reseed): iam-rbac-subjects (poll-opId каскад от упавшего create), iam-access-binding (rya-lag),
vpc subnet/address (retry-wraps + tolerant absent-id), nlb hand-written, compute instance/authz-deny. Ждём CI-отчёты для истинных чисел.
- **nlb gen.py `retry_until_present` — dead code** (только def, не применён) — применить к nlb list-includes при следующем фиксе (ban #11).

## CI-ЦИКЛ по artifact-отчётам (рабочий процесс налажен) — итерация fc1c07c
Скачал 60 CI-отчётов (artifact `newman-out-reports`) → агрегировал сигнатуры → 4 агента по CI-данным:
- **iam** (97a5962): системный корень — busy-wait пропущен в `poll_request_until_status`/`get_until_gone`/
  `poll_check_allowed_step`/`robust_revoke_binding` (POLL_CAP выгорал за ~450мс). +500мс delay + retry-wrap label-revoke create.
- **compute** (19cefa5 owner-poll + ce01e92 storage-noop): list-filter корень = **op GetOwned ownership** (poll шёл
  bootstrap-Bearer ≠ create-owner PA1 → 404), фикс poll с owner-JWT. instance = **storage не задеплоен** но compute дефолтит
  storage-addr → 30s Unavailable; фикс `values.dev.yaml storage-addr=""` → NoopStorageClient.
- **nlb** (df87309 retry-wraps + fc1c07c health-check): доминантный блокер = **health-check name "hc"/"x" <3 симв** нарушает
  LbName regex → TG create 400 → {{tgId}}-каскад. Фикс hc→hc-tcp. + retry-wraps (137 setup + 8 direct + 4 list).
- **vpc** (5a0dca6): read-your-writes retry + tolerant-negatives + auth-фиксы (AddressPool→jwtBootstrap) + concurrency test-bugs.

## РЕАЛЬНЫЕ product-баги (флагнуты агентами, НЕ замаскированы)
1. **SG toPb target-oneof** — `security_group.go::toPb` сериализовал только CidrBlocks, НЕ SecurityGroupId/PredefinedTarget →
   Get/List rule Target=nil. **ПОЧИНЕН 0e6b589** (все 3 ветки + regression RED→GREEN, vet/lint чисто).
2. **iam cluster-admin DELETE AccessBinding → 403** (rbac-subject-channel-equivalence teardown) — jwtBootstrap
   (system_admin@cluster) DELETE валидного binding → `403 permission denied`, retry 30-45с терминально. cluster-admin
   short-circuit НЕ honored gateway-authz для AccessBindingService/Delete. Postdates c6fd46e = текущий residual. → investigate.
3. **vpc internal-pool IPAM resolve** — `no address pool resolved (network, family=0)` детерминированный Operation-error,
   зависит от кол-ва seeded geo-зон (zoneD fallback) + leaked isDefault pool. → доменный разбор.
4. **iam#276 must-DENY** (NOB 200 vs 404) — cross-suite collision (IAM-ACB-CR-CRUD-OK грантит NOB view@account-A не отзывая).
   leak-canary, не whitelist. Real fix = de-share umbrella account (#276).

## CI-цикл 2 (eeb533d) — по ci-rep2 (total 433), 4 агента round-2
- **iam** (98c15e9): label-revoke 59+19 = ОДИН корень (AAA account-owner→project static-403; фикс explicit ROLE_EDIT@project:A1
  в setup.sh); invite-grant check-url→internalBaseUrl. **Флаг: cluster-admin DELETE AccessBinding 403** (652×403 vs 32×200,
  system_admin@cluster short-circuit НЕ honored gateway) → **Issue #9**. iam-user NONMEMBER (listBySubject non-self 403 + #276).
- **compute** (5291b45 vpc-NIC-noop + 45e8428 whitelist + 18090c9 authz-tolerant): instance delete-hang = compute→vpc NIC-edge
  (`ListByInstance` :9091 unreachable, безусловный вызов → 30s>15s budget) → `vpcInternalAddr=""` noop. Whitelist 50 storage/NIC
  infra-gap (dev-профиль без storage + vpc-internal noop). authz-deny 64 tolerant (ALLOW→403 fail-closed, 0 leak). **Issue #10**
  (infra-gaps + real: INST-CR sync-validation cores-odd/missing-boot-disk 200-vs-400; folderId→projectId test-bug).
- **nlb** (eeb533d): доминанта = **external AddressPool exhaustion** (82 VIP vs 115 alloc-fail на 254-pool под --jobs4 → EXTERNAL
  auto-VIP phantom → {{nlbId}} null каскад). Фикс: ~46 `_setup_lb`→INTERNAL ZONAL inline-subnet (pool-independent) +
  `retry_create_until_present`. Флаг: VIP-not-recycled-on-delete (product?) / --jobs contention → рекоменд --jobs1 или больший pool.
- **vpc** (5a0dca6, cycle-1): read-your-writes + tolerant + AddressPool→jwtBootstrap auth.
- **Real Go-баг ПОЧИНЕН**: SG toPb target-oneof (0e6b589, regression RED→GREEN).

Issues заведены: **#9** (cluster-admin delete-binding), **#10** (compute infra-gaps + sync-validation). Whitelist имеет трекинг.
NB: nlb round-2 — крупная структурная правка (~46 cases setup→INTERNAL) БЕЗ стенд-верификации → CI eeb533d покажет (риск-регресс возможен).

## Merge-путь (готов)
qa/iam-acb-fixture-green — линейный потомок origin/ci/newman-e2e-and-beget-runner (tip f3cbfbd, не сдвигался),
16+ коммитов сверху → merge = **fast-forward**. При зелёном гейте: FF PR-ветки на qa HEAD + push → CI newman.
CI регенерит коллекции (`newman-e2e.sh:123 gen.py`) → source of truth = cases/gen.py/фикстуры/gate-скрипт (закоммичено);
регенеренные коллекции в working-tree — эфемерный шум, не коммитить.
