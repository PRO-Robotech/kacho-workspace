---
title: "kaname#257: код при незаведённом факторе — тот же отказ, что неверный пароль"
aliases:
  - issue-257-kaname
ticket_id: 257
category: kac
status: done
type: fix
repos:
  - kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/264
issue_url: https://github.com/PRO-Robotech/kaname/issues/257
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - iam
  - security
verified_against: "kaname main@16b5cade (MR #266); проба internal/handler/loginlanehttp/second_factor_not_enrolled_integration_test.go; приёмка Ф12 редакция 8 APPROVED (kacho#1281 issuecomment-5711101932)"
---

# kaname#257: «не заведён» отвечал только тому, кто знает пароль — оракул совпадения

**Предмет.** Вход с полем `secondFactor` у личности без фактора отвечал 400 «фактор не заведён»
**после** проверки пароля: неверный пароль давал 401, верный — 400. Различимый ответ выдавал
совпадение пароля тому, у кого фактора нет, — оракул на полосе входа.

**Решение.** Код при незаведённом факторе — тот же отказ, что неверный пароль: тела и коды
побайтово равны (401). Положительный близнец в той же пробе: верный пароль **без** кода —
сессия «1». Строка таблицы отказов на странице приведена; приёмка Ф12 получила редакцию 8.

**Чем держится.** `second_factor_not_enrolled_integration_test.go` утверждает **байты** обоих
отказов, а не только код; интеграция на MR зелёная.

**Класс.** Тот же, что hide-existence у края (`security-hardening.md` п. 6): различимый текст —
оракул; правится сравнением байтов, а не тоном.

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — исход `login` с полем `secondFactor` у личности без фактора.
- [[issue-1281-kaname]] — Ф12, редакция 8.

#kac #kacho-iam #iam #security
