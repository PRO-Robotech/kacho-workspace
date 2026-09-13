# Сквозные пробы newman: eventual-consistency и параллельный прогон

Часть правила `.claude/rules/testing.md`. Инварианты, общие всем suite'ам — RYW-retry,
authz-first толерантность негативов, per-service fixture isolation, идемпотентность
прогона, — живут там же, §«e2e-инварианты», и здесь не повторяются.

Kachō eventually-consistent (`api-conventions.md` Operation.done), поэтому black-box newman
обязан быть **robust к read-your-writes окну**, но НИКОГДА не маскировать реальный дефект.

## op-poll с РЕАЛЬНОЙ inter-poll задержкой (выведено из owner-tuple раундов)

**Норма.** Busy-wait ~400-500ms в retry-петле, budget покрывает async-op tail ~15s:
back-to-back поллы без задержки хаммерят и сами создают нагрузку. Правило относится к
**КАЖДОЙ рукописной петле**, не только к хелперам `gen.py`: любой
`pm.execution.setNextRequest(pm.info.requestName)` (self-retry) ОБЯЗАН иметь busy-wait
**непосредственно перед ним** — `const _x = Date.now(); while (Date.now() - _x < N) void 0;`
(newman исполняет test-script синхронно и вызывает `setNextRequest` ДО любого `setTimeout` →
busy-wait — единственный способ реально разнести поллы).

**Цена измерена.** Без него петля на 30 итераций покрывает **~0.15s**, а не секунды: op
завершался за 3.6s, а кейс сдавался мгновенно (инцидент `IAM-USR-INV-CRUD-OK`; sweep нашёл
**51** такую петлю в **26** case-файлах iam/registry/nlb).

**Задержку размеряй от cap петли, а не константой**: `delay = clamp(30000/cap, 100..500)ms` —
caps в delay-less петлях исторически раздували именно чтобы компенсировать отсутствие
ожидания (`POLL_CAP=300`), поэтому фиксированные 500ms дали бы 150s worst-case.

**Проверка (grep-гейт):** каждый `setNextRequest(pm.info.requestName)` имеет
`while (Date.now() - _` в пределах 4 строк выше.

**Симптом класса**: «поллер сдался, хотя async-хвост был здоров» — выглядит как
materialization-лаг сервиса, а на деле проба вообще не ждала.

## Fixture-seed обязан проверять `op.error` перед извлечением id из `metadata`

Kachō Operation несёт **pre-allocated id в `metadata` ДАЖЕ на `done:true` с `error`** (id
аллоцируется до async-фейла). Хелпер `ensure_<resource>`, читающий `metadata.<res>Id` без
проверки `result.error`, вернёт **фантомный id** несозданного ресурса → пропатчит его в env →
downstream FGA-биндинги пишутся против фантома (gateway 200), а cross-service peer-check
(`vpc/compute → iam ProjectService.Get`) отдаёт `NOT_FOUND` → каскад.

**Всегда:** op-poll до `done` → assert `!op.error` → только тогда извлекай id. Флейки-фикстура —
предпочти **self-seed свежего ресурса per-case** (не shared-литерал env-var, который мог
async-упасть), как `discover_zone`/`create_suite_project`.

## Serialised suite (`--jobs 1`) для pool-contended ресурсов

Кейсы, аллоцирующие из ограниченного пула (external VIP/AddressPool, N адресов), под
`--jobs >1` исчерпывают пул → `could not allocate` → phantom-ресурс → каскад. Либо больший пул
(seed-CIDR), либо `--jobs 1` для этой суиты, либо перевод на pool-independent ресурс (INTERNAL
вместо EXTERNAL). Проверь **recycle-on-delete** — если пул не возвращает адрес на Delete, это
product-баг.

## Параллельный прогон суит и точечный debug

`newman-parallel.sh` fan-out iam/vpc/compute/nlb после единого seed → wall-time = max(суита),
убирает serial-timeout (суиты независимы **при изоляции**). Debug — точечно:
`newman run collections/<битая>.json` + `--folder <case>`; Go-фикс →
`make reload-svc SVC=x` (patch без dev-up) → re-run той коллекции.

## Параллельный newman — слоёная parallel-safety (выведено из e2e-newman стабилизации 2026-07, serial 90мин→parallel ~35мин)

Fan-out суит требует НЕ одного фикса, а **пирога** — каждый слой обнажает следующий. При
«довести параллельный e2e до зелёного» проверяй ВСЕ (не сдавайся на «ещё 1 суита» — хвост
движется, но конечен):

1. **Throughput материализации grant** — owner-tuple создателя должен материализоваться быстро под N× нагрузкой. Форвард
   fast-path (`ReconcileObjectForward`, additive per-object, **SHARE**-advisory-lock не EXCLUSIVE → concurrent creates
   сосуществуют). Full `ReconcileObject` (EXCLUSIVE-lock) сериализует — под параллелью дрейнит. См. `data-integrity.md`.
2. **Create vs update дискриминатор** — регистрация ресурса у владельца прав (`RegisterResource`) зовётся
   не только на create, но и на **правку меток**. Аддитивный fast-path (никогда не удаляет) на правке
   означает «добавить и ничего не снять» — то есть **снятие права просто не применяется**. Fast-path обязан
   различать: нет existing-members ⇒ create→forward; есть ⇒ update→full (delete-stale). Проверять надо
   **исход отзыва**, а не факт вызова: аддитивный путь на отзыве зелёный по всем «вызвали/эмитировали»
   утверждениям и неверен ровно в том, ради чего отзыв делается.
3. **Волновая изоляция iam** — iam-СОБСТВЕННАЯ authz-материализация (AccessBinding CRUD, label-revoke) идёт full-path
   EXCLUSIVE-lock; под конкурентной leaf-нагрузкой (vpc/compute/nlb регистрируют ресурсы) дрейнит (get-confirms 404,
   revoke-not-sticking). Гони iam **отдельной волной** (`PHASE2_SERVICES=iam` в newman-parallel.sh) — без конкурирующей нагрузки.
4. **Полная fixture-изоляция** (серийно скрыта, параллельно рвётся): (a) **shared no-binding subject** — grant-суиты его
   реально грантят → течёт в see-nothing leak-guard'ы через account→project containment → выделенный **never-granted**
   `jwtPureNoBindings`; (b) **AddressPool default-per-(zone,kind)** — zone-collapse (3 geo-зоны, zoneC≡zoneD) + cross-service
   shared CIDR EXCLUDE → disjoint CIDR-блоки + serial-tail contended-коллекций (`serial-collections.txt`); (c) **account-member
   visibility floor** — `ProjectService.List` возвращает ВСЕ проекты аккаунта члену → бьёт by-label narrowing → fresh per-run
   private account для exact-visibility кейсов.
5. **Shared-resource CIDR/name collision маскируется под EC-флейк** — «блуждающий» флейк (1-2 РАЗНЫЕ суиты/прогон) часто НЕ
   eventual-consistency, а **детерминированная коллизия**: subnet-CIDR `10.{hash(runId)%N}.{seq}.0/24` — общий runId → тот же
   октет для всех коллекций, `seq` рестартит с 1 в каждом newman-процессе → параллельные процессы коллизят; какой hash попадёт
   на насыщенную band — дрейфует по прогонам → «блуждание». Фикс: широкая run-random энтропия ОБОИХ октетов (~56k /24), НЕ
   retry-обёртки. При «блуждающем» флейке — **проверь shared-resource collision (CIDR/pool/name) ПЕРЕД тем как винить EC**.
6. **Idempotency/phantom под параллелью**: ALREADY_EXISTS (prior grant не отревокан — best-effort teardown принял transient
   403 → binding остался ACTIVE → strict-create UNIQUE-slot занят) → preclean-revoke обязан **ретраить DELETE на 403** до успеха,
   не fire-forget. «not found» под нагрузкой — phantom-id (§«Fixture-seed обязан проверять `op.error`») ИЛИ peer-RYW →
   `retry_create_until_present` message-discriminated (retry на 400/404+`/not found/`; валидационные 400 «cover all zones»/«overlap» проходят сквозь).
7. **Ordering-tolerance негативов**: peer-first-vs-authz-first — `move.go` зовёт `ProjectService.Get(dst)` ДО authz → недоступный
   dst → hide-existence 400 «not found» до scope-Check. STRICT-403-негатив неверен → tolerant `400/403/404, never 200`; реальный
   scope-deny всё равно pinned отдельным precond'ом (не маскировка).

**Мета**: массовая параллелизация большого e2e (65+ коллекций) — инженерная задача пирога throughput+isolation+idempotency,
а не «добавить retry». Retry-обёртки — для истинного read-your-own-writes EC-окна; НЕ лечат collision/phantom/idempotency
(там — fixture-изоляция/энтропия/preclean-retry). Прод-фиксы (форвард/lock/delete-stale) — TDD+db-review; тест-фиксы не маскируют.
