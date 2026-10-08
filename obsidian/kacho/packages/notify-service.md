---
title: "services/notify — шлюз уведомлений: шлюз, проба-источник и точка наката"
aliases:
  - notify
  - kacho-notify
  - notify-probe
category: packages
status: test
repo: kacho
layer: service
path: services/notify
verified_against: "`project/kacho` @`2c283f99f4bc` (merge-коммит PR #3019 в ветку эпика `2914-notify` — координата, не живая ссылка; 2026-10-04). Прочитаны README, doc.go, servesurface_ledger.go, cmd/notify/serve.go, cmd/migrator/chains.yaml, proto internal_notify_probe_service.proto; состав каталога (60 путей) и чарта снят `git ls-tree`. На `origin/main` того же дня каталога `services/notify` нет"
tags:
  - packages
  - kacho
  - service
  - internal
  - go
---

# services/notify — шлюз уведомлений

> [!warning] Предмет живёт в ветке эпика, а не в стволе
> Каталог есть в `2914-notify` (координата, не живая ссылка) с merge-коммита `2c283f99f4bc`.
> На `main` его нет, поэтому статус записки — `test`. Предикат снятия оговорки: путь
> `services/notify` резолвится на `origin/main`.

Это единственный процесс платформы, который держит креды почты. Письма он не принимает
вызовом: забирает их сам из лент источников, у kaname спрашивает право на каждое письмо и
отправляет. Замысел и приёмка — в [[KAC/issue-2915]].

## Три корня процессов, один образ

Образ `kacho-notify` несёт три бинаря:

| корень | роль | поверхность | база |
|---|---|---|---|
| `cmd/notify` | шлюз (`kacho-notify serve`) | только диагностический HTTP: `/healthz`, `/readyz`, `/metrics`; gRPC-слушателя нет | `kacho_notify` |
| `cmd/notify-probe` | стендовая проба-источник (`kacho-notify-probe serve`) | внутренний gRPC-слушатель | `kacho_notifyprobe` |
| `cmd/migrator` | точка наката (`kacho-migrator up`) | — | выбирает цепочку по имени базы в DSN |

Набор служб каждого корня записан в ведомости `servesurface_ledger.go`. У `cmd/notify` этот
набор пуст.

## Проба-источник

На внутреннем слушателе проба служит три сервиса:

- `kacho.cloud.notify.v1.InternalNotifyProbeService/Send` ставит письмо шаблона
  `probe-hello` и отвечает `notification_id` закоммиченной строки. Право —
  `notify.probeNotifications.send` в области `cluster`.
- лента `corelib.notify.InternalNotificationFeedService`;
- подписка `corelib.subscription.InternalSubscriptionService`.

Ленту и подписку проба поднимает только при `KACHO_NOTIFYPROBE_NOTIFICATIONS_ENABLED=true`.
Все три сервиса — `Internal*`: внешний край их не маршрутизирует. Шаблон лежит в
`notifications/probe-hello/`; генератор `notifygen` из corelib порождает по нему
`notifications_probe-hello.gen.go`.

## Две базы — две цепочки

У каталога две базы (database per service). Цепочка пробы — в
`internal/probemigrations`, а не в `internal/migrations`. Таблица «база → каталог цепочки»
объявлена у точки наката файлом `cmd/migrator/chains.yaml`. На `2c283f99f4bc` в таблице
одна строка, `kacho_notifyprobe`. Как гейты дерева находят цепочку — в
[[packages/kacho-migrationchains]].

## Записанные решения «поверхности нет»

В README службы записаны три решения о поверхности, которой нет. Каждое держит гейт дерева,
и каждое снимается появлением предмета:

- шлюз не служит подписку, а сам открывает её к источникам;
- публичного `List*` нет, поэтому нет и анализатора отбора списков;
- слоя use-case `internal/apps/` нет.

## Конфигурация и развёртывание

- Ручки — `KACHO_NOTIFY_*` без умолчаний, пакет `internal/config`. Если обязательная ручка
  не задана или её значение вне границы, процесс не стартует и называет ручку.
- Чарт `deploy/helm/notify` (`name: notify`, `0.1.0`): deployment, pdb, certificate,
  configmap, serviceaccount, секрет ключа адресата.

## Чего на этой ревизии нет

Подписчика лент и отправки почты на `2c283f99f4bc` нет: `cmd/notify/serve.go` поднимает
только пул базы и диагностическую поверхность. Поэтому нет и ребра «шлюз → источник» в
`edges/`. Записка о ребре заводится той волной, которая посадит подписчика.

## History

- 2026-10-04 — #2915: записка заведена по merge-коммиту `2c283f99f4bc` (PR #3019 в
  `2914-notify`). Волна принесла каркас N1, чарт D1/D1s и пробу D4.

#packages #kacho #service #internal #go
