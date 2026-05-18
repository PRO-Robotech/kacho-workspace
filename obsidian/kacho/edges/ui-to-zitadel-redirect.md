---
title: "ui → zitadel: OIDC redirect (signup-flow)"
aliases:
  - ui to zitadel
  - signup flow ui
category: edge
caller_repo: kacho-ui
callee_repo: zitadel
sync_async: sync
protocol: HTTPS+OIDC (Authorization Code + PKCE)
status: planned
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-107]]"
  - "[[KAC-109]]"
tags:
  - edge
  - kacho-ui
  - cross-service
  - planned
---

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
