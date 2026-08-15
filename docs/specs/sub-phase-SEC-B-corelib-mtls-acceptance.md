# Sub-phase SEC-B — corelib mTLS transport (grpcsrv/grpcclient + identity-extractor) — Acceptance

> Статус: DRAFT
> Дата: 2026-06-11
> Ревьюер: acceptance-reviewer (pending)
> Эпик/тикет: SEC (mTLS + IAM-fronted authz + least-privilege) — см.
> `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`, подфаза **SEC-B** (таблица §4).
> Гейт по workspace `CLAUDE.md` «Non-negotiables» #1 (ban #1): этот документ обязан
> получить `✅ APPROVED` от `acceptance-reviewer` **до** любой строчки кода.

---

## Обзор

SEC-B даёт `kacho-corelib` транспортную основу для mTLS как **opt-in расширения** (эпик
требование #1, #2, #5; решение §3.2). Добавляются:
- TLS-credentials в `grpcsrv` (server-cert + client-CA, `RequireAndVerifyClientCert`);
- TLS-credentials в `grpcclient` (client-cert + server-CA + `server_name`);
- config-структуры `TLSServer{enable,cert_file,key_file,client_ca_files}` и
  `TLSClient{enable,cert_file,key_file,ca_files,server_name}`;
- identity-extractor из client-cert SAN (`spiffe://kacho/<sva-id>` — как непрозрачная строка),
  реализующий **инвариант доверия** (эпик design-review I2): principal-metadata доверяется
  на cluster-internal listener **⟺** peer прошёл mTLS client-cert verify из internal CA.

Это **горизонтальный транспортный/wiring-слой**, не новый доменный ресурс/RPC. Поэтому
сценарии ниже описывают наблюдаемое поведение TLS-handshake, конфигурации и identity-extract,
а не payload'ы доменных RPC. Уровни верификации помечены у каждого кейса: `[unit]`,
`[bufconn]` (in-process gRPC через `bufconn` listener с настоящим TLS-handshake поверх
in-memory conn), `[guard]` (анти-регресс).

SEC-B самостоятельно НЕ включает mTLS ни на одном ребре стенда — она лишь делает его
**возможным** через флаги. Включение реальных рёбер (gateway→backend, vpc→iam, …) — SEC-D/E/G;
PKI (cert-manager) — SEC-F. **Мёрж SEC-B в `main` с `enable=false` повсеместно = текущее
insecure-поведение без изменений** (DoD-инвариант ниже, FD-1).

### Что НЕ входит в scope SEC-B (явно)

- Любая правка `cmd/<svc>/main.go` в сервисных репо (это SEC-D/E/G — wiring per-edge).
- cert-manager / Certificate / Issuer / secret-mount (SEC-F).
- Маппинг `client-cert identity → ServiceAccount` в IAM (это SEC-C; SEC-B даёт только
  **extract строки** identity из SAN, не её resolve в SA).
- Hot-reload сертификатов по file-watch (эпик §3.2 / решение §6.2 — restart-on-rotate для MVP).
  SEC-B читает cert-файлы один раз при старте; rotate = рестарт пода.
- Реальный AuthN/JWT (не меняется, эпик #7).

---

## Зафиксированные решения (fixed-decisions — часть контракта)

Эти решения нормативны для SEC-B; реализация и тесты обязаны им соответствовать. Менять —
только через правку этого документа + повторный review.

### FD-1. `enable=false` ⇒ строго текущее insecure-поведение (backward-compat)

- `TLSServer.enable=false` → `grpcsrv` отдаёт server без TLS (как сейчас:
  `insecure.NewCredentials()` на стороне сервера, т.е. plaintext listener).
- `TLSClient.enable=false` → `grpcclient` дайлит `insecure.NewCredentials()` (как сейчас).
- Дефолт обоих полей `enable` — `false`. Пустой/незаданный TLS-конфиг ⇒ insecure. Это
  гарантирует, что мёрж SEC-B в `main` без выставленных флагов не меняет dev-поведение
  (эпик DoD «`enable=false` — dev работает как сейчас (insecure)»).

### FD-2. Раздельные client- и server-credentials (эпик #5)

- Server-сторона использует **server-cert** (`TLSServer.cert_file`/`key_file`) + доверяет
  client'ам по **client-CA** (`TLSServer.client_ca_files`), `ClientAuth =
  RequireAndVerifyClientCert` (эпик §3.2: «server-cert + client-CA,
  RequireAndVerifyClientCert»).
- Client-сторона использует **client-cert** (`TLSClient.cert_file`/`key_file`) + доверяет
  серверу по **server-CA** (`TLSClient.ca_files`) + сверяет `server_name` против SAN
  серверного cert (эпик §3.2: «client-cert + server-CA + server-name»).
- Это два разных набора cert/key и два разных CA-bundle. SEC-B не предполагает один общий
  cert на обе роли (эпик #5: «два раздельных сертификата: client и server»).

### FD-3. Per-edge независимость (эпик решение §6.5 — rollback per-edge feature-flag)

- `enable` — поле **на каждый TLSServer/TLSClient инстанс**, не один глобальный switch.
  Один процесс может одновременно иметь TLS-сервер (`enable=true`) и insecure-клиент к
  какому-то peer (`enable=false`), и наоборот. Каждое ребро (`gateway→vpc/compute`,
  `vpc→iam`, `compute→iam`, `vpc↔compute`, `operator→vpc`) конфигурируется независимым
  `TLSServer`/`TLSClient`-блоком.
- corelib НЕ хранит глобального TLS-состояния и НЕ имеет process-wide TLS-синглтона
  (правило architecture.md: запрет глобальных синглтонов вне `cmd/`). Каждый
  `grpcsrv.NewServer(...)` / `grpcclient`-dial получает свой TLS-конфиг аргументом.

### FD-4. Инвариант доверия principal ⟺ mTLS (эпик design-review I2)

- identity-extractor (server-side interceptor/helper из corelib) на cluster-internal
  listener **доверяет** входящему `x-kacho-principal-*` (identity пользователя) **только
  если** peer прошёл mTLS client-cert verify из internal CA. Нет verified client-cert ⇒
  principal-metadata от такого peer НЕ доверяется (отбрасывается / не используется для authz).
- cert-identity (модуль, из SAN) и principal (пользователь, из metadata) — **ортогональны**
  и логируются ОБА (для аудита). cert-identity не подменяет principal и наоборот.
- Когда `TLSServer.enable=false` (insecure listener, dev-mode) — инвариант неприменим:
  client-cert'а нет, principal-metadata принимается как сейчас (backward-compat dev-mode,
  эпик security.md: «dev-mode anonymous → full access»). Инвариант **активируется только
  под mTLS** и НЕ меняет dev-поведение.

### FD-5. identity-extract — непрозрачная строка из SAN (эпик решение §6.3)

- Extractor читает SAN URI вида `spiffe://kacho/<sva-id>` из verified client-cert и отдаёт
  его **как строку** (непрозрачный identity-string). corelib НЕ парсит `<sva-id>`, НЕ
  валидирует его против IAM и НЕ резолвит в ServiceAccount (это SEC-C).
- Формат SPIFFE-like совместим с будущим SPIRE (эпик N4); SEC-B хранит/прокидывает строку,
  не привязываясь к SPIRE-инфраструктуре.
- Поведение при отсутствии/множественности SAN — детерминировано (см. SEC-B-12, SEC-B-13).

### FD-6. fail-closed на handshake-fail (эпик решение §6.7, data-integrity.md)

- mTLS handshake fail (нет/истёкший/неверным CA подписанный client-cert на сервере; нет/
  неверный server-cert или `server_name`-mismatch на клиенте) ⇒ соединение НЕ
  устанавливается; RPC по нему завершается `Unavailable` (cross-domain fail-closed для
  мутаций). Никакого silent-fallback на insecure при `enable=true`.

### FD-7. Helper, не дублирование (corelib reuse, architecture.md)

- TLS-credentials строятся единым corelib-helper'ом (по аналогии с keepalive-helper FD-4
  KAC-244): напр. `grpcsrv.TLSServerCreds(TLSServer) (grpc.ServerOption, error)` и
  `grpcclient.TLSClientCreds(TLSClient) (grpc.DialOption, error)` — единая точка истины для
  FD-1/FD-2/FD-6. Сервисы (SEC-D/E/G) не собирают `tls.Config` руками. Helper покрыт
  собственными unit-тестами (SEC-B-15, SEC-B-16).

---

## Группа A — Config-структуры и режим insecure (backward-compat)

### SEC-B-01 — `TLSServer`/`TLSClient` существуют с требуемыми полями `[unit]`
> Трассировка: эпик §3.2 (config-структура), SEC-B-строка таблицы §4. Требование #1/#5.

- **Given** пакеты `kacho-corelib/grpcsrv` и `kacho-corelib/grpcclient`
- **When** инспектируется config-API corelib
- **Then** определена структура `TLSServer` с полями (имена/типы — контракт):
  `enable bool`, `cert_file string`, `key_file string`, `client_ca_files []string`
- **And** определена структура `TLSClient` с полями:
  `enable bool`, `cert_file string`, `key_file string`, `ca_files []string`,
  `server_name string`
- **And** обе структуры загружаемы существующим config-механизмом (envconfig/`corelib/config`;
  имена env-тегов — `KACHO_<DOMAIN>_<...>` по naming-convention), без нового глобального
  config-синглтона (FD-3)

### SEC-B-02 — `TLSServer.enable=false` ⇒ insecure server (dev backward-compat) `[unit/bufconn]`
> Трассировка: FD-1, эпик DoD «enable=false — dev работает как сейчас». Требование #1.

- **Given** `TLSServer{enable:false}` (cert/key/client_ca — любые, в т.ч. пустые)
- **When** строится server через corelib-helper (`grpcsrv.TLSServerCreds` / `NewServer`)
- **Then** возвращается server **без** TLS-credentials (plaintext, как текущий
  `insecure.NewCredentials()`-эквивалент) — ошибки нет, cert-файлы НЕ читаются
- **And** insecure-клиент (`TLSClient{enable:false}`) успешно делает RPC к этому серверу
  (bufconn happy-path без TLS — текущее поведение сохранено)

### SEC-B-03 — `TLSClient.enable=false` ⇒ insecure dial (dev backward-compat) `[unit/bufconn]`
> Трассировка: FD-1. Требование #1.

- **Given** `TLSClient{enable:false}` (cert/key/ca/server_name — любые, в т.ч. пустые)
- **When** строится dial-option через corelib-helper (`grpcclient.TLSClientCreds`)
- **Then** возвращается `insecure.NewCredentials()`-эквивалент (как сейчас); cert-файлы НЕ читаются
- **And** RPC к insecure-серверу (SEC-B-02) проходит успешно

### SEC-B-04 — оба `enable=false` ⇒ существующий wiring не изменился `[guard]`
> Трассировка: FD-1, эпик DoD-инвариант мёржа. Требование #1.

- **Given** дерево corelib после SEC-B + дефолтный (незаданный) TLS-config
- **When** прогоняется guard: дефолтные `TLSServer{}`/`TLSClient{}` (zero-value) применяются к
  helper'ам
- **Then** оба дают insecure-режим (zero-value `enable=false`) — мёрж SEC-B в `main` без
  выставленных флагов = текущее поведение byte-for-byte по транспорту
- **And** существующие unit/bufconn-тесты grpcsrv/grpcclient остаются зелёными без правок их
  ожиданий (нет регресса insecure-пути)

---

## Группа B — mTLS handshake (positive)

### SEC-B-05 — `enable=true` обе стороны, валидные cert ⇒ handshake OK, RPC проходит `[bufconn]`
> Трассировка: FD-2, эпик §3.2, требование #5 (раздельные client/server cert).

- **Given** тестовая internal CA, выпущены: server-cert (SAN `dns:test.kacho.svc` /
  URI совместимый), client-cert (SAN `spiffe://kacho/sva-test01`)
- **And** server сконфигурён `TLSServer{enable:true, cert_file:<server.crt>,
  key_file:<server.key>, client_ca_files:[<ca.crt>]}` (`RequireAndVerifyClientCert`)
- **And** client сконфигурён `TLSClient{enable:true, cert_file:<client.crt>,
  key_file:<client.key>, ca_files:[<ca.crt>], server_name:"test.kacho.svc"}`
- **When** client делает RPC к server по bufconn с TLS поверх in-memory conn
- **Then** TLS-handshake завершается успешно (взаимная верификация: сервер проверил
  client-cert по client-CA, клиент проверил server-cert по server-CA + `server_name`)
- **And** RPC завершается успешно (тот же ответ, что в insecure-режиме) — mTLS не меняет
  семантику самого RPC

### SEC-B-06 — server требует client-cert (`RequireAndVerifyClientCert`) `[bufconn]`
> Трассировка: FD-2, эпик §3.2 «RequireAndVerifyClientCert».

- **Given** server `TLSServer{enable:true,...}` как в SEC-B-05
- **And** client использует TLS, но **без** client-cert (только server-CA: одностороннее TLS)
- **When** client пытается выполнить RPC
- **Then** handshake **отвергается** сервером (нет предъявленного client-cert) →
  RPC завершается `Unavailable` (FD-6) — сервер НЕ принимает соединение без client-cert
  (не «verify if given», а «require and verify»)

### SEC-B-07 — `server_name` сверяется клиентом `[bufconn]`
> Трассировка: FD-2 «client-cert + server-CA + server-name».

- **Given** server-cert с SAN `test.kacho.svc`; client `TLSClient{enable:true,...,
  server_name:"test.kacho.svc"}`
- **When** client делает RPC
- **Then** handshake OK, RPC проходит (SAN совпал с `server_name`)
- **And** контрольный прогон: тот же server, но client `server_name:"wrong.kacho.svc"` →
  handshake fail (SAN-mismatch) → `Unavailable` (FD-6); пара демонстрирует, что `server_name`
  реально проверяется, а не игнорируется

---

## Группа C — mTLS handshake (negative / fail-closed)

### SEC-B-08 — client-cert подписан чужим CA ⇒ handshake fail, `Unavailable` `[bufconn]`
> Трассировка: FD-6, эпик решение §6.7 fail-closed.

- **Given** server `TLSServer{enable:true, client_ca_files:[<internalCA.crt>]}`
- **And** client предъявляет client-cert, подписанный **другим** (внешним) CA
- **When** client делает RPC
- **Then** сервер отвергает handshake (client-cert не верифицируется внутренним client-CA) →
  RPC завершается `Unavailable` — fail-closed, НИКАКОГО silent-fallback на insecure

### SEC-B-09 — server-cert не верифицируется client'ом ⇒ handshake fail `[bufconn]`
> Трассировка: FD-2, FD-6.

- **Given** client `TLSClient{enable:true, ca_files:[<internalCA.crt>]}`
- **And** server предъявляет server-cert, подписанный чужим / неизвестным client'у CA
- **When** client делает RPC
- **Then** клиент отвергает handshake (server-cert не верифицируется по `ca_files`) →
  `Unavailable` (FD-6)

### SEC-B-10 — `enable=true` на сервере, insecure-client ⇒ fail (не downgrade) `[bufconn]`
> Трассировка: FD-3 (per-edge mismatch), FD-6, эпик §6.5 «mismatch → Unavailable».

- **Given** server `TLSServer{enable:true,...}`; client `TLSClient{enable:false}` (insecure)
- **When** insecure-client пытается RPC к mTLS-серверу (edge-mismatch: одна сторона включила,
  другая нет)
- **Then** соединение/RPC завершается ошибкой (`Unavailable`); сервер НЕ обслуживает
  plaintext-клиента на TLS-listener'е — mismatch детектируется, нет тихого downgrade
- **And** симметрично: mTLS-client (`enable:true`) к insecure-серверу (`enable:false`) →
  тоже fail (TLS поверх plaintext-listener не устанавливается) → `Unavailable`

> Реализм: это и есть механизм per-edge rollback-safety (эпик §6.5) — нельзя «наполовину
> включить» ребро; включаются обе стороны согласованно, иначе e2e per-edge ловит `Unavailable`.

### SEC-B-11 — невалидная TLS-конфигурация (`enable=true`, нечитаемый cert) ⇒ ошибка на старте `[unit]`
> Трассировка: FD-6 (fail-closed), FD-7 (helper).

- **Given** `TLSServer{enable:true, cert_file:"/nonexistent.crt", key_file:"/nonexistent.key"}`
  (или несовпадающая cert/key пара, или пустой `client_ca_files` при `enable=true`)
- **When** вызывается corelib-helper `grpcsrv.TLSServerCreds(...)`
- **Then** возвращается **ошибка** (не silent insecure-fallback) — процесс при wiring обязан
  упасть на старте, а не молча обслуживать plaintext (fail-closed на misconfiguration)
- **And** симметрично для `grpcclient.TLSClientCreds(...)` при `enable=true` и нечитаемых
  cert/key/ca — ошибка, не insecure-fallback

---

## Группа D — identity-extractor из client-cert SAN

### SEC-B-12 — extract SAN `spiffe://kacho/<sva-id>` как строка `[bufconn/unit]`
> Трассировка: FD-5, эпик §3.3 / решение §6.3, требование #4.

- **Given** verified client-cert с SAN URI `spiffe://kacho/sva-compute01` (peer прошёл mTLS
  verify по SEC-B-05)
- **When** server-side identity-extractor (corelib helper/interceptor) обрабатывает peer-conn
- **Then** extractor отдаёт identity-string **точно** `spiffe://kacho/sva-compute01`
  (непрозрачная строка; corelib НЕ парсит `<sva-id>`, НЕ резолвит в SA — FD-5)
- **And** extracted identity доступен downstream (в ctx / metadata) для логирования и для
  будущего IAM-resolve (SEC-C), рядом с principal-metadata (ортогонально, FD-4)

### SEC-B-13 — client-cert без SPIFFE-SAN ⇒ детерминированный исход `[unit/bufconn]`
> Трассировка: FD-5 (детерминизм), FD-6.

- **Given** verified client-cert **без** URI-SAN вида `spiffe://kacho/...` (напр. только
  DNS-SAN, или CN-only)
- **When** extractor обрабатывает peer
- **Then** identity-string — **пустой** (extractor возвращает empty, не паникует и не
  угадывает) — детерминированное поведение зафиксировано
- **And** последствие пустого identity на authz-пути НЕ решается в SEC-B (это SEC-C: пустой
  module-identity → deny/`Unavailable` при service→service). SEC-B лишь гарантирует empty,
  не leak чужого поля и не panic

### SEC-B-14 — несколько URI-SAN ⇒ детерминированный выбор `[unit]`
> Трассировка: FD-5 (детерминизм).

- **Given** verified client-cert с несколькими URI-SAN (один из них `spiffe://kacho/sva-x`)
- **When** extractor обрабатывает peer
- **Then** выбирается **первый** SAN с префиксом `spiffe://kacho/` (детерминированный, стабильный
  порядок — как в cert); прочие игнорируются; результат стабилен между вызовами
- **And** правило выбора задокументировано в helper-комментарии (часть контракта extractor'а)

---

## Группа E — инвариант доверия principal ⟺ mTLS

### SEC-B-15 — под mTLS principal-metadata доверяется ⟺ verified client-cert `[bufconn]`
> Трассировка: FD-4, эпик design-review I2, требование #3/#6.

- **Given** internal listener `TLSServer{enable:true,...}` (mTLS обязателен) с
  identity-extractor + principal-aware interceptor
- **When** приходит RPC с verified client-cert **и** `x-kacho-principal-*` metadata
- **Then** principal-metadata **доверяется** (доступно downstream для authz), cert-identity
  (модуль) и principal (пользователь) **оба** логируются (аудит, FD-4) — не подменяют друг друга

### SEC-B-16 — без verified client-cert (на TLS-listener) principal-metadata НЕ доверяется `[bufconn]`
> Трассировка: FD-4, эпик I2 «доверяет principal ⟺ peer прошёл mTLS verify».

- **Given** тот же internal listener `TLSServer{enable:true,...}` (`RequireAndVerifyClientCert`)
- **When** клиент пытается прислать `x-kacho-principal-*` metadata **без** валидного client-cert
- **Then** соединение вообще не устанавливается (SEC-B-06: require-and-verify режет до
  application-слоя) → RPC `Unavailable`; principal-metadata от недоверенного peer заведомо не
  достигает authz (инвариант соблюдён транзитивно через handshake-reject)
- **And** дополнительный unit на extractor: если (гипотетически) peer без verified client-cert
  всё же дошёл до interceptor'а (мисконфиг) — extractor помечает peer как «не-mTLS-verified»,
  и principal-aware слой обязан отбросить principal-metadata (defense-in-depth, FD-4); тест
  фиксирует этот отказ от доверия

### SEC-B-17 — insecure-режим (`enable=false`) принимает principal как сейчас (dev) `[bufconn]`
> Трассировка: FD-1, FD-4 (инвариант активен только под mTLS), security.md dev-mode.

- **Given** insecure listener `TLSServer{enable:false}` (dev-mode, нет client-cert вовсе)
- **When** приходит RPC с `x-kacho-principal-*` metadata
- **Then** principal-metadata принимается как сейчас (backward-compat dev) — инвариант
  principal⟺mTLS **неприменим** к insecure-listener'у и НЕ ломает текущий dev-flow
- **And** этим подтверждается, что мёрж SEC-B не вводит фейл в dev (эпик DoD-инвариант)

---

## Группа F — Helper / hardening / анти-регресс

### SEC-B-18 — corelib TLS-helper'ы — единая точка истины `[unit]`
> Трассировка: FD-7, architecture.md reuse.

- **Given** `grpcsrv.TLSServerCreds(TLSServer)` и `grpcclient.TLSClientCreds(TLSClient)`
- **When** инспектируется их поведение
- **Then** `enable=false` → insecure-эквивалент (FD-1); `enable=true` + валидные файлы →
  корректные TLS-credentials (FD-2: server `RequireAndVerifyClientCert`+client-CA; client
  client-cert+server-CA+server_name); `enable=true` + невалидные файлы → ошибка (FD-6, SEC-B-11)
- **And** оба helper'а покрыты собственными unit-тестами (единая точка истины — здесь нет
  magic-`tls.Config` по сервисным репо)

### SEC-B-19 — нет прямого `tls.Config`/creds-сборки вне corelib-helper `[guard]`
> Трассировка: FD-7. Превентивно для SEC-D/E/G (чтобы сервисы не дублировали).

- **Given** corelib после SEC-B
- **When** запускается guard (тест/grep): сборка TLS-credentials для inter-service gRPC идёт
  только через `TLSServerCreds`/`TLSClientCreds`-helper'ы
- **Then** guard зелёный на дереве corelib; добавление прямого `credentials.NewTLS(...)` /
  ручного `tls.Config` в обход helper'а делает guard красным (RED→GREEN продемонстрировать)
- **And** allow-list для тестового кода (тест-CA/cert-генерация в `*_test.go`) допустим —
  guard про прод-код

---

## Трассируемость acceptance ↔ test (TDD-red)

Все тесты пишутся **до** кода (ban #12, testing.md), прогоняются RED, затем GREEN. SEC-B —
corelib-only, поэтому пирамида: **unit** (config/helper/extractor) + **bufconn** (настоящий
TLS-handshake поверх in-memory conn). Newman для SEC-B **не применим** (нет публичного RPC /
api-gateway-поверхности в этой подфазе — e2e mTLS проверяется в SEC-E/F/G).

| Сценарий | Уровень | Где живёт тест (kacho-corelib) | Трассировка к эпику |
|---|---|---|---|
| SEC-B-01 | unit | `grpcsrv`/`grpcclient` config-struct test | §3.2 config, #1/#5 |
| SEC-B-02 | unit+bufconn | `grpcsrv` insecure-server test | FD-1, #1 |
| SEC-B-03 | unit+bufconn | `grpcclient` insecure-dial test | FD-1, #1 |
| SEC-B-04 | guard | corelib zero-value backward-compat guard | FD-1, DoD-мёрж |
| SEC-B-05 | bufconn | mTLS happy-path (тест-CA + 2 cert) | FD-2, #5 |
| SEC-B-06 | bufconn | server require-client-cert test | FD-2 |
| SEC-B-07 | bufconn | `server_name` match + mismatch | FD-2 |
| SEC-B-08 | bufconn | client-cert wrong-CA → Unavailable | FD-6, §6.7 |
| SEC-B-09 | bufconn | server-cert wrong-CA → Unavailable | FD-2/FD-6 |
| SEC-B-10 | bufconn | enable-mismatch обе стороны → Unavailable | FD-3/FD-6, §6.5 |
| SEC-B-11 | unit | misconfig (нечитаемый cert) → error | FD-6, FD-7 |
| SEC-B-12 | bufconn+unit | extractor SAN→string | FD-5, #4 |
| SEC-B-13 | unit+bufconn | extractor no-SPIFFE-SAN → empty | FD-5 |
| SEC-B-14 | unit | extractor multi-SAN детерминизм | FD-5 |
| SEC-B-15 | bufconn | principal доверяется при verified cert | FD-4, I2, #3 |
| SEC-B-16 | bufconn+unit | principal НЕ доверяется без verified cert | FD-4, I2 |
| SEC-B-17 | bufconn | insecure-listener принимает principal (dev) | FD-1/FD-4 |
| SEC-B-18 | unit | helper'ы — единая точка истины | FD-7 |
| SEC-B-19 | guard | нет прямого tls.Config вне helper | FD-7 |

---

## Definition of Done (SEC-B)

- [ ] **Test-first соблюдён** (ban #12): для ключевых кейсов показана пара RED→GREEN — минимум
      SEC-B-05 (handshake undefined→OK), SEC-B-06 (require-client-cert), SEC-B-12 (extractor),
      SEC-B-16 (инвариант доверия). RED прогнан до кода, зафиксирован в PR.
- [ ] `TLSServer{enable,cert_file,key_file,client_ca_files}` и
      `TLSClient{enable,cert_file,key_file,ca_files,server_name}` определены в corelib и
      загружаемы config-механизмом; per-instance (нет глобального TLS-синглтона — FD-3).
- [ ] corelib-helper'ы `grpcsrv.TLSServerCreds` / `grpcclient.TLSClientCreds` (или
      эквивалент): `enable=false`→insecure (FD-1); `enable=true`→mTLS (FD-2,
      `RequireAndVerifyClientCert` на сервере, server-CA+server_name на клиенте);
      misconfig→error (FD-6). Покрыты unit (SEC-B-18).
- [ ] identity-extractor из client-cert SAN: SAN→string (SEC-B-12), no-SAN→empty (SEC-B-13),
      multi-SAN детерминизм (SEC-B-14), непрозрачная строка без resolve в SA (FD-5).
- [ ] Инвариант доверия (FD-4): principal-metadata доверяется ⟺ verified client-cert на
      mTLS-listener (SEC-B-15/16); insecure-listener — dev-backward-compat (SEC-B-17);
      cert-identity и principal логируются ОБА.
- [ ] **Backward-compat мёржа**: оба `enable=false` ⇒ текущее insecure-поведение byte-for-byte
      по транспорту (SEC-B-04); существующие grpcsrv/grpcclient unit/bufconn-тесты зелёные без
      правок ожиданий. SEC-B мёржится в `main`, ничего не включая.
- [ ] fail-closed: handshake-fail / mismatch / misconfig → `Unavailable`/error, НИКАКОГО
      silent-fallback на insecure при `enable=true` (SEC-B-08/09/10/11, FD-6).
- [ ] Анти-регресс guard (SEC-B-19): TLS-credentials собираются только через corelib-helper'ы
      (RED→GREEN на искусственном bare `credentials.NewTLS`).
- [ ] **Никаких TODO/FIXME/skip** в diff (ban #11/#13); никакого тех-долга «на потом». Hot-reload
      сертификатов осознанно вне scope (restart-on-rotate MVP, эпик §6.2) — не TODO, а решение.
- [ ] Финальная верификация corelib: `go test ./... -race` + `golangci-lint run` +
      `govulncheck` зелёные (testing.md §«Финальная верификация»).
- [ ] **Vault обновлён**: `KAC/KAC-<SEC-B>.md` (trail, PR-ссылка, acceptance-чеклист);
      `packages/corelib-grpcsrv.md` (+TLS server creds + identity-extractor),
      `packages/corelib-grpcclient.md` (создать/обновить: +TLS client creds),
      `packages/corelib-config.md` (TLSServer/TLSClient структуры). Инвариант principal⟺mTLS —
      пометить в `packages/corelib-auth.md`. Новых edges SEC-B не вводит (рёбра включаются
      в SEC-D/E/G).
- [ ] PR в `kacho-corelib`, ветка `KAC-<N>`; downstream-репо НЕ трогаются в этой подфазе
      (SEC-B — лист графа: corelib без зависимостей, эпик §4 «Зависит от: —»). Сервисы
      подхватят helper'ы в SEC-C/D/E/G.

---

## Примечания по реализму (входные данные, не предмет ревью контракта)

- **bufconn + настоящий TLS**: тест поднимает `grpc.Server` с `TLSServerCreds` на bufconn
  listener; клиент дайлит через `grpc.WithContextDialer(bufDialer)` + `TLSClientCreds`.
  TLS-handshake выполняется поверх in-memory conn — настоящая взаимная верификация без сети.
  Тест-CA/cert генерируются в `*_test.go` (ephemeral, `x509`/`crypto/tls`), не коммитятся в
  репо (ban: секреты в git — нет; cert-материал для тестов — генерируемый, не хранимый).
- **SAN-формат**: `spiffe://kacho/<sva-id>` ставит cert-manager (SEC-F); в SEC-B тест-cert
  сам прописывает URI-SAN в этом формате, чтобы зафиксировать контракт extractor'а заранее.
- **Точная сигнатура helper'ов** (`TLSServerCreds`/`TLSClientCreds` vs опции `NewServer`) —
  деталь реализации; контракт SEC-B — поведение (FD-1..FD-7) и наличие единой точки (FD-7),
  не имя функции. Имя уточняется реализацией, тест проверяет поведение.
