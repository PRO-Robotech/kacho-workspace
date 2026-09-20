---
title: "kacho#1269: iam Ф3 — полоса входа паролем, наша сессия, отзыв и выход"
aliases:
  - issue-1269
ticket_id: 1269
category: kac
status: in-progress
type: feature
repos:
  - kaname
  - kacho
areas:
  - iam
  - gateway
prs:
  - https://github.com/PRO-Robotech/kaname/pull/173
  - https://github.com/PRO-Robotech/kaname/pull/179
  - https://github.com/PRO-Robotech/kaname/pull/189
  - https://github.com/PRO-Robotech/kacho/pull/2689
issue_url: https://github.com/PRO-Robotech/kacho/issues/1269
opened: 2026-08-24
tags:
  - kac
  - kacho-iam
  - kacho-api-gateway
  - iam
  - go
  - migrations
verified_against: "kaname: main@af0ca8f3 и release/iam-lines@6acf8f19 — каталог полосы, миграция и перечень путей прочитаны по дереву; kacho: ветка issue-1269-login-lane-edge@2dcf7f2e против main@972bdc34 — перечень файлов края снят `git diff --name-only`; задача, PR и записи вердиктов — `gh` 2026-09-17; стенд не поднимался, о поведении продукта вердикта нет"
---

# kacho#1269: полоса входа — наша сессия, и выход завершает её на стороне сервера

**Предмет.** Фаза Ф3 эпика `kacho#1266`. До неё сессию человека выдавал и проверял чужой
компонент, а наш авторитет отзыва стоял **рядом** с чужой сессией, не над ней. Ф3 заводит свой
поток: форма → проверка пароля → сессия-запись службы; печенье с именем, сроком и атрибутами;
отзыв на выходе, смене пароля и блокировке — **на стороне сервера**, а не гашением носителя у
клиента. Задача открыта: закрывается **парой половин** (служба · край), и вторая половина ещё
не в стволе платформы.

## Приёмки — две, обе одобрены внешним событием

| документ (дом `PRO-Robotech/kaname`) | вердикт | круг | PR |
|---|---|---|---|
| `docs/engineering/acceptance/login-session-and-credentials-are-our-contract.md` (Ф1, предпосылка Ф3) | APPROVED 2026-09-16, ревизия `478b3fcc`, отпечаток `b30ee296…` | 8 | kaname#104 |
| `docs/engineering/acceptance/login-lane-issues-our-session-and-logout-ends-it-server-side.md` (Ф3) | APPROVED 2026-09-16, ревизия `b10566a5`, отпечаток `1a7f6846…` | 2 (оппонент 7 → 4, рецензия 4 → 0) | kaname#173 |

Ф3 — 52 сценария; 47 строк ведомости Ф1 §5, отданных Ф3, закрыты по одной. Что оба
вердикта **не** утверждают: стенд не поднимался, Ф3-46 (перевод стенда, «103/106 сессий
поставщика») — ориентир, «не выполнилось» by construction.

## Половина службы — В СТВОЛЕ `main` службы

PR kaname#179 (`issue-1269-login-lane` → линия `release/iam-lines`, `c0eb17c5`), затем линия
целиком → `main` PR kaname#189 (`af0ca8f3`, 2026-09-16T22:31Z).

| предмет | где | что держит |
|---|---|---|
| сессия как запись службы | миграция `internal/migrations/20260916190000_human_session_is_our_record.sql`: `kaname.human_sessions`, `kaname.human_first_authentications`, `kaname.login_failures` | [[resources/iam-human-session]] |
| поток входа · выхода · смены пароля | `internal/apps/kaname/api/humansession/` (`login.go`, `logout.go`, `change_password.go`, `issue.go`, `resolve.go`, `refusals.go`, `rate.go`, `password_rule.go`) | пробы того же каталога; порт — `iface.go` |
| глаголы формы на HTTP-слушателе полосы | `internal/handler/loginlanehttp/handler.go` — `Paths()` одним объявлением, семь путей | [[rpc/iam-login-lane]] |
| резолв сессии для края | `project/kaname/proto/kaname/cloud/iam/v1/human_session_service.proto` — `InternalHumanSessionService.Resolve` (`<exempt>`, внутренний слушатель) | строка каталога прав — [[issue-184-kaname]] |
| ручки полосы | `internal/apps/kaname/config/login_lane.go` — `authn.login.*` (`session-ttl`, `cookie-domain`, окна и потолки неверных предъявлений, правило пароля, формат хеша) одним перечнем `LoginLaneKnobs` | страж посадки `own` читает тот же перечень |

## Половина края — ВЕТКА, PR открыт в `main` платформы

PR kacho#2689 (`issue-1269-login-lane-edge`, база `main`; 69 файлов, +5117/−162 относительно
`main@972bdc34`): пин службы в `go.mod` поднят до `main` службы `af0ca8f3` вместе с пином образа
в пяти профилях зонтичного чарта; каталог прав перегенерирован — прибавилась **одна** запись,
`InternalHumanSessionService/Resolve`. Свои файлы края — `gateway/internal/middleware/`
(`auth_own_session.go`, `auth_session_cutoff.go`, `human_session.go`, `login_lane_paths.go`,
`own_session_assurance.go`), `gateway/internal/handler/login_lane_relay.go`,
`gateway/internal/handler/logout_handler.go`, `gateway/internal/clients/session_revocations_client.go`.

Локально на голове ветки (по комментарию 2026-09-16T23:18Z): `scripts/ci-local.sh proto go` —
25 из 25; `ui` — 37 ok и 4 «не выполнено» (пробы браузером без стенда); хук отправки 36 из 36;
`-race` не исполнялся (нет C-компилятора) — вердикт даст конвейер.

## Посылки задачи — перемерены (документ Ф3 §0.4)

- **подтвердилось:** сессию выдавал чужой компонент; авторитет отзыва стоял рядом; выход не
  завершал сессию на стороне сервера (предмет Ф1-14: сохранить печенье, выйти, предъявить
  снова → отказ);
- **опровергнуто:** «край получает четыре поля» — полей **семь** (`kacho#1201`, `kacho#1252`).

## Что осталось и чем закрывается

1. **вливание kacho#2689 в `main` платформы** — вторая половина пары; предикат:
   `git -C kacho grep -c 'InternalHumanSessionService/Resolve' origin/main -- gateway/internal/middleware/embed/permission_catalog.json` → 1;
2. **предикат задачи на стенде** — перевод стенда на посадку `own` (Ф3-46), сквозная проба
   «сохранить печенье → выйти → предъявить → отказ»: здесь «не выполнилось», стенд не поднимался.
   На уровне держателей обе стороны есть: у службы — отзыв на выходе и смене пароля, у края —
   отказ F4d-22 на снятой сессии с гашением носителя (`gateway/internal/middleware/own_session_lane_test.go`);
3. **половина Ф1-61/66 о маршруте «кто я»** исполняется исходом Д13 до правки Ф1 у владельца
   (`kaname#177`) — как записано в приёмке.

## Находки по дороге — заведены задачами

- [[issue-184-kaname]] — копия каталога прав службы и строка `Resolve`: порядок синхронизации
  копий между репозиториями;
- [[issue-188-kaname]] — проба Ф3-31: отказ на неверном пароле различим по времени **между
  классами стоимости**; решение об устройстве выравнивания — владельца;
- [[issue-195-kaname]] — Ф11 §9 п.3 и Ф3-45 называют разный момент снятия сопоставления словаря
  поставщика на крае;
- [[issue-2697]] — сессию восстановления с требованием сменить пароль (Ф3 Р8, Ф3-23) не выдаёт ни
  один глагол; решение принято 2026-09-17.

## Затронутые сущности vault

- [[resources/iam-human-session]] — заведена этой задачей.
- [[rpc/iam-login-lane]] — глаголы входа, выхода, смены пароля и признака формы (регистрация — Ф4
  [[issue-1270-kaname]], восстановление — Ф5 [[issue-1271]]).
- [[resources/iam-session-revocation]] — отсечка: писатели `logout` и `password-change` те же,
  что причины снятия строки сессии.
- [[edges/api-gateway-to-iam-acr-floor]] — уровень сессии читается краем из нашей записи (Ф11,
  [[issue-1280]]), не из словаря поставщика.
- [[rpc/iam-internal-user-service]] — `UpsertFromIdentity` остаётся путём зеркала внешней
  личности; полоса паролем его не зовёт.

#kac #kacho-iam #kacho-api-gateway #iam #go #migrations
