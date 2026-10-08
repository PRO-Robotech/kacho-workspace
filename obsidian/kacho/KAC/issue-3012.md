---
title: "kacho#3012: стенд a8f60d отстал от main — перепин профиля и выкатка"
aliases:
  - issue-3012
ticket_id: 3012
category: kac
status: in-progress
verified_against: "тело задачи, метки и голова main сверены `gh` 2026-10-04 (main ba01514b98b); пины values.a8f60d.yaml и счёт коммитов прочитаны на ba01514b98b; стенд мной не опрашивался"
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella
prs: []
issue_url: https://github.com/PRO-Robotech/kacho/issues/3012
opened: 2026-10-04
tags:
  - kac
  - kacho-deploy
---

# kacho#3012: стенд a8f60d отстал от main — перепин профиля и выкатка

**Состояние на момент записи**: `in-progress`. Задача **открыта**, PR нет. Метки: `P1`,
`size:M`, `area:deploy`, `release:identity-own`; метки состояния `status:in-progress` на
задаче нет (`gh issue view 3012 --repo PRO-Robotech/kacho --json labels`, 2026-10-04).
Ветка `issue-3012` (координата, не живая ссылка) заведена в клоне продукта на
`ba01514b98b` — голове `main`, коммитов сверх ствола нет; на `origin` её пока нет
(`gh api repos/PRO-Robotech/kacho/branches/issue-3012` → 404).

**Роль исполнителя:** `deploy-engineer`. Тип в задании — «deploy»; канонического значения
`type` для него нет, записано `fix` (см. возврат, вопрос владельцу).

## Что и зачем

Стенд `a8f60d` стоит на образах `main-a2981976` — со слов тела задачи; на `main`
`ba01514b98b` это **587** коммитов назад (`git rev-list --count a2981976..ba01514b98b`).
Профиль `deploy/helm/umbrella/values.a8f60d.yaml` на `ba01514b98b` закреплён в основном на
`main-275240ef`: 17 вхождений из 19 тегов вида `main-<sha>`, ещё два — по одному на
`main-0dd03218` и `main-7bb0a6e1`. Цепочка профилей стенда — [[packages/kacho-deploy-helm-umbrella]].

Предмет: перезакрепить пины профиля в дереве на сборку `main` `ba01514b` и выкатить
`stack-up STACK=a8f60d`. Решения владельца 2026-10-04: живые hydra и kratos на `a8f60d`
снимаются; пины перезакрепляются в дереве; выкатка и починка идут параллельно.

## DoD (из тела задачи)

- [ ] профиль перезакреплён и влит в `main`;
- [ ] на `a8f60d` релиз `kacho-umbrella` стоит на образах из пинов влитого профиля,
      rollout-ready;
- [ ] провенанс применённого сходится с пинами (образы релиза против пинов).

Артефакт — PR перезакрепления, вывод сверки провенанса и rollout-статуса. До вливания в
`main` статус записки не выше `test`.

## Связанные задачи

- https://github.com/PRO-Robotech/kacho/issues/2920 — тот же профиль.
- https://github.com/PRO-Robotech/kacho/issues/2875 — тот же профиль.

## History

- 2026-10-04 — trail заведён вместе с веткой; PR и sha посадки нет.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — зонт и цепочки его профилей.

#kac #kacho-deploy
