---
title: "kacho#1270: iam Ф4 — регистрация и её три следствия одним исходом"
aliases:
  - issue-1270-kaname
  - issue-1270
ticket_id: 1270
category: kac
status: test
type: feat
repos:
  - kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/196
issue_url: https://github.com/PRO-Robotech/kacho/issues/1270
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - iam
  - go
verified_against: "ветка issue-1270-registration от release/iam-lines@af0ca8f3 (kaname): приёмка registration-and-its-three-consequences.md, запись ревью 397640b0… APPROVED (issued 2026-09-16T04:22:24Z); 24 сценария — держатели названы ниже, по каждому пара RED→GREEN"
---

# kacho#1270: регистрация нашей полосой — три следствия одной транзакцией

**Предмет.** Приёмка `PRO-Robotech/kaname:docs/engineering/acceptance/registration-and-its-three-consequences.md`
(Ф4 эпика `kacho#1266`). Регистрация перестаёт быть списком хуков чужой конфигурации:
глагол `POST /iam/v1/auth/register` на полосе формы (Ф3) пишет **зеркало · адрес · сессию**
одним writer'ом одной транзакции базы; полоса регистрации — сущность нашего кода
(`registration.Lanes`), и гейт сходимости полос читает это объявление.

## Решения, принятые здесь (приёмка их не пересматривала)

| ось | решение | почему |
|---|---|---|
| один writer | порт `registration.Writer` = `humansession.Writer` + `Mirror` + `InsertLoginMethod`; адаптер `pg.RegistrationWriter` — над одной `pgx.Tx`; `Commit` — мост корневого писателя (отложенные отказы схемы) | сшивка тремя writer'ами невыразима: у порта нет способа открыть второй |
| зеркало | тело `bootstrapPersonalResources`/активации вынесено в `user.BootstrapPersonalResourcesTx` / `ActivateInviteTx` / `RegisterMirrorTx` над writer'ом вызывающего; провизион-хук зовёт их своей транзакцией, состав эмитируемого сохранён | Р1: зеркало пишет тот же writer, что сессию |
| адаптер порта — в композиционном корне | `pg` порт не импортирует (пробы пакета зеркала зовут адаптер → круг в пробах); композицию зеркала над `MirrorWriter()` исполняет корень и харнесс | иначе `internal/apps/kaname/api/user [setup failed]` |
| идентичность | `domain.NewOwnLaneSubject()` → `own:sub-…` (F4d Р10/F4d-52); голова читается триггером темпа | ACTIVE требует непустого `external_id`; ослабление ограничения отвергнуто F4d |
| носитель ключа темпа (Р5) | триггер `kacho_admission_rate_count` ключует окно `lower(email)` у полосы с головой `own:`, внешним идентификатором — у поставщика; миграция `20260917120000_registration_carrier_keys_the_admission_rate.sql` замещает тело функции по имени | ключ по свежей идентичности — рубеж, исчезающий молча |
| величина темпа (Ф4-18/19) | `authn.registration.admissions-per-window` + `admission-window`; строка таблицы полос — **только под `own`**; на старте проектируется в `account_admission_rate_limits` (`OwnCeilingRepo.ApplyAdmissionRate`) | под `external` строку авторитета правит администратор облака (существующие пробы это утверждают); второго писателя не заводится |
| единый отказ (Р3) | `registration.ErrRefused` → 400 `FAILED_PRECONDITION` `registration refused`, reason `REGISTRATION_REFUSED`, без `Retry-After`; занятость · активация конкурентом · истёкшее приглашение · потолок темпа — один текст, причина в клетке `kaname_registration_outcomes_total{lane,outcome}` | 409/429 — оракул |
| приглашённый (Р6) | та же полоса; `PENDING` по адресу активируется в той же транзакции; истёкшее приглашение держит ключ почты → тот же отказ (паритет с полосой поставщика, MAIL-23) | третьей полосы нет |
| полоса ↔ глагол (Р4) | `NewRegisterUseCase` собирается только для полосы, объявившей все три следствия; `Execute` исполняет объявленные | гейт судит то же, что исполняется |

## Сценарии → держатели (RED → GREEN)

| сценарии | держатель | RED | GREEN |
|---|---|---|---|
| Ф4-06…10 | `internal/check` `TestRegistration_EveryLaneIssuesASession` + `registration_lanes_injection_test.go` | `[setup failed]` — пакета нет; затем «вердикта НЕТ: файла объявления в дереве нет» | полос 1 · выдают 1 · файлов 908; инъекция на живом дереве — «полоса "password" не выдаёт сессию» |
| Ф4-01…05, 11, 13, 23, 24, Ф1-62 | `registration/register_integration_test.go` (реальная база, отказ по одному следствию) + `register_test.go` (подставные порты) | `undefined: registration.Store` | 6/6 интеграция, 4/4 юнит |
| Ф4-01 E, Ф4-11/12 тело | `loginlanehttp/register_test.go` | `undefined: loginlanehttp.PathRegister` | 2/2 |
| Ф4-14…16 | `registration/timing_probe_test.go`: критерий на синтетике (всегда) + живой замер ручкой | — | синтетика 3 исхода; живой: Δ 215µs ≤ IQR 3.1ms; инъекция одного хеша — красное, 34.5ms; на Postgres Δ 3.7ms ≤ IQR 48.6ms |
| Ф4-12, 17, Р5 | `pg/registration_carrier_rate_integration_test.go`, `registration/…F4_12_17…`, `migrations/own_lane_head_agrees_test.go` | `ApplyAdmissionRate undefined` | 3/3 + 1 + 1 |
| Ф4-18, 19 | `config/registration_test.go`, строка `LaneRequirements` (табличная проба F4d-10), `cmd/kaname/admission_rate_apply_test.go` | `undefined: config.RegistrationConfig`; `TestDeclaredDomainPassesTheStart` красный на годной посадке без величины | зелёные |
| Ф4-20…22 | `pg/registration_materialization_integration_test.go` | — | сессия годна до доставки; намерения в очереди; после реконсайла доступ материализован |

## Что осталось — с носителем

- **Край (kacho)**: пятый глагол `/iam/v1/auth/register` в `gateway/internal/middleware/login_lane_paths.go` (ветка `issue-1269-login-lane-edge`, PR kacho#2689 открыт) — без него E-уровень через край недостижим; профили `deploy/helm/umbrella/charts/kaname/values*.yaml` под `own` обязаны объявить `KANAME_AUTHN__REGISTRATION__ADMISSIONS_PER_WINDOW` и `…ADMISSION_WINDOW`, иначе старт под `own` отвергается (Ф4-18). Не правилось по условию задачи — заведено находкой.
- **Ф10 `#1276`**: снятие `deploy/identity_registration_lanes_issue_a_session_test.go` вместе с чужим объявлением полос — «Дано» Ф4-10 (запись ревью, В3).
- **Смена почты сбрасывает окно темпа** у людей нашей полосы (ключ — текущий `lower(email)`); до Ф6 (`#1272`, действия требуют подтверждённого адреса) это обход рубежа ценой смены адреса — названо задачей.
- **Ф4-21 текст «повторить»** производит край (bounded client-retry); в доме службы держится различимость (намерение в очереди при годной сессии).

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — заведена: пять глаголов полосы формы, отказы, печенья.
- [[resources/iam-user]] — путь регистрации нашей полосой; идентичность `own:`; носитель ключа темпа.
- [[issue-1271]] — Ф5, параллельная полоса (вид письма здесь не заводится). Записки Ф3 (`kacho#1269`) в хранилище нет — над ней стоит эта фаза; её след — приёмка `login-lane-issues-our-session-and-logout-ends-it-server-side.md` в доме службы.

#kac #kacho-iam #iam #go
