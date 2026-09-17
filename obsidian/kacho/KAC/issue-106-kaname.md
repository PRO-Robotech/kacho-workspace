---
title: "kaname#106: MRW-1 — группу пишущих кортежи объявляет манифест службы, а не SQL-свод"
aliases:
  - issue-106-kaname
  - MRW-1
ticket_id: 106
category: kac
status: test
type: feature
repos:
  - kaname
  - kacho
areas:
  - iam
  - deploy
prs:
  - https://github.com/PRO-Robotech/kaname/pull/150
  - https://github.com/PRO-Robotech/kaname/pull/169
  - https://github.com/PRO-Robotech/kacho/pull/2693
  - https://github.com/PRO-Robotech/kaname/pull/170
issue_url: https://github.com/PRO-Robotech/kaname/issues/106
opened: 2026-09-15
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - migrations
  - config
verified_against: "kaname main@af0ca8f3: `manifest.yaml` несёт `seed:` (S1 влита с линией через kaname#189); release/iam-lines@6acf8f19: миграция `20260916150000_quota_readers_group_leaves_the_baseline.sql` (S2б) — в линии, в main её нет; kacho main@972bdc34: `git grep -c module-quota-readers -- 'services/*/manifest.yaml'` → 0 в пяти, `module-relation-writers` → по 1 (S2а); PR и вердикт — `gh` 2026-09-17"
---

# kaname#106: право писать кортежи владения — поверхность службы, и объявляет его её манифест

**Предмет.** Группы, в которые вступают модули платформы (`module-relation-writers`,
`module-quota-readers`), и выдача первой из них (`fga_writer` на кластере) жили в SQL-своде
службы (`0001_initial.sql`; выдачу завела миграция kacho#914 до того, как манифест научился
сеять). Валидатор связности требует, чтобы группу, заведённую манифестом, тот же манифест и
одаривал (`ErrGroupNeverGranted`), а у манифеста службы посева не было — держателя не было
именно там. **Решение владельца 2026-09-16:** аудиторию возможности `RegisterResource`/
`UnregisterResource` объявляет владелец возможности — манифест службы, — модули лишь
вступают своим `seed.joins`. Сопутствующее того же предмета: `module-quota-readers` **мертва**
(её выдачу отозвала `20260914091500_limit_reader_grant_is_revoked.sql`, kaname#59) — снимается
вместе со вступлениями.

## Приёмка — одобрена внешним событием

`docs/engineering/acceptance/service-manifest-seeds-its-own-groups.md`, PR kaname#150, третий
круг (5 → 3 → 0), APPROVED 2026-09-16, ревизия `b756b532`, отпечаток `08550d59…`. Три
блокирующих круга 2 повторены тем же опытом; три находки оппонента подтверждены прогоном против
Postgres (пакет `internal/migrations`: 107 PASS · 1 SKIP · 0 FAIL). Стенд не поднимался.

## Реализация — три стадии, три PR, два репозитория

| стадия | что | PR | где сегодня |
|---|---|---|---|
| **S1** | манифест службы объявляет `module-relation-writers` и её выдачу `fga_writer` @ `iam.cluster/cluster_root` (`manifest.yaml`, раздел `seed:`); встроен в образ носителем `internal/servicemanifest/` (`servicemanifest.go`, `manifest.embedded.yaml`, пара «цель порождает · проба держит»); доезжает до применителя посева отдельным доводом и применяется **первым**; форма субъекта группы — у канона; идемпотентность выдачи — естественным ключом (до правки — `23505` на базе миграций дерева); сверка паритета `internal/moduleseedparity/parity.go` относит группу и выдачу к модулю по объявлению, шапка приведена к факту | kaname#169 (`700d30d0` → линия `9a1e24b1`) | **в `main` службы** (`af0ca8f3`, с линией через kaname#189) |
| **S2а** | вступления в `module-quota-readers` сняты из пяти манифестов платформы (`services/{compute,nlb,registry,storage,vpc}/manifest.yaml`) | kacho#2693 (`741d340e`), задача kacho#2687 закрыта | **в `main` платформы** |
| **S2б** | миграция `internal/migrations/20260916150000_quota_readers_group_leaves_the_baseline.sql` снимает `module-quota-readers` с членствами, кортежи выводятся журналом, след остаётся, откат возвращает строку свода; проба `quota_readers_group_retired_integration_test.go` | kaname#170 (`4167cc03` → линия `5d9b3791`; допуск был внешний — после S2а) | **в линии `release/iam-lines`**, в `main` службы ещё нет |

Применённые миграции не правились (ban #5): живые строки свода усыновляет и снимает новая
миграция; применитель кладёт объявленное поверх живой строки, не меняя идентификатора, поэтому
кортежи уже живых установок не рвутся.

## Предикат снятия — по пунктам тела

| # | пункт | исход |
|---|---|---|
| 1 | манифест службы несёт `seed` с группой и выдачей; применитель не рвёт кортежи живых установок | S1, опыт на установке со строкой и на чистой |
| 2 | свод перестаёт быть источником истины; применённая миграция не правится | S1 + S2б |
| 3 | `module-quota-readers` и вступления сняты в пяти манифестах платформы и в базе службы новой миграцией, с выводом кортежей через очередь | S2а + S2б |
| 4 | сверка паритета судит группы наравне с учётками, шапка приведена к факту | S1 |
| 5 | приёмка — до кода | kaname#150 APPROVED до kaname#169 |

**Что держит статус `test`, а не `done`:** S2б лежит в линии, а не в `main` службы; закрытие —
вливанием линии в ствол (`git -C kaname ls-tree -r --name-only origin/main internal/migrations/ | grep -c quota_readers_group` → 1).
Локально по PR: `go test -short ./...` 118 ok, `make lint` 0, интеграция `migrations` /
`moduleseedparity` / `repo/kaname/pg` без `-short` ok; `-race` не гонялся (нет cgo), стенд не
поднимался.

## Затронутые сущности vault

- [[resources/iam-group]] — две системные группы модулей: одна теперь объявлена манифестом
  службы, вторая снята.
- [[packages/iam-seed]] — применитель посева получил второй довод (манифест службы) и порядок
  «служба первой».
- [[rpc/iam-internal-iam-service]] — `RegisterResource`/`UnregisterResource`: аудитория
  возможности объявлена у её владельца.
- [[edges/vpc-to-iam-fgaproxy]], [[edges/compute-to-iam-fgaproxy]], [[edges/storage-to-iam-fgaproxy]],
  [[edges/nlb-to-iam-fga-register]], [[edges/registry-to-iam-fga-register]] — пять
  вступающих модулей; вступление в снятую группу чтения пределов у них больше не объявляется.

#kac #kacho-iam #iam #go #migrations #config
