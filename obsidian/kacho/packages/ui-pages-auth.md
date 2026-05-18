---
title: "ui src/pages/auth + components/auth + contexts/AuthContext"
aliases:
  - ui auth
  - signup flow files
category: packages
repo: kacho-ui
layer: ui-pages
tags:
  - packages
  - kacho-ui
  - planned
---

# ui — auth pages + context

**Repo**: `kacho-ui`
**Layer**: UI pages + React-context
**Status**: реализован в kacho-ui#41 ([[../KAC/KAC-109]] DoD #1). Backend `/iam/v1/auth/*` — pending [[../KAC/KAC-107]].

## Файлы

| Path | Назначение |
|---|---|
| `src/api/auth.ts` | fetch helpers (login/callback/me/logout) с `credentials: 'include'` |
| `src/contexts/AuthContext.tsx` | `AuthProvider` + `useAuth()` hook, hydrate через GET /me на mount |
| `src/components/auth/LoginButton.tsx` | AntD primary button, `window.location.assign('/iam/v1/auth/login')` |
| `src/components/auth/UserMenu.tsx` | Dropdown в header: avatar-initials + {Профиль, Выйти} |
| `src/components/auth/HeaderAuth.tsx` | switch loading/user → LoginButton vs UserMenu |
| `src/pages/auth/AuthCallback.tsx` | landing `/auth/callback`, extract code+state, POST /callback, refresh /me, navigate / |
| `src/pages/auth/Logout.tsx` | `/logout` route — clear session + redirect |

## Exported API

- `AuthProvider` (wrap App)
- `useAuth()` → `{user, loading, login, logout, refresh, hasPermission}`
- `authApi.{login, callback, me, logout}`
- `hasPermission(user, perm)` — поддерживает `*` admin wildcard

## Поведение

- На mount `AuthProvider` зовёт `authApi.me()`; 401/network → `user=null` (grace).
- `LoginButton` — full-page redirect (не XHR — нужен 302 на Zitadel).
- `AuthCallback` — `useRef`-guard от двойного callback (Strict-Mode, code одноразовый).
- `ServiceSidebar` — IAM-кнопка hidden пока `!user || !hasPermission('iam.read')`; Profile-кнопка — только когда залогинены.

## See also

[[../edges/ui-to-zitadel-redirect]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-104]] [[../KAC/KAC-107]] [[../KAC/KAC-109]]

#packages #kacho-ui #planned


## 2026-05-17 nginx resolver fix

`deploy/05-resolver-from-resolvconf.sh` + `deploy/default.conf.template` (был `nginx.conf`) — на startup нгинкс читает nameserver из /etc/resolv.conf и подставляет в `resolver`-директиву. Cluster-agnostic, без env-vars.