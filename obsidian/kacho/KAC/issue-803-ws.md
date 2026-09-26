---
title: "ws#803: номер проверки tooling-gate уникален на сведённой голове волны 0"
aliases:
  - issue-803-ws
ticket_id: 803
category: kac
status: test
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/tooling-gate
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/853
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/803
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - fix
verified_against: "PRO-Robotech/kacho-workspace, 2026-09-26: коммит c2d0a4f5 — предок origin/771 3956217c и не предок origin/main 6eddaa5e (`git merge-base --is-ancestor`); предикат тела задачи на 3956217c — повторов номера 0 при 13 файлах проверок (`git ls-tree … | uniq -d`); трекер — закрыта 2026-09-26T19:23:32Z, меток status:* нет (`gh issue view 803`). Исходы run-all и inject — из комментария закрытия, мной не перемерялись"
---

# ws#803: номер проверки tooling-gate уникален на сведённой голове волны 0

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере
2026-09-26T19:23:32Z каскадом волны [[KAC/issue-778-ws|#778]]: запрос волны PR #853 влит в ветку
эпика `771` (координата, не живая ссылка) коммитом слияния `3956217c`; `status:test` снята, метки:
`tech-debt`, `P2`, `size:S`, `area:tooling`, `release:wave`, `release:identity-own`. В `main`
работа **не** доехала: `done` — посадкой эпика #771 в ствол.

> [!note] Одноимённая записка — о другом трекере
> [[KAC/issue-803]] — задача продукта PRO-Robotech/kacho#803, с этой не связана.

## Что и зачем

Номер `check-16` в `scripts/tooling-gate` взяли три ветки вне волны 0 разом: `git merge-tree`
конфликта не показывает, потому что имена файлов разные, а механического держателя уникальности
номера у набора не было. Прецедент того же класса — три `check-03` в `docs-gate`
([[KAC/issue-754-ws|#754]]). Задача родилась в [[KAC/issue-780-ws|#780]].

## Путь в волну

| что | координата |
|---|---|
| работа | `c2d0a4f5` — проверке маршрута посадки волны дан номер 19 |
| запрос волны | PR #853 `778` → `771`, коммит слияния `3956217c` |

## DoD

- [x] предикат тела задачи на `3956217c` — пусто, файлов проверок 13; перемерено мной;
- [x] `tooling` `run-all.sh` 13 из 13, `inject.sh` 136 из 136 — по комментарию закрытия,
  рецензенты на `a9159c46`, мной не перемерялось;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах по этой задаче нет.

- [[KAC/issue-778-ws]] — волна.

#kac #fix
