---
title: "kacho#2701: край ретранслирует восстановление доступа, профили несут срок кода (Ф5)"
aliases:
  - issue-2701
ticket_id: 2701
category: kac
status: test
type: feat
repos:
  - kacho
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2704
issue_url: https://github.com/PRO-Robotech/kacho/issues/2701
opened: 2026-09-17
tags:
  - kac
  - kacho-api-gateway
  - kacho-iam
  - iam
  - go
  - helm
verified_against: "kacho, ветка batch-kaname-main-f4-f5 от origin/main@275240ef (пин kaname@94352d9c): предикаты задачи прогнаны на дереве; величина под own проверена рендером подчарта с величинами боевого профиля"
---

# kacho#2701: два глагола восстановления и срок кода в профилях чарта

**Предмет.** Половина Ф5 (`kacho#1271`) в доме платформы: `POST /iam/v1/auth/recovery` и
`POST /iam/v1/auth/recovery/complete` ретранслируются краем тем же перечнем, что глаголы Ф3;
ручка `authn.login.recovery-code-ttl` объявляется профилем. Сделано одним change-set с
`kacho#2699` — см. [[issue-2699]]; здесь только то, что относится к Ф5.

## Решения

| ось | решение |
|---|---|
| два глагола — два имени | `recovery` и `recovery-complete`; путь завершения — подпуть запроса кода, и точное совпадение обязано различать их (проба несёт отрицательный контроль на `/recovery/` и `/recovery/completex`) |
| полоса сессии | оба ключуются кодом, а не носителем: недоступность ретранслируется, как на входе |
| срок кода | `recoveryCodeTtl: 5m` в блоке `login` боевого профиля — перенос Ф1 §4.1; ключ рендерится в `authn.login.recovery-code-ttl` |

## Предикат задачи — исход

1. `IsLoginLanePath("/iam/v1/auth/recovery/complete")` → **true** (`TestLoginLanePaths_F4_F5…`).
2. `git grep -c RECOVERY_CODE_TTL -- deploy/helm/umbrella` → 3 файла; профилей, объявляющих
   `KANAME_AUTHN__LOGIN__SESSION_TTL` литералом, — **0**: профили объявляют `sessionTtl`
   YAML-ключом, поэтому неравенство выполнено, но единица предиката была не та.
3. `helm template` подчарта с величинами боевого профиля под `identityProvider: own` отдаёт
   `recovery-code-ttl: "5m"`; профиля на `own` в дереве нет — рендер сделан подстановкой посадки.

Задача закрыта по предикату; остаток общий с [[issue-2699]] (стенд `own`, `kaname#205`).

## Затронутые сущности vault

- [[rpc/iam-login-lane]]; [[issue-1271]] — остаток «Край» той записки закрыт этой.

#kac #kacho-api-gateway #kacho-iam #iam #go #helm
