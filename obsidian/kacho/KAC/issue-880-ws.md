---
title: "#880 (ws): пакет документов сервиса уведомлений — приёмки NTF-1..4, замысел, маршрут"
aliases:
  - issue-880-ws
ticket_id: 880
category: kac
status: in-progress
type: docs
repos:
  - kacho-workspace
areas:
  - docs/specs
  - docs/specs/reviews
  - docs/changes
prs: []
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/880
opened: 2026-09-29
tags:
  - kac
  - docs
---

# #880 (ws): пакет документов сервиса уведомлений

**Type**: docs · **Роль исполнителя**: acceptance-author / tooling-maintainer

**Состояние на момент записи**: in-progress — ветка воркспейса `issue-880` (ветка: координата,
не ссылка) заведена от ствола `6eddaa5e`, на origin её ещё нет; PR не открыт.

**Эпик**: [[KAC/issue-2914]] — PRO-Robotech/kacho#2914.

**Чем сверено**: `gh issue view 880 -R PRO-Robotech/kacho-workspace` и `gh issue view` по
каждой задаче из таблицы ниже (2026-09-30); `git merge-base --is-ancestor HEAD origin/main`
для ветки.

## Что и зачем

У под-фаз NTF-1..NTF-4 эпика нет ни одной приёмки, поэтому все кодинг-задачи эпика открыты с
меткой `blocked` — код не пишется без APPROVED приёмки (ban #1). Эта задача пишет пакет
документов, который снимает блок:

- четыре приёмки `docs/specs/sub-phase-NTF-<k>-…-acceptance.md` (NTF-1 включает раздел NS —
  политику выпуска сертификатов служб);
- замысел `design.md` и маршрут `tasks.md` пакета изменения в `docs/changes/<id>/`;
- пробелы, найденные критиком полноты, закрываются сценариями Given-When-Then в приёмке своей
  под-фазы; требование к подписке служебного подписчика формулируется в NTF-1.

Решения эпика здесь не пересказываются — они в теле эпика и в [[KAC/issue-2914]].

## Затронутые сущности vault

Пока нет: пакет документов не меняет ни ресурсов, ни RPC, ни рёбер дерева. Рёбра notify
появятся в записках `edges/` с посадкой NTF-1 (задача правил — PRO-Robotech/kacho-workspace#881).

## DoD

- [ ] приёмки NTF-1..4 существуют и имеют вердикт APPROVED записью ревью
      `docs/specs/reviews/<имя-приёмки>/<sha256>.yaml`, чей `subject.sha256` равен хешу файла;
- [ ] каждая строка Scope несёт сценарий (`scripts/docs-gate/check-03-scope-row-scenario.py` — код 0);
- [ ] замысел и маршрут пакета изменения записаны;
- [ ] PR ветки влит в `main` воркспейса.

## Связанные задачи

- эпик — PRO-Robotech/kacho#2914 → [[KAC/issue-2914]] (там же перечень под-фаз);
- правила — PRO-Robotech/kacho-workspace#881.

## History

- 2026-09-30 — trail заведён; состояние in-progress, PR нет.

#kac #docs
