---
title: "kaname#710: ci: stand-own.sh down оставляет анонимные тома Postgres"
aliases:
  - issue-710-kaname
  - kaname#710
ticket_id: 710
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kaname/pull/715
issue_url: https://github.com/PRO-Robotech/kaname/issues/710
opened: 2026-10-11
closed: 2026-10-12
tags:
  - kac
  - fix
  - kacho-test
verified_against: "`gh` 2026-10-12: kaname PR #715 MERGED в `296` 2026-10-12T05:09Z коммитом слияния 110db75359d5; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kaname#710: ci: stand-own.sh down оставляет анонимные тома Postgres

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `296`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Снятие автономного стенда `.github/scripts/stand-own.sh down` оставляло анонимные тома базы на машине (найдено полосой [[KAC/issue-664-kaname]]). Тома своих контейнеров теперь снимаются вместе с ними — норма «тест не оставляет мусора» (ws#967).

## Затронутые каталоги

`.github/scripts` (PRO-Robotech/kaname). Ветка задачи — `710` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kaname#715](https://github.com/PRO-Robotech/kaname/pull/715) | `296` | `110db75359d5` | 2026-10-12T05:09Z | запрос задачи |

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `296` — коммит слияния `110db75359d5` (kaname#715);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/710#issuecomment-6117045515);
- [x] вливание — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/710#issuecomment-6118145611): `ci-read` код 0 (24 проверки из 19), `merge-readiness` код 0 (11 из 11), `landing-precheck` код 0;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик службы доступа

## History

- 2026-10-12 — trail заведён после вливания (kaname#715); статус `test` (ws#1035).

#kac #fix #kacho-test
