---
title: "kacho#2863: image-size 2.0.4 в lock-файлах сайтов документации"
aliases:
  - issue-2863
ticket_id: 2863
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/docs
  - services/compute
  - services/geo
  - services/nlb
  - services/registry
  - services/storage
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2861
  - https://github.com/PRO-Robotech/kacho/pull/2869
issue_url: https://github.com/PRO-Robotech/kacho/issues/2863
opened: 2026-09-25
tags:
  - kac
  - fix
  - docs
verified_against: "PRO-Robotech/kacho: голова задачи ac222f0d0d8 — предок коммита слияния волны 7190c3e5274 в ветку эпика 2564 и не предок origin/main 1d42a6728bf (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# kacho#2863: image-size 2.0.4 в lock-файлах сайтов документации

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `bug`, `status:test`, `P1`, `size:S`, `area:ci`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-2796|#2796]], волна — в ветку эпика `2564` (координата, не живая ссылка) запросом PR #2869; в `main` **не** доехала: закроет её посадка эпика #2564 в ствол.

## Что и зачем

В семи lock-файлах сайтов документации стояла версия `image-size` ниже исправленной. Правка поднимает её в пределах объявленного диапазона, `package.json` не трогает. Разбор уязвимости сюда не пишется: адрес правки — коммит слияния ниже.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `ac222f0d0d8` → слияние в ветку сборки `2857` `4568ea19219` — «#2857 merge #2863: image-size 2.0.4 в lock-файлах сайтов документации» |
| запрос сборки | PR #2861 `2857` → `2796`, голова `86d8244838f`, коммит слияния `ec8f4f445b4`; прогоны головы — 9 прогонов, все `success` |
| запрос волны | PR #2869 `2796` → `2564`, голова `ec8f4f445b4`, коммит слияния `7190c3e5274`; прогоны головы — 8 прогонов, все `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- во всех семи lock-файлах `node_modules/image-size` поднят в пределах `^2.0.2` до версии с исправлением, `package.json` не тронут, прочие записи lock-файлов не изменились;
- `trivy fs --severity CRITICAL,HIGH` по этим файлам — 0 находок;
- `docs-sites` (сборка всех сайтов) зелёный.

Предикат снятия: `git ls-files '*package-lock.json' | xargs grep -A1 '"node_modules/image-size"' | grep '"version"'` — нет версии ниже исправленной.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `7190c3e5274` в ветку эпика `2564`;
- [ ] предмет в стволе: `main` — посадкой эпика #2564.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-2796]] — волна.

#kac #fix #docs
