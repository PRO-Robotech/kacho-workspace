---
title: "kaname#254: ResetSecondFactor — распоряжение личностью не есть право аккаунта (governingRPCs)"
aliases:
  - issue-254-kaname
ticket_id: 254
category: kac
status: in-progress
type: fix
repos:
  - kaname
areas:
  - internal/authzmap
  - internal/apps/kaname/api/user
prs:
  - PRO-Robotech/kaname#294
issue_url: https://github.com/PRO-Robotech/kaname/issues/254
opened: 2026-09-18
tags:
  - kac
  - kacho-iam
  - iam
  - fix
verified_against: "kaname origin/main `internal/authzmap/governing_the_identity_is_not_an_account_right_test.go` прочитан (гейт на класс: распоряжаться строкой личности не вправе распорядитель аккаунта; отношение спрашивается у каталога прав, не литералом). Authz-часть — squash `8294f83a` (PR #294); остаток (proto-комментарий, `user.mdx`, самосброс Ф12-45) — со слов полосы, задача остаётся open"
---

# kaname#254: распоряжение личностью не есть право аккаунта

**Состояние**: in-progress — **authz-часть влита** волной 2 (PR kaname#294, squash `8294f83a`);
задача остаётся open на остаток (ниже).

**PRs**: PRO-Robotech/kaname#294 (authz-часть)
**Issue**: https://github.com/PRO-Robotech/kaname/issues/254

## Что и зачем

Человек в этом дереве — **глобальная личность**: одна строка `iam_user` на все его аккаунты,
принадлежность выражают строки `memberships`. Значит всё, что записано в строку личности, и всё,
что ею **распоряжается** (сброс второго фактора и подобное), действует **во всех** аккаунтах
человека сразу. Отсюда класс: распорядитель одного аккаунта, получив такое право, получает власть
за границей своего аккаунта. Директива владельца (2026-08-23): «тот кто пригласил может только
удалить/добавить права».

`UserService/ResetSecondFactor` (Ф12 Р10, [[KAC/issue-1281-kaname]]) заведён под гейт
распоряжения личностью (**governingRPCs**): отношение, которым гейтится RPC, **спрашивается у
каталога прав** (генерируется из proto — единственный источник per-RPC решения края), не задаётся
литералом имени. Гейт `internal/authzmap/governing_the_identity_is_not_an_account_right_test.go`
проверяет с обеих сторон: у отношения **нет** источников уровня аккаунта (ни пообъектной выдачи,
ни делегированного администратора, ни владельца) и **нет** прямого списка субъектов (нельзя
вручить кортежем/выдачей/материализацией), а держатель **есть** — администратор облака. Тем же
заходом закрыта матрица verb×role и линия держателя.

## Остаток (задача open)

- [ ] proto-комментарий у `ResetSecondFactor` в `user_service.proto` — назвать гейт словами;
- [ ] доковка `user.mdx` — распоряжение личностью и его держатель;
- [ ] самосброс Ф12-45 — сам человек сбрасывает свой фактор без распорядителя.

## Затронутые сущности vault

- [[packages/iam-authzmap]] — где живёт каталог прав и гейт класса.
- [[rpc/iam-user-service]] — `ResetSecondFactor` и его authz.
- [[KAC/issue-1281-kaname]] — Ф12, откуда `ResetSecondFactor`.

## DoD

- [x] authz `ResetSecondFactor` под governingRPCs, отношение из каталога, гейт с обеих сторон
- [x] матрица verb×role + линия держателя
- [ ] proto-комментарий, `user.mdx`, самосброс Ф12-45

#kac #kacho-iam #iam #fix
