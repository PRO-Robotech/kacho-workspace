---
title: "kacho#3054: deploy: чарт монтирует копию корня CA, которую сам не производит"
aliases:
  - issue-3054
  - kacho#3054
ticket_id: 3054
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella
  - deploy/scripts
  - deploy/tests/helm
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/3054
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-deploy
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @4157f4fbf68d; пробы и конвейер этой записью не перезапускались"
---

# kacho#3054: deploy: чарт монтирует копию корня CA, которую сам не производит

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Чарт монтировал копию корня CA, которую сам не производит. Копии корня в пространстве имён релиза больше нет; профиль a8f60d садится на ревизии `1266`; комментарий сверки копии называет нужное право чтения.

## Затронутые каталоги

`deploy/helm/umbrella`, `deploy/scripts`, `deploy/tests/helm` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`4157f4fbf68d` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3054#issuecomment-6035119462): bash deploy/tests/helm/internal-ca-root-copy-test.sh → PASS, утверждений 18 из 18, рендеров helm 11, цепочек 7, корней вне namespace релиза 2 (a8f60d, fe3455), потребителей копии у них 0.
- [x] стендовая часть — подзадача [[KAC/issue-3065]]: переустановка с нуля без ручных шагов на `1266` @`0ca88998`, закрыта 2026-10-10 (DoD-proof в задаче).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]]

## Связанные задачи

- [[KAC/issue-3065]] — стендовая часть
- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #fix #kacho-deploy
