---
title: "kaname#367: волна-4 identity-own — из службы доступа снято всё, что держало прежнего издателя"
aliases:
  - issue-367-kaname
  - волна-4 kaname identity-own
ticket_id: 367
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - cmd/kaname
  - internal
  - proto
  - pkg/api
  - tools/declaredbreak
  - deploy
  - docs
  - tests/newman
  - .github
prs:
  - https://github.com/PRO-Robotech/kaname/pull/485
  - https://github.com/PRO-Robotech/kaname/pull/487
  - https://github.com/PRO-Robotech/kaname/pull/489
  - https://github.com/PRO-Robotech/kaname/pull/491
  - https://github.com/PRO-Robotech/kaname/pull/492
issue_url: https://github.com/PRO-Robotech/kaname/issues/367
opened: 2026-09-22
closed: "2026-09-30"
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - proto
  - migrations
verified_against: "kaname 357@73dc6598c (дерево 5bdd770f6) и main@cbbac984b, 2026-09-30: состав волны — git rev-list / diff --no-renames по 734f69fb4..4ae67c59e; закрытость — gh issue list и дерево подзадач (GraphQL subIssues) #367, #333, #357; конвейер — gh api commits/4ae67c59e/check-runs; пробы не перезапускались"
---

# kaname#367: волна-4 identity-own — из службы доступа снято всё, что держало прежнего издателя

> [!note] Состояние — `test`, хотя волна закрыта
> Волна влита в ветку эпика `357` локальным коммитом слияния
> `73dc6598c1a38321cdee20731cb5547cd4a158c3` (`--no-ff`, родители `734f69fb4` и `4ae67c59e`,
> дерево `5bdd770f6` равно дереву головы волны). Запрос
> [kaname#492](https://github.com/PRO-Robotech/kaname/pull/492) — MERGED 2026-09-30, серверного
> слияния не было. Задача закрыта 2026-09-30, её задачи — каскадом тем же заходом. В `main`
> службы волна не влита: запрос эпика [kaname#359](https://github.com/PRO-Robotech/kaname/pull/359)
> открыт черновиком (замер 2026-09-30), поэтому здесь `test`, и у каждой задачи волны тоже.

## Что и зачем

Родитель — эпик kaname#357: служба доступа не зависит от прежнего поставщика личности, церемония
идёт на движке фундамента. Волна-4 снимает всё, что держало прежнего издателя: зеркало его набора
ключей, поле, вид и столбец его зеркала, его издатель в наших токенах, переключатель посадки, имена
в производстве и документы о его ключах. Она питает волну-4 платформы (PRO-Robotech/kacho#2798) и
волну-4 фундамента (PRO-Robotech/corelib#29, снятие значения внешней посадки из словаря посадок).

Ветки по правилу эпика: ветка волны `367` от ветки эпика `357`, ветка задачи — её номером от ветки
волны, вливание коммитом слияния без сквоша и rebase.

## Сборки

| сборка | задача | запрос | голова сборки | слияние в `367` | полосы |
|---|---|---|---|---|---|
| 1 | [[KAC/issue-483-kaname]] | [kaname#485](https://github.com/PRO-Robotech/kaname/pull/485) | `86eb67120` | `d5e515e04` | [[KAC/issue-368-kaname]], [[KAC/issue-364-kaname]], [[KAC/issue-323-kaname]], [[KAC/issue-471-kaname]], [[KAC/issue-474-kaname]], [[KAC/issue-328-kaname]] (с [[KAC/issue-329-kaname]] и [[KAC/issue-362-kaname]]), [[KAC/issue-259-kaname]], [[KAC/issue-338-kaname]], [[KAC/issue-480-kaname]], [[KAC/issue-361-kaname]] |
| 2 | [[KAC/issue-486-kaname]] | [kaname#487](https://github.com/PRO-Robotech/kaname/pull/487) | `b1427b775` | `290239435` | [[KAC/issue-363-kaname]], [[KAC/issue-380-kaname]] |
| 3 | [[KAC/issue-488-kaname]] | [kaname#489](https://github.com/PRO-Robotech/kaname/pull/489) | `bc2ff28b2` | `caf1c95ca` | [[KAC/issue-376-kaname]], [[KAC/issue-276-kaname]], [[KAC/issue-332-kaname]] |
| 4 | [[KAC/issue-490-kaname]] | [kaname#491](https://github.com/PRO-Robotech/kaname/pull/491) | `a098ac605` | `4ae67c59e` | [[KAC/issue-398-kaname]] |

## Состав — замеры этой записи

- Диапазон `734f69fb4..4ae67c59e` — 79 коммитов (`git rev-list --count`).
- Путей в диффе к `357` без распознавания переименований 561: добавлено 76, снято 128, изменено 357.
  Из снятых 98 — коммитом `69e61c563` (kaname#363); каталог `internal/handler/iamhooks/` снят целиком.
- Миграций добавлено две: `20260928231124_provider_mirror_leaves_the_credential_tables.sql`
  (kaname#362) и `20260930090111_provider_compensation_queue_stops_notifying.sql` (возврат по
  kaname#363 в сборке 2). Применённые не тронуты — со слов тела kaname#492.
- Путей с именем прежнего поставщика: на `73dc6598c` 0, на `main` службы @ `cbbac984b` 10
  (`git ls-tree -r --name-only <rev> | grep -icE 'hydra|kratos'`) — предикат узла kaname#333.
- Конвейер на `4ae67c59e` (дерево то же): проверок 24, success 20, skipped 4 (задание вердикта ствола
  срабатывает только на отправке в `main`), failure 0 — `gh api commits/…/check-runs`, 2026-09-30.

## Закрыто каскадом

Закрыто 23 задачи в окне 2026-09-30 19:35–19:43Z, сверх самой #367: 22 из дерева подзадач
(16 прямых подзадач #367 и 6 подзадач узла kaname#333) и kaname#474, у которой родителя нет.
Число «22», названное в возврате вливания, считает только дерево подзадач.

- С трейлом (ветка была): [[KAC/issue-235-kaname]], [[KAC/issue-259-kaname]], [[KAC/issue-276-kaname]],
  [[KAC/issue-323-kaname]], [[KAC/issue-328-kaname]], [[KAC/issue-329-kaname]], [[KAC/issue-332-kaname]],
  [[KAC/issue-338-kaname]], [[KAC/issue-361-kaname]], [[KAC/issue-362-kaname]], [[KAC/issue-364-kaname]],
  [[KAC/issue-368-kaname]], [[KAC/issue-376-kaname]], [[KAC/issue-380-kaname]], [[KAC/issue-424-kaname]],
  [[KAC/issue-471-kaname]], [[KAC/issue-474-kaname]], [[KAC/issue-480-kaname]].
- Без своей ветки, трейла нет: kaname#327, kaname#330, kaname#331 — их код снят вместе с kaname#363
  коммитом `69e61c563`; kaname#375 — в ветке `364`, см. [[KAC/issue-364-kaname]]; kaname#333 — узел,
  его предикат выше дал 0.
- Сборки #483, #486, #488, #490 закрыты раньше, каждая — вливанием своего запроса в ветку `367`.

## Осталось открытым под эпиком kaname#357

Со слов тела kaname#492 (счёт модуля `.github/scripts/newman-suite-debt.py` на `4ae67c59e`, код 0);
этой записью не перемерялось.

- [[KAC/issue-363-kaname]] — две позиции приёмок, IC-SECRET-11 и Ф3-46.
- [[KAC/issue-398-kaname]] — п.4 предиката, запись пары в ведомости пар воркспейса.
- kaname#415 — 9 коллекций newman; шесть переносит PRO-Robotech/kacho#2912, у седьмой
  (`iam-account-id-edge-format`) задачи платформы нет.
- kaname#416 — 1 коллекция и 5 позиций приёмки; перенос ведёт PRO-Robotech/kacho#2913.

## Расхождения, найденные при записи

- Три буквальных предиката задач не дают нуля при исполненном предмете: kaname#362 — 45 строк,
  kaname#363 — 18, kaname#480 — 6. Во всех трёх остаток — пути, которые предмет снимают или несут
  (снимающая миграция, отказ шаблона по снятому ключу, кейс, несущий позицию), а литерал их не
  исключает. Разбор — в трейлах этих задач. Задачи закрыты каскадом, комментарий закрытия говорит,
  что предикат не перепроверялся.
- kaname#424: п.1 её предиката на `73dc6598c` даёт 0 — вызов проверки старта снят вместе с ключом
  посадки; держится альтернатива «предикат kaname#363».
- Чек-лист тела #367 не совпадал с деревом подзадач: kaname#480 в нём не было — со слов разведки
  перед финальной переписью (2026-09-30); дерево подзадач — полнее.

## Узкие записки о снятом — почему не правлены

Волна влита в ветку эпика, а не в `main` службы. На `main` @ `cbbac984b` предметы живы:
`internal/handler/iamhooks/` — 32 пути, строк зеркала набора ключей — 113, строк
`hydra_client_id` вне начальной миграции — 113. Узкие записки, описывающие эти предметы по дереву
платформы 2026-08, сегодня не ложны о `main` и правятся посадкой эпика в `main`, а не этой волной:
[[edges/iam-to-hydra-admin]], [[packages/iam-handler-iamhooks]],
[[resources/iam-service-account-oauth-client]], [[rpc/iam-sa-key-service]],
[[rpc/iam-internal-bootstrap-token-service]].

Возвраты полос волны-4 поля «затронуто в vault» не несут: где поле есть, стоит «—». Узкие записки
по ним не заводились — без данных полосы предмет не выдумывается.

Здесь стояло «трейлов эпика kaname#357 и волн 1–3 (#365, #358, #366) в хранилище нет, а из задач
службы после kaname#270 не записана ни одна». Это было неверно уже в день записи: трейлы
[[KAC/issue-358-kaname]] и [[KAC/issue-365-kaname]] лежали в хранилище с 2026-09-24 и 2026-09-26,
записки задач службы после kaname#270 — с 2026-09-24 (например, [[KAC/issue-287-kaname]];
`git log --diff-filter=A`). Трейлов эпика и волны-3 действительно не было; они заведены
2026-10-01 — [[KAC/issue-357-kaname]] и [[KAC/issue-366-kaname]].

## Затронутые сущности vault

Трейлы задач волны перечислены выше. Узких записок `resources/` · `rpc/` · `packages/` · `edges/`
волна не завела и не правила — раздел выше.

## Связанные задачи

- [[KAC/issue-357-kaname|kaname#357]] — эпик identity-own, запрос в `main` [kaname#359](https://github.com/PRO-Robotech/kaname/pull/359)
- [[KAC/issue-366-kaname|kaname#366]] — волна-3, влита в `357` запросом [kaname#481](https://github.com/PRO-Robotech/kaname/pull/481) коммитом `734f69fb4`
- [[KAC/issue-493-kaname|kaname#493]] — волна-5, следующая
- PRO-Robotech/kacho#2798 — волна-4 платформы; PRO-Robotech/corelib#29 — волна-4 фундамента

#kac #kacho-iam #iam #go #proto #migrations
