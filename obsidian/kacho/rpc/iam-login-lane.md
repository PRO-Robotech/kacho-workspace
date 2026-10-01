---
title: Полоса формы входа и регистрации (kaname)
aliases:
  - iam-login-lane
  - loginlanehttp
category: rpc
backend: kaname
backend_port: 9100
visibility: cluster-internal
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 13
async_methods: 0
status: test
related_tickets:
  - "[[issue-1269]]"
  - "[[issue-1270-kaname]]"
  - "[[issue-1271]]"
  - "[[issue-1281-kaname]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "kaname release/iam-lines@6acf8f19 (Ф3 kaname#179, Ф4 kaname#196, Ф5 kaname#200 влиты в линию) — семь путей Ф3/Ф4/Ф5; Ф12 — ветка issue-1281-second-factor на 1d1bd21a (PR kaname#215): перечень путей `loginlanehttp.Paths()` — 13; сверен с обработчиком и копией края"
---

# Полоса формы: вход, выход, смена пароля, признак формы, регистрация, восстановление

**Транспорт**: HTTP-слушатель `internal/handler/loginlanehttp` на адресе
`KANAME_API_SERVER__LOGIN_LANE_ENDPOINT`, поднимается ТОЛЬКО посадкой `authn.identity-provider=own`,
взаимный TLS, допускается **ровно край** (SAN = имя края). Не gRPC и не proto: глаголы формы
ретранслирует край на адрес консоли; перечень путей — `loginlanehttp.Paths()`, и край держит
свою копию (`gateway/internal/middleware/login_lane_paths.go`).

| путь | метод | вид признака | глагол | ответ |
|---|---|---|---|---|
| `/iam/v1/auth/csrf?form=<вид>` | GET | — | признак формы для контекста `kaname_form` | `{csrfToken}` |
| `/iam/v1/auth/login` | POST | `login` | `humansession.Login` (Ф3) | `{user, session}` + `kaname_session` |
| `/iam/v1/auth/logout` | POST | `logout` | `humansession.Logout` | `{}`; печенье снято |
| `/iam/v1/auth/password` | POST | `password` | `humansession.ChangePassword` | `{session}` |
| `/iam/v1/auth/register` | POST | `register` | `registration.Register` (Ф4) — зеркало · адрес · сессия одной транзакцией | как у входа; `emailVerified=false` |
| `/iam/v1/auth/recovery` | POST | `recovery` | `humansession.RequestRecovery` (Ф5-01/02) — чеканка кода и письмо одной транзакцией | `200 {}` при **любом** исходе, без печений: адрес не подтверждается ответом |
| `/iam/v1/auth/recovery/complete` | POST | `recovery-complete` | `humansession.CompleteRecovery` (Ф5-03…08, Ф5-17) — код и новый пароль **одним** обращением, текущий пароль не спрашивается | `{session}` + `kaname_session`; заблокированной личности — учётные данные сменены, сессии нет |
| `/iam/v1/auth/second-factor` | GET | — | `SecondFactorStatus` (Ф12) | `{totp:{enrolled,pendingUntil|confirmedAt}, backupCodes?:{remaining,total}}` |
| `/iam/v1/auth/second-factor/enroll` | POST | `second-factor` | `EnrollSecondFactor` — секрет один раз; сессия свежая (Р8) | `{secret, otpauthUri, expiresAt}` |
| `/iam/v1/auth/second-factor/confirm` | POST | `second-factor` | `ConfirmSecondFactor` — предъявление, коды один раз | `{backupCodes, session, assurance}` + новый `kaname_session` |
| `/iam/v1/auth/second-factor/remove` | POST | `second-factor` | `RemoveSecondFactor` — код в теле `{method, code}`; прочие сессии сняты | `{session, assurance, backupCodesRemaining?}` |
| `/iam/v1/auth/second-factor/backup-codes` | POST | `second-factor` | `RegenerateBackupCodes` — код в теле | `{backupCodes, session, assurance}` |
| `/iam/v1/auth/step-up` | POST | `step-up` | `StepUp` — `method` ∈ `password` · `totp` · `lookup_secret` | `{session, assurance, backupCodesRemaining?}` |

Вход (`/login`) принимает необязательное поле `secondFactor: {method, code}` — сессия сразу «2»
(Ф12 Р5). Отказы семейства: состояние — `400 FAILED_PRECONDITION` с токенами
`SECOND_FACTOR_NOT_ENROLLED` / `ENROLLMENT_NOT_PENDING`, «уже заведён» — `409 ALREADY_EXISTS`,
свежесть — `403 SESSION_NOT_FRESH`, материал не открылся — `503 second factor temporarily unavailable`.

**Отказы** — `google.rpc.Status` JSON фиксированными текстами. Регистрация: занятость адреса,
активация приглашения конкурентом, истёкшее приглашение, потолок темпа — **один** отказ
`400 FAILED_PRECONDITION "registration refused"` (`reason: REGISTRATION_REFUSED`), без
`Retry-After`; правило пароля — `400 INVALID_ARGUMENT "Illegal argument password: …"`
(осознанное исключение, Ф1-32); хранилище не ответило — `503`. Причина единого отказа —
только в `kaname_registration_outcomes_total{lane,outcome}`.

**Полосы регистрации** объявлены одним местом — `registration.Lanes`
(`internal/apps/kaname/api/registration/lanes.go`); гейт `TestRegistration_EveryLaneIssuesASession`
требует от каждой выдачи сессии и находит второй литерал полосы вне объявления.

## Ключи доступа (Ф13) — два глагола, объявленные приёмкой и ещё не вошедшие в перечень

| путь | метод | что делает |
|---|---|---|
| `POST /iam/v1/auth/access-key/begin` | POST | выдаёт испытание входа, **не назвав человека**: привязано к контексту формы, одно на контекст, живёт срок испытания |
| `POST /iam/v1/auth/access-key/login` | POST | принимает утверждение; сверяет тем же проверяющим, что регистрация ключа; находит человека по идентификатору удостоверения; **сверяет рукоятку**; выдаёт сессию — как `/iam/v1/auth/login` |

Состояние на 2026-09-22, перемерено по `project/kaname`:

- на ветке ключей доступа `fix/access-key-irreversible-facts` (координата, не живая ссылка)
  @`bd10ba67c1b` обоих путей в `loginlanehttp.Paths()` **нет**: перечень там прежний, тринадцать.
  Пути объявлены только приёмкой Ф13;
- перечень с обоими глаголами живёт на ветке `issue-1282-f13-implementation` (координата, не
  живая ссылка) @`1d51d8068e6` — там они объявлены в самом обработчике полосы.

Рукоятка, которую сверяет вход, — предмет [[resources/iam-user-access-key]]: 64 случайных байта
на человека, платформенным `id` **не** являющиеся.

## History

- 2026-09-22 — добавлен раздел о глаголах ключей доступа: возврат полосы назвал
  `access-key/begin` и `access-key/login` затронутыми RPC. Перечень `Paths()` этой записки
  (13) **не менялся**: на обеих измеренных ветках он либо прежний, либо принадлежит другой
  ветке, и в ствол не влит. Сопутствующая задача контракта — [[issue-351-kaname]].

#rpc #kacho-iam #iam
