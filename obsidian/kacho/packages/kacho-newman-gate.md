---
title: newman — гейт, known-RED и загрязнение фикстур
category: packages
repo: kacho
layer: ci
status: stable
tags: [packages, architecture, cross-service, kacho-iam]
---

# newman: гейт и почему он краснеет

Вердикт по e2e выносит **не exit-код newman**, а `services/iam/tests/newman/scripts/assert-suites-green.sh`.
Скрипт ОДИН (живёт в iam) и применяется к каждому сервису **с его cwd** — он глобит
`collections/` + `out/` относительно pwd. Так же было в polyrepo; при переезде в монорепу
вызов потерялся, и гейтом стал голый exit newman → краснели кейсы RED-by-design.

## Дефекты гейта (оба чинились 2026-07-16)

> [!danger] Вычитание из РАЗНЫХ популяций прятало падения
> `fails` = `.run.stats.assertions.failed` (только AssertionError), а `known_red`
> считался по всему `.run.failures[]` — там ещё JSONError/script-ошибки. Разница давала
> **запас поглощения** (замер: nlb 9 vs 6, channel-equiv 8 vs 6, invite-grant 3 vs 2), а
> клэмп `fails<0 → 0` глушил перекос молча.
>
> Не теория: `rbac-subject-channel-equivalence` был зелёным ТОЛЬКО из-за перекоса —
> whitelist там нацелен на шаги `*-gone` (они дают JSONError), а настоящие AssertionError
> сидели в **других** шагах: `nonmember-denied` ×2 (не-член не получил отказ),
> `user-not-inherits` ×2 (юзер унаследовал гранты SA). Тесты изоляции падали при зелёном
> гейте. Лечится `select(.error.name=="AssertionError")` в known_red.

**Мёртвый комментарий** про `neg-v_delete-denied`/`neg-v_update-denied`: этих шагов в
`cases/` нет (grep → 0), в whitelist они не входят (doc-truthfulness).

## Корень остаточной красноты — загрязнение фикстур, НЕ баг продукта

На кластере с нуля (26/26 Running) остаётся **68** падений в 8 наборах. Первое звено:

```
IAM-ACB-CR-CRUD-OK :: poll-op
  code 6 ALREADY_EXISTS: "these permissions are already granted to <NOB> on account:acc…"
```

Это **правильное** поведение продукта (UNIQUE → AlreadyExists). Неверен тест: он ждёт
чистый лист для ресурса, **не привязанного к `runId`** (binding NOB на fixture-аккаунте A).
Create не прошёл → `get-confirms` 404 → каскад.

`setup.sh` про это знает (шаг «4b KAC-132: clean up stale NOB bindings»), но чистит
**один раз перед** прогоном, а загрязнение возникает **во время**: коллекции идут по
списку (`authz-deny` → … → `iam-access-binding`), ранняя создаёт binding, поздняя на него
натыкается. KAC-132 лечит симптом.

**Почему per-case pre-clean не спасает.** У `IAM-ACB-CR-CRUD-OK` есть свой pre-clean, но
он зовёт `ListBySubject` — а тот **cluster-scoped** (`scope_extractor.object_type: cluster`,
`required_relation: viewer`, `required_acr_min: 2`). Account-admin не cluster-viewer → 403,
скрипт `if(code===200)` его не ловит, дубль не удаляется. Правильный путь (проверено
вручную): `ListByScope(resourceType=account)` + step-up токен `jwtAccountAdminAStepUp`
(account-admin — viewer на своём account-scope). В polyrepo этот pre-clean был тот же и
так же не работал — RESULTS.md звал это «occasionally flake». Направление фикса и где он
застрял (step-up не резолвится в рантайме newman) — kacho#6.

Масштаб: `listBySubject` в pre-clean/setup — **7 кейсов**, не везде это pre-clean (местами
тест контракта, 403 ожидаем). Каждый требует разбора. Полный зелёный — крупная
fixture-переработка, не один заход.

> [!danger] Автоматическое применение step-up РЕГРЕССИРУЕТ — только ручной разбор
> Замеры на iam-access-binding: базовый pre-clean-фикс 40→28. Массовая замена всех
> мутаций (26 шагов) на step-up → **34**. Замена «в non-deny кейсах» (25 шагов) → **46**
> (total assertions упал 390→289 — `setNextRequest`-цепочки порвались, кейсы пропущены).
> Даже специализированный `qa-test-engineer` агент со всем контекстом → **47**.
> Причина: каждый шаг взаимодействует с соседними через `setNextRequest`, а step-up
> меняет не только acr-проход, но и семантику (deny-тест 403→200, existence-hide 404→200).
> Различать success-мутацию / deny-тест / chain-звено можно ТОЛЬКО читая test_script и
> id кейса поштучно, прогоняя после КАЖДОЙ правки и сверяя, что total assertions не упал.
> Это ~28 шагов в одном наборе × 8 наборов, прогон 3-4 мин каждый — дни работы, kacho#6.

> [!warning] 403 парсится как пустой список
> `delete_binding_if_exists` звал УДАЛЁННЫЙ роут `:listByResource` (RPC переименован в
> `ListByScope`, wire-имя снято) → 403 приходил **валидным** JSON'ом, `.get('accessBindings', [])`
> давал пустой список → «удалено 0» и отчёт об успехе. Очистка не работала никогда.
> Проверяй HTTP-код, а не только парсинг тела. См. [[../rpc/iam-access-binding-service]].

## Гочи прогона (стоили часов отладки)

> [!danger] Не держи ручной `kubectl port-forward` во время `newman-e2e.sh`
> Скрипт сам поднимает port-forward на :18080/:18081/:19091. Висящий ручной форвард
> (напр. для отладочного curl) занимает порт → `setup.sh` не достучится до
> iam-internal :19091 → `FATAL: user AAA resolved to an empty id`. Прогон падает на
> setup, `out/*.json` НЕ обновляется. Перед прогоном: `pkill -f 'port-forward svc'`.

> [!warning] Single-collection прогон пишет ТОЛЬКО cli, не `out/*.json`
> `newman-e2e.sh iam <collection>` запускает newman с `--reporters cli` — JSON-отчёт в
> `out/` НЕ пишется, там остаётся файл от последнего ПОЛНОГО прогона (`run.sh`). Парсить
> результат надо из **cli-лога** (`│ assertions │ … │`, `inside "IAM-…"`), а не из
> `out/*.json` — иначе анализируешь устаревший отчёт (реальная потеря: час на «фикс не
> применяется», хотя out/ был просто старый).

## Что вычитается корректно (RED-by-design, каждый с тикетом)

- `SEC-C-A-*` — fga-proxy Register/Unregister: internal-only :9091 **без** `google.api.http`
  → REST-хендлера нет вовсе, как black-box неисполнимы; покрыты `fgaproxy_test.go` (#111).
- `T31-LBLREVOKE-NLB-*` — infra-RED: EXTERNAL listener требует zone_id, которого env не
  провиженит (#217).
- `iam-invite-grant-fga` T-E4 — product-gap: `CreateRoleRequest` без `project_id` (#212).
- `*-gone` — poll-хвост eventual-consistency (#257).

Связано: [[kacho-ci-runners]], [[kacho-ci-determinism]], [[../rpc/iam-access-binding-service]].

#packages #architecture #cross-service #kacho-iam
