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
verified_against: "kaname main@af0ca8f3 (миграция и домен `internal/domain/human_session.go` прочитаны); release/iam-lines@6acf8f19 — то же дерево по этому предмету; адаптер `internal/repo/kaname/pg/human_session_repo.go` — по именам методов, построчно не пересматривался. 2026-09-21: словарь `ended_reason` пересверен по обеим миграциям на ревизии 229a0693 — значений три, не два; остальные строки таблицы колонок при этой сверке не пересматривались. Перемер 2026-09-26: словарь ended_reason прочитан в миграциях 20260917160000_second_factor_rows_carry_state_and_step.sql (есть в origin/main службы cbbac984b7b) и 20260923160455_human_session_end_reason_names_the_forced_exit.sql (только в ветке эпика 357, PRO-Robotech/kaname@fc9f5aff19c); 2026-10-06 — ветка эпика 296@2cf9c8528b1f: наличие гейта единственного писателя уровня — git grep TestSessionLevelHasOneWriterCallSite (humansession/session_level_writer_test.go); колонки не пересматривались"
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
| `ended_at` · `ended_reason` | timestamptz · text | снятие — **отметка, а не удаление**; пара CHECK `(ended_at IS NULL) = (ended_reason IS NULL)`; причина — закрытый словарь `human_sessions_ended_reason_check`: в `main` службы `logout`, `password-change`, `second-factor-removed` (третье значение заведено миграцией `20260917160000_second_factor_rows_carry_state_and_step.sql`); в ветке эпика `357` к ним добавлена `admin-force-logout` — выход по решению распорядителя ([[KAC/issue-334-kaname\|kaname#334]]). Писатели отсечки — [[resources/iam-session-revocation]] |
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

> [!warning] В `main` службы административный выход причиной не различается
> На `main` службы принудительный выход распорядителя снимает запись **той же** причиной
> `logout`, какой помечает себя выход самого человека: значения «выведен распорядителем» в
> закрытом словаре там нет. В ветке эпика `357` это снято: своя причина `admin-force-logout`
> ([[KAC/issue-334-kaname]]), и запись события принудительного выхода кладётся после снятия и
> несёт исход ([[KAC/issue-340-kaname]]); в `main` обе правки придут посадкой эпика.

## Кто ещё держит ключ на эту строку

`kaname.token_families` ссылается на запись сессии внешним ключом (ветка эпика `357`,
сверено 2026-09-26). Что снятая сессия не несёт живого выданного, держат писатели с обеих
сторон — снятие и выдача кода: ребро [[edges/kaname-session-end-vs-code-issue]].

## История

- `kn-313` — принудительный выход стал снимать и **нашу** запись сессии; отсюда
  [[KAC/issue-334-kaname]] (четвёртое значение словаря) и [[KAC/issue-340-kaname]]
  (число снятого не доезжает до события). Полоса в `main` не влита на 2026-09-21.
- [[KAC/issue-1281-kaname]] — третье значение словаря, `second-factor-removed`.
- 2026-09-22 — заведены ссылки на записку внутреннего глагола `Resolve` и на переходник края,
  который его зовёт. Повод: возврат полосы края назвал `InternalHumanSessionService.Resolve`
  затронутым RPC. Состав колонок и контракт не правились.
- 2026-09-26 (#778) — раздел о семействах, ссылающихся на эту строку, сведён к ссылке на
  ребро: пересказ того, чем снятие и выдача расходились до фикса полосы `kn-313`, снят —
  адрес такого разбора дифф фикса, а не записка. Колонки не правились.
- 2026-09-26 — словарь причин снятия исправлен по дереву: прежняя редакция называла два значения,
  хотя `second-factor-removed` в `main` службы с 2026-09-17; волна [[KAC/issue-358-kaname|kaname#358]]
  добавляет `admin-force-logout` ([[KAC/issue-334-kaname|kaname#334]]). Снята оговорка «те же
  значения, что у писателей отсечки»: после смены словаря она мной не подтверждена. Запись события
  принудительного выхода теперь кладётся после снятия сессий и несёт исход
  ([[KAC/issue-340-kaname|kaname#340]], [[rpc/iam-internal-iam-service]]).
- 2026-09-27 (#846) — две правки 2026-09-26 из параллельных линий сведены: строка словаря
  называет и `main`, и ветку эпика; врезка об административном выходе ограничена `main`
  службы — в ветке эпика `357` предмет снят задачами #334 и #340.
- 2026-10-06 — волна-4 эпика `296` ([[KAC/issue-538-kaname]], PR kaname#623, `2cf9c8528b1f`; в `main` службы
  не влито): колонку `assurance_level` пишет один вызов, гейт `TestSessionLevelHasOneWriterCallSite`
  ([[KAC/issue-343-kaname]]); копия уровня в ответе смены пароля читает записанное значение
  ([[KAC/issue-208-kaname]]); сессию выдаёт и вход ключом доступа ([[KAC/issue-613-kaname]]). Колонки не
  правились.

## See also

[[rpc/iam-login-lane]] · [[resources/iam-session-revocation]] · [[resources/iam-recovery-code]] ·
[[KAC/issue-1269]] · [[KAC/issue-1280]] · [[resources/iam-token-family]] ·
[[resources/iam-user-token-revocation]] · [[rpc/iam-internal-human-session-service]] ·
[[packages/apigw-clients]]

#resource #kacho-iam #iam #internal #migrations
