---
title: "ui → zitadel: OIDC redirect (signup-flow)"
aliases:
  - ui to zitadel
  - signup flow ui
category: edge
caller_repo: kacho-ui
callee_repo: zitadel (вызываемого в дереве НЕТ — снят KAC-127, см. врезку)
sync_async: sync
protocol: HTTPS+OIDC (Authorization Code + PKCE)
status: superseded
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-107]]"
  - "[[KAC-109]]"
tags:
  - edge
  - kacho-ui
  - cross-service
  - deprecated
verified_against: "предмет ребра перемерен на дереве продукта 6b1293713 (2026-08-08): вызываемого нет, три из четырёх маршрутов не резолвятся; текст ниже сохранён как решение и его отмена"
---

> [!warning] Ребро НЕ СОСТОИТСЯ: вызываемого в дереве нет (перемерено 2026-08-08 на `6b1293713`)
> Чарт и конфигурация Zitadel сняты (KAC-127); ярус входа — **Ory Kratos + Hydra**.
>
> Предикат и обе стороны счёта: `git grep -il zitadel` → **13** файлов (**19** строк), из них
> ни одного развёртывающего — это `.gitignore`, отрицающие комментарии в чарте и профиле
> (`deploy/Makefile:977` прямым текстом: цель администрирования удалена, Zitadel заменён на
> Ory Kratos + Hydra) и остаточные имена в консоли; `git grep -il hydra` → **435** файлов
> (**3611** строк). Порядок величин и есть ответ.
>
> Маршруты: `/iam/v1/auth/login`, `/iam/v1/auth/callback`, `/iam/v1/auth/logout` — по **0**
> файлов каждый. Исключение названо, потому что иначе врезка была бы неверна в другую сторону:
> `/iam/v1/auth/me` **резолвится** (`gateway/internal/middleware/session_identity_handler.go:87`,
> провязан в `gateway/cmd/api-gateway/main.go`), но отвечает он **сессией Kratos**, а не обменом
> кода у Zitadel — то есть это другой предмет с тем же префиксом пути.
>
> **Почему `status` больше не `planned`.** `planned` — ведро «в работе»: предмета ещё нет, но он
> ожидается. Здесь предмета не будет: замена уже сделана и зафиксирована в профилях
> развёртывания. Записка, обещающая будущее, которого не будет, хуже устаревшей — по ней
> начинают работу. Живой ярус входа описывают [[edges/iam-to-hydra-admin]] и
> [[edges/iam-to-kratos-admin]]; здесь — только решение и его отмена.
>
> Ниже **не правлено ничего**: текст верен как история проектного решения и по нему
> прослеживаются KAC-104/107/109. Слово «planned» в теле относится к моменту записи.

# ui → zitadel: OIDC redirect (signup-flow)

**Caller**: `kacho-ui` (header `LoginButton` + `/auth/callback`)
**Callee**: `zitadel` (через api-gateway: `/iam/v1/auth/login` → 302 Zitadel `/oauth/v2/authorize`; `/iam/v1/auth/callback` обменивает code на JWT)
**Protocol**: HTTPS + OIDC (Authorization Code + PKCE)
**Sync/Async**: **sync** на login-path (полный round-trip browser→api-gw→Zitadel→browser→api-gw)
**Status**: **planned** — backend `/iam/v1/auth/*` endpoint'ы появляются в E2 ([[KAC-107]]); UI ([[KAC-109]] kacho-ui#41) уже реализован, на E0 грациозно отрисует «не залогинен» state.

## Flow

```
UI (LoginButton)
  → window.location.assign('/iam/v1/auth/login')
api-gateway
  → генерирует state + PKCE verifier → state-cookie
  → 302 → Zitadel /oauth/v2/authorize?client_id=kacho-platform&redirect_uri=<UI>/auth/callback&response_type=code&scope=openid+profile+email&state=<s>&code_challenge=...
Zitadel (login form / signup form / consent)
  → 302 → UI /auth/callback?code=<c>&state=<s>
UI (AuthCallback)
  → POST /iam/v1/auth/callback?code=<c>&state=<s> (credentials: include)
api-gateway
  → проверяет state-cookie, обменивает code на JWT (Zitadel /oauth/v2/token, PKCE verifier)
  → InternalIamService.LookupSubject(external_id=sub) (upsert User mirror)
  → ставит httpOnly session-cookie с JWT
  → 200 OK
UI (AuthCallback)
  → refresh() /iam/v1/auth/me → setUser → navigate('/')
```

## Endpoints (api-gateway side, planned KAC-107)

| Path | Method | Purpose |
|---|---|---|
| `/iam/v1/auth/login` | GET | 302 → Zitadel /oauth/v2/authorize, state-cookie |
| `/iam/v1/auth/callback` | POST `?code&state` | exchange code → JWT, set session cookie, return 200 |
| `/iam/v1/auth/me` | GET | return current `{user: {id, display_name, email, subject_type, account_id, permissions[]}}` |
| `/iam/v1/auth/logout` | POST | clear session cookie, 204 |

UI шлёт `credentials: 'include'` на все запросы (httpOnly session cookie).

## UI side files

- `src/api/auth.ts` — fetch helpers (login/callback/me/logout)
- `src/contexts/AuthContext.tsx` — Provider + `useAuth()` hook
- `src/components/auth/{LoginButton,UserMenu,HeaderAuth}.tsx`
- `src/pages/auth/{AuthCallback,Logout}.tsx`

## Error handling

| Scenario | UI behaviour |
|---|---|
| `error`/`error_description` в callback URL (user denied / Zitadel error) | AuthCallback показывает `Alert error`, кнопка «На главную» |
| `code`/`state` отсутствует | то же |
| api-gw 4xx/5xx на /callback | то же, выводит сообщение из error.message |
| /me возвращает 401/4xx (E0 / истёкший cookie) | `user=null`, UI рендерит `LoginButton` |

## E0 status (текущий)

- Backend `/iam/v1/auth/*` **не реализован** — UI отрисует `LoginButton`, клик уйдёт на /iam/v1/auth/login → api-gw 404; user остаётся anon.
- Получает «не залогинен» состояние без поломок (AuthContext catches 401/network errors).

## See also

[[iam-to-zitadel-oidc]] [[../rpc/iam-internal-iam-service]] [[../KAC/KAC-104]] [[../KAC/KAC-107|KAC-107 (E2)]] [[../KAC/KAC-109|KAC-109 (E4)]] [[../packages/ui-pages-auth]]

#edge #kacho-ui #cross-service #planned
