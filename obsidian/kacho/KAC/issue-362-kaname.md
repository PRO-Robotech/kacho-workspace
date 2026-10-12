---
title: "kaname#362: поле, вид LEGACY и столбец зеркала поставщика сняты одним ломающим выпуском"
aliases:
  - issue-362-kaname
ticket_id: 362
category: kac
status: done
type: refactor
repos:
  - kaname
areas:
  - proto
  - pkg/api
  - internal/migrations
  - internal/domain
  - internal/repo
  - internal/apps
  - internal/check
  - docs/engineering
prs:
  - https://github.com/PRO-Robotech/kaname/pull/485
  - https://github.com/PRO-Robotech/kaname/pull/492
issue_url: https://github.com/PRO-Robotech/kaname/issues/362
opened: 2026-09-22
closed: "2026-09-30"
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - proto
  - migrations
verified_against: "kaname 357@73dc6598c (дерево 5bdd770f6, 2026-09-30): предикаты DoD, заданные командой git grep / ls-tree, прогнаны по этой ревизии; состав коммитов и путей — git log/show по диапазону 734f69fb4..4ae67c59e; пробы и конвейер не перезапускались"
---

# kaname#362: поле, вид LEGACY и столбец зеркала поставщика сняты одним ломающим выпуском

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-09-30 каскадом волны-4 [[KAC/issue-367-kaname]]: волна влита в ветку
> эпика `357` коммитом слияния `73dc6598c1a38321cdee20731cb5547cd4a158c3`
> ([kaname#492](https://github.com/PRO-Robotech/kaname/pull/492)). В `main` службы код не влит — запрос эпика
> [kaname#359](https://github.com/PRO-Robotech/kaname/pull/359) открыт черновиком (замер 2026-09-30), поэтому состояние
> записки `test`. Комментарий закрытия говорит прямо: предикат задачи при закрытии не
> перепроверялся — основание закрытия вливание кода волны.

**Состояние на 2026-10-03**: `done`, работа в `main`. Задача закрыта на трекере 2026-09-30 (`completed`); эпик kaname#357 влит в `main` запросом kaname#359 2026-10-02 коммитом слияния `8cbc0fdc82c` — предок `origin/main` (`git merge-base --is-ancestor`, 2026-10-03); зонтичный эпик kacho#2564 закрыт 2026-10-03 — [[KAC/issue-2564|#2564]].

## Что и зачем

Имя прежнего издателя стояло полем идентификатора клиента у поставщика в двух сообщениях клиентов
OAuth, видом `CREDENTIAL_KIND_LEGACY` в словаре видов удостоверения и столбцом обеих таблиц
клиентов. Порядок снятия был решён страницей
`docs/engineering/architecture/provider-mirror-column-retirement.md`, но не исполнен.

Исполнено одним ломающим выпуском, три предмета вместе: контракт (`reserved` номера и имени поля и
вида, запись в `proto/declared-breaks.yaml`), схема (новая миграция
`20260928231124_provider_mirror_leaves_the_credential_tables.sql` — отказывает, если строка зеркала
есть, затем снимает ветвь `LEGACY` из ограничений формы, индексы и столбец), код (обратное
заполнение вида снято, наш путь выдачи отказывает без порта владельца персонального токена).

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса → ветка `328` | ветка `362` → ветка `328` | aee0b2e48 | bd9252571 | — |
| полоса → сборка 1 | ветка `328` → ветка `483` | da251de19 | b7d5e28d5 | — |
| сборка 1 → волна | ветка `483` → ветка `367` | 86eb67120 | d5e515e04 | [kaname#485](https://github.com/PRO-Robotech/kaname/pull/485) |
| волна → эпик | ветка `367` → ветка `357` | 4ae67c59e | 73dc6598c | [kaname#492](https://github.com/PRO-Robotech/kaname/pull/492) |

## Затронутые каталоги

Коммитов 7 (`0b3cf8a76` красные пробы, `371523374` миграция, `dbec74f58` домен и хранилище,
`cb0ff5fa0` снятие измерителя и гейта окна, `a29d52f33` контракт, `15691dd24` документы,
`aee0b2e48` путь выдачи), путей 151: `internal/apps/` 48, `internal/repo/` 27,
`internal/handler/` 13, `cmd/kaname/` 10, `internal/service/` 8, `internal/migrations/` 7,
`pkg/api/` 6, `docs/engineering/` 6, `internal/domain/` 5, `proto/kaname/` 5.

## DoD

Отметка `[x]` — измерено этой записью на `73dc6598c` (дерево `5bdd770f6`, то же у головы волны `4ae67c59e`) либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено либо не выполнено, причина в строке.

- [x] `git grep -n 'CREDENTIAL_KIND_LEGACY' 73dc6598c -- proto` → одна строка, `reserved` (`credential_kind.proto:62`).
- [ ] буквальный предикат `git grep -n 'hydra_client_id' -- ':!internal/migrations/0001_initial.sql' ':!docs/specs/reviews' | wc -l` на `73dc6598c` даёт 45, а не 0. Остаток по файлам: сама снимающая миграция 23 и её проба 6, `reserved` в двух `.proto` и двух стабах 4, документы о снятии 11, проба ведомости 1 — то есть предикат не исключает снимающие предмет пути. Задача закрыта каскадом без перепроверки предиката.
- [ ] `buf breaking` по записи в `declared-breaks.yaml` — хуком не гонялся, задание конвейера этой записью не установлено.
- [x] проба миграции существует: `provider_mirror_leaves_the_credential_tables_integration_test.go`; задание `интеграция (Postgres в контейнерах)` — success на `4ae67c59e`.
- [x] страница о порядке снятия называет его исполненным — коммит `15691dd24`.

## Затронутые сущности vault

Пробел, названный как пробел: возвраты полос волны-4 поля «затронуто в vault» не несут (журналы исполнителей, строки `result`; где поле есть — стоит «—»). Узкие записки `resources/` · `rpc/` · `packages/` · `edges/` по этой задаче не заведены и не правлены: без данных полосы предмет не выдумывается. Почему узкие записки о снятом не правятся и сейчас — раздел «Узкие записки» в [[KAC/issue-367-kaname]].

## Связанные задачи

- [[KAC/issue-328-kaname]] — ветка-носитель
- [[KAC/issue-474-kaname]] — точность записи о снятии значения
- [[KAC/issue-364-kaname]]
- [[KAC/issue-367-kaname]] — волна-4

#kac #kacho-iam #iam #go #proto #migrations
