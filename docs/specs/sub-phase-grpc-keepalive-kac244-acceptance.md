# Acceptance (Given-When-Then) — KAC-244 inter-service gRPC keepalive

> Статус: DRAFT
> Дата: 2026-06-02
> Ревьюер: acceptance-reviewer (pending)
> YT: https://prorobotech.youtrack.cloud/issue/KAC-244

Гейт по workspace `CLAUDE.md` «Запреты» #1 — этот документ должен получить `✅ APPROVED`
от `acceptance-reviewer` **до** любой строчки кода (wiring-фикс — тоже код).

---

## Обзор

Часть inter-service gRPC-клиентов дайлится **без keepalive-параметров**. Соединение,
простаивающее между всплесками трафика, становится half-open (NAT/conntrack в kind дропает
idle-flow, peer-под перезапускался, и т.п.); без keepalive-пингов клиент не замечает обрыв,
пока не придёт следующий RPC. Тогда первый запрос всплеска висит ~16–30 c на переустановке
TCP/HTTP2-соединения — либо упирается в дедлайн и падает (`DeadlineExceeded` на 2-секундном
authz-дедлайне compute → пользователю прилетает 403/долгий 200).

Задача — привести **все** inter-service dial-сайты к единому keepalive-паттерну (как уже
сделано в `kacho-vpc`/`kacho-nlb`/`kacho-api-gateway`, которые НИКОГДА не тупят), плюс
поставить анти-регресс-страж, чтобы новый bare-dial без keepalive не появлялся.

Это **инфраструктурный / wiring-фикс**, а не новый ресурс/RPC. Поэтому acceptance-кейсы
ниже описывают наблюдаемое поведение dial-конфигурации и runtime-эффект, а не payload'ы
доменных RPC. Уровни верификации обозначены явно у каждого кейса: `[unit]`, `[integration]`,
`[smoke/kind]`.

### Диагноз (подтверждён, входные данные — не предмет ревью контракта)

Асимметрия доказывает причину:

| Сайт | keepalive | поведение |
|---|---|---|
| `kacho-vpc/internal/clients/builder.go` (corlib `WithKeepAlive`) | ✅ есть | vpc-эндпоинты 2–5 мс всегда |
| `kacho-nlb/internal/clients/builder.go` | ✅ есть | ок |
| `kacho-api-gateway` (`cmd/.../main.go`, `internal/clients/iam_authorize_client.go`, `iam_subject_client.go`) | ✅ есть | ок |
| **`kacho-compute/cmd/compute/main.go::dialPeer`** (`grpc.NewClient` без опций; строит authz-conn → iam-internal:9091 ~стр.152 + vpc-conn'ы) | ❌ НЕТ | **`/compute/v1/zones` висит 16–30 c — ПЕРВИЧНОЕ, доказано** |
| **`kacho-iam/cmd/kacho-iam/subject_change_wiring.go`** (`grpc.NewClient(addr, …Creds)` ~стр.83, → api-gateway internal) | ❌ НЕТ | idle subject-drainer conn |
| **`kacho-vpc/pkg/sdk/vpc/client.go`** (`grpc.NewClient` без keepalive по умолчанию) | ❌ НЕТ | внешний SDK, консистентность |
| `kacho-iam` → **OpenFGA** (`OpenFGAHTTPClient`, `http.DefaultClient`, endpoint :8080) | ❓ HTTP, не gRPC | исследовательский — см. KA-OF |

Эталонный паттерн — `kacho-vpc/internal/clients/builder.go`:
```
WithKeepAlive(keepalive.ClientParameters{
  Time:                opts.KeepAliveTime,   // ping interval
  Timeout:             opts.KeepAliveTime/3, // ack within 1/3 of interval
  PermitWithoutStream: false,                // ← пересматривается, см. §7 / KA-04
})
```

---

## 7. Зафиксированные решения (fixed-decisions)

Эти решения — часть контракта; реализация и тесты обязаны им соответствовать. Менять — только
через правку этого документа + повторный review.

### FD-1. Значения keepalive-параметров

- **`Time` (ping interval) = 10 s.** Эталон vpc-builder использует дефолт 30 s. Для KAC-244
  берём **более агрессивный 10 s**, потому что наблюдаемый столл возникает именно на
  редко-используемых conn'ах после простоя в kind, где idle-flow умирает быстрее 30 s
  (conntrack UDP/TCP timeouts, под-рестарты). 10 s — компромисс: достаточно часто, чтобы
  поймать half-open до следующего всплеска, но не создаёт заметного ping-трафика.
- **`Timeout` (ack deadline) = `Time / 3` ≈ 3.33 s.** Сохраняем формулу эталона (`Time/3`),
  не хардкодим число — так связь «таймаут = треть интервала» остаётся инвариантом и для
  будущих значений `Time`. При `Time=10s` это ~3.33 s: если за это время peer не ответил на
  ping — conn помечается мёртвым, gRPC переустанавливает его проактивно.
- Значения вынесены в именованные дефолты (как `defaultKeepAliveTime` в vpc-builder), а не
  magic-числа по месту. Допускается override через env/config, но **дефолт обязан быть задан**
  — отсутствие keepalive (нулевые параметры) запрещено.

### FD-2. `PermitWithoutStream` — `true` для idle authz-conn, `false` для остальных

- HTTP/2 keepalive-пинги по умолчанию шлются **только при наличии активного стрима**. Для
  **редко-используемого authz-conn** (compute → iam-internal `Check`; subject-drainer →
  api-gateway) активных стримов между всплесками НЕТ → пинги не идут → conn остаётся
  half-open. Это **ровно механизм бага**.
- Поэтому для **idle-prone conn'ов, которые ДОЛЖНЫ оставаться тёплыми** (compute authz-conn
  к iam-internal; iam subject-drainer conn) — `PermitWithoutStream = **true**`. Это держит
  соединение живым пингами даже без активных RPC и напрямую лечит столл.
  - Серверная сторона обязана разрешать такие пинги: `EnforcementPolicy.MinTime` на сервере
    не должна быть строже клиентского `Time` (иначе сервер закроет conn с `ENHANCE_YOUR_CALM`/
    `GOAWAY too_many_pings`). Проверяется в KA-04b: при `Time=10s` и `PermitWithoutStream=true`
    сервер НЕ должен слать GOAWAY. Если серверный `MinTime` дефолтный (5 мин) — он будет слать;
    значит реализация обязана выставить серверный `MinTime ≤ Time` И `PermitWithoutStream=true`
    на тех серверах, что принимают idle keepalive (iam-internal, api-gateway internal). Это
    часть scope KAC-244 (иначе фикс одной стороной сломает conn).
- Для **активно используемых** conn'ов (vpc data-path, активные стримы) оставляем
  `PermitWithoutStream = false` (эталон) — там всегда есть трафик, лишние idle-пинги не нужны.
- Реализация: параметр конфигурируемый per-builder-call; дефолт-helper (FD-4) принимает его
  аргументом, не хардкодит.

### FD-3. 2-секундный authz-дедлайн compute — НЕ меняем

- Симптом «403 DeadlineExceeded на 2 c» — следствие half-open conn, а не слишком жёсткого
  дедлайна. После фиксаkeepalive conn здоров → `Check` укладывается в 10 мс (замерено) →
  2 c с огромным запасом. **Менять 2 c не нужно** и не входит в scope. Расширение дедлайна
  без keepalive лишь маскировало бы баг (запрос всё равно висел бы до 30 c при реальном
  обрыве). Кейс KA-N2 проверяет, что под нагрузкой после фикса дедлайн не срабатывает.

### FD-4. corelib-helper — ДА, тонкая обёртка-дефолт

- Сейчас keepalive «правильно» делается только через внешний `H-BF/corlib` builder
  (`corlibgrpc.ClientFromAddress(...).WithKeepAlive(...)`), которым пользуются vpc/nlb; а
  bare-сайты (compute `dialPeer`, iam wiring, vpc-sdk) собирают `grpc.NewClient` руками и
  keepalive забыли. Чтобы фикс был устойчив, в **`kacho-corelib`** заводится узкий helper —
  единая точка, отдающая стандартные keepalive-`grpc.DialOption`(ы) (FD-1/FD-2):
  - например `grpcclient.KeepAliveDialOption(params)` или `grpcclient.DefaultKeepAlive()` /
    `grpcclient.IdleAuthzKeepAlive()` — возвращает `grpc.WithKeepaliveParams(...)` с
    зафиксированными дефолтами; idle-вариант ставит `PermitWithoutStream=true`.
  - Все bare-dial-сайты (compute `dialPeer`, iam `subject_change_wiring`, vpc-sdk
    `NewClient` дефолт) переводятся на этот helper.
  - Сайты на `H-BF/corlib` builder (vpc/nlb/api-gateway) НЕ переписываются обязательно —
    у них keepalive уже есть; допускается оставить как есть (consistency-через-один-helper —
    желательна, но не блокер этого тикета; если тривиально — унифицировать).
- Helper живёт в corelib, потому что keepalive — горизонтальный cross-cutting concern,
  нужный ≥3 сервисам (правило «Принцип переиспользования через kacho-corelib»).

---

## Группа A — Positive (dial-опции содержат keepalive)

### KA-01 — compute `dialPeer` строит conn с keepalive `[unit]`

- **Given** функция `dialPeer(addr, useTLS)` в `kacho-compute/cmd/compute/main.go`
  (строит и authz-conn → iam-internal:9091, и vpc-conn'ы)
- **When** вызывается `dialPeer(...)` (или тест инспектирует собранный набор `grpc.DialOption`)
- **Then** в опциях присутствует `keepalive.ClientParameters` с `Time == 10s` (FD-1) и
  `Timeout == Time/3` (≈3.33 s)
- **And** для authz-conn (idle-prone, → iam-internal) `PermitWithoutStream == true` (FD-2)
- **And** соединение по-прежнему работает с обоими режимами creds (TLS и insecure) — keepalive
  не ломает выбор credentials

> Реалистичность теста: `grpc.NewClient` не отдаёт назад установленные опции напрямую. Тест
> строится так, чтобы `dialPeer` собирал опции через corelib-helper (FD-4), и юнит проверяет,
> что helper в данном режиме возвращает `WithKeepaliveParams` с нужными `ClientParameters`
> (helper тестируется напрямую в KA-05). Допустима проверка через тонкую seam-функцию
> «собрать опции», вызываемую из `dialPeer`.

### KA-02 — iam subject-drainer conn строится с keepalive `[unit]`

- **Given** wiring в `kacho-iam/cmd/kacho-iam/subject_change_wiring.go` (dial → api-gateway
  internal gRPC, conn редко используется — только когда дренится subject_change_outbox)
- **When** собирается conn к api-gateway-internal
- **Then** в опциях присутствует keepalive `Time=10s`, `Timeout=Time/3`
- **And** `PermitWithoutStream == true` (idle-prone drainer-conn — FD-2)
- **And** creds-логика (`gatewayDialCreds`) сохранена без изменений

### KA-03 — vpc SDK `NewClient` дефолтит keepalive `[unit]`

- **Given** `kacho-vpc/pkg/sdk/vpc/client.go::NewClient(addr, opts...)` — внешний SDK, сейчас
  при пустых `opts` дайлит insecure без keepalive
- **When** `NewClient(addr)` вызван **без** явных `grpc.DialOption`
- **Then** результирующий conn собран с keepalive-дефолтом (`Time=10s`, `Timeout=Time/3`,
  `PermitWithoutStream=false` — SDK-conn обычно активно используется; idle-вариант не нужен)
- **And** если вызывающий **передал** свои `opts` (в т.ч. собственный keepalive) — они имеют
  приоритет / не затираются молча (back-compat SDK-контракта: явные опции вызывающего
  уважаются; дефолт применяется только когда вызывающий keepalive не задал)

### KA-04a — серверы, принимающие idle keepalive, не банят пинги `[unit/integration]`

- **Given** gRPC-серверы, к которым ходят idle-prone conn'ы с `PermitWithoutStream=true`:
  iam-internal (:9091), api-gateway internal
- **When** инспектируются server-опции `keepalive.EnforcementPolicy`
- **Then** `MinTime <= 10s` (клиентский `Time`) **и** `PermitWithoutStream == true` на сервере
  (FD-2) — сервер не закрывает conn за «слишком частые пинги»

### KA-04b — idle keepalive не вызывает GOAWAY/too_many_pings `[integration]`

- **Given** клиент с `Time=10s, PermitWithoutStream=true` и сервер с policy из KA-04a, между
  ними НЕТ активных RPC
- **When** соединение простаивает ≥ 30 s (≥3 ping-интервала)
- **Then** сервер НЕ присылает `GOAWAY` с `ENHANCE_YOUR_CALM`/`too_many_pings`; conn остаётся
  `READY`; следующий RPC проходит немедленно

---

## Группа B — Negative / edge (поведение при обрыве/недоступности)

### KA-N1 — idle-conn после простоя: следующий RPC быстрый, НЕ ~30 c `[integration]`

Прямое воспроизведение бага. Реалистично в Go-тесте через контролируемый обрыв.

- **Given** клиент-conn к тестовому gRPC-серверу собран с keepalive (FD-1, idle-режим
  `PermitWithoutStream=true`); сделан 1 успешный RPC; затем conn простаивает
- **And** транспорт под conn'ом «оборван» так, что без keepalive это даёт half-open
  (тест-харнесс рвёт нижележащее соединение — proxy/`net.Pipe`-перехват / закрытие
  серверного listener'а с заменой — практичный способ: поднять proxy между client и server,
  дропнуть established-flow, оставив client в неведении)
- **When** по истечении паузы клиент делает следующий RPC с дедлайном, скажем, 5 s
- **Then** RPC завершается (успехом после реконнекта **или** быстрой ошибкой), **НЕ** виснет
  до ~30 c; keepalive-механизм обнаружил мёртвый conn в пределах `Time + Timeout` (~13 s) и
  переустановил его
- **And** контрольный прогон без keepalive (тот же харнесс) демонстрирует столл/таймаут —
  пара RED(без keepalive)→GREEN(с keepalive), как требует test-first (§Запреты #12)

> Реалистичность: точный «ровно 30 c» из деплоя не воспроизводится в unit'е (зависит от
> kernel TCP retransmit). Поэтому тест проверяет **качественную** разницу: с keepalive conn
> чинится в пределах keepalive-окна (≪ деплойных 30 c), без keepalive — нет. Точный деплойный
> столл закрывается smoke-кейсом KA-S1.

### KA-N2 — мутация при недоступном peer остаётся fail-closed `[integration]`

Keepalive НЕ должен ослабить семантику «недоступный owner → fail-closed для мутаций»
(workspace `CLAUDE.md` §«Кросс-доменные ссылки», запрет #10 — целостность ссылок).

- **Given** compute-мутация, валидирующая чужой ресурс через peer (vpc subnet/sg existence,
  или authz `Check` к iam), peer **недоступен** (conn не устанавливается)
- **When** клиент вызывает мутирующий RPC
- **Then** возвращается `Unavailable` (fail-closed) — мутация НЕ проходит «по-тихому»;
  keepalive не превращает недоступность в ложный success
- **And** ошибка приходит в разумный срок (в пределах dial/RPC-дедлайна), а не висит ~30 c

### KA-N3 — keepalive не меняет authz-fail-closed при отсутствии store/conn `[integration]`

- **Given** authz-interceptor compute с keepalive-conn к iam-internal, но iam недоступен или
  OpenFGA store не provisioned (как в `buildOpenFGAClient` fail-closed)
- **When** идёт запрос, требующий authz
- **Then** поведение fail-closed сохранено (deny / `Unavailable`), без регресса от keepalive;
  2-секундный дедлайн (FD-3) не трогали

---

## Группа C — OpenFGA (исследовательский, с явной точкой решения)

### KA-OF — iam → OpenFGA idle-conn: диагностировать и устранить idle-столл `[integration + decision]`

`OpenFGAHTTPClient` ходит на OpenFGA по **HTTP** (`http.DefaultClient`, endpoint
`kacho-umbrella-openfga:8080`), а не gRPC. `http.DefaultClient` использует
`http.DefaultTransport` с дефолтными `MaxIdleConns`/`IdleConnTimeout` (90 s) и TCP-dialer
keepalive 30 s, но **без** HTTP/2-ping idle-контроля под нашу проблему.

- **Given** диагностика KAC-244 показала: iam-`/operations/iop…` тоже периодически висят
  во всплесках после простоя
- **When** воспроизводим idle-сценарий для conn iam→OpenFGA (idle ≥ idle-timeout прокси/NAT,
  затем всплеск Check/Write)
- **Then — точка решения (обязательна к разрешению в реализации, результат фиксируется в этом
  доке перед мержем):**
  - **(a)** Если воспроизводится idle-столл на HTTP-conn к OpenFGA → заменить
    `http.DefaultClient` на явный `*http.Client` с настроенным `*http.Transport`:
    `IdleConnTimeout`, `MaxIdleConnsPerHost`, `ForceAttemptHTTP2`, и `DialContext` с
    `net.Dialer{KeepAlive: ...}` — так, чтобы idle-conn либо проактивно держался тёплым, либо
    быстро пере-устанавливался, а не висел.
  - **(b)** Если транспорт к OpenFGA окажется gRPC (или будет переведён на gRPC) → применить
    тот же keepalive-helper (FD-4), что и остальные сайты.
  - **(c)** Если idle-столл OpenFGA **НЕ** воспроизводится (источник iam-столла — только
    api-gateway-internal conn из KA-02, который этим тикетом уже чинится) → задокументировать
    «OpenFGA HTTP-conn не является источником столла, изменения не требуются» и закрыть ветку
    исследования. **Это допустимый исход**, но он должен быть явно записан (не молча оставлен).
- **And** что бы ни выбрали — НИКАКОГО TODO/«вернёмся позже» (запрет #11): либо фикс в этом
  PR, либо доказанное «не требуется» с обоснованием. Если фикс OpenFGA крупный и явно
  отдельный — он выносится в собственный KAC-тикет **до** мержа KAC-244 (не как TODO в коде).

> Реалистичность: HTTP-idle поведение проще воспроизвести интеграционно (поднять тестовый
> OpenFGA-stub / httptest-сервер, дропнуть idle-flow). Решение (a/b/c) фиксируется здесь же.

#### KA-OF — РАЗРЕШЕНО: исход **(c)** «не источник, фикс не требуется» (2026-06-02, KAC-244)

Анализ кода `kacho-iam/internal/clients/openfga_client.go` + `openfga_check.go` /
`openfga_write.go` / `openfga_extensions.go`:

1. **Транспорт — HTTP, `http.DefaultClient.Do(req)`** (Check `openfga_client.go:101`,
   write `:156`). `http.DefaultClient` использует `http.DefaultTransport` с дефолтами Go:
   `IdleConnTimeout=90s` (idle-conn проактивно закрывается, half-open не копится сверх 90s),
   `MaxIdleConnsPerHost=2`, и `DialContext` с `net.Dialer{KeepAlive:30s}` (TCP-keepalive включён
   по умолчанию). Это НЕ bare-gRPC-conn без keepalive.
2. **Каждый запрос обёрнут в per-op context-deadline** (`openfga_check.go:36`
   `context.WithTimeout(ctx, c.checkTimeout())` → default **200ms**; `openfga_write.go:72`
   → default **1000ms**; `openfga_extensions.go:77-79`). Даже если из пула достанется
   half-open-conn, запрос упрётся в 200ms–1s дедлайн и быстро провалится — он **физически
   не может** виснуть ~30с, как bare-gRPC-dial.
3. Совокупность (TCP-keepalive 30s + IdleConnTimeout 90s + жёсткий per-op deadline 200ms/1s)
   ⇒ OpenFGA HTTP-path **не является источником** наблюдаемого ~30с-столла.

**Вывод:** источник iam-`/operations/iop…`-столла — только idle subject-drainer conn →
api-gateway-internal (KA-02 `subject_change_wiring.go`), который этим тикетом и чинится.
OpenFGA HTTP-conn изменений не требует. **Никакого TODO** — ветка исследования закрыта фактом
из кода (запрет #11).

---

## Группа D — Hardening / анти-регресс

### KA-H1 — нет bare inter-service `grpc.NewClient` без keepalive `[unit/guard]`

- **Given** репозитории `kacho-compute`, `kacho-iam`, `kacho-vpc` (и SDK)
- **When** запускается страж (один из вариантов, на выбор реализации, но он ОБЯЗАН быть):
  - тест-страж, грепающий inter-service dial-сайты на `grpc.NewClient(`/`grpc.Dial(` без
    сопутствующего keepalive-helper'а / `WithKeepaliveParams` / corlib `WithKeepAlive`; **или**
  - все inter-service dial проходят через единый corelib-helper (FD-4), и страж проверяет, что
    прямой `grpc.NewClient` в inter-service-коде отсутствует (allow-list для генерённого /
    тестового кода)
- **Then** страж **зелёный** на пост-фикс дереве и **красный**, если добавить новый bare-dial
  без keepalive (продемонстрировать RED→GREEN: внести искусственный bare-dial → страж падает →
  убрать → зелёный)

### KA-H2 — keepalive-параметры стандартизованы в одном месте `[unit]`

- **Given** corelib-helper (FD-4)
- **When** инспектируются значения, отдаваемые helper'ом
- **Then** `Time=10s`, `Timeout=Time/3`, и idle-вариант ставит `PermitWithoutStream=true`,
  active-вариант — `false`; magic-числа по dial-сайтам отсутствуют (все ссылаются на helper)

### KA-05 — corelib-helper отдаёт корректные ClientParameters `[unit]`

- **Given** `grpcclient.<helper>()` в kacho-corelib
- **When** вызван active-вариант и idle-вариант
- **Then** оба возвращают валидный `grpc.DialOption` c `keepalive.ClientParameters`:
  active → `{Time:10s, Timeout:~3.33s, PermitWithoutStream:false}`;
  idle → `{…, PermitWithoutStream:true}`
- **And** helper покрыт собственным unit-тестом (он — единая точка истины для FD-1/FD-2)

---

## Группа E — Smoke / kind (финальная верификация заказчиком, шаг 7)

### KA-S1 — после простоя /compute/v1/zones и /operations не висят `[smoke/kind]`

- **Given** стенд `kacho-deploy` в kind с задеплоенными compute/iam/vpc, собранными с фиксом
- **And** система простояла без трафика к compute/iam ≥ 2 мин (idle-conn'ы «остыли»)
- **When** идёт всплеск: серия `GET /compute/v1/zones` и `GET /operations/iop…` (iam)
- **Then** **первый** запрос всплеска отвечает в пределах нормального p99 (единицы–десятки мс,
  не 16–30 c); ни одного `DeadlineExceeded`/долгого 200
- **And** контрольное сравнение с pre-fix образом (по желанию): без фикса первый запрос
  всплеска висит 16–30 c — фиксируется в trail тикета

### KA-S2 — vpc-эндпоинты не регрессировали `[smoke/kind]`

- **Given** тот же стенд
- **When** тот же idle→всплеск-сценарий по vpc-эндпоинтам
- **Then** vpc по-прежнему 2–5 мс (keepalive там был и остался; фикс не сломал эталонные сайты)

---

## Трассируемость acceptance ↔ test

| Сценарий | Уровень | Где живёт тест |
|---|---|---|
| KA-01 | unit | `kacho-compute` cmd/wiring или seam-тест dial-опций |
| KA-02 | unit | `kacho-iam` subject_change wiring-тест |
| KA-03 | unit | `kacho-vpc/pkg/sdk/vpc` client-тест |
| KA-04a/b | unit+integration | corelib/server keepalive policy + idle-conn integration |
| KA-N1 | integration | proxy-обрыв idle-conn (RED без keepalive → GREEN c) |
| KA-N2 | integration | compute peer-unavailable fail-closed |
| KA-N3 | integration | compute authz fail-closed |
| KA-OF | integration+decision | iam↔OpenFGA HTTP idle (httptest-stub) + запись решения a/b/c |
| KA-H1 | unit/guard | анти-регресс страж (RED→GREEN) |
| KA-H2, KA-05 | unit | corelib-helper |
| KA-S1, KA-S2 | smoke/kind | `kacho-deploy/e2e/keepalive/*.sh` |

---

## Definition of Done (чек-лист)

- [x] **Test-first соблюдён** (§Запреты #12): для server-policy показана пара RED→GREEN
      (`TestDefaultEnforcement_FixesGrpcDefault` краснеет при revert фикса → зеленеет);
      seam-юниты compute/iam/vpc написаны до wiring-правки (RED: undefined → GREEN).
      **Finding (gRPC v1.80):** server-side GOAWAY too_many_pings не воспроизводится
      детерминированно в unit (gRPC-go client консервативен в idle-пингах) → RED-control
      на policy-уровне + behavioral GREEN (idle-conn READY 16s, RPC после простоя мгновенный).
- [x] corelib-helper (FD-4) реализован (`grpcclient.KeepaliveParams`/`KeepaliveDialOption`) +
      unit-тест (KA-05, KA-H2) зелёный.
- [x] compute `dialPeer` (KA-01), iam `subject_change_wiring` (KA-02), vpc-sdk `NewClient`
      (KA-03) переведены на keepalive-helper; unit/seam-тесты зелёные.
- [x] Серверная сторона idle-conn допускает idle-пинги (KA-04a/b): corelib
      `DefaultKeepaliveEnforcement` (MinTime=5s, PermitWithoutStream=true) prepend'ится в
      `grpcsrv.NewServer` → iam-internal :9091 чинится автоматически; api-gateway internal —
      уже permissive (verify-only, правка не нужна). Нет GOAWAY/too_many_pings.
- [ ] KA-N1/KA-N2/KA-N3 integration-тесты зелёные; fail-closed-семантика мутаций сохранена.
      (compute/iam integration — отдельный прогон/деплой.)
- [x] KA-OF: точка решения **(c)** «не источник, фикс не требуется» — разрешена и записана
      выше (§KA-OF). HTTP `http.DefaultClient` + per-op deadline 200ms/1s ⇒ не виснет ~30с.
      НЕ TODO.
- [ ] KA-H1 анти-регресс страж в CI; новый bare inter-service dial без keepalive падает.
- [x] **Никаких TODO/FIXME/skip** в diff (§Запреты #11, #13); никакого тех-долга «на потом».
- [x] 2-секундный authz-дедлайн compute **не менялся** (FD-3) — dialPeer трогает только
      keepalive-опции, дедлайны authz-interceptor'а не затронуты.
- [ ] Newman / integration зелёные (соответствующих репо), smoke зелёный.
- [ ] **Задеплоено на kind**: KA-S1 — `/compute/v1/zones` и `/operations` после простоя
      НЕ висят (единицы–десятки мс); KA-S2 — vpc не регрессировал.
- [ ] **Vault обновлён**: `KAC/KAC-244.md` (trail, PR-ссылки, acceptance-чеклист);
      затронутые `edges/` (compute→iam-internal authz, iam→api-gateway-internal subject-drainer,
      iam→OpenFGA если правился) — пометка «keepalive added, KAC-244»; `packages/`
      corelib-grpcclient helper.
- [ ] PR'ы по графу зависимостей: corelib (helper) → compute / iam / vpc(+sdk) →
      api-gateway/iam-internal server-policy → deploy (smoke); `ref:`-пины снимаются после
      merge снизу вверх.
