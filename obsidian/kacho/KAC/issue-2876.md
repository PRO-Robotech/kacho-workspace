---
title: "kacho#2876: security.txt объявляет Expires моментом рендера"
aliases:
  - issue-2876
ticket_id: 2876
category: kac
status: to-do
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella/templates
  - deploy/helm/umbrella/values*.yaml
  - deploy/*_test.go
prs: []
issue_url: https://github.com/PRO-Robotech/kacho/issues/2876
opened: 2026-09-26
tags:
  - kac
  - fix
  - kacho-deploy
verified_against: "PRO-Robotech/kacho: трекер — задача открыта, родителя нет (`gh issue view 2876`, `gh api .../parent` → 404), PR и веток с номером нет, 2026-09-26. Строки 34–35 security-txt-configmap.yaml на 7190c3e5274 — `git show`, совпадают с телом задачи; дифф ревизий выкатки — из тела задачи"
---

# kacho#2876: security.txt объявляет Expires моментом рендера

**Состояние на момент записи**: `to-do` — 2026-09-26. Задача **открыта**, метки: `bug`, `P3`,
`size:S`, `area:deploy`, `release:platform`; родителя нет. Заведена 2026-09-26T11:43:55Z по
итогам выкатки линии эпика `2564` (координата, не живая ссылка). Роль — `deploy-engineer`.
Работы по ней нет.

## Что и зачем

**Признак.** `deploy/helm/umbrella/templates/security-txt-configmap.yaml:34-35` задаёт
`Expires` через `now` — одинаково на `origin/main` @ `1d42a672` и на `2564` @ `7190c3e527`.
Поле равно моменту рендера и истекает в ту же секунду, в которую файл выкатывается; по
RFC 9116 §2.5.5 файл с прошедшим `Expires` считается устаревшим. Комментарий строкой выше
обещает «не позже года» и со значением расходится. Второе следствие — рендер невоспроизводим:
по телу задачи, ревизии `helm upgrade` при выкатке 2026-09-26 различались только этой отметкой и
строкой о моменте генерации.

**Предмет.** `Expires` — объявленная величина: значение профиля либо дата, выведенная из
объявленной даты выпуска плюс срок не больше года, а не `now`. Рендер детерминирован по входу.

## DoD

Из тела задачи, раздел «ПРЕДИКАТ» (перечислено как есть):

1. `git grep -n 'now' -- deploy/helm/umbrella/templates/security-txt-configmap.yaml` — 0 строк;
2. два рендера одной цепочки подряд дают байт-в-байт одинаковый ConfigMap
   `kacho-security-txt` (sha256 равны);
3. проба в `deploy/` на управляемых часах: в рендере каждой цепочки `deploy/stacks.txt`
   `Expires` позже момента проверки и не дальше года от объявленной даты; инъекция
   `Expires = now` даёт красное, законный близнец молчит.

Артефакт — PR с `Closes` этой задачи; вывод п.2 — комментарием.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — зонт, в чьих шаблонах лежит ConfigMap; утверждений
  о `security.txt` записка не несёт.

#kac #fix #kacho-deploy
