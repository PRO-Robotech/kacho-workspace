---
title: "kacho#2876: security.txt объявляет Expires моментом рендера"
aliases:
  - issue-2876
ticket_id: 2876
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella/templates
  - deploy/helm/umbrella/values*.yaml
  - deploy/*_test.go
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/2876
opened: 2026-09-26
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-deploy
verified_against: "PRO-Robotech/kacho: трекер — задача открыта, родителя нет (`gh issue view 2876`, `gh api .../parent` → 404), PR и веток с номером нет, 2026-09-26. Строки 34–35 security-txt-configmap.yaml на 7190c3e5274 — `git show`, совпадают с телом задачи; дифф ревизий выкатки — из тела задачи; 2026-09-28 (#846): состояние, метки и родитель — трекер (`gh issue view 2876 -R PRO-Robotech/kacho`, `gh api .../parent`), вливания — `gh pr view` либо лог ветки волны; DoD не перемерялся; 2026-10-08 — трекер: CLOSED 2026-10-07 completed, DoD-proof @4157f4fbf68d (gh api …/comments), коммит слияния PR #3073 = 8725b886e124 в 1266 (gh pr view)"
---

# kacho#2876: security.txt объявляет Expires моментом рендера

**Состояние на момент записи**: `to-do` — 2026-09-26. Задача **открыта**, метки: `bug`, `P3`,
`size:S`, `area:deploy`, `release:platform`; родителя нет. Заведена 2026-09-26T11:43:55Z по
итогам выкатки линии эпика `2564` (координата, не живая ссылка). Роль — `deploy-engineer`.
Работы по ней нет.

**Состояние на 2026-09-28**: `wontfix`. Задача **закрыта** 2026-09-27T11:16:29Z как NOT_PLANNED, меток `status:*` нет. Основание в комментарии закрытия — решение владельца 2026-09-27: задача заводится, только если находка влияет на корректность ПО или безопасность продукта; эта — текст документа, а не контроль. Работы по ней нет и не будет.

**Состояние на 2026-10-08**: `test`. Задача снова открыта и закрыта 2026-10-07 как completed работой полосы
kacho#3054 (коммит `4157f4fbf68d`, `Expires` объявлен), влитой первой сборкой волны-6 [[KAC/issue-2969]]
([kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073), `8725b886e124`) в ветку эпика `1266`; в `main` не влито.
Переоткрыта 2026-10-06 решением диспетчера и взята в волну-6 тем же предметом: опубликованный на стенде
`security.txt` истекал в момент публикации (комментарий переоткрытия).

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

- [x] DoD-proof @`4157f4fbf68d` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2876#issuecomment-6035120321):
  `go test ./deploy/ -run TestSecurityTxt` — PASS 3 из 3; `security-txt-render-test.sh` — утверждений 9 из 9;
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## History

- 2026-09-28 (#846) — состояние приведено к трекеру: to-do → wontfix: задача закрыта как NOT_PLANNED по решению владельца 2026-09-27.
- 2026-10-08 (волна-6, [[KAC/issue-2969]]) — wontfix → test: закрыта как completed работой kacho#3054, влитой в `1266`.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — зонт, в чьих шаблонах лежит ConfigMap; утверждений
  о `security.txt` записка не несёт.

#kac #fix #kacho-deploy
