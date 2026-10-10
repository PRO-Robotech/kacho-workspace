---
title: "ws#967: правило — прогон не оставляет следов; перепись следов до и после прогона"
aliases:
  - issue-967-ws
  - ws#967
ticket_id: 967
category: kac
status: done
type: feature
repos:
  - kacho-workspace
areas:
  - .claude/rules
  - scripts/residue-census
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/971
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/967
opened: 2026-10-07
closed: 2026-10-07
tags:
  - kac
  - feature
  - conventions
verified_against: "kacho-workspace main: коммит слияния PR #971 = ffaae161d44f (gh pr view → MERGED 2026-10-07T22:35Z; git log origin/main); файлы — gh pr view --json files; состояние задачи — gh issue view 2026-10-08 (CLOSED); DoD — комментарий задачи DoD-proof @50de201d4e9b; самопробы этой записью не перезапускались"
---

# ws#967: правило — прогон не оставляет следов; перепись следов до и после прогона

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#971](https://github.com/PRO-Robotech/kacho-workspace/pull/971) влит коммитом слияния `ffaae161d44f`
> 2026-10-07; задача закрыта как completed.

## Что и зачем

Решение владельца 2026-10-07: тест не оставляет мусора. В норму тестирования вошёл раздел «Прогон не
оставляет следов» (уборка заводится до создания и исполняется на падении; своё пространство имён прогона на
внешнем кластере; приёмка — перепись до и после; отчёт красного под `--keep` — не дольше семи суток; найденный
след — задача). Перепись — `scripts/residue-census/census.sh`, только чтением, со сравнением двух снимков;
доказательство инъекцией — `scripts/residue-census/inject.sh` (10 случаев). Потолок корпуса правил не менялся:
три файла `testing*` сжаты, прежние редакции — в `.claude/backup/`.

## Затронутые каталоги

`.claude/rules/{testing,testing-verdict,testing-newman,MANIFEST}.md`, `.claude/backup`, `scripts/residue-census`,
`.github/workflows/ci.yaml` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `ffaae161d44f` (ws#971);
- [x] DoD-proof @`50de201d4e9b` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/967#issuecomment-6044274472): `inject.sh` — случаев 10, сошлось 10, разошлось 0 (код 0).

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-924-ws]] — фикстура вне рабочей копии, тот же класс следа
- [[KAC/issue-1266]] — релиз, на волнах которого действует

#kac #feature #conventions
