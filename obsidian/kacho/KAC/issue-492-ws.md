---
title: "ws#492: фикстура вердикта артефакта заведена, правила у неё ещё нет"
aliases:
  - issue-492-ws
ticket_id: 492
category: kac
status: done
type: test
repos:
  - kacho-workspace
areas:
  - scripts/change-graph-gate/tests
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/492
opened: 2026-09-03
tags:
  - kac
  - testing
verified_against: "kacho-workspace@sdd/n1-fixtures: `run_case.py --case SDD-1-AUTH-09` → HARNESS · exit 40 (испытуемый: CG_SELF_WORLD_FACT_UNREAD, факт `artifact.verdict`); `selftest/prove.py` → FAIL B: ждали 'RED · CG_REVIEW_VERDICT_MISMATCH · exit 10', имеем '(без вывода)' (код 40), совпало 194 из 195"
---

# ws#492: фикстура вердикта артефакта заведена, правила у неё ещё нет

**Type**: test

**Состояние на момент записи**: падающий тест до кода написан и прогнан; правило
семейства `cg.auth` пишет следующая полоса — 2026-09-03.

## Что и зачем

Ряд `SDD-1-AUTH-09` объявлен приёмкой (§13 и §14), а фикстуры не имел: матрица клала
его в третью категорию — `HARNESS · HARNESS_FIXTURE_MISSING · exit 40`, то есть вердикта
не выдавала вовсе. Фикстура заведена; теперь кейс исполняется и **краснеет по нужной
причине** — правила о вердикте в семействе `cg.auth` нет, и испытуемый говорит это сам.

Дельта относительно положительного twin `SDD-1-AUTH-01` — **один факт**, и он
пересчитывается драйвером независимо: `add artifact.verdict = CHANGES_REQUESTED` при
сохранённом `event.verdict = APPROVED`.

## Почему лист заведён у кейса, а НЕ в базовом мире twin'а

Это решение, а не удобство, и цена его измерена.

Испытуемый отказывается судить мир, в котором есть факт, объявленный координатой его
семейства и не прочитанный ни одним правилом (`CG_SELF_WORLD_FACT_UNREAD`, exit 40 —
вердикт НЕ выносится). Правила о вердикте в `cg.auth` сегодня семь и ни одного о нём,
поэтому лист в базовом мире `SDD-1-AUTH-01` погасил бы **восемь** соседних кейсов вместе
с положительным twin'ом.

| где заведён лист | поломок harness в `run_matrix.py final` |
|---|---:|
| базовый мир `SDD-1-AUTH-01` | **9** |
| только `SDD-1-AUTH-09` (выбрано) | **1** |

Второй довод сильнее первого: **выбор места — это выбор стороны в споре, который ведёт
сама эта задача.** §4 и §7 приёмки перечисляют вердикт среди содержимого артефакта, §13
у `SDD-1-AUTH-01` — нет. Лист в базовом мире означал бы «§13 догоняет §4», то есть
решение, принятое фикстурой вместо приёмки. Фикстура дословно следует §13 и стороны не
занимает.

## Перемер предиката задачи на этой ветке

```sh
python3 - <<'PY'
import glob, os, yaml
post, with_verdict, event_verdict = [], [], []
for path in sorted(glob.glob("scripts/change-graph-gate/tests/testdata/*/world.yaml")):
    world = yaml.safe_load(open(path, encoding="utf-8")) or {}
    case = os.path.basename(os.path.dirname(path))
    if world.get("epoch") == "post-cutover":
        post.append(case)
        artifact = world.get("artifact")
        if isinstance(artifact, dict) and "verdict" in artifact:
            with_verdict.append(case)
    event = world.get("event")
    if isinstance(event, dict) and "verdict" in event:
        event_verdict.append(case)
print(len(post), len(with_verdict), with_verdict, len(event_verdict))
PY
# было (тело задачи, ствол 94331c8): post-cutover 8 · у артефакта verdict 0 · у события 21
# стало (эта ветка):                 post-cutover 9 · у артефакта verdict 1 ['SDD-1-AUTH-09'] · у события 22
```

Посылка задачи **подтверждена**: сравнивать было нечему, потому что координаты у
артефакта post-cutover не существовало ни в одном мире. Теперь она есть ровно у того
кейса, ради которого заведена.

## Что снимет красноту — и чего делать НЕ надо

Правило `cg.auth`, читающее `artifact.verdict` и сравнивающее его с `event.verdict`.
Тогда факт становится прочитанным, тройка выдаётся, и обе красноты (матрица и
`selftest/prove.py`) уходят **без правки фикстуры**.

Отвергнуто, замер сделан: перенести лист на верхний уровень мира (`artifact_verdict`).
Испытуемый относит такой факт к «вне предмета семейства (судит другое семейство)» и
отвечает `GREEN · CG_OK · exit 0` — поломка превращается в расхождение, и предикат волны
формально сходится. Но ни одно другое семейство этот факт не судит: мир утверждал бы о
себе неправду, а правило пришлось бы писать против координаты, которой у артефакта не
объявляет ни §4, ни §7, ни §13.

## Затронутые сущности vault

- [[lessons/checks-with-form-but-no-substance]] — вердикт, читаемый на непустоту и ни с
  чем не сравниваемый, выглядит учтённым.
- [[lessons/absence-of-finding-versus-absence-of-inspection]] — до фикстуры кейс не
  давал вердикта вовсе, и это было неотличимо от «проверено».

## Acceptance / Definition of Done

- [x] фикстура предъявлена в дереве: `scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-09/`
- [x] дельта относительно twin равна одному объявленному факту (пересчитана драйвером)
- [x] падающий тест прогнан ДО кода и падает по нужной причине (`CG_SELF_WORLD_FACT_UNREAD`, факт назван)
- [ ] правило `cg.auth` о вердикте заведено; `run_matrix.py final` — поломок harness 0
- [ ] `selftest/prove.py` — 195 из 195 по секции B

## Связанные тикеты

- [[issue-494-ws]] — вторая фикстура той же полосы

#kac
