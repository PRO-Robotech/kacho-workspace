---
title: human_sessions
aliases:
  - HumanSession (iam)
  - human_session
category: resource
domain: iam
id_prefix: hss-
owner_table: kaname.human_sessions
owner_db: kaname
project_level: false
status: done
related_rpc:
  - "[[rpc/iam-login-lane]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC/issue-1269]]"
  - "[[KAC/issue-1280]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "kaname main@af0ca8f3 (миграция и домен `internal/domain/human_session.go` прочитаны); release/iam-lines@6acf8f19 — то же дерево по этому предмету; адаптер `internal/repo/kaname/pg/human_session_repo.go` — по именам методов, построчно не пересматривался"
---

# human_sessions (iam)

**Schema**: `kaname.human_sessions` (миграция
`PRO-Robotech/kaname:internal/migrations/20260916190000_human_session_is_our_record.sql`)
**Owner**: kaname · **Visibility**: internal — запись не адресуется ничем внешним: клиент держит
носитель в печенье `kaname_session`, край получает субъекта и поля записи через
`InternalHumanSessionService.Resolve`; номер записи (`hss-…`, дефисный канон) наружу не выходит.

## Назначение

Сессия человека — **запись службы** (Ф3 Р1, приёмка
`PRO-Robotech/kaname:docs/engineering/acceptance/login-lane-issues-our-session-and-logout-ends-it-server-side.md`),
а не сессия чужого компонента. Выдаётся входом паролем, регистрацией (Ф4) и завершением
восстановления (Ф5); снимается выходом и сменой пароля; срок — один столбец.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `id` | text | **PK** — `hss-…`; наружу не выходит |
| `user_id` | text | FK `users(id)` ON DELETE CASCADE |
| `bearer_digest` | text | SHA-256 носителя, шестнадцатерично; UNIQUE; CHECK `^[0-9a-f]{64}$`; статистика планировщика выключена (`SET STATISTICS 0`) |
| `authenticated_at` | timestamptz | момент аутентификации; **неподвижен** (Ф11 Р6) |
| `last_presented_at` | timestamptz | сдвигается предъявлением способа; CHECK `>= authenticated_at` |
| `expires_at` | timestamptz | **единственный** срок (F4d-27, гейт `TestHumanSessionExpiryIsDeclaredOnce`); CHECK `> authenticated_at` |
| `assurance_level` | text | обязателен, CHECK `IN ('1','2','3')` — ось Ф11 |
| `presented_methods` | text[] | непусто, CHECK `<@ {password, totp, lookup_secret, webauthn, recovery_code}` — словарь `assurance.Methods()`, сверяется пробой `TestHumanSessionMethodVocabularyAgreesWithTheRule` |
| `password_change_required` | boolean | DEFAULT false; прод-производителя `true` нет — предмет [[KAC/issue-2697]] (решение: поле снимается с контракта) |
| `ended_at` · `ended_reason` | timestamptz · text | снятие — **отметка, а не удаление**; пара CHECK `(ended_at IS NULL) = (ended_reason IS NULL)`; причина ∈ `{logout, password-change}` — те же значения, что пишут писатели отсечки [[resources/iam-session-revocation]] |
| `created_at` | timestamptz | DEFAULT now() |

Индексы: `human_sessions_user_id_idx (user_id)`, `human_sessions_expires_at_idx (expires_at)` —
уборка идёт по сроку и отметке снятия.

## Соседние таблицы той же миграции

| таблица | что | писатель |
|---|---|---|
| `kaname.human_first_authentications` | момент **первой** аутентификации личности нашей посадкой (Ф3 Р5); PK `user_id`, FK CASCADE | один — выдача сессии, `LEAST` (не поднимается, коммутативна под конкуренцией); уборке не подлежит |
| `kaname.login_failures` | одна строка на неверное предъявление пароля по оси `address` либо `source` (Ф3 Р10); CHECK на ось и непустой ключ | счёт — строки в окне (`authn.login.address-*`, `source-*`); успешный вход снимает ось `address`; строки старше окна убирает уборка |

## Контракт

- **Носитель не хранится** — только свёртка; копия таблицы не даёт ни одного годного носителя.
  Случайная часть — 32 байта (`domain.SessionBearerBytes`), в URL-безопасном base64 43 знака;
  носитель не сериализуется ни в JSON, ни в текст (`ErrSessionBearerNotSerializable`) — уходит
  клиенту одним путём, заголовком `Set-Cookie` обработчика полосы.
- **Резолв снятой строки отличается от резолва неизвестного значения только клеткой счётчика**
  (Ф3-27: снята · истекла · заблокирована · неизвестна); удалённая строка была бы неотличима от
  никогда не существовавшей — потому снятие отметкой.
- Уборка снятых и истёкших строк — реестр `retention` (`internal/apps/kaname/retention/registry.go`,
  предметы `human_sessions` и `login_failures`), а не глагол.
- Срок и домен печенья — ручки `authn.login.session-ttl` / `authn.login.cookie-domain`; страж
  посадки `own` отказывает в старте без них.

## See also

[[rpc/iam-login-lane]] · [[resources/iam-session-revocation]] · [[resources/iam-recovery-code]] ·
[[KAC/issue-1269]] · [[KAC/issue-1280]]

#resource #kacho-iam #iam #internal #migrations
