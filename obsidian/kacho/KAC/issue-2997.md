---
title: "kacho#2997: deploy: профиль зонта объявляет ручки без читателя в шаблонах"
aliases:
  - issue-2997
  - kacho#2997
ticket_id: 2997
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/2997
opened: 2026-10-02
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2997: deploy: профиль зонта объявляет ручки без читателя в шаблонах

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Ручки `global.kacho` профиля зонта без читателя в шаблонах сняты; суд — исходом рендера каждой цепочки (`TestEveryGlobalKachoKnobOfTheUmbrellaHasAReader`), а не поиском по тексту.

## Затронутые каталоги

`deploy/helm/umbrella`, `deploy` (PRO-Robotech/kacho).

Коммиты в составе волны: `b84d96b6b45`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2997#issuecomment-6012647618): `go test -count=1 -tags helmcharts ./deploy/ -run 'TestEveryGlobalKachoKnobOfTheUmbrellaHasAReader|TestGlobalKnobJudgement_CanFailAndStaysSilent'` → код 0, «профилей 10 · цепочек 7 · ручек global.kacho 13 · рендеров 33 · находок 0», инъекция PASS; `git grep -n 'identity.hooks\|kacho.hooks.tokenHookSecretName\|kacho.iam.jwks' origin/1266 -- deploy/helm/umbrella` → 1 строка, и это запись о снятии (`values.yaml:36`, комментарий). Конвейер: юниты deploy — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — ручки без читателя сняты (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-deploy
