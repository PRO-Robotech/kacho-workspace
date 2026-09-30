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

**Состояние на момент записи (2026-09-30)**: in-progress — **не влито**. Ветка воркспейса
`issue-880` (ветка: координата, не ссылка) — 34 коммита от ствола `6eddaa5e`, голова `ca5f5e78`;
на origin её нет, PR не открыт, sha вливания нет. Посадка остановлена вердиктом ⛔
landing-reviewer на голове `ca5f5e78`: ни одна приёмка не одобрена, в записях ревью остались
места против гигиены публичного текста, в приёмке NTF-5 — имена чужих облаков.

**Эпик**: [[KAC/issue-2914]] — PRO-Robotech/kacho#2914.

**Чем сверено**: `gh issue view 880 -R PRO-Robotech/kacho-workspace` и `gh issue view` по
каждой задаче из таблицы ниже (2026-09-30); `git merge-base --is-ancestor HEAD origin/main`
для ветки.

## Что и зачем

У под-фаз NTF-1..NTF-4 эпика нет ни одной приёмки, поэтому все кодинг-задачи эпика открыты с
меткой `blocked` — код не пишется без APPROVED приёмки (ban #1). Эта задача пишет пакет
документов, который снимает блок:

- шесть приёмок `docs/specs/sub-phase-NTF-<k>-…-acceptance.md` (NTF-1 включает раздел NS —
  политику выпуска сертификатов служб; NTF-5 и NTF-6 добавлены задачами
  PRO-Robotech/kacho#2924 и PRO-Robotech/kacho#2925);
- замысел `design.md` и маршрут `tasks.md` пакета изменения в `docs/changes/<id>/`;
- пробелы, найденные критиком полноты, закрываются сценариями Given-When-Then в приёмке своей
  под-фазы; требование к подписке служебного подписчика формулируется в NTF-1.

Решения эпика здесь не пересказываются — они в теле эпика и в [[KAC/issue-2914]].

## Приёмки и их вердикт

Вердикт сверен отпечатком: sha256 файла приёмки против записи ревью на этот отпечаток
`docs/specs/reviews/<имя-приёмки>/<sha256>.yaml`, @`ca5f5e78`.

| под-фаза | приёмка | отпечаток | вердикт | шапка |
|---|---|---|---|---|
| NTF-1 | `docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` | `a6cb0c1f…` | CHANGES_REQUESTED | DRAFT |
| NTF-2 | `docs/specs/sub-phase-NTF-2-identity-provider-mail-removal-acceptance.md` | `33e199c9…` | CHANGES_REQUESTED | DRAFT |
| NTF-3 | `docs/specs/sub-phase-NTF-3-kacho-modules-notifications-acceptance.md` | `52ef8689…` | CHANGES_REQUESTED | DRAFT |
| NTF-4 | `docs/specs/sub-phase-NTF-4-delivery-feedback-reputation-acceptance.md` | `97046469…` | CHANGES_REQUESTED | DRAFT |
| NTF-5 | `docs/specs/sub-phase-NTF-5-operator-notices-acceptance.md` | `47ac6f8b…` | CHANGES_REQUESTED | DRAFT |
| NTF-6 | `docs/specs/sub-phase-NTF-6-console-notification-center-acceptance.md` | `7a50855c…` | CHANGES_REQUESTED | DRAFT |

Одобренных приёмок: 0 из 6.

Пакеты изменения: `docs/changes/issue-{2915,2917,2918,2919,2924,2925}/` — в каждом
`change.yaml`, `holders.yaml`, `evidence/`. Файлов `design.md` и `tasks.md` в дельте ветки нет
(`git diff --name-only origin/main...HEAD | grep -E 'design\.md|tasks\.md'` — 0 строк); пункт DoD
о замысле и маршруте не выполнен.

## Затронутые сущности vault

Пока нет: пакет документов не меняет ни ресурсов, ни RPC, ни рёбер дерева. Рёбра notify
появятся в записках `edges/` с посадкой NTF-1 (задача правил — PRO-Robotech/kacho-workspace#881).

## DoD

- [ ] приёмки NTF-1..6 существуют и имеют вердикт APPROVED записью ревью
      `docs/specs/reviews/<имя-приёмки>/<sha256>.yaml`, чей `subject.sha256` равен хешу файла;
- [ ] каждая строка Scope несёт сценарий (`scripts/docs-gate/check-03-scope-row-scenario.py` — код 0);
- [ ] замысел и маршрут пакета изменения записаны (`design.md`, `tasks.md` — в дельте нет);
- [ ] PR ветки влит в `main` воркспейса.

## Связанные задачи

- эпик — PRO-Robotech/kacho#2914 → [[KAC/issue-2914]] (там же перечень под-фаз);
- правила — PRO-Robotech/kacho-workspace#881;
- NTF-5 — PRO-Robotech/kacho#2924; NTF-6 — PRO-Robotech/kacho#2925 (обе open, blocked).

## History

- 2026-09-30 — trail заведён; состояние in-progress, PR нет.
- 2026-09-30 — итог захода посадки: не влито, PR нет, ветки на origin нет; голова `ca5f5e78`,
  вердикт landing-reviewer ⛔; приёмки NTF-1..6 — все CHANGES_REQUESTED, DRAFT; добавлены
  задачи NTF-5 (#2924) и NTF-6 (#2925).

#kac #docs
