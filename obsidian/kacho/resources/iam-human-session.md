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
verified_against: "kaname main@af0ca8f3 (миграция и домен `internal/domain/human_session.go` прочитаны); release/iam-lines@6acf8f19 — то же дерево по этому предмету; адаптер `internal/repo/kaname/pg/human_session_repo.go` — по именам методов, построчно не пересматривался. 2026-09-21: словарь `ended_reason` пересверен по обеим миграциям на ревизии 229a0693 — значений три, не два; остальные строки таблицы колонок при этой сверке не пересматривались"
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
| `ended_at` · `ended_reason` | timestamptz · text | снятие — **отметка, а не удаление**; пара CHECK `(ended_at IS NULL) = (ended_reason IS NULL)`; причина ∈ `{logout, password-change, second-factor-removed}` (словарь **закрыт**, `human_sessions_ended_reason_check`; третье значение заведено миграцией `20260917160000_second_factor_rows_carry_state_and_step.sql`) |
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

> [!warning] Административный выход причиной не различается
> Принудительный выход распорядителя снимает запись **той же** причиной `logout`, какой
> помечает себя выход самого человека: значения «выведен распорядителем» в закрытом словаре
> нет, а значение вне словаря база отвергнет. От строки сессии к событию дороги при этом
> тоже нет — событие принудительного выхода номера сессии не несёт. Предмет и решение —
> [[KAC/issue-334-kaname]].

## Кто ещё держит ключ на эту строку

`kaname.token_families` ссылается на запись сессии внешним ключом с каскадом **на удалении**,
а снятие строку не удаляет. Отсюда — писатель, отзывающий семейства снятых сессий в той же
транзакции, и ребро [[edges/kaname-session-end-vs-code-issue]].

## История

- `kn-313` — принудительный выход стал снимать и **нашу** запись сессии; отсюда
  [[KAC/issue-334-kaname]] (четвёртое значение словаря) и [[KAC/issue-340-kaname]]
  (число снятого не доезжает до события). Полоса в `main` не влита на 2026-09-21.
- [[KAC/issue-1281-kaname]] — третье значение словаря, `second-factor-removed`.
- 2026-09-22 — заведены ссылки на записку внутреннего глагола `Resolve` и на переходник края,
  который его зовёт. Повод: возврат полосы края назвал `InternalHumanSessionService.Resolve`
  затронутым RPC. Состав колонок и контракт не правились.

## See also

[[rpc/iam-login-lane]] · [[resources/iam-session-revocation]] · [[resources/iam-recovery-code]] ·
[[KAC/issue-1269]] · [[KAC/issue-1280]] · [[resources/iam-token-family]] ·
[[resources/iam-user-token-revocation]] · [[rpc/iam-internal-human-session-service]] ·
[[packages/apigw-clients]]

#resource #kacho-iam #iam #internal #migrations
