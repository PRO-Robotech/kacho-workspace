#!/usr/bin/env python3
"""check-01 — `scripts/pr-body.sh <репо> <база> <голова>` выводит тело PR из git (ws#1146, прежде ws#930).

ЧТО УТВЕРЖДАЕТ. На подставном репозитории `PRO-Robotech/kaname` (ведомости долга этого
имени — из перечня `DEBT_LEDGERS`; клонов чужих ведомостей нет) и подставном трекере.
Диапазон: база `main` (на ней — коммит #42, вне диапазона), голова — ветка волны `50`,
куда первым родителем влиты полоса `41-a` и полоса `42-b`, а в `42-b` — вложенная `44-c`;
плюс коммит линии головы. Утверждения:
  * СОСТАВ — каждый коммит диапазона назван своим sha, по полосам: заголовок полосы —
    слияние первого родителя, вложенное слияние — уровнем ниже (отступ), коммит линии
    головы — в своём разделе;
  * НОМЕРА — каждый `#N` тела (выражение `NUM_RE`, оно же у landing-precheck) — номер
    первой строки коммита диапазона; номер из тела сообщения (#47), из `kaname#48` и из
    второй строки первого абзаца (#49, `%s` git склеил бы её с первой) идёт без `#`;
    `#99` из заголовка задачи — `№99`; задача своего репозитория, названная в первой строке
    полной формой (`kaname#52`, `PRO-Robotech/kaname#53`), — задача, и пишется полной формой;
    `otherorg/kaname#77` — чужой владелец, не задача (ни строки, ни Closes, ни в упомянутых);
    ДОГОН базы — по структуре (слияние, сторонний родитель достижим из базы), не по тексту:
    строки `DOGON` (четыре формы перечня, `#main`, «слияние», «догон», догон базы-эпика
    `3172-epic`, своя #59 лишь в префиксе) — номер базы ни задача, ни упомянутая, в теле его
    нет, в составе он с `№`; #59 из префикса — задача (T8); близнецы — слияние соседней полосы
    с непустой ветвью (#57) и коммит-не-слияние «merge main» (#67, T7) — номера остаются;
  * CLOSES — #41: доказательство DoD ревизией диапазона (близнец: та же задача упомянута
    ведомостью прозой, не формой держателя, — Closes остаётся); #42: доказательство ревизией
    БАЗЫ (предок головы, но не коммит диапазона) — Refs; #44: ревизия, которой нет, — Refs;
    #45: держит запись `newman-suite-debt.py` (`PRO-Robotech/kaname#45 — …`) при годном
    доказательстве — Refs; #46: держит объявление RESULTS.md — Refs; #43 закрыта — Refs (и при
    доказательстве диапазона);
    #50 без доказательства — Refs; доказательство #50 на предке головы с тем же деревом (голова —
    слияние ствола) — Closes, как у merge-readiness и landing-precheck (замер на kaname#876); kaname#52 с доказательством диапазона — Closes полной
    формой, kaname#53 без него — Refs полной формой; закрытой #43 доказательство диапазона Closes не даёт; #51 — запрос, в задачи не идёт;
  * ХВОСТ — закрывающие строки последними, Refs перед ними, хвост сплошной;
  * распознаватель доказательства общий (`dod_proof.jq`): `@main`, `@abc12`, `@develop`,
    `abc1234` без `@` и маркер посреди прозы — не доказательства; полный sha — доказательство;
    из нескольких доказательств диапазона названо последнее; доказательство 101-м
    комментарием (вторая страница) находится;
  * атрибуция в коммите — отказ (код 1), sha назван; в заголовке задачи — отказ «в собранном
    теле»; близнец — слово в середине прозы — тело собрано;
  * ССЫЛКА НА ЗАДАЧУ — одно правило (ws#1155): `task_ref_re` (держатель записи долга) и
    `issue_refs` (номера задач текста) исполняются НАСТОЯЩИМИ функциями ритуала на одной
    таблице строк и обязаны совпасть с ожидаемым и друг с другом: своя полная, краткая и
    адресная формы (и владелец в нижнем регистре) — ссылка; `<чужая организация>/kacho#5`
    (любым регистром, через `-`, однобуквенная) и адрес чужого владельца — нет; мусор
    (`x.kacho#5`, `kacho#55`, `kacho-workspace#5`, `#5a`) — нет; голый `#5` — ссылка лишь в
    ведомости своего репозитория. Поведением: строка ведомости `otherorg/kaname#41 — …`
    держателем #41 не делает — Closes #41 остаётся;
  * НОМЕР ДРУГОГО РЕПОЗИТОРИЯ (ws#1164, голова `50-cross`): номера первой строки нет в
    репозитории запроса (трекер — 404 настоящей формы) — он ищется в прочих репозиториях
    владельца из ведомости стволов `scripts/ci-read-expected.tsv` дерева: #3274 найдена в
    одном (`PRO-Robotech/kacho`) — строкой и `Refs` полной формой, а не `Closes`, хотя
    доказательство у неё в диапазоне (закрывает её каскад своего репозитория); #3275 — в двух,
    #3276 — ни в одном: строкой «без задачи» без `#`, ни Refs, ни Closes; `kaname#3277` полной
    формой своего репозитория, которого нет, — «без задачи», в других не ищется; отказ чтения
    кандидата (не 404) — код 2, а не «нет нигде»;
  * не выполнилось (код 2): задача не прочитана; диапазон пуст; ревизии нет; ведомость
    долга своего репозитория снята с головы; форма вызова не та.
Каждый отказ судится по коду И по причине: красное от соседнего отказа пробу не проходит.
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет (git, подпись, PyYAML).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

R = "PRO-Robotech/kaname"
# Выражение номера — то же, что `NUM` пункта (в) landing-precheck и `NUM_RE` ритуала.
NUM = re.compile(r"(?<![\w/#])#([0-9]+)\b")
LEDGER = ('DEBT = {\n    "suite-a": ("B", "довод", "PRO-Robotech/kaname#45 — прогонит набор"),\n'
          '    "suite-b": ("B", "довод", "otherorg/kaname#41 — задача чужого владельца"),\n}\n'
          "# история: kaname#41 упомянута прозой, не держит ничего\n")
RESULTS = "# Newman results\n\n<!-- known-failing: #46 — кейс красен до починки -->\n"


def issue(n, state="open", pr=False, title=None):
    it = {"number": n, "id": 7000 + n, "title": title or "задача %d" % n, "state": state,
          "html_url": "https://github.com/%s/issues/%d" % (R, n)}
    if pr:
        it["pull_request"] = {"url": "x"}
    return it


def comment(n, i, text):
    return {"id": i, "body": text, "html_url": "https://github.com/%s/issues/%d#issuecomment-%d" % (R, n, i)}


def tail_of(out):
    """Хвост закрывающих строк: последние подряд строки Refs/Closes."""
    lines = out.rstrip("\n").splitlines()
    t = []
    for ln in reversed(lines):
        if re.match(r"^(Refs|Closes) ([\w.-]+/[\w.-]+)?#\d+$", ln):
            t.append(ln)
        else:
            break
    return list(reversed(t))


def closes(out):
    return [ln for ln in out.splitlines() if ln.startswith("Closes ")]


def seed(pr):
    """Репозиторий-диапазон; возвращает каталог и sha по ролям."""
    d = pr.repo("repo", {"f.txt": "0\n", ".github/scripts/newman-suite-debt.py": LEDGER,
                         "tests/newman/docs/RESULTS.md": RESULTS})
    sha = {"base42": pr.commit(d, "#42 правка, уже влитая в базу")}
    pr.git(d, "checkout", "-qb", "41-a", "main")
    sha["41a"] = pr.commit(d, "#41 первая правка", rel="a.txt")
    sha["41b"] = pr.commit(d, "#41 вторая правка (kaname#52)\nпродолжение абзаца про #49\n\nтело называет #47 и kaname#48",
                           rel="a.txt")
    pr.git(d, "checkout", "-qb", "44-c", "main")
    sha["44"] = pr.commit(d, "#44 вложенная полоса (PRO-Robotech/kaname#53)", rel="c.txt")
    pr.git(d, "checkout", "-qb", "42-b", "main")
    sha["42"] = pr.commit(d, "#42 полоса после базы (#43)", rel="b.txt")
    sha["45"] = pr.commit(d, "#45 держатель записи долга", rel="b.txt")
    sha["46"] = pr.commit(d, "#46 кейс под объявлением (otherorg/kaname#77)", rel="b.txt")
    pr.git(d, "merge", "-q", "--no-ff", "44-c", "-m", "#42 merge #44: вложенная сборка")
    sha["m44"] = pr.git(d, "rev-parse", "HEAD").strip()
    pr.git(d, "checkout", "-qb", "50", "main")
    pr.git(d, "merge", "-q", "--no-ff", "41-a", "-m", "#50 merge #41: сборка")
    sha["m41"] = pr.git(d, "rev-parse", "HEAD").strip()
    pr.git(d, "merge", "-q", "--no-ff", "42-b", "-m", "#50 merge #42: сборка, запрос #51")
    sha["m42"] = pr.git(d, "rev-parse", "HEAD").strip()
    sha["50"] = pr.commit(d, "#50 правка линии головы", rel="h.txt")
    # Догон базы, как kaname 870 @9d692d7fe: слияние, сторонний родитель которого достижим из
    # базы, дерево не меняется. Признак — структура: формы строки ниже отличаются от
    # `merge main` одним фактом, две последние словесные — вне всякого перечня, `3172-epic` —
    # догон базы-эпика; #59 есть ТОЛЬКО в префиксе догона (T8).
    pr.git(d, "branch", "3172-epic", "main")
    pr.git(d, "checkout", "-qb", "50-dogon", "50")
    for key, n, msg in DOGON:
        m = pr.git(d, "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-p", "3172-epic" if n == 3259 else "main",
                   "-m", msg).strip()
        pr.git(d, "merge", "-q", "--ff-only", m)
        sha[key] = m
    # Близнецы на голове `50-twins`: слияние соседней полосы (ветвь второго родителя непуста)
    # и коммит-не-слияние со словами «merge main» — номера #57 и #67 остаются задачами.
    pr.git(d, "checkout", "-qb", "1147-autoland", "main")
    sha["side"] = pr.commit(d, "правка соседней полосы", rel="s.txt")
    pr.git(d, "checkout", "-qb", "50-twins", "50-dogon")
    pr.git(d, "merge", "-q", "--no-ff", "1147-autoland", "-m", "#50 merge 1147-autoland (#57)")
    sha["twin-merge"] = pr.git(d, "rev-parse", "HEAD").strip()
    sha["twin-t7"] = pr.commit(d, "#50 fix: не делать merge main (#67)", rel="h.txt")
    # Номера первых строк, которых нет в репозитории запроса (ws#1164): задача другого
    # репозитория владельца, номер двух репозиториев и номер ни одного.
    pr.git(d, "checkout", "-qb", "50-cross", "50")
    sha["x3274"] = pr.commit(d, "#3274 приёмка: задача другого репозитория", rel="x.txt")
    sha["x3275"] = pr.commit(d, "#3275 номер двух репозиториев", rel="x.txt")
    sha["x3276"] = pr.commit(d, "#3276 номер ни одного репозитория (PRO-Robotech/kaname#3277)", rel="x.txt")
    return d, sha


# Догоны базы на голове `50-dogon`: (ключ, номер базы в строке, строка).
DOGON = (
    ("dogon", 56, "#50 merge main: догон ствола (#56) перед PR"),
    ("dogon-origin", 60, "#50 merge origin/main: догон ствола (#60)"),
    ("dogon-git-branch", 61, "Merge branch 'main' into 50-dogon (#61)"),
    ("dogon-git-remote", 62, "Merge remote-tracking branch 'origin/main' into 50-dogon (#62)"),
    ("dogon-hash-main", 63, "#50 merge #main: догон ствола (#63)"),
    ("dogon-ru", 64, "#50 слияние origin/main (#64)"),
    ("dogon-word", 65, "#50 догон main (#65)"),
    ("dogon-epic", 3259, "#50 merge 3172-epic: догон базы-эпика (#3259)"),
    ("dogon-prefix-only", 66, "#59 merge main: догон ствола (#66)"),
)


def world(sha, c41=None, title41=None):
    issues = {n: issue(n) for n in (41, 42, 44, 45, 46, 50, 52, 53, 56, 57, 59, 67, 77)}
    issues[43] = issue(43, "closed")
    issues[51] = issue(51, pr=True)
    issues[41]["title"] = title41 or "задача 41 (после #99)"
    return {
        "issues": {"%s#%d" % (R, n): it for n, it in issues.items()},
        "comments": {
            "%s#41" % R: c41 if c41 is not None else [comment(41, 1, "DoD-proof @%s\nкоманда — код 0" % sha["41a"][:9])],
            "%s#42" % R: [comment(42, 2, "DoD-proof @%s\nкод 0" % sha["base42"][:9])],
            "%s#44" % R: [comment(44, 4, "DoD-proof @deadbee1\nкод 0")],
            "%s#45" % R: [comment(45, 5, "DoD-proof @%s\nкод 0" % sha["45"])],
            "%s#46" % R: [comment(46, 6, "DoD-proof @%s\nкод 0" % sha["46"][:12])],
            "%s#77" % R: [comment(77, 8, "DoD-proof @%s\nкод 0" % sha["46"][:9])],
            "%s#52" % R: [comment(52, 7, "DoD-proof @%s\nкод 0" % sha["41b"][:9])],
            "%s#43" % R: [comment(43, 3, "DoD-proof @%s\nкод 0" % sha["42"][:9])],
        },
    }


# Таблица правила ссылки (ws#1155): строка → ссылка ли она на задачу PRO-Robotech/kacho#5.
REF_TABLE = (
    ("PRO-Robotech/kacho#5", True), ("kacho#5", True), ("(kacho#5).", True), ("pro-robotech/kacho#5", True),
    ("https://github.com/PRO-Robotech/kacho/issues/5", True), ("https://github.com/pro-robotech/kacho/issues/5", True),
    ("OtherOrg/kacho#5", False), ("other-org/kacho#5", False), ("x/kacho#5", False), ("otherorg/KACHO#5", False),
    ("https://github.com/OtherOrg/kacho/issues/5", False), ("x.kacho#5", False), ("kacho#55", False),
    ("kacho-workspace#5", False), ("xkacho#5", False), ("PRO-Robotech/kacho#5a", False),
    ("x.github.com/PRO-Robotech/kacho/issues/5", False),
)
# Голый номер — ссылка лишь в тексте своего репозитория.
BARE_TABLE = (("#5", True), ("см. #5.", True), ("x#5", False), ("/#5", False), ("##5", False), ("#55", False))


def ref_rule(pr):
    """Обе функции ритуала — одним правилом на одной таблице (ws#1155)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("rituals_under_test", os.path.join(P.RIT, "rituals.py"))
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:  # noqa: BLE001 — ритуал не загрузился: предмета нет
        raise P.Void("rituals.py не загружается: %s" % e)
    trepo, other = "PRO-Robotech/kacho", "PRO-Robotech/kaname"
    for text, want in REF_TABLE:
        holder = re.search(mod.task_ref_re(trepo, 5, other), text) is not None
        refs = 5 in mod.issue_refs(trepo, text)
        pr.ok("ссылка «%s»: держатель %s, номер текста %s — ждали %s" % (text, holder, refs, want),
              holder is want and refs is want)
    for text, want in BARE_TABLE:
        own = re.search(mod.task_ref_re(trepo, 5, trepo), text) is not None
        refs = 5 in mod.issue_refs(trepo, text)
        foreign = re.search(mod.task_ref_re(trepo, 5, other), text) is not None
        pr.ok("голый «%s»: своя ведомость %s, номер текста %s — ждали %s; чужая ведомость %s — ждали False"
              % (text, own, refs, want, foreign), own is want and refs is want and not foreign)


def body(pr):
    ref_rule(pr)
    d, sha = seed(pr)
    extra = {"RITUAL_REPO_DIR": d, "RITUAL_LEDGER_CLONES": os.path.join(pr.tmp, "no-clones")}
    args = [R, "main", "50"]
    in_range = [s for k, s in sha.items() if k == "50" or not (k == "base42" or k.startswith(("dogon", "twin", "side", "x")))]

    rc, out, err, st = pr.run("pr-body", args, pr.state(world(sha)), extra=extra)
    pr.ok("законный вход: код 0", rc == 0, err)
    pr.ok("трекер не изменён", not P.writes(st), str(P.writes(st)))

    # состав
    pr.ok("каждый коммит диапазона назван sha (%d)" % len(in_range),
          all(("`%s`" % s[:9]) in out for s in in_range), out)
    pr.ok("коммит базы в составе не назван", ("`%s`" % sha["base42"][:9]) not in out, out)
    pr.ok("перепись состава: коммитов 10, полос 2, вне полос 1",
          "коммитов 10: полос (слияний первого родителя) 2, коммитов линии головы вне полос 1" in out, out)
    m = re.search(r"### Полоса 1 — `%s`.*?(?=### )" % sha["m41"][:9], out, re.S)
    pr.ok("полоса 1 — слияние #41 и оба коммита #41",
          bool(m) and ("`%s`" % sha["41a"][:9]) in m.group(0) and ("`%s`" % sha["41b"][:9]) in m.group(0), out)
    m = re.search(r"### Полоса 2 — `%s`.*?(?=### )" % sha["m42"][:9], out, re.S)
    pr.ok("полоса 2 — вложенное слияние #44 и его коммит уровнем ниже",
          bool(m) and ("- `%s`" % sha["m44"][:9]) in m.group(0) and ("\n  - `%s`" % sha["44"][:9]) in m.group(0), out)
    pr.ok("коммит линии головы — в своём разделе",
          re.search(r"### Линия головы вне полос\n\n- `%s`" % sha["50"][:9], out) is not None, out)

    # номера
    first = {"41", "42", "43", "44", "45", "46", "50", "51"}
    pr.ok("каждый #N тела — номер первой строки диапазона", set(NUM.findall(out)) <= first,
          str(sorted(set(NUM.findall(out)) - first)))
    pr.ok("#47, #48, #49 — строкой без #", "Упомянуты вне первых строк (без закрытия): 47, 48, 49" in out, out)
    pr.ok("заголовок задачи: #99 → №99", "№99" in out and "#99" not in out, out)
    pr.ok("запрос #51 — не задача", "Запросы в первых строках (не задачи): #51" in out
          and "«задача 51»" not in out, out)

    # закрытия
    pr.ok("закрывающие: #41 и полной формой kaname#52", closes(out) == ["Closes #41", "Closes %s#52" % R], out)
    pr.ok("Refs: #42 #43 #44 #45 #46 #50 и полной формой kaname#53",
          all(("Refs #%d" % n) in tail_of(out) for n in (42, 43, 44, 45, 46, 50))
          and ("Refs %s#53" % R) in tail_of(out), out)
    pr.ok("хвост: Refs, затем Closes последними, сплошь",
          tail_of(out)[-2:] == ["Closes #41", "Closes %s#52" % R] and len(tail_of(out)) == 9
          and all(x.startswith("Refs") for x in tail_of(out)[:-2]), out)
    # Чужой владелец: `otherorg/kaname#77` — не задача диапазона (у своей #77 есть
    # доказательство диапазона, так что засчитанная ошибочно, она дала бы Closes).
    pr.ok("otherorg/kaname#77 — не задача: ни строки, ни Closes, ни в упомянутых",
          "«задача 77»" not in out and not any("77" in x for x in tail_of(out))
          and "77" not in (re.search(r"Упомянуты вне первых строк[^\n]*", out) or [""])[0], out)
    pr.ok("задача первой строки в полной форме — строкой полной формы",
          ("- %s#52 «задача 52» — доказательство DoD" % R) in out
          and ("- %s#53 «задача 53» — доказательства DoD нет" % R) in out, out)
    pr.ok("#42: доказательство ревизией базы — не коммит диапазона",
          ("`DoD-proof @%s` не коммит диапазона" % sha["base42"][:9]) in out, out)
    pr.ok("#44: ревизии нет — не коммит диапазона", "`DoD-proof @deadbee1` не коммит диапазона" in out, out)
    pr.ok("#45: держатель newman-suite-debt.py, строка 2",
          "держит запись долга `kaname:.github/scripts/newman-suite-debt.py:2`" in out, out)
    pr.ok("#46: держатель RESULTS.md, строка 3", "держит запись долга `kaname:tests/newman/docs/RESULTS.md:3`" in out, out)
    pr.ok("близнец: проза ведомости (kaname#41) держателем не делает", "Closes #41" in out, out)
    pr.ok("ws#1155: otherorg/kaname#41 — задача чужого владельца — держателем не делает",
          "Closes #41" in closes(out) and "держит запись долга `kaname:.github/scripts/newman-suite-debt.py:3`" not in out, out)
    pr.ok("#43 закрыта — Refs", "#43 «задача 43» — уже закрыта" in out, out)
    pr.ok("перепись: Closes 2, Refs 7, полной формой 2; чужие ведомости — НЕ СВЕРЕНА",
          "Closes 2, Refs 7, из них полной формой 2" in err and "НЕ СВЕРЕНА" in err, err)

    # распознаватель (общий dod_proof.jq)
    for text in ("DoD-proof @main\nкод 0", "DoD-proof @abc12\nкод 0", "DoD-proof @develop\nкод 0",
                 "DoD-proof %s\nкод 0" % sha["41a"][:9], "см. DoD-proof @%s у соседа" % sha["41a"][:9]):
        rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=[comment(41, 1, text)])), extra=extra)
        # «доказательства нет», а не «не коммит диапазона»: иначе распознаватель, засчитавший
        # `@main` ревизией, прятался бы за сверкой с диапазоном (M21, M26 инъекции).
        pr.ok("не доказательство «%s»: Refs #41, доказательства нет" % text.splitlines()[0][:40],
              rc == 0 and "Refs #41" in out and "Closes #41" not in closes(out)
              and re.search(r"- #41 «[^»]*» — доказательства DoD нет", out) is not None, out + err)
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=[comment(41, 1, "DoD-proof @%s" % sha["41b"])])),
                             extra=extra)
    pr.ok("близнец: полный sha — доказательство", rc == 0 and "Closes #41" in closes(out)
          and ("DoD-proof @%s" % sha["41b"]) in out, out + err)
    # ws#1242: частичное доказательство (пункт пачки) — Refs; близнец — полное той же ревизии — Closes.
    for text in ("DoD-proof @%s — частично: пункт 0\nкод 0" % sha["41b"][:9],
                 "DoD-proof @%s — только пункт 0 (ветка x)\nкод 0" % sha["41b"][:9]):
        rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=[comment(41, 1, text)])), extra=extra)
        pr.ok("частичное «%s»: Refs #41, названо частичным" % text.splitlines()[0][-24:],
              rc == 0 and "Refs #41" in out and "Closes #41" not in closes(out)
              and ("`DoD-proof @%s` частичный" % sha["41b"][:9]) in out, out + err)
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=[
        comment(41, 1, "DoD-proof @%s — частично: пункт 0" % sha["41a"][:9]),
        comment(41, 2, "DoD-proof @%s — полностью, пункты 0–5\nкод 0" % sha["41b"][:9])])), extra=extra)
    pr.ok("близнец: частичное, затем полное — Closes #41 по полному",
          rc == 0 and "Closes #41" in closes(out) and ("`DoD-proof @%s`, коммит диапазона" % sha["41b"][:9]) in out, out + err)
    two = [comment(41, 1, "DoD-proof @%s\nпервое" % sha["41a"][:9]), comment(41, 2, "обсуждение"),
           comment(41, 3, "DoD-proof @%s\nпоследнее" % sha["41b"][:9]), comment(41, 4, "DoD-proof @%s\nбаза" % sha["base42"][:9])]
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=two)), extra=extra)
    pr.ok("несколько доказательств: названо последнее из диапазона (issuecomment-3)",
          rc == 0 and ("issuecomment-3 (`DoD-proof @%s`" % sha["41b"][:9]) in out, out + err)
    many = [comment(41, i, "обсуждение %d" % i) for i in range(1, 101)] + [
        comment(41, 101, "DoD-proof @%s\nкод 0" % sha["41a"][:9])]
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, c41=many)), extra=extra)
    pr.ok("доказательство 101-м комментарием (вторая страница): Closes #41",
          rc == 0 and "Closes #41" in closes(out) and "issuecomment-101" in out, out + err)

    # Слияние ствола и доказательство на предке с деревом головы (ws#1146, kaname 870).
    # Судьи засчитывают такое доказательство оба — замер 2026-10-17 на kaname#876 при одном
    # доказательстве @717cdaaf2: merge-readiness «с доказательством DoD: 1», landing-precheck
    # «Closes 1, с доказательством 1» (ревизия — коммит диапазона); генератор обязан так же.
    w = world(sha)
    w["comments"]["%s#50" % R] = [comment(50, 9, "DoD-proof @%s\nкод 0" % sha["50"][:9])]
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-dogon"], pr.state(w), extra=extra)
    pr.ok("догон: код 0", rc == 0, out + err)
    mentioned = (re.search(r"Упомянуты вне первых строк[^\n]*", out) or [""])[0]
    for key, n, msg in DOGON:
        pr.ok("догон «%s»: названо sha, #%d нет в теле, в составе — №%d" % (msg, n, n),
              ("`%s`" % sha[key][:9]) in out and ("#%d" % n) not in out and ("(№%d)" % n) in out, out)
        pr.ok("догон «%s»: %d — ни задача, ни Refs/Closes, ни упомянутая" % (msg, n),
              ("«задача %d»" % n) not in out and not any(str(n) in x for x in tail_of(out))
              and str(n) not in mentioned, out)
    pr.ok("T8: своя #59 — только в префиксе догона — задача", "- #59 «задача 59»" in out and "Refs #59" in out, out)
    pr.ok("доказательство на предке с деревом головы (коммит диапазона) — Closes #50, как у судей",
          "Closes #50" in closes(out) and ("`DoD-proof @%s`, коммит диапазона" % sha["50"][:9]) in out, out)

    # Близнецы: слияние соседней полосы и коммит-не-слияние «merge main» — номера остаются.
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-twins"], pr.state(world(sha)), extra=extra)
    pr.ok("близнец: слияние соседней полосы (ветвь непуста) — #57 задача",
          rc == 0 and "- #57 «задача 57»" in out and "Refs #57" in out, out + err)
    pr.ok("близнец T7: коммит-не-слияние «merge main» — #67 задача",
          rc == 0 and "- #67 «задача 67»" in out and "Refs #67" in out, out + err)
    pr.ok("близнецы: догоны на той же голове — по-прежнему без #56", "#56" not in out, out)

    # Номер другого репозитория (ws#1164): kacho-workspace PR приёмки kacho#3274 — генератор
    # отказывал кодом 2 «GET repos/<репо PR>/issues/3274 — код 1: … 404».
    w = world(sha)
    for key in ("PRO-Robotech/kacho#3274", "PRO-Robotech/kacho#3275", "PRO-Robotech/corelib#3275"):
        r_, n_ = key.split("#")
        w["issues"][key] = dict(issue(int(n_)), html_url="https://github.com/%s/issues/%s" % (r_, n_))
    w["comments"]["PRO-Robotech/kacho#3274"] = [comment(3274, 31, "DoD-proof @%s\nкод 0" % sha["x3274"][:9])]
    rc, out, err, st = pr.run("pr-body", [R, "main", "50-cross"], pr.state(w), extra=extra)
    pr.ok("другой репозиторий: код 0, а не отказ «404»", rc == 0, out + err)
    pr.ok("другой репозиторий: трекер не изменён", not P.writes(st), str(P.writes(st)))
    pr.ok("#3274 — задача PRO-Robotech/kacho: строка полной формой",
          "- PRO-Robotech/kacho#3274 «задача 3274» — задача PRO-Robotech/kacho, не %s" % R in out, out)
    pr.ok("#3274 — Refs полной формой, не Closes (доказательство диапазона есть)",
          "Refs PRO-Robotech/kacho#3274" in tail_of(out) and not any("3274" in x for x in closes(out)), out)
    pr.ok("#3274 — голым #N в хвосте нет", not any(re.match(r"^(Refs|Closes) #327[456]$", x) for x in tail_of(out)), out)
    orphan = (re.search(r"Номера первых строк без задачи[^\n]*", out) or [""])[0]
    pr.ok("#3275 — в двух репозиториях: без задачи, оба названы, без #",
          "3275 — в нескольких: PRO-Robotech/corelib, PRO-Robotech/kacho" in orphan and "#3275" not in orphan, out)
    pr.ok("#3276 — ни в одном: без задачи, без #", "3276 — ни в одном из" in orphan and "#3276" not in orphan, out)
    pr.ok("kaname#3277 — полная форма своего репозитория, номера нет: без задачи, в других не ищется",
          "3277 — в %s номера нет, а назван он полной формой этого репозитория" % R in orphan, out)
    pr.ok("#3275, #3276 — ни Refs, ни Closes", not any(("3275" in x or "3276" in x) for x in tail_of(out)), out)
    pr.ok("перепись: другого репозитория 1, без задачи 3", "другого репозитория 1, без задачи 3" in err, err)
    w["fail"] = ["GET repos/PRO-Robotech/kacho/issues/3274"]
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-cross"], pr.state(w), extra=extra)
    pr.refused("отказ чтения кандидата (не 404) — не «нет нигде»", rc, err,
               "GET repos/PRO-Robotech/kacho/issues/3274 — код 1", want=2)
    pr.ok("отказ чтения кандидата: тела нет", out == "", out)

    # атрибуция
    link = "claude" + ".ai/code"
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(sha, title41="разбор %s/session" % link)), extra=extra)
    pr.refused("атрибуция из заголовка задачи", rc, err, "атрибуция в собранном теле")
    pr.ok("атрибуция из заголовка задачи: тело не выдано", out == "", out)
    pr.git(d, "checkout", "-qb", "50-twin", "50")
    pr.commit(d, "#50 про строку co-authored-by: в середине прозы", rel="h.txt")
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-twin"], pr.state(world(sha)), extra=extra)
    pr.ok("близнец атрибуции: ключ посреди прозы — тело собрано", rc == 0 and "Closes #41" in out, err)
    bad = pr.commit(d, "#50 третья\n\nCo-Authored-By: Someone <x@example.com>", rel="h.txt")
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-twin"], pr.state(world(sha)), extra=extra)
    pr.refused("атрибуция в коммите", rc, err, "атрибуция в сообщениях коммитов")
    pr.ok("атрибуция в коммите: тело не выдано, sha назван", out == "" and bad[:10] in err, out + err)

    # не выполнилось
    w = world(sha)
    w["fail"] = ["GET repos/%s/issues/42" % R]
    rc, out, err, _ = pr.run("pr-body", args, pr.state(w), extra=extra)
    pr.refused("задача не прочитана", rc, err, "GET repos/%s/issues/42 — код 1" % R, want=2)
    pr.ok("задача не прочитана: тела нет", out == "", out)
    rc, out, err, _ = pr.run("pr-body", [R, "50", "50"], pr.state(world(sha)), extra=extra)
    pr.refused("диапазон пуст", rc, err, "коммитов ноль", want=2)
    rc, out, err, _ = pr.run("pr-body", [R, "main", "нет-такой"], pr.state(world(sha)), extra=extra)
    pr.refused("ревизии нет", rc, err, "не коммит", want=2)
    rc, out, err, _ = pr.run("pr-body", [R, "41-a", "main", "50"], pr.state(world(sha)), extra=extra)
    pr.refused("прежняя форма с веткой", rc, err, "usage: pr-body.sh <владелец/имя> <база> <голова>", want=2)
    pr.git(d, "checkout", "-qb", "50-noledger", "50")
    pr.git(d, "rm", "-q", ".github/scripts/newman-suite-debt.py")
    pr.git(d, "commit", "-qm", "#50 ведомость снята")
    rc, out, err, _ = pr.run("pr-body", [R, "main", "50-noledger"], pr.state(world(sha)), extra=extra)
    pr.refused("ведомость своего репозитория снята", rc, err, "ведомость долга .github/scripts/newman-suite-debt.py не найдена",
               want=2)
    pr.ok("ведомость снята: тела нет", out == "", out)


if __name__ == "__main__":
    sys.exit(P.main("check-01-pr-body", body))
