---
title: "kaname#363: у службы одна посадка личности — ключ посадки и ветви external сняты"
aliases:
  - issue-363-kaname
ticket_id: 363
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - internal/apps/kaname/config
  - cmd/kaname
  - internal/handler
  - deploy
  - internal/migrations
  - docs/content
  - INSTALL.md
prs:
  - https://github.com/PRO-Robotech/kaname/pull/487
  - https://github.com/PRO-Robotech/kaname/pull/492
issue_url: https://github.com/PRO-Robotech/kaname/issues/363
opened: 2026-09-22
closed: ""
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - deploy
  - config
  - migrations
verified_against: "kaname 357@73dc6598c (дерево 5bdd770f6, 2026-09-30): предикаты DoD, заданные командой git grep / ls-tree, прогнаны по этой ревизии; состав коммитов и путей — git log/show по диапазону 734f69fb4..4ae67c59e; пробы и конвейер не перезапускались"
---

# kaname#363: у службы одна посадка личности — ключ посадки и ветви external сняты

> [!note] Состояние — `test`, задача открыта
> Код влит в ветку волны и с ней — в ветку эпика `357` коммитом слияния
> `73dc6598c1a38321cdee20731cb5547cd4a158c3` ([kaname#492](https://github.com/PRO-Robotech/kaname/pull/492)). Каскадом волны задача
> не закрыта: это держатель открытого долга — две позиции приёмок (IC-SECRET-11 и Ф3-46), позиции уходят из приёмки её редакцией (тело kaname#492). При вливании волны переведена под эпик kaname#357; в трекере
> `status:test`.

## Что и зачем

Посадку выбирал ключ `authn.identityProvider` с двумя значениями, и боевой профиль объявлял
внешнюю. После снятия поставщика личности значение `external` не описывает ничего, что можно
поднять. Сняты ключ, ветви по нему в корне, требования старта внешней полосы, накладки профилей и
обработчики хуков поставщика; каталог `internal/handler/iamhooks/` снят целиком. Чарт отказывает
профилю, который ещё несёт снятый ключ, и называет его.

Тем же снятием ушёл код kaname#327, kaname#330 и kaname#331 (коммит `69e61c563`) и предметы
пробы kaname#368 и гейта kaname#338. Возврат рецензии сборки 2: миграция
`20260930090111_provider_compensation_queue_stops_notifying.sql` снимает производителя канала
очереди компенсаций, чей слушатель снят (`baf16c76e`, доводка пробы отката `b1427b775`).

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса → сборка 2 | ветка `363` → ветка `486` | 833cd429a | d292ad9c9 | — |
| сборка 2 → волна | ветка `486` → ветка `367` | b1427b775 | 290239435 | [kaname#487](https://github.com/PRO-Robotech/kaname/pull/487) |
| волна → эпик | ветка `367` → ветка `357` | 4ae67c59e | 73dc6598c | [kaname#492](https://github.com/PRO-Robotech/kaname/pull/492) |

## Затронутые каталоги

Коммитов полосы 3 (`45a8288c8` красные пробы, `69e61c563` снятие, `833cd429a` документы), путей 326:
`internal/apps/` 74, `cmd/kaname/` 62, `internal/handler/` 44, `deploy/` 35, `internal/check/` 18,
`internal/clients/` 17, `docs/content/` 14, `internal/repo/` 11, `internal/service/` 10,
`docs/engineering/` 8. Из 128 путей, снятых волной, 98 сняты коммитом `69e61c563`.

## DoD

Отметка `[x]` — измерено этой записью на `73dc6598c` (дерево `5bdd770f6`, то же у головы волны `4ae67c59e`) либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено либо не выполнено, причина в строке.

- [x] `git grep -n -E 'IdentityProviderExternal|identityposture\.External' 73dc6598c -- ':!docs/specs/reviews' | wc -l` → 0.
- [ ] `git grep -n 'identityProvider' 73dc6598c -- deploy | wc -l` → 18, а не 0. Остаток — отказ шаблона `deploy/templates/_helpers.tpl`, называющий снятый ключ, его пробы `deploy/*_test.go` и одна строка комментария `deploy/values.yaml` о том, что ключа больше нет: читателей ключа среди них нет, но буквальный предикат их не исключает.
- [ ] старт не читает ключа, `helm template` каждого профиля рендерит одну полосу — не перепроверено; задание `чарт поднимается в боевой посадке (kind)` — success на `4ae67c59e`.
- [ ] позиции приёмок IC-SECRET-11 и Ф3-46 — открыты, задача держит их долг.

## Затронутые сущности vault

Пробел, названный как пробел: возвраты полос волны-4 поля «затронуто в vault» не несут (журналы исполнителей, строки `result`; где поле есть — стоит «—»). Узкие записки `resources/` · `rpc/` · `packages/` · `edges/` по этой задаче не заведены и не правлены: без данных полосы предмет не выдумывается. Почему узкие записки о снятом не правятся и сейчас — раздел «Узкие записки» в [[KAC/issue-367-kaname]].

## Связанные задачи

- [[KAC/issue-367-kaname]] — волна-4
- [[KAC/issue-380-kaname]]
- [[KAC/issue-424-kaname]]
- [[KAC/issue-368-kaname]]
- [[KAC/issue-338-kaname]]
- [[KAC/issue-486-kaname]] — сборка 2

#kac #kacho-iam #iam #go #deploy #config #migrations
