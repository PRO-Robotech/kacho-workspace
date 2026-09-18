---
title: "ws#666: проекция оснастки для чужих агентских сред снята целиком"
aliases:
  - issue-666-ws
  - снятие проекции codex
ticket_id: 666
category: kac
status: test
type: refactor
repos:
  - kacho-workspace
areas:
  - tooling
  - rules
  - docs/specs
prs:
  - PRO-Robotech/kacho-workspace#667
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/666
opened: 2026-09-18
tags:
  - kac
  - conventions
  - architecture
verified_against: "kacho-workspace@b3f75bfc (origin/main, 2026-09-18) против ветки 239afde6: числа сняты `git ls-tree -r <ревизия> --name-only` и `gh pr view 667`; промежуток ban #1 воспроизведён в отдельной копии (приёмка с `cbbe7603`, код со ствола) и откачен с доказательством — `git status --porcelain` пуст. Содержание приёмки SDD-1 построчно не пересматривалось: её вердикт выносил `acceptance-reviewer`, запись `57a17bee….yaml`"
---

# ws#666: проекция оснастки для чужих агентских сред снята целиком

**Состояние на момент записи**: `test`. PR [#667](https://github.com/PRO-Robotech/kacho-workspace/pull/667)
**открыт**, база `main`, `mergedAt` пуст (`gh pr view 667 --json state,baseRefName,mergedAt`).
До вливания в ствол статус не `done`.

## Что и зачем

Решение владельца 2026-09-18, дословно: **«удали все от codex и все что туда относится»**.

Отменяется устройство, при котором из единственной оснастки `.claude/` порождалась
**проекция** для сред, читающих `AGENTS.md`, `.agents/skills/` и `.codex/`: оснастка была
входом, проекция — отслеживаемым выходом, владение объявлял манифест, а сходимость выхода с
регенерацией держал собственный набор проверок.

Предмет снятия — **контур целиком**, а не каталог: вход, манифест владения, генератор,
отслеживаемый выход, сверяющий набор, держатель в ведомости пакета изменения, обещание
перегенерации в правилах и строка в конвейере. Класс и его признак —
[[lessons/derived-output-is-retired-by-its-contour-not-its-directory]].

## Что снято и что правлено — две единицы счёта, обе названы

| единица | число | предикат |
|---|---:|---|
| снятых файлов | **74** | `git diff --name-status origin/main 239afde6 \| awk '$1=="D"' \| wc -l` |
| из них `.codex/` | 43 | `git ls-tree -r origin/main --name-only -- .codex \| wc -l` |
| из них `.agents/` | 15 | то же по `.agents` |
| из них `scripts/adapter-gate/` | 12 | то же по каталогу |
| поимённо | 4 | `AGENTS.md` · `.claude/adapters.yaml` · `scripts/adapter/generate.py` · `scripts/change-graph-gate/check-04-canonical-inputs-match-manifest.sh` |
| правленых файлов | **21** | `git diff --name-status origin/main 239afde6 \| awk '$1=="M"' \| wc -l` |
| из них оснастка (правила, агенты, хуки, скрипты) | 19 | остаток перечня |
| из них не оснастка | 2 | `.gitignore` и `.github/workflows/ci.yaml` |

Последняя строка — не педантизм: «правлен 21 файл оснастки» было бы заявлением шире
сделанного, а «правлено 19» умолчало бы о конвейере и об исключениях git.

**Предикат готовности снятия** (первый комментарий задачи, воспроизведён здесь):

```sh
git ls-tree -r <ревизия> --name-only \
  | grep -cE '^\.codex/|^\.agents/|^AGENTS\.md$|^\.claude/adapters\.yaml$|^scripts/adapter/|^scripts/adapter-gate/'
# origin/main b3f75bfc → 73 · ветка 239afde6 → 0
```

73, а не 74: снятый `check-04` живёт в каталоге контура и под этот образец не подпадает —
единица предиката уже единицы снятия, и это надо знать, сверяя числа.

## Ведомость держателей: 23 → 22, и снятие обязательно

Пакет изменения `docs/changes/standalone-iam/holders.yaml` называет **точное** множество
держателей. Держатель `ws-adapter-gate` снят: его `executable` —
`./scripts/adapter-gate/run-all.sh` — после снятия отвечает кодом **127**, то есть давал бы
**«не выполнилось» навсегда**, а предикат готовности пакета становился бы недостижим
*by construction*.

```sh
git show <ревизия>:docs/changes/standalone-iam/holders.yaml \
  | python3 -c "import sys,yaml;print(len(yaml.safe_load(sys.stdin)['required_holders']))"
# origin/main → 23 · 239afde6 → 22
```

Это тот же класс, что «исключение, которому нечего исключать»: запись точного множества без
предмета не истекает сама и молча делает вердикт недостижимым.

## Числа воркспейса, сдвинутые снятием

| величина | ствол `b3f75bfc` | ветка `239afde6` | предикат |
|---|---:|---:|---|
| проверок воркспейса | **45** | **37** | `git ls-tree -r <рев> --name-only \| grep -cE '^scripts/[^/]+/check-[^/]+\.(sh\|py)$'` |
| наборов `run-all.sh` | 8 | 7 | тот же обход по `run-all\.sh$` |
| планов свидетельства пакета | 23 | 23 | `git ls-tree -r <рев> --name-only -- docs/changes/standalone-iam/evidence/ \| awk -F/ '{print $5}' \| sort -u \| wc -l` |

**Объявленное число проверок было просрочено и ДО этой работы**: правило называло 43, ствол
давал 45. Правка довела объявление до 37 — то есть закрыла сразу две вещи, и вторая к
предмету задачи отношения не имеет. Названо, чтобы «43 → 37» не читалось как «сняли шесть».

Третья строка — остаток: планов свидетельства 23 при 22 держателях, потому что
`evidence/ws-adapter-gate/` снят намеренно **не** этой полосой (он запись о намерении, а не
наблюдение). Предмет —
[ws#668](https://github.com/PRO-Robotech/kacho-workspace/issues/668).

## Промежуток между приёмкой и кодом — ban #1 изнутри

Редакция приёмки SDD-1 («семейство `ADAPTER` снято вместе с предметом») идёт **отдельной**
полосой. Пока код семейства `cg.adapter` в дереве, а приёмка его диагностик больше не
объявляет, набор `change-graph-gate` красен. Воспроизведено мной в отдельной копии:

```
change-graph-gate: рассмотрено проверок 4; пройдено 3, провалено 1, без предмета 0   → код 1
  FAIL I1 каждая диагностика правил стоит в ОБЪЯВЛЯЮЩЕЙ ПОЗИЦИИ приёмки
  перепись сверки диагностик: диагностик правил 135 · диагностик приёмки 127 · мимо приёмки 9
контроль на чистом стволе: мимо приёмки 0 · утверждений 192, провалено 0
```

Класс и оба его направления — [[lessons/acceptance-retires-a-case-while-the-rule-still-produces-it]].
Следствие для посадки: редакция и снятие кода вливаются **вместе** либо снятие идёт
немедленно следом.

## Приёмка SDD-1 — два круга, вердикт APPROVED

Не мой предмет и здесь не пересказывается; координаты:

- отпечаток предмета `57a17beed851c4e27c1868fe95bd7cfcbbd2ab125cbd28587984c7370aca5bc7`,
  ревизия `cbbe7603`, запись
  `docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-acceptance/57a17bee….yaml`;
- круг 1 — `CHANGES_REQUESTED`, два блокирующих: снятие объявлено **в прошедшем времени**
  при живых координатах в дереве; третья категория подана зелёным. Круг 2 — оба закрыты;
- событие санкции — комментарий
  [#666 issuecomment-5727459724](https://github.com/PRO-Robotech/kacho-workspace/issues/666#issuecomment-5727459724),
  `effective_approval.issued: true` (коммит `163f8673`);
- кейсов приёмки **198 → 185**, тринадцать `SDD-1-ADAPTER-01…13` сняты **надгробиями**:
  номера сохранены, метки не переиспользуются. Предикат:
  `python3 scripts/change-graph-gate/tests/run_case.py --list | grep -cE '^SDD-1-'`.

## Что осталось незакрытым

| остаток | предмет |
|---|---|
| семейство `cg.adapter` и 13 фикстур `tests/testdata/SDD-1-ADAPTER-*` **в дереве обеих веток** | снимаются полосой кода; предикат конца промежутка — набор даёт код 0 и «мимо приёмки 0» |
| фикстура, которую приёмка больше не называет, **молчит** | [ws#672](https://github.com/PRO-Robotech/kacho-workspace/issues/672) |
| планов свидетельства 23 при 22 держателях | [ws#668](https://github.com/PRO-Robotech/kacho-workspace/issues/668) |
| `class-guard/prove.sh` красен на стволе | [ws#669](https://github.com/PRO-Robotech/kacho-workspace/issues/669), P1 |
| «8 провязок» хуков при фактических 10 | [ws#670](https://github.com/PRO-Robotech/kacho-workspace/issues/670) |
| `change-graph.md` §0 «пакетов нет» против своего же предиката | [ws#671](https://github.com/PRO-Robotech/kacho-workspace/issues/671) |

## Затронутые сущности vault

[[lessons/derived-output-is-retired-by-its-contour-not-its-directory]] ·
[[lessons/acceptance-retires-a-case-while-the-rule-still-produces-it]] ·
[[docs/change-graph-contour]] · [[KAC/issue-504-ws]] · [[KAC/issue-506-ws]]

## DoD

- [x] решение владельца записано дословно, без пересказа
- [x] числа снятия и правки перемерены своим предикатом, обе единицы счёта названы
- [x] ведомость держателей приведена к предмету (23 → 22), причина названа кодом 127
- [x] промежуток ban #1 воспроизведён и снят с контролем в обе стороны
- [x] класс записан двумя уроками, каждый со своим предметом
- [x] остатки заведены задачами ws#668–ws#672
- [ ] PR #667 влит в `main` — до вливания статус `test`
- [ ] семейство `cg.adapter` и 13 осиротевших фикстур сняты, набор даёт код 0

## Связанные задачи

ws#668 · ws#669 · ws#670 · ws#671 · ws#672 — все заведены этой работой; ws#671 и ws#670
к предмету снятия не относятся и попали в перечень как находки по дороге.

#kac #conventions #architecture
