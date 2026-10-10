---
title: "ws#938: зависимая полоса волны — от сводки голов deps; фундамент соседа — при обоих репозиториях"
aliases:
  - issue-938-ws
  - ws#938
ticket_id: 938
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - .claude/workflows
  - scripts/plan-precheck.sh
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/939
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/938
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@b92cf1212743 (коммит слияния PR #939; gh pr view 939 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#938: зависимая полоса волны — от сводки голов deps; фундамент соседа — при обоих репозиториях

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#939](https://github.com/PRO-Robotech/kacho-workspace/pull/939) влит коммитом слияния `b92cf1212743` 2026-10-06; задача закрыта как completed.

## Что и зачем

Найдено при разборе плана волны-5: шаблон заводил ветку зависимой полосы от базы волны, и полоса не видела кода предшественников. Теперь она стартует от временной сводки голов deps (слияния без переписывания истории), а предпроверка полосы судит, что код предшественников в ветке есть. Предпроверка плана судит фундамент соседа, когда в плане оба репозитория либо объявлен `crossRepo`.

## Затронутые каталоги

`.claude/workflows`, `scripts/plan-precheck.sh` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `b92cf1212743` ([ws#939](https://github.com/PRO-Robotech/kacho-workspace/pull/939));
- [x] DoD-proof @`be51e89f27da` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/938#issuecomment-6015419330): `plan-precheck-inject.sh` — утверждений 34, разошлось 0; мутантов 6, красных 6; доводка по возврату check-verifier (11 выживших мутантов шаблона на прежней голове).

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
