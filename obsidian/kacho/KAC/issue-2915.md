---
title: "kacho#2915: служба notify NTF-1 — ядро шлюза уведомлений"
aliases:
  - issue-2915
  - NTF-1
ticket_id: 2915
category: kac
status: in-progress
verified_against: "`gh` 2026-10-04: PR #3019 MERGED в `2914-notify` merge-коммитом 2c283f99f4bc (родители e415e59a225b и 71174f56e52e), задача #2915 OPEN, эпик #2914 OPEN; состав `services/notify`, `internal/migrationchains`, `internal/pgdsn`, `deploy/helm/notify` снят `git ls-tree` на 2c283f99f4bc; на `origin/main` (того же дня) ни одного из этих путей нет; прогоны мной не перезапускались"
type: feature
repos:
  - kacho
  - corelib
  - kaname
areas:
  - services/notify
  - proto/kacho/cloud/notify/v1
  - internal/migrationchains
  - internal/pgdsn
  - deploy/helm/notify
  - deploy/helm/umbrella
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2960
  - https://github.com/PRO-Robotech/kacho/pull/3019
issue_url: https://github.com/PRO-Robotech/kacho/issues/2915
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2915: служба notify NTF-1 — ядро шлюза уведомлений

**Состояние на момент записи**: `in-progress`. Две волны задачи влиты в ветку эпика
`2914-notify` (координата, не живая ссылка); в `main` не влито ничего. Задача открыта:
по каскаду «задача → волна → эпик → main» она закрывается, когда закрыт её последний
предмет, а предметы Ф1 и Ф2 ещё впереди. Статус `done` записке не положен до посадки
эпика в `main`.

**Эпик:** https://github.com/PRO-Robotech/kacho/issues/2914. **Роль исполнителя:**
`go-implementer`.

## Что и зачем

До задачи службы `notify` в дереве нет, а креды почты держат два процесса. Предмет —
`services/notify`, единственный процесс с кредами почты. Письма он забирает сам из лент
источников по закрытому перечню, у kaname спрашивает право на каждое письмо и отправляет.
Полный объём — в теле задачи и в приёмке.

Изменения объёма, записанные комментариями задачи (тело не правилось):

- 2026-09-30, решение Д2 — звено идентичности служб в corelib: проверенный сертификат
  службы даёт служебный принципал на закрытом перечне методов;
- 2026-10-01, заказ NTF-2 (Е8 (в)) — описание шаблона, порождаемое `notifygen`, выгружает
  лимит на адресата в сутки.

## Документы

- Приёмка: `docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md`
  (воркспейс), редакция 22. Вердикт ✅, отпечаток `c19490f97c3f…`, событие в задаче
  2026-10-03.
- Замысел: `docs/changes/issue-2915/design.md` (воркспейс), редакция 46. APPROVED,
  отпечаток `cf479ca85f67…`, событие в задаче 2026-10-03.
- В стволе воркспейса обоих файлов **нет**: они на ветке `docs-ntf-approved`
  (координата, не живая ссылка), запрос в ствол — PRO-Robotech/kacho-workspace#885 (OPEN,
  2026-10-04). Предикат снятия оговорки: пути резолвятся на `origin/main` воркспейса.

## Волны в ветку эпика

| волна | PR | merge-коммит | состав |
|---|---|---|---|
| P001 | [#2960](https://github.com/PRO-Robotech/kacho/pull/2960) | `e415e59a225b` | контракт ленты `corelib.notify`, пин kaname `484-notify` |
| ядро-1 | [#3019](https://github.com/PRO-Robotech/kacho/pull/3019) | `2c283f99f4bc` | N1, D1/D1s, D4, догон `main` после посадки Ory |

Сведения о волне ядра-1 (голова `71174f56e52e`, влита 2026-10-04T02:23Z), из PR и
комментария сдачи в задаче:

- **N1** — каркас `services/notify`. Входящего RPC у шлюза нет, есть только внутренняя
  диагностическая поверхность.
- **D1/D1s** — чарт `deploy/helm/notify`, копия осмотра и deploy-гейты.
- **D4** — проба-источник `cmd/notify-probe` с глаголом
  `kacho.cloud.notify.v1.InternalNotifyProbeService/Send`, точка наката
  `services/notify/cmd/migrator`, пакеты `internal/migrationchains` и `internal/pgdsn`.
- Вердикт посадки ✅ на `71174f56e52e`. `merge-readiness.sh`: код 0, обязательных
  контекстов 42, из них зелёных 42. Integration (notify) 38/38. Числа со слов
  исполнителя (комментарий сдачи); мной не перепрогонялись.
- Ветки волны и полос сняты. Запрос #3019 заменил прежний запрос той же волны #2991.

Зависимые линии, влитые под эту волну:

- corelib `77-notify`: [#83](https://github.com/PRO-Robotech/corelib/pull/83) (C13a,
  `fe0dccf1794e`) и [#87](https://github.com/PRO-Robotech/corelib/pull/87) (догон `main`,
  `f8aa88d1998d`; правка правила запроса Д99 — со слов задания);
- kaname `484-notify`: [#555](https://github.com/PRO-Robotech/kaname/pull/555) (перепин
  corelib, `57f1841789bd`) и [#588](https://github.com/PRO-Robotech/kaname/pull/588)
  (догон `main`, `06966a081c7a`);
- оснастка воркспейса: задача
  [kacho-workspace#913](https://github.com/PRO-Robotech/kacho-workspace/issues/913)
  закрыта, PR #914 влит (`050e09cdec87`).

## DoD (из тела задачи)

Предикат задачи — сценарии раздела «notify» приёмки зелёные **исполненными** пробами;
артефакт — PR в ветку эпика.

- [x] волна P001 — контракт ленты — влита в `2914-notify` (#2960);
- [x] волна ядра-1 (N1, D1/D1s, D4) влита в `2914-notify` (#3019);
- [ ] хвост Ф1: N7, D3, N11r, D2 (по комментарию сдачи 2026-10-04);
- [ ] Ф2;
- [ ] сценарии раздела «notify» приёмки зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- https://github.com/PRO-Robotech/kacho/issues/2914 — эпик «Сервис уведомлений».
- https://github.com/PRO-Robotech/kacho/issues/3017 — DKIM, SPF и DMARC домена
  отправителя профиля a8f60d (P3, решение за владельцем).
- https://github.com/PRO-Robotech/kacho/issues/3018 — агрегат «После Основы»: то, что
  отложено решением Д96.
- https://github.com/PRO-Robotech/kaname/issues/484 — потребитель выгрузки лимита шаблона.
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела задачи.

## History

- 2026-10-04 — trail заведён после вливания волны ядра-1 (#3019, `2c283f99f4bc`) в
  `2914-notify`. Волна P001 (#2960, `e415e59a225b`, 2026-10-01) внесена задним числом.
  Статус `in-progress`.

## Затронутые сущности vault

- [[packages/notify-service]] — служба целиком: шлюз, проба-источник, точка наката, чарт.
- [[packages/kacho-migrationchains]] — перечень цепочек миграций дерева.
- [[packages/kacho-pgdsn]] — подмена базы в строке соединения проб.
- Ребра notify → источник в vault нет: на `2c283f99f4bc` шлюз не открывает ни одного
  исходящего gRPC-соединения (`cmd/notify/serve.go` поднимает пул базы и диагностическую
  поверхность). Запись ребра заводится вместе с подписчиком.

#kac #feature
