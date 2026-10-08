---
title: "kacho#2924: notify NTF-5 — извещения оператора"
aliases:
  - issue-2924
  - NTF-5
ticket_id: 2924
category: kac
status: in-progress
verified_against: "`gh` 2026-10-08 (после вливания #3099): kacho PR #3099 MERGED в `2914-notify` 2026-10-08T10:36Z merge-коммитом 515e017c873a (родители cd20a05cfa72 и голова волны fc51651d5c83); голова `2914-notify` = 515e017c873a; ветки `2924-*` на origin сняты (`git ls-remote` пусто); пины на голове прочитаны в `go.mod` — corelib 18d105d0f50a, kaname 33010d434767; размер дельты — `gh pr view` (31 коммит, 132 файла, +16517 / −263); `notice.proto`, `notice_service.proto`, `internal_notice_service.proto`, `servesurface_ledger.go`, README службы, `gateway/internal/restmux/mux.go` и `gateway/internal/allowlist/list.go` прочитаны через `gh api contents` на 515e017c873a; приёмка NTF-5 есть на `origin/issue-880` воркспейса и нет на `origin/main` (`git cat-file -e`); задача #2924 и эпик #2914 OPEN; прогоны мной не перезапускались. `gh` 2026-10-07: kacho PR #3070 MERGED в `2914-notify` 2026-10-07T12:38Z merge-коммитом 4d5295f1ae96 (голова волны `2924-wave-f1` e3f4cb0949f9, база 829e1a26cb18), голова `2914-notify` = 4d5295f1ae96; ветки `2924-wave-f1` и `2924-n1-notice-schema` на origin сняты (`git ls-remote` пусто); corelib PR #98 MERGED в `77-notify` (d3c964ae6fa7); задача #2924 и эпик #2914 OPEN. Состав миграции снят `git show 4d5295f1ae96:services/notify/internal/migrations/20261006232858_operator_notices.sql`; прогоны мной не перезапускались"
type: feature
repos:
  - kacho
  - corelib
areas:
  - services/notify
  - internal/repohygiene
  - gateway
  - deploy/helm/notify
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3070
  - https://github.com/PRO-Robotech/corelib/pull/98
  - https://github.com/PRO-Robotech/kacho/pull/3099
issue_url: https://github.com/PRO-Robotech/kacho/issues/2924
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2924: notify NTF-5 — извещения оператора

**Состояние на момент записи**: `in-progress`. Две волны линии F влиты в ветку эпика
`2914-notify` (координата, не живая ссылка): F1 — схема стадии S1 (#3070), S1 — контракт,
развёртывание notify-api и край (#3099). В `main` не влито ничего; задача открыта — PR
несут `Refs`, не `Closes`. Статус `done` записке не положен до посадки эпика в `main`.

**Эпик:** [[KAC/issue-2914]]. **Блокеры из тела:** #2915,
PRO-Robotech/kacho-workspace#880. **Роль исполнителя:** `go-implementer`.

## Что и зачем

Ресурса «извещение оператора» в контракте нет, и оператору нечем известить аккаунты о
работах, авариях и выводе из эксплуатации. Предмет — ресурс «извещение» с жизненным
циклом «запланировано → идёт → завершено», класс OB (обязательный, не отключается).
Создаёт и ведёт извещение только оператор, арендатор читает извещения своих аккаунтов.
Доставка — лента консоли и почта через notify. Полный объём — в теле задачи.

## Документы

- Приёмка: `docs/specs/sub-phase-NTF-5-operator-notices-acceptance.md` (воркспейс). На
  `origin/main` воркспейса 2026-10-08 её по-прежнему нет; она лежит в ветке `issue-880`
  (координата, не живая ссылка). Шапка миграции волны ссылается на редакцию 20. Предикат снятия
  оговорки: путь резолвится на `origin/main` воркспейса.

## Волна F1 (стадия S1, схема)

| репозиторий | ветка эпика | PR | merge-коммит | состав |
|---|---|---|---|---|
| corelib | `77-notify` | [#98](https://github.com/PRO-Robotech/corelib/pull/98) | `d3c964ae6fa7` | F-C5: obligation в `notify/spec`, лента V3, ядро взятия и исхода (в одной волне def2 с E-X3 задачи [[KAC/issue-2919]]) |
| kacho | `2914-notify` | [#3070](https://github.com/PRO-Robotech/kacho/pull/3070) | `4d5295f1ae96` | F-N1 и подъём lock-файлов сайтов документации (#3044) |

Состав kacho #3070 (влит 2026-10-07T12:38Z), из описания PR и `git diff --stat
829e1a26cb18 4d5295f1ae96` (21 файл, +1146 / −126):

- **F-N1** — миграция `20261006232858_operator_notices.sql` цепочки `kacho_notify`: семь
  таблиц стадии S1 (заявки создания, извещения, аудитория, затронутые ресурсы,
  напоминания, события этапа, счётчики исходов). Инварианты — на уровне базы, ограничения
  названы. Пробы схемы — `notices_schema_integration_test.go`; пакет миграций внесён в
  отбор шага `test-pg-outside-selection`, строка в `docs/acceptance-ledger.yaml`.
- **#3044** — подъём lock-файлов семи сайтов документации, перенесённый с ветки
  эпика-источника.

Чего в волне нет, по шапке миграции: строк адресатов, кандидатов, исходов областей и окна
OB (стадия S2, отдельная миграция), API извещений и края. Схема — в
[[packages/notify-service]].

## Волна S1 (#3099): контракт, notify-api, край

| репозиторий | ветка эпика | PR | merge-коммит | влит (UTC) |
|---|---|---|---|---|
| kacho | `2914-notify` | [#3099](https://github.com/PRO-Robotech/kacho/pull/3099) | `515e017c873a` | 2026-10-08T10:36Z |

Голова волны `fc51651d5c83`, ветка `2924-wave-f2` (координата, не живая ссылка; снята вместе
с `2924-p1-notice-contract`). 31 коммит, 132 файла, +16517 / −263. Состав — со слов
описания PR; контракт, ведомость служб и регистрация края прочитаны на `515e017c873a`.

- **Контракт** — ресурс «извещение» в `proto/kacho/cloud/notify/v1/`: `NoticeService`
  (чтение арендатором) и `InternalNoticeService` (ведение оператором, мутации возвращают
  `Operation`). Ресурс и методы — [[resources/notify-notice]].
- **notify-api** — новый корень процесса `cmd/notify-api`: приём, переходы, чтение, сужение,
  звено прав носителя; слой use-case `internal/apps/kacho/api/{notice,publicnotice}`,
  хранилище `internal/repo/noticerepo`; миграция операций `20261007120000_operations.sql`
  цепочки `kacho_notify`. Корень — в [[packages/notify-service]].
- **Анализатор списков** notify (`tools/auditlistfilter`) и шаг `listauthz` в конвейере.
- **Край** — `NoticeService` наружу, `InternalNoticeService` только на внутреннем mux; оба
  ходят на один внутренний слушатель notify-api. Каталог прав края регенерирован под kaname
  `33010d434767`.
- **Развёртывание** — объекты `api-*` в чарте `deploy/helm/notify`, ребро края к notify-api,
  ручки загрузчика в профилях.
- **Пины фундамента** — corelib `18d105d0f50a`, kaname `33010d434767`; оба по дереву равны
  головам веток эпиков фундамента (см. [[KAC/issue-2914]]).
- **Пробы** — пять мутаций `InternalNoticeService`, красные пробы приёма, переходов, чтения и
  звена прав до кода, проба рядов сетки и лента пробы на схеме V3.

Исход посадки — со слов комментария в задаче: accept `landing-reviewer` на `fc51651d5c83`,
`landing-precheck` и `merge-readiness` код 0 (обязательных 42 из 42 зелёных).

## DoD (из тела задачи)

Предикат задачи — сценарии приёмки NTF-5 зелёные исполненными пробами. Артефакт — PR в
ветку эпика.

- [x] стадия S1, схема извещений, влита в `2914-notify` (#3070), ядро ленты F-C5 — в
  `77-notify` (corelib #98);
- [x] ресурс в контракте `proto/kacho/cloud/notify/v1/`, развёртывание notify-api и край в
  `gateway/` — волна S1 (#3099, `515e017c873a`, ветка эпика);
- [ ] стадия S2: адресаты, исходы областей, окно OB;
- [ ] доставка извещений через notify (лента консоли и почта);
- [ ] сценарии приёмки NTF-5 зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-2914]] — эпик «Сервис уведомлений».
- [[KAC/issue-2915]] — NTF-1, ядро шлюза; блокер из тела.
- https://github.com/PRO-Robotech/kacho/issues/3044 — подъём lock-файлов сайтов
  документации (CLOSED), ушёл в эту же волну.
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib эпика. Trail — [[KAC/issue-77-corelib]].
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела.

## History

- 2026-10-07 — trail заведён после вливания волны F1: kacho #3070 (`4d5295f1ae96`) в
  `2914-notify`, corelib #98 (F-C5, `d3c964ae6fa7`) в `77-notify`. Статус `in-progress`.
- 2026-10-08 — внесена волна S1 (#3099, `515e017c873a`): контракт извещений, notify-api,
  край, пины corelib `18d105d0f50a` и kaname `33010d434767`; ветки волны сняты. Заведена
  [[resources/notify-notice]]. Статус `in-progress`.

## Затронутые сущности vault

- [[packages/notify-service]] — раздел «Схема извещений оператора (S1)» и вторая строка
  таблицы цепочек (#3070); корень `cmd/notify-api`, слой use-case, истёкшие решения о
  поверхности (#3099).
- [[resources/notify-notice]] — ресурс «извещение» и обе службы (#3099).

#kac #feature
