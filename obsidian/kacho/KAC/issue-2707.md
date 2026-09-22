---
title: "kacho#2707: край снимает читателя passwordChangeRequired вместе с предметом"
aliases:
  - issue-2707
ticket_id: 2707
category: kac
status: test
type: fix
repos:
  - kacho
prs: []
issue_url: https://github.com/PRO-Robotech/kacho/issues/2707
opened: 2026-09-17
tags:
  - kac
  - kacho-api-gateway
  - iam
  - go
verified_against: "kacho ветка w16-edge-f12 на c7d8545b (слияние issue-1281-second-factor-edge со стволом b5fa0933 + пин kaname 16b5cade): git grep PasswordChangeRequired -- '*.go' ':!*_test.go' → 0; пакеты middleware/clients/observability/allowlist зелёные; полный локальный прогон proto go — результат не прочитан"
---

# kacho#2707: край читал состояние, которого не бывает

**Предмет.** Служба сняла поле 8 `HumanSession.password_change_required` (kaname#201,
`reserved`): решение kacho#2697 (исход 1) оставило завершение восстановления одним обращением, и
производителя значения `true` не было ни одного. Край держал читателя в **девяти** прод-файлах:
контекст запроса, ветку отказа `PASSWORD_CHANGE_REQUIRED` до вопроса к модели, клетку метрики,
поле сессии, «кто я».

**Решение.** Снято целиком, не ослаблено; сессия, выданная восстановлением, судится каталогом
как всякая сессия входа (Ф5-24). Пробы: Ф3-23 заменена положительным близнецом Ф5-24 (полоса
пропускает сессию к решению по каталогу с личностью и уровнем); клетка метрики — пробой её
**отсутствия** с живым соседом `scope_filtered` как контролем; «кто я» утверждает, что снятого
поля нет ни истиной, ни ложью.

**Порядок был несущим.** На прежнем пине геттер `GetPasswordChangeRequired` ещё существовал, и
снятие читателя не краснело компиляцией — ловит его только пин: сперва
`go get github.com/PRO-Robotech/kaname@16b5cade`, потом снятие. Так и сделано, одним PR с краем
Ф12 (kacho#1281).

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — «кто я» без поля `passwordChangeRequired`.
- [[issue-1281-kaname]] — та же посадка пина.

#kac #kacho-api-gateway #iam #go
