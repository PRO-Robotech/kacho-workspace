---
title: "kaname#358: волна-2 identity-own — сборки, влитые в ветку волны"
aliases:
  - issue-358-kaname
ticket_id: 358
category: kac
status: in-progress
type: epic
repos:
  - kaname
areas:
  - internal/migrations
  - internal/repo/kaname/pg
  - internal/domain
  - cmd/kaname
  - internal/check
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kaname/pull/411
  - https://github.com/PRO-Robotech/kaname/pull/326
issue_url: https://github.com/PRO-Robotech/kaname/issues/358
opened: 2026-09-22
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "PRO-Robotech/kaname: origin/358 = d22123ba0957625fa791649bd72b6fffd694cfa0 на 2026-09-24 (`git ls-remote origin refs/heads/358`); не предок origin/357 и origin/main (`git merge-base --is-ancestor`). Запросы в ветку волны — `gh pr list --state all --base 358` (3 запроса, все влиты). Состав задач волны перечнем здесь не держится — только командой"
---

# kaname#358: волна-2 identity-own — сборки, влитые в ветку волны

**Состояние на момент записи**: `in-progress` — 2026-09-24. Волна **открыта**; её запрос в
ветку эпика `357` (координата, не живая ссылка) не открыт
(`gh pr list -R PRO-Robotech/kaname --base 357 --state all` — запросов из `358` нет).
Родитель — эпик kaname#357.

## Что и зачем

Своя запись кода авторизации и семейств токенов в службе доступа. Эта записка — trail волны
как единицы вливания: что влито в её ветку, с какими головами и каким вердиктом. Предмет
каждой задачи — в её записке.

Задачи волны — её sub-issue; перечнем они здесь не выписываются, состав меняется переносами:

```sh
gh api repos/PRO-Robotech/kaname/issues/358/sub_issues --paginate -q '.[] | "#\(.number) \(.state) \(.title)"'
```

## Как вливается

Готовые задачи сводятся в ветку сборки коммитом слияния (`git merge --no-ff`); конвейер,
рецензенты и сверка гоняются один раз на голову сборки. Задачи, влитые в волну, не
закрываются: метка `status:test`, закроет их посадка эпика #357 в `main`.

## Вливания в ветку волны

| что | запрос | голова | коммит слияния в `358` | вердикт головы |
|---|---|---|---|---|
| #313 (до сборок) | PR #326, влит 2026-09-23T00:33:07Z | `410d750ba46b91f3a7f7300462aebb5df7bf8be3` | `9dc46b4722bea058c3642c803aae6a102ad1f98f` | контекстов на голове нет: триггера на ветку-номер тогда не было ([[KAC/issue-394-kaname]]) |
| база эпика | — | `357` @ `d65f97e9e3e` | `462f916e0eaf43a1b91b367fbcab23f001a285f1` | — |
| сборка 1, задача сборки #408 (закрыта) | PR #411, влит 2026-09-24T14:05:18Z | `2f45e7c8aa0ebb6a1ec25ff26523cc70e205bb03` | `d22123ba0957625fa791649bd72b6fffd694cfa0` (родители `462f916e0`, `2f45e7c8a`) | 3 прогона `pull_request`, 20 заданий: 17 `success`, 3 `skipped` («вердикт ствола» — только push в `main`), 0 упавших |

### Сборка 1 — задачи и головы

| задача | первое сведение: голова → слияние | повторное сведение: голова → слияние |
|---|---|---|
| [[KAC/issue-317-kaname\|#317]] | `2b203955a36` → `a37b67366bb` | — |
| [[KAC/issue-404-kaname\|#404]] | `b9dd132dc46` → `ba62d8d8ecd` | — |
| [[KAC/issue-396-kaname\|#396]] | `c49152dd3c7` → `61c47dcf79d` | `b372cba3e1c` → `dd1e253219c` |
| [[KAC/issue-314-kaname\|#314]] | `30c41bbcf0c` → `0abe7af28a9` | `0b8113cb894` → `effd23c3f17` |
| [[KAC/issue-394-kaname\|#394]] | `bae45d0fdd5` → `b709c3a218c` | `09bb99905d9` → `8fc953171b8` |
| [[KAC/issue-320-kaname\|#320]] | `074b2fd3e51` → `6e7fc244372` | `e4048dc37d9` → `351a853b117` |

Таблица тела PR #411 называет только головы **первого** сведения; повторное сведение и два
коммита #379 прямо на ветке сборки (`d0afbb45d4c`, `2f45e7c8aa0`) пришли после. #379 —
задача волны-1 #365, её записки в хранилище нет. Финальные головы задач — предки origin/`358`
и не предки origin/`357` и origin/`main`; у пяти задач они равны голове их ветки на origin,
ветка `394` с origin снята.

Не вошли по конфликту слияния, возвращены исполнителю: #316 и #319 — пути и стороны названы
в теле PR #411.

## Затронутые сущности vault

Поля «затронуто в vault» у задач сборки 1 нет; узкие записки не менялись.

- [[KAC/issue-317-kaname]] · [[KAC/issue-404-kaname]] · [[KAC/issue-396-kaname]] ·
  [[KAC/issue-314-kaname]] · [[KAC/issue-394-kaname]] · [[KAC/issue-320-kaname]] — задачи
  сборки 1.
- [[KAC/issue-295-kaname]] — sub-issue этой волны, влита через волну [[KAC/issue-377-kaname|#377]].

#kac #kacho-iam #epic
