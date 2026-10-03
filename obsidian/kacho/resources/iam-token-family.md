---
title: token_families
aliases:
  - TokenFamily (kaname)
  - token_family
  - iam-token-family
category: resource
domain: iam
id_prefix: tfm-
owner_table: kaname.token_families
owner_db: kaname
project_level: false
status: test
related_rpc:
  - "[[rpc/iam-internal-session-revocations-service]]"
related_packages:
  - "[[packages/kaname-repo-pg]]"
  - "[[packages/kaname-migrations]]"
  - "[[packages/corelib-oauthceremony]]"
  - "[[packages/corelib-ids]]"
related_tickets:
  - "[[KAC/issue-339-kaname]]"
  - "[[KAC/issue-366-kaname]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "2026-10-01, голова ветки эпика 357 @ 7c5409f5e: Up-разделы миграций, добавленных после fc9f5aff и трогающих таблицу (`20260925121413_token_family_carries_its_login_level.sql`, `20260926141908_token_family_person_is_the_person_of_its_session.sql`, `20260927001324_family_revocation_reason_names_the_client_revocation.sql`, `20260927072645_family_revocation_reason_leaves_the_words_without_a_writer.sql`; перечень — `git diff --name-status fc9f5aff19c origin/357 -- internal/migrations`), и словарь `internal/domain/oauth_ceremony.go`; на origin/main @ cbbac984b таблицы нет (`git grep token_families` по миграциям — 0 файлов). Остальные разделы этой сверкой построчно не пересматривались. Прежняя сверка: DDL прочитан в `internal/migrations/20260920175117_authorization_code_is_our_record.sql` и словарь причин — в `internal/migrations/20260923225650_consent_leaves_the_schema.sql`, оба на ветке эпика 357 (fc9f5aff) продукта PRO-Robotech/kaname (2026-09-26); колонки и ограничения сверены построчно; на origin/main (cbbac984) таблицы нет, поведение на стенде не наблюдалось. Разделы о детях и о читателе — по разделам Up тех же миграций и `20260923231545_access_token_belongs_to_its_family.sql` на fc9f5aff19c, 2026-09-26; поведение писателей и проб не перезапускалось"
---

# token_families (kaname)

**Schema**: `kaname.token_families` · **Owner**: kaname · **Visibility**: internal —
номер (`tfm-…`) наружу не выходит, семейство адресуется только изнутри церемонии. Ключ
`tfm-<17 base32>` чеканит сама служба крючком церемонии `oauthceremony.Config.NewGrantID`
([[packages/corelib-oauthceremony]], префикс — [[packages/corelib-ids]]).

> [!warning] Состояние — `test`: предмета на стволе нет
> Таблица заведена полосой `kn-313`, живёт в ветке эпика `357` (волна
> [[KAC/issue-358-kaname|kaname#358]]) и в `main` не влита (сверено 2026-09-26 и 2026-10-01). Всё ниже
> описывает ветку эпика, а не поднятую посадку. Внешнего API у ресурса нет: пишет и читает его
> только церемония службы.

## Назначение

Семейство — всё, что выдано по **одному** коду авторизации: сам код, токены обновления каждого
оборота и выпуски токена доступа. Строка несёт контекст церемонии — клиента, человека, сессию
входа, область — и отметку отзыва. Отзыв семейства снимает всё выданное по нему.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `id` | text | **PK**, форма `tfm-` + 17 знаков алфавита без похожих букв |
| `client_id` | text | FK `interactive_clients(client_id)` CASCADE |
| `user_id` | text | FK `users(id)` CASCADE |
| `session_id` | text | FK `human_sessions(id)` CASCADE — сессия **обязательна** |
| `scope` | text[] | непуста, без `NULL` и без пустых имён |
| `acr` | text | уровень входа гранта, `NOT NULL`, словарь `1`/`2`/`3` — **снимок** на выдаче кода: обмен и оборот его не пересчитывают, у сессии уровень подвижен |
| `created_at` | timestamptz | `now()` |
| `revoked_at` | timestamptz | NULL, пока семейство живо |
| `revoked_reason` | text | закрытый словарь, см. ниже |
| `live` | boolean | `true`, пока семейство живо; колонка существует ради ключа живости |

## Инварианты, которые держит схема

- `token_families_context_uk` UNIQUE (`id`, `client_id`, `user_id`, `session_id`, `scope`) —
  **составной ключ контекста, на который ссылаются код и обновляющий токен**. Он и делает
  согласие контекста свойством схемы: контекст на строке семейства и на строке выданного
  молча разойтись не может, расхождение отвергает база. Каскада на обновлении у этой ссылки
  нет: контекст выданного неизменяем.
- `token_families_live_uk` UNIQUE (`id`, `live`) — **ключ живости**, на который выданное
  ссылается отдельно, с каскадом на обновлении. Вставку в отозванное семейство отвергает
  база, отзыв доезжает до выданного каскадом — [[edges/kaname-family-revoke-vs-token-issue]].
- `token_families_live_pair_ck` — живость и отметка отзыва суть одно состояние, записанное
  дважды; согласие держит база.
- `token_families_scope_ck` — пустая область не «все права», а отсутствие решения, и хранить
  её как область нельзя.
- `token_families_revoked_pair_ck` — отметка и причина появляются и исчезают вместе.
- `token_families_revoked_reason_ck` — словарь причин **закрыт**, корзины «прочее» нет.
- `token_families_acr_ck` — уровень входа из того же словаря, что у `human_sessions.assurance_level`.
- `token_families_session_user_fk` — (`session_id`, `user_id`) ссылается на пару
  `human_sessions(id, user_id)` с каскадом удаления: человек семейства — это человек его сессии,
  разойтись они не могут (ключ пары `human_sessions_id_user_uniq` заведён той же миграцией).

## Дети и как до них доезжает отзыв

| таблица | что хранит | связь с семейством |
|---|---|---|
| `kaname.authorization_codes` | код — свёрткой, с привязкой PKCE (метод только S256) и адресом возврата | внешний ключ на контекст семейства и второй — на пару `(id, live)` |
| `kaname.refresh_tokens` | токен обновления — свёрткой, номер оборота и свёртка преемника | те же два ключа |
| `kaname.access_tokens` | выпуск токена доступа: `jti` → семейство | ключ на `(id, live)`; при снятии семейства живость становится пустой, запись остаётся |

Живость семейства (`live`) снесена в детей каскадом внешнего ключа (`ON UPDATE CASCADE`):
писатель её не выставляет, а отзыв одной строкой семейства доезжает до каждого ребёнка.
Признак активности кода и токена обновления — производный столбец от отметки снятия и
живости; использованный код и отротированный токен живут до истечения, чтобы «неактивен» и
«не найден» различались. Записки детей — [[resources/iam-authorization-code]],
[[resources/iam-refresh-token]].

## Словарь причин отзыва

`code-replay` · `refresh-replay` · `session-ended` · `client-revoke`.

Словарь домена `FamilyRevocationReason` и ограничение схемы совпадают в обе стороны — это держит
проба живой схемы `TestIntegration_RevocationVocabularyAgreesWithTheDomain`; у каждого слова есть
писатель — гейт `TestFamilyRevocationVocabulary_KN_FRV_17_EveryWordHasAWriter`.

Как словарь пришёл к этому виду: `consent-withdrawn` снято миграцией
`20260923225650_consent_leaves_the_schema.sql` вместе с таблицей согласий
([[KAC/issue-404-kaname]]); `client-revoke` добавлено миграцией
`20260927001324_family_revocation_reason_names_the_client_revocation.sql` (kaname#406) — написание
дословно причина фундамента, потому что адаптер порта отзыва сопрягает словари по значению;
`logout` и `client-removed` сняты миграцией
`20260927072645_family_revocation_reason_leaves_the_words_without_a_writer.sql`
([[KAC/issue-339-kaname]]) — писателя у них не было.

## Кто читает

Решение об отзыве на пути предъявления: `IsRevoked` отвечает и об отзыве семейства
предъявленного токена доступа по его `jti`, тем же обращением —
[[rpc/iam-internal-session-revocations-service]].

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`.
- 2026-09-23 — схема семейства, кода и токена обновления ([[KAC/issue-313-kaname|kaname#313]],
  запрос #326 в ветку волны).
- 2026-09-24 — сборка 1 (PR #411): согласие снято со схемы, `consent-withdrawn` ушла из словаря
  причин ([[KAC/issue-404-kaname|kaname#404]]); адаптеры портов церемонии
  ([[KAC/issue-396-kaname|kaname#396]]). Сборка 2 (PR #413): изоляция обмена кода названа, исход
  «ноль строк» классифицирован ([[KAC/issue-316-kaname|kaname#316]]).
- 2026-09-25 — сборка 4 (PR #421): выпуск токена доступа записывается в `access_tokens`
  ([[KAC/issue-319-kaname|kaname#319]]); пробы выдачи внахлёст и ключа живости
  ([[KAC/issue-369-kaname|kaname#369]]). Волна #358 влита в ветку эпика `357` (PR #422,
  `fc9f5aff19c`).
- 2026-09-26 (#778) — пересверена на ветке эпика `357`: добавлены колонка `live`, ключ
  живости и пара живости, словарь приведён к пяти значениям. Снят раздел о том, чего схема
  на `229a0693` не держала: живость с тех пор держит ключ, а разбор прежнего состояния
  адресуется диффом фикса, а не записке (`security-disclosure.md` §«Публичные артефакты»).
- 2026-09-26 — параллельная линия завела вторую записку того же ресурса (дети, читатель,
  словарь фундамента): в основе той линии этой записки ещё не было.
- 2026-09-27 (#846) — обе записки сведены в одну при слиянии линий: оболочка и инварианты —
  отсюда, разделы о детях, читателе и словаре фундамента — из второй.
- 2026-10-01 — сверена с головой `357` @ `7c5409f5e` по миграциям волны-3
  ([[KAC/issue-366-kaname|kaname#366]]): колонка `acr` и ключ пары сессии и человека
  (kaname#423), слово `client-revoke` (kaname#406), снятие `logout` и `client-removed`
  ([[KAC/issue-339-kaname|kaname#339]]). Словарь записки стоял на пяти словах ревизии `fc9f5aff`.

## See also

[[resources/iam-authorization-code]] · [[resources/iam-refresh-token]] ·
[[resources/iam-human-session]] · [[KAC/issue-339-kaname]] ·
[[rpc/iam-internal-session-revocations-service]]

#resource #kacho-iam #iam #internal #migrations
