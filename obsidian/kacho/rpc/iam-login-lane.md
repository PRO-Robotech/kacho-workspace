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
methods_count: 5
async_methods: 0
status: test
related_tickets:
  - "[[issue-1270-kaname]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "kaname, ветка issue-1270-registration от release/iam-lines@af0ca8f3: перечень путей — `loginlanehttp.Paths()`; сверен с обработчиком"
---

# Полоса формы: вход, выход, смена пароля, признак формы, регистрация

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

**Отказы** — `google.rpc.Status` JSON фиксированными текстами. Регистрация: занятость адреса,
активация приглашения конкурентом, истёкшее приглашение, потолок темпа — **один** отказ
`400 FAILED_PRECONDITION "registration refused"` (`reason: REGISTRATION_REFUSED`), без
`Retry-After`; правило пароля — `400 INVALID_ARGUMENT "Illegal argument password: …"`
(осознанное исключение, Ф1-32); хранилище не ответило — `503`. Причина единого отказа —
только в `kaname_registration_outcomes_total{lane,outcome}`.

**Полосы регистрации** объявлены одним местом — `registration.Lanes`
(`internal/apps/kaname/api/registration/lanes.go`); гейт `TestRegistration_EveryLaneIssuesASession`
требует от каждой выдачи сессии и находит второй литерал полосы вне объявления.

#rpc #kacho-iam #iam
