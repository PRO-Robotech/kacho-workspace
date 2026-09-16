---
title: "kaname#181: у членства появился пишущий глагол — MembershipService.Create"
aliases:
  - issue-181-kaname
ticket_id: 181
category: kac
status: test
type: feat
repos:
  - kaname
prs: []
issue_url: https://github.com/PRO-Robotech/kaname/issues/181
opened: 2026-09-16
tags:
  - kac
  - kacho-iam
  - iam
  - go
verified_against: "ветка issue-181-membership-create от release/iam-lines@dfe2fefa (kaname): предикаты 1, 2, 3, 4, 6, 8 тела задачи прогнаны на итоговом дереве; 5 и 7 — частично, край не перегенерирован"
---

# kaname#181: приглашение переезжает на ресурс членства — контрактом, не потоком

**Предмет.** Стадия S3.2 приёмки IAM-ID-1 (`docs/specs/sub-phase-IAM-ID-1-identity-account-decoupling-acceptance.md`,
§4): глагол приглашения получает второй адрес на ресурсе членства —
`MembershipService.Create`, `POST /iam/v1/memberships`, `response: Membership`. Без него
стадия S4 ([[issue-1351]], снятие `InviteUserRequest`) неисполнима by construction.

## Решения, принятые здесь (приёмки их не пересматривали)

| ось | решение | почему |
|---|---|---|
| поток | **один на оба глагола**: `user.InviteUserUseCase` — общие `admit` (синхронно) и `run` (транзакция); различаются только сообщения операции | второй поток — два места об одном предмете; до S4 живут оба глагола |
| порт | `membership.Creator` + `membership.CreateInput` объявлены у ресурса членства, реализует их поток приглашения | направление «поставщик реализует порт потребителя»; после S4 поток переезжает к порту |
| ответ | `Membership` читается **той же транзакцией**, что его завела (`repouser.ReaderIface.Membership(user, account)`) | узкий корень чтения ходит на пул чтения — на реплике строки могло бы ещё не быть |
| проекция | одна — реестр `internal/dto/toproto` (`membership.go`); обработчик чтений, ответ создания и резолвер зовут её | второй перевод разошёлся бы молча |
| метаданные | `CreateMembershipMetadata{account_id, user_id}`; `user_id` известной почты — её строка (приёмка спрашивает почту до чеканки) | фантом в метаданных и слепое разрешение сироты; арбитр остаётся транзакция |
| сирота | резолвер разрешает по паре: есть — `done` с членством, нет — `interrupted` (повтор идемпотентен) | гейт `TestEveryOperationMetadataIsResolvedOrPinned` нашёл класс до посадки |
| каталог прав | своя копия несёт запись, порождённую генератором края над контрактом; окно до подъёма пина объявлено **вторым видом записи ведомости сверки** (`check.CatalogPendingEntries`) с внешним предикатом снятия | промежуточного состояния, где обе копии совпали бы, нет by construction; самоистечение доказано на настоящем артефакте будущего края |

## Посылки задачи — перемерены

- **Подтверждено:** производителей строки членства в прод-коде два (`Upsert`, `InsertPending`, оба в `user_repo.go`); `rpc` в `membership_service.proto` — 2 до, 3 после; `buf breaking` против `origin/main` и `origin/release/iam-lines` — код 0.
- **Опровергнуто (п. 7 предиката):** «пустой `account_id` → 400 с именем поля» через дверь **недостижим**. `account_id` — объект, про который гейт спрашивает модель прав; пустой объект — вызов без области, и обе двери (край и собственная дверь службы, `corelib/authz/catalogderive.buildExtractor`) отвергают его отказом прав **до сервиса**: 403/`PERMISSION_DENIED`. Текст `Illegal argument account_id: required` производит `admit` и утверждает проба use-case; сквозной кейс утверждает то, что производит дверь.

## Что осталось и чем закрывается

- **п. 5 (край)** — kacho не перегенерирован: `gateway/internal/middleware/embed/permission_catalog.json` (+1 запись) и `internal/middleware/rest_route_table_gen.go` (+`POST /iam/v1/memberships`). Предикат: `git grep -c 'MembershipService/Create' -- gateway/internal/middleware/embed/permission_catalog.json` → 1 на стволе платформы после подъёма пина; тогда запись ведомости в `internal/check/catalog_copy_parity.go` снимается и зовётся `make sync-permission-catalog`.
- **п. 7 (сквозные)** — кейсы `IAM-ID1-MBR-CREATE-*` написаны и порождены, локального стенда нет: вердикт даст прогон конвейера после подъёма пина краем (до него край отвечает «catalog: no entry for method»).
- **п. 6** — IAM-ID-1-31/-57/-65 в дереве проб не названы ни одним файлом (`git grep -ln 'IAM-ID-1-31\|IAM-ID-1-57\|IAM-ID-1-65' -- '*.go' '*.py'` → пусто до и после); «зелены без синтетики» держится посевом второго членства (`TestUserInvite_ExistingActiveEmail_SecondAccount`, §16.2 приёмки) и новыми пробами исхода, а не пробами с этими номерами.

## Затронутые сущности vault

- [[rpc/iam-membership-service]] — заведена этой задачей.
- [[rpc/iam-user-service]] — `Invite` получил преемника; сам глагол не менялся.
- [[resources/iam-user]] — путь приглашения тот же.
- [[issue-1351]] — S4 разблокирована по этой оси.

#kac #kacho-iam #iam #go
