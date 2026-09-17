---
title: "kacho#2699: край ретранслирует регистрацию, профили несут её величины (Ф4)"
aliases:
  - issue-2699
ticket_id: 2699
category: kac
status: test
type: feat
repos:
  - kacho
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2704
issue_url: https://github.com/PRO-Robotech/kacho/issues/2699
opened: 2026-09-17
tags:
  - kac
  - kacho-api-gateway
  - kacho-iam
  - iam
  - go
  - helm
verified_against: "kacho, ветка batch-kaname-main-f4-f5 от origin/main@275240ef (пин kaname@94352d9c): предикаты задачи п.1–2 прогнаны на дереве; п.3 (сквозная проба на стенде own) — стенда own нет ни в одном профиле, не исполнялся"
---

# kacho#2699: пятый глагол полосы формы и две величины регистрации

**Предмет.** Кросс-репо половина Ф4 (`kacho#1270`, приёмка
`PRO-Robotech/kaname:docs/engineering/acceptance/registration-and-its-three-consequences.md`,
Р5, Ф4-18/19) в доме платформы. Служба обслуживает `POST /iam/v1/auth/register` тем же
перечнем, что четыре глагола Ф3 (`loginlanehttp.Paths()` → 7); край знал четыре и отвечал 404.
Сделано одним change-set с `kacho#2701` — предмет один и тот же (объявление перечня), делить его
пополам значило бы два диффа одной строки.

## Что сделано

| ось | решение |
|---|---|
| перечень края | `gateway/internal/middleware/login_lane_paths.go` — семь глаголов одним объявлением: читают его полоса сессии, перечень путей без записи каталога и регистрация ретрансляции |
| полоса сессии на новом глаголе | как на входе: «сессии нет» и недоступность ретранслируются, отсечка отвергается краем; состояния под сессией носителя регистрация не меняет (асимметрия смены пароля F4d-23 не распространяется) |
| словарь меток | `kacho_api_gateway_login_lane_relayed_total{verb="register"}` — клетка существует с нулём; сходимость двух словарей держит `TestSessionLane_F3_48_VerbLabelsMatchTheDeclaredRoutes` |
| подчарт службы | блок `authn.registration` рендерится из `config.authn.registration`: `admissions-per-window` по `hasKey` + `int64` (ноль законен), `admission-window` |
| боевой профиль | `values.prod.yaml`: `registration: {admissionsPerWindow: 3, admissionWindow: 1h}` — перенос справочника службы; в ведомости `login_lane_umbrella_test.go` с причиной (страж читает под `own`, профиль на `external`) |

## Пары RED → GREEN

- `TestLoginLanePaths_F3_51…`: объявлено 4, ожидалось 7 → 7; `TestLoginLanePaths_F4_F5…`: три пути не узнаёт ни полоса, ни `isPublicHTTPPath` → узнаёт.
- `TestOwnSessionLane_F4_F5…`: на перечне из четырёх «сессии нет» на `/register` даёт 401 → ретранслируется.
- `TestLoginLane_F4_F5_UmbrellaSubchartExpressesRegistrationAndRecovery`: блока `registration` нет → рендерится 2 из 2; `TestLoginLane_F3_45_ProductionProfilesDeclareTheLaneWithAReason`: 17 из 20 → 20 из 20.

## Предикат задачи — исход

1. `git grep -c 'auth/register' -- gateway/internal/middleware/login_lane_paths.go` → **1**.
2. Профили под `own` объявляют обе величины — профилей на `own` в дереве **0** (перепись гейта);
   объявляет боевой профиль по установленной форме Ф3. Предикат задачи считал переменные
   среды (`AUTHN__REGISTRATION` в `charts/kaname/values*.yaml` → 3): чарт объявляет YAML-ключи,
   а имена переменных стоят в образце базового профиля — единица предиката была не та.
3. Сквозная проба регистрации через край на стенде `own` — **условие не создано**: стенда `own`
   нет, фикстура `register(page)` в `ui-future/e2e` ведёт поток поставщика (`/registration`,
   `traits.email`), а не полосу формы. Задача **частично**: п.3 закрывается первым стендом на `own`.

## Что осталось

- Собственный чарт службы несёт тот же долг — `PRO-Robotech/kaname#205`.
- Соседняя полоса `issue-1281-second-factor-edge` расширяет ТО ЖЕ объявление (шесть глаголов Ф12): слияние с этой веткой — по существу (перечень, каталог, allowlist, словарь меток, пин).

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — край теперь ретранслирует 7 из 13 путей перечня службы (Ф3+Ф4+Ф5; Ф12 — своей полосой).
- [[issue-1270-kaname]] — служба; здесь платформенная половина.

#kac #kacho-api-gateway #kacho-iam #iam #go #helm
