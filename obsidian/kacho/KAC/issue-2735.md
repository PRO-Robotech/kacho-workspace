---
title: "kacho#2735: посадка own во всех профилях, чужие службы личности выключены"
aliases:
  - issue-2735
ticket_id: 2735
category: kac
status: test
type: refactor
repos:
  - kacho
areas:
  - deploy/tests
  - deploy
  - deploy/helm
  - deploy/scripts
  - gateway/deploy
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2861
  - https://github.com/PRO-Robotech/kacho/pull/2869
issue_url: https://github.com/PRO-Robotech/kacho/issues/2735
opened: 2026-09-21
closed: 2026-09-26
tags:
  - kac
  - refactor
  - kacho-deploy
verified_against: "PRO-Robotech/kacho: голова задачи af6d21f7d65 — предок коммита слияния волны 7190c3e5274 в ветку эпика 2564 и не предок origin/main 1d42a6728bf (`git merge-base --is-ancestor`), 2026-09-26. Пункт DoD об объявленной посадке перемерен слиянием YAML цепочек; прочие пункты не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:40:29Z, меток status:* нет (`gh issue view`); коммит слияния волны 7190c3e5274 — в origin/2564, не в origin/main (`gh api compare`)"
---

# kacho#2735: посадка own во всех профилях, чужие службы личности выключены

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:40:29Z вместе с волной [[KAC/issue-2796|#2796]]: запрос волны PR #2869 влит в ветку эпика `2564` (координата, не живая ссылка), коммит закрытия — слияние волны `7190c3e5274`; метка `status:test` снята, метки сейчас: `tech-debt`, `P1`, `size:M`, `area:deploy`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #2564 в ствол.

## Что и зачем

Профили развёртывания поднимали чужой стек личности, хотя служба доступа и край работают на посадке own. Задача объявляет `identityProvider: own` у службы и у края в каждом профиле, снимает привязки к чужим службам и снижает потолок гейта `vendorTreePlatform` тем же изменением. Та же ветка `2735` (координата, не живая ссылка) несёт [[KAC/issue-2777|#2777]] и [[KAC/issue-2733|#2733]].

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `af6d21f7d65` → слияние в ветку сборки `2857` `9672c86fac5` — «#2857 merge #2735: гейт пробросов к поставщику судит весь файл» |
| запрос сборки | PR #2861 `2857` → `2796`, голова `86d8244838f`, коммит слияния `ec8f4f445b4`; прогоны головы — 9 прогонов, все `success` |
| запрос волны | PR #2869 `2796` → `2564`, голова `ec8f4f445b4`, коммит слияния `7190c3e5274`; прогоны головы — 8 прогонов, все `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- число прибора в области профилей **0**: ни одной привязки в десяти файлах выше;
- потолок `vendorTreePlatform` снижен **тем же изменением** ровно на снятое; гейт зелен;
- `identityProvider: own` объявлен у службы и у края в каждом профиле, а не умолчанием;
- `helm template` зелен на каждом профиле, и хотя бы один стек реально поднимается
  (`helm install` + rollout ready), а не только рендерится;
- `git grep -niE 'hydra|kratos|oryd/' -- 'deploy/helm/umbrella/values*.yaml' 'deploy/helm/umbrella/charts/*/values.yaml'` → 0.

Решение 2026-09-24 (комментарий задачи): два нулевых пункта — число прибора в профилях зонта и грубый `git grep` по той же области — перенесены в #1276 вместе с физическим снятием шаблонов поставщика. Здесь остаются потолок, снижаемый тем же изменением, объявленный `own` и `helm template` с подъёмом стека.

Сверено мной:

- [x] грубый прибор перенесённого пункта для справки: `git grep -niE 'hydra|kratos|oryd/' 7190c3e5274 -- 'deploy/helm/umbrella/values*.yaml' 'deploy/helm/umbrella/charts/*/values.yaml' | wc -l` → 327 (при заведении задачи — 426); по DoD задачи это уже не её предмет;
- [x] `identityProvider: own` у службы и у края на каждой из семи цепочек `deploy/stacks.txt` — слиянием YAML `values.yaml` и файлов цепочки на `7190c3e5274` (рендера helm не было); объявления — в корнях `values.dev.yaml` и `values.prod.yaml`, а не умолчанием чарта;
- [x] голова задачи — предок коммита слияния волны `7190c3e5274` в ветку эпика `2564`;
- [ ] предмет в стволе: `main` — посадкой эпика #2564.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: deploy/helm/umbrella (профили own), gateway/deploy, deploy/scripts (гейты стека own), internal/repohygiene (потолок retiredidentityvendorceiling).

- [[KAC/issue-2796]] — волна.
- [[KAC/issue-2777]]
- [[KAC/issue-2733]]
- [[packages/kacho-deploy-helm-umbrella]]

#kac #refactor #kacho-deploy
