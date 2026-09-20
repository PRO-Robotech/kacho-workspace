---
title: "kaname#184: копия каталога прав отстанет от края на строку Resolve — запись ведомости ожидания"
aliases:
  - issue-184-kaname
ticket_id: 184
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - iam
prs:
  - https://github.com/PRO-Robotech/kaname/pull/193
issue_url: https://github.com/PRO-Robotech/kaname/issues/184
opened: 2026-09-16
tags:
  - kac
  - kacho-iam
  - iam
  - go
verified_against: "kaname release/iam-lines@6acf8f19: ведомость `internal/check/catalog_copy_parity.go` и копия каталога прочитаны (записей 341, из них ждущих края 3); kacho main@972bdc34: копия края 338 записей, `Resolve` нет; ветка kacho issue-1269-login-lane-edge@2dcf7f2e: пин службы af0ca8f3, копия края 339; задача и PR — `gh` 2026-09-17"
---

# kaname#184: строка `Resolve` — у службы уже, у края после подъёма пина

**Предмет.** Найдено по дороге Ф3 ([[issue-1269]]). Контракт
`InternalHumanSessionService.Resolve` (`project/kaname/proto/kaname/cloud/iam/v1/human_session_service.proto`,
`<exempt>`, внутренний слушатель) аннотирован, а копия каталога прав службы
(`internal/apps/kaname/seed/embedded/permission_catalog.json`) сверяется гейтом паритета с копией
**края на `main` платформы** — и та строку получит только после того, как платформа поднимет пин
службы и перегенерирует каталог. Порядок синхронизации копий между репозиториями — по построению,
не дефект; задача заведена, чтобы шаг не потерялся и гейт службы не покраснел без объяснения.

## Посылка задачи — сместилась, и это сказано в ленте

Тело обещало красное «после вливания kacho#2689». Перемер на голове #2689 того дня (`3983bc5e`):
пин службы там был **тот же**, что на `main` платформы (`40bd49a3`), копия края — 338 строк без
`Resolve`; глагол объявлен контрактом с `c0eb17c5` (kaname#179), то есть **позже** пина. Верная
формулировка: красное сверки наступит с тем PR платформы, который **поднимет пин** до ревизии не
старше `c0eb17c5` **и** перегенерирует каталог — каким бы номером он ни шёл.

На 2026-09-17 это и есть kacho#2689: его голова `2dcf7f2e` пинит `af0ca8f3` (`main` службы) и
несёт копию края в 339 записей с `Resolve`.

## Что сделано — PR kaname#193 (поверх #191, влит в линию `210b6a98`)

| предмет | где | чем доказано |
|---|---|---|
| строка `kaname.cloud.iam.v1.InternalHumanSessionService/Resolve` в копии службы | `internal/apps/kaname/seed/embedded/permission_catalog.json` | порождена генератором края (`gateway/scripts/gen-permission-catalog.sh` платформы) над контрактом службы, не вписана руками |
| запись ведомости, **ждущей края** | `internal/check/catalog_copy_parity.go`, `CatalogPendingEntries()` — `OwnFQN`, причина, **предикат снятия**, `Refs: kaname#184 · PRO-Robotech/kacho#2689` | самоистечение проверено на порождённом артефакте будущего края: при копии края с `Resolve` гейт даёт находку ведомости «предикат снятия наступил» |
| гейт «копия обязана покрывать собственный контракт» | `internal/check/catalog_covers_contract.go`, проба `catalog_covers_own_contract_test.go` (`TestOwnCatalogCopyCoversOwnContract`) | был красен ровно на этой строке: RPC в контракте 107, своих строк в копии 106 |

Записей, ждущих края, в ведомости на линии **три** — `MembershipService/Create`
([[issue-181-kaname]]), `InternalHumanSessionService/Resolve` (эта задача),
`UserService/ResendInvite` (kaname#186); копия службы 341 = 338 у края + 3.

## Предикат снятия записи — он же закрытие задачи

```sh
make check-permission-catalog EDGE_TREE=<чекаут PRO-Robotech/kacho на main>
# → находка ведомости: «край уже несёт глагол …/Resolve — предикат снятия наступил»
#   при «побайтово до ведомости true»
```

Тогда запись снимается **тем же изменением**, а копия синхронизируется
(`make sync-permission-catalog`). Закрывает задачу снятие записи, а не ветка #193: она лишь
переносит ожидание из «покраснеет без объяснения» в «истечёт само, с именем предмета».

## Затронутые сущности vault

- [[rpc/iam-permission-catalog-service]] — каталог прав: две копии, направление синхронизации
  «край → служба» по стволу платформы.
- [[issue-1269]] — вторая половина пары (край), чьё вливание и есть производитель снятия.
- [[issue-181-kaname]] — та же форма ведомости заведена там первой (`MembershipService/Create`).

#kac #kacho-iam #iam #go
