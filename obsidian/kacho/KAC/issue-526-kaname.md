---
title: "kaname#526: полоса входа — отказ неподтверждённого адреса называет шаг подтверждения"
aliases:
  - issue-526-kaname
  - kaname#526
ticket_id: 526
category: kac
status: test
type: fix
repos:
  - kaname
  - kacho-workspace
areas:
  - docs/engineering/acceptance
  - docs/specs/reviews
  - internal/admission
  - docs/content/api
  - docs/specs (воркспейс, приёмка F6b)
prs:
  - https://github.com/PRO-Robotech/kaname/pull/629
  - https://github.com/PRO-Robotech/kacho-workspace/pull/944
  - https://github.com/PRO-Robotech/kaname/pull/640
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/526
opened: 2026-10-01
closed: 2026-10-08
tags:
  - kac
  - kacho-iam
  - kacho-api-gateway
verified_against: "kaname 296@d9e233f42051 (коммит слияния PR #629; голова origin/296 = этот коммит, git ls-remote 2026-10-07): состав по задаче — тело PR #629; kacho-workspace main@4c94df1bbd44 (коммит слияния PR #944, gh pr view 944 → MERGED 2026-10-06T14:41Z, файлы — приёмка F6b и две записи ревью); состояние задачи — gh issue view 2026-10-07 (OPEN, родитель kaname#540); пробы и конвейер этой записью не перезапускались; 2026-10-08 — gh issue view (CLOSED 2026-10-08T02:43Z, completed), комментарии DoD-proof @8f96e12055ed и закрытия (gh api …/comments); коммиты слияния PR kaname#640 = 76ca2c8aa6e0 и #668 = 8b0379e2a9c5 (gh pr view)"
---

# kaname#526: полоса входа — отказ неподтверждённого адреса называет шаг подтверждения

> [!note] Состояние — `test`: задача закрыта 2026-10-08 волной-6 [[KAC/issue-540-kaname]], в `main` не влита
> Сторона службы и обе приёмки влиты: служба — в `296`, приёмка края F6b ред. 9 — в `main` воркспейса
> ([ws#944](https://github.com/PRO-Robotech/kacho-workspace/pull/944), `4c94df1bbd44`). DoD-proof @`8f96e12055ed`.
> Сторона края — текст отказа на краю и переутверждение проб F6b-10/25/29/33 — вынесена в kacho#3069 (открыта,
> волна-6 платформы [[KAC/issue-2969]]).

## Что и зачем

Отказ полосы входа для неподтверждённого адреса называл состояние, но не шаг: клиент API не узнавал, что код ему
уже отправлен. Соседние отказы той же полосы шаг называют. Тексты отказа — часть контракта, поэтому меняются
одновременно в приёмке службы, приёмке края F6b, службе и на краю.

## Ход

- **Волна-4 платформы** — правка текста на краю ушла вперёд приёмки и была откачена; урок —
  [[lessons/edge-refusal-text-changed-past-its-acceptance]].
- **Приёмка службы** `access-beyond-login-needs-a-verified-address`: ред. 5–6 (круги 4–5), ред. 7 — сведена с правкой
  kaname#458 коммитом слияния (`6f4fe5a84`), ред. 8 — команды измерения исполнимы дословно; круг 6 — возврат
  (команды неисполнимы), круг 7 — принято, событие одобрения опубликовано (`037d6a3fc`).
- **Приёмка края F6b**: ред. 8 — пара к ред. 7 службы; круг 8 — возврат (пара названа отпечатком возвращённой
  редакции); ред. 9 — пара службы названа документом, а не отпечатком; круг 9 — принято; событие одобрения
  ([ws#944](https://github.com/PRO-Robotech/kacho-workspace/pull/944), задача-эпик воркспейса #896 — `Refs`).
- **Волна-5 службы**, полоса N-ADDR: текст отказа положения в службе называет шаг подтверждения (`2fa094596`);
  попутно — kaname#197 (закрыта) и пробы kaname#198 (открыта). По возврату сверки волны — запись долга EV-14 в
  ведомости набора с держателем этой задачи (`7d7793fc5`).

- **Волна-6 службы** ([[KAC/issue-540-kaname]]): DoD-proof @`8f96e12055ed` (полоса #261, первая сборка kaname#640,
  `76ca2c8aa6e0`); держатель записи долга EV-14 перенесён на kacho#3069 — сторону края и переутверждение F6b
  (полоса LEDGER, сборка 6b kaname#668, `8b0379e2a9c5`). Задача закрыта 2026-10-08 как completed.

## Затронутые каталоги

kaname: `docs/engineering/acceptance/`, `docs/specs/reviews/`, `internal/admission/`, `docs/content/api/auth-lane.mdx`, `tests/newman/`, `.github/scripts/`
(ведомость долга набора). Воркспейс: `docs/specs/sub-phase-F6b-console-and-edge-confirmed-address-gate-acceptance.md`
и записи ревью.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] приёмка службы ред. 8 — APPROVED, событие опубликовано (`037d6a3fc` в `296`);
- [x] приёмка края F6b ред. 9 — APPROVED, событие опубликовано (`ddb912225`, влито в `main` воркспейса `4c94df1bbd44`);
- [x] текст отказа в службе — в ветке эпика `296` (`2fa094596`, предок `d9e233f42051`);
- [ ] текст отказа на краю и переутверждение проб F6b-10/25/29/33 — перенесено в kacho#3069 (открыта, волна-6 платформы);
- [x] позиция EV-14 уровня E — держатель перенесён на kacho#3069 (ведомость долга на `296`@`8b0379e2a9c5`, со слов комментария закрытия);
- [x] DoD-proof @`8f96e12055ed` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/526#issuecomment-6028685647): исполнено 406 проб в 10 пакетах, отказов 0;
- [ ] влито в `main` службы — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — откат текста отказа на краю в волне-4 (History 2026-10-06); новая правка края — волна-6

## Связанные задачи

- [[KAC/issue-539-kaname]] — волна-5 службы
- [[KAC/issue-2967]] — волна-4 платформы, откат
- [[KAC/issue-197-kaname]] — та же полоса N-ADDR
- kaname#458, kaname#198 — та же полоса, открыты

#kac #kacho-iam #kacho-api-gateway
