---
title: "Change Graph: контур изменения — координаты и состояние"
aliases:
  - change-graph-contour
  - контур изменения
  - Change Graph
category: docs
status: in-progress
verified_against: "kacho-workspace@56935d4d (origin/main, 2026-09-03): координаты и числа сняты `git ls-tree -r origin/main`; предикат каждого стоит рядом с ним. Число провязок хуков перемерено на release/sdd-closeout 2026-09-03 (`grep -c 'hooks/.*\\.sh' .claude/settings.json` → 8, различных скриптов 7). Тексты приёмки и модуля правил построчно не пересматривались; границу машинного суждения и режим полномочия записка не излагает, а адресует §2 и §4 приёмки"
related_kac:
  - "[[KAC/issue-504-ws]]"
  - "[[KAC/issue-485]]"
  - "[[KAC/issue-486]]"
  - "[[KAC/issue-488-ws]]"
  - "[[KAC/issue-493]]"
related_lessons:
  - "[[lessons/checks-with-form-but-no-substance]]"
  - "[[lessons/one-diagnostic-many-worlds-lanes-diverge-invisibly]]"
  - "[[lessons/proof-runner-crashed-and-silence-looked-like-cost]]"
tags:
  - docs
  - architecture
---

# Change Graph: контур изменения — координаты и состояние

Контур связывает шесть предметов одного изменения — наблюдаемое поведение, технический
замысел, маршрут исполнения, свидетельство, фактический дифф и посаженное содержимое —
машинно проверяемыми связями. Нового процесса поверх существующего он не заводит: приёмка
до кода, строгий TDD, профильные ревью и посадка уже действуют, а контур делает так, чтобы
между ними нельзя было пройти молча.

Задача — [PRO-Robotech/kacho-workspace#480](https://github.com/PRO-Robotech/kacho-workspace/issues/480)
(Issue #480 владеет «зачем», приоритетом и живым состоянием).

> [!important] Эта записка — КАРТА, а не норма и не приёмка
> Норму для инженера держит `.claude/rules/change-graph.md` (`@import` в каждую сессию);
> наблюдаемое поведение и перечень кейсов — приёмка
> `docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`; что меняется в главе о
> процессе — `docs/specs/04-roadmap-and-phasing.md` §2.7. Здесь их содержание **не
> пересказывается**: четыре места об одном предмете разошлись бы молча.
>
> Здесь то, чего нет ни в одном из трёх: **где что лежит сегодня, в каком это состоянии и
> из каких задач выросло**.

## Где что лежит

| предмет | координата | предикат |
|---|---|---|
| приёмка контура | `docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` | `ls docs/specs/sub-phase-SDD-1-*.md` |
| bootstrap-записи ревью | `docs/specs/reviews/` | `git ls-tree -r origin/main --name-only \| grep -c 'docs/specs/reviews/'` → **2** |
| замысел | `docs/superpowers/specs/2026-09-02-kacho-change-graph-design.md` | тот же обход по имени |
| корень доверия и cutover | `docs/changes/policy.yaml` + `docs/changes/policy.schema.json` | `git ls-tree -r origin/main --name-only -- docs/changes/` |
| перепись legacy | `docs/changes/census/` | там же |
| испытуемый и его матрица | `scripts/change-graph-gate/` | `git ls-tree -r origin/main --name-only -- scripts/change-graph-gate/ \| wc -l` → **1097** файлов |
| владение производным оснастки | `.claude/adapters.yaml` | `ls .claude/adapters.yaml` |
| модуль правил | `.claude/rules/change-graph.md` | `git grep -c change-graph CLAUDE.md` |

**Пакетов изменения `docs/changes/<change-id>/` в дереве ноль** — первый заводится первым
изменением, идущим по контуру. Предикат:
`ls -d docs/changes/*/ 2>/dev/null | grep -v census` → пусто.

## Состояние на ревизии записки

- **приёмка** несёт статическую форму `DRAFT`; действующее одобрение живёт во внешнем
  событии и добавляемой записи, а не в слове заголовка — на отпечаток `47f5f98f…` запись
  ревью в дереве есть;
- **первичный разбор классов риска** привязан к тому же отпечатку приёмки и перечисляет
  **22** пункта (`CGX-01`…`CGX-22`); замысел отображает **все 22** — предикат:
  `grep -oE 'CGX-[0-9]+' <замысел> | sort -u | wc -l`;
- **пересверки разбора на отпечаток замысла в дереве НЕТ**, и это остаток, а не упущение
  записки: такая запись требует внешнего проверенного события и инженером не пишется.
  Предикат: `ls docs/specs/reviews/*class-exposure*/revalidation/ 2>/dev/null` → путь не
  существует. **Каким режимом полномочия она выпускается, эта записка не решает и не
  подразумевает**: режим задаёт **§4 приёмки**, и эпоха там объявлена **выводимой**
  координатой — её задаёт предок базы изменения относительно `cutover_commit` своего
  репозитория из `docs/changes/policy.yaml` (§8), а не имя ветки, не дата и не поле в самой
  записи. Предикат эпохи:
  `git merge-base --is-ancestor <cutover_commit своего repo> <база изменения>`. Про остатки
  самого SDD-1 §4 говорит отдельной фразой — читать её надо там, здесь она не
  воспроизводится;
- **обязательность контура начинается с cutover, не раньше** — до него работа идёт прежним
  укладом (`.claude/rules/git-issues.md`, `.claude/rules/multi-agent-flow.md`). Читать это
  надо из `docs/changes/policy.yaml`, а не из даты записки.

## Чем контур держится

- **испытуемый** — `scripts/change-graph-gate/`: **33** семейства правил
  (`git ls-tree -r origin/main --name-only -- scripts/change-graph-gate/cglib/families/ | grep -vc __init__`)
  и **196** кейсов с фикстурами
  (`git ls-tree -r origin/main --name-only -- scripts/change-graph-gate/tests/testdata/ | awk -F/ '{print $5}' | sort -u | wc -l`);
- **провязка** — набор `scripts/change-graph-gate/run-all.sh` зовётся хуком отправки вместе
  с остальными наборами воркспейса (их **6**: `git ls-files 'scripts/*/run-all.sh' | wc -l`)
  и отдельным заданием конвейера; кто и откуда его зовёт — [[KAC/issue-504-ws]];
- **производное оснастки** — `scripts/adapter-gate/run-all.sh` сверяет отслеживаемый выход с
  регенерацией побайтово; владение объявлено в `.claude/adapters.yaml`;
- **напоминание в момент правки** — хук `change-graph-reminder.sh` (`PostToolUse`), одна из
  **8** провязок `.claude/settings.json` (`grep -c 'hooks/.*\.sh' .claude/settings.json` → 8;
  то же число называет `.claude/rules/multi-agent-flow.md` §8). Единица здесь — **провязка,
  а не скрипт**: различных скриптов **7**
  (`grep -o '\.claude/hooks/[a-z-]*\.sh' .claude/settings.json | sort -u | wc -l`), потому
  что `docfresh.sh` провязан дважды. По порядку в файле этот вызов **шестой** — порядковым
  числительным «восьмой» его называть нельзя ни при какой из двух единиц.

## Чего контур НЕ судит

Границу между машинным и человеческим суждением задаёт **§2 приёмки** («Truth ownership»);
здесь она **не пересказывается** — иначе записка становится тем самым вторым местом об одном
предмете, от которого отгораживается врезкой выше.

Записка отвечает за другое, и это её собственный предмет: эта граница — **свойство по
построению, а не остаток работ**, поэтому в перечне состояния выше её нет намеренно, и в
число незакрытого её вносить нельзя. Класс, которым такую границу путают с недоделкой, —
[[lessons/checks-with-form-but-no-substance]].

## Из каких задач вырос

Контур собирался волнами, и уроки этих волн лежат отдельными записками — здесь только
адреса, содержание там:

| задача | предмет |
|---|---|
| [[KAC/issue-504-ws]] | оснастку контура не звал ни хук, ни конвейер |
| [[KAC/issue-485]] | предмет пробы, исчезнувший вместе с посаженным семейством |
| [[KAC/issue-486]], [[KAC/issue-493]] | правки самого испытуемого |
| [[KAC/issue-488-ws]] | семейство выводится из идентификатора кейса |

Классы дефектов, найденные по дороге: [[lessons/one-diagnostic-many-worlds-lanes-diverge-invisibly]]
(одна диагностика на много миров — полосы расходятся невидимо) и
[[lessons/proof-runner-crashed-and-silence-looked-like-cost]] (прогонщик доказательств упал,
и молчание выглядело как цена).

#docs #architecture
