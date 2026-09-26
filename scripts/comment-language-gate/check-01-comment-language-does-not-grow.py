#!/usr/bin/env python3
"""check-01 — УБЫВАЮЩИЙ ПОТОЛОК: не-русской прозы комментария не становится больше.

ЯРУС, КОТОРЫЙ РАБОТАЕТ БЕЗ СРОКОВ. Требование владельца 2026-09-21 дословно:
«комментарии только на русском. Существующие правки привести к виду». «Привести
к виду» — обязанность, привязанная к СОБЫТИЮ (рука в файле), а не к дате;
обязанность со словом «потом» есть пожелание. Чтобы событийная обязанность не
оказалась несходящейся молча — файл, которого никто не трогает, к виду не
приводится никогда, — её несходимость обязана быть видна ЧИСЛОМ.

ТРИ ЧИСЛА, А НЕ ОДНО, И КАЖДОЕ ЛОВИТ СВОЁ:

  files   файлов с находкой. Растёт, когда не-русская проза появилась там, где
          её не было.
  blocks  блоков комментария с находкой. Новый английский блок в УЖЕ красном
          файле счёт файлов не меняет — он меняет счёт блоков.
  lines   строк-находок. Разрастание УЖЕ красного блока не меняет ни того, ни
          другого; без третьего числа потолок был бы слеп ровно к самому
          дешёвому способу ухудшения.

ЧИСЛА — ПО ДЕРЕВУ, А НЕ ИТОГОМ. Итог по четырём деревьям позволял убыли в одном
стволе молча оплатить рост в другом. Каждое дерево сверяется со своей строкой.

ДВЕ ФОРМЫ СВЕРКИ, ПОТОМУ ЧТО У ДЕРЕВЬЕВ РАЗНЫЙ ДОМ ИЗМЕНЕНИЯ (ws#789):

  ПРОДУКТ (kacho, kaname, corelib). Изменение, убавившее не-русскую прозу, живёт
  в стволе продукта, а ведомость — в воркспейсе, и «затяните тем же изменением»
  там невыполнимо по построению: точный храповик по чужому стволу краснил
  воркспейс на каждом шаге ствола, ничего в воркспейсе не меняя (2026-09-22:
  kacho f445aaaa554 → b32ca653083, блоков −5, строк −19), и хук отправки
  останавливал отправку ЛЮБОЙ ветки воркспейса. Поэтому у продукта в ведомости
  ЗАКРЕПЛЁННАЯ РЕВИЗИЯ и три числа на ней, и судится так:
    · числа на закреплённой ревизии воспроизводятся ТОЧНО — ведомость есть
      утверждение о названной ревизии, и завышенное число ложно (`testing.md`
      ledger-exact-not-ceiling: ведомость, прощающая 42 при 36, храповиком не
      является);
    · закреплённая ревизия — предок ствола: коммит ветки полосы точкой отсчёта
      быть не может. Ревизия ни предок, ни потомок ствола — находка; потомок —
      «считать не по чему» (ствол не подтянут либо это коммит ветки поверх
      ствола, без сети их не различить);
    · на стволе РОСТ против закреплённого — находка; УБЫЛЬ — не находка, а
      запас, и он печатается числом. Затягивание — перезакрепление ревизии, то
      есть событие воркспейса, видимое в диффе ведомости.
  Вход — ревизия, а не рабочая копия клона: клон на ветке полосы и клон на
  `origin/main` дают один вердикт.

  ВОРКСПЕЙС. Изменение и ведомость живут в одном дереве, поэтому храповик здесь
  ТОЧНЫЙ, как и был: выросло — ухудшение; убыло — затяните тем же изменением,
  иначе ведомость прощает возврат английского в уже вычищенное место.

ПОЧЕМУ НЕ «ПЕРЕВЕСТИ ВСЁ ОДНИМ ЗАХОДОМ». Довод не в сборке — при соблюдении
исключений не краснеет ничего, и это измерено четырьмя инъекциями. Довод в том,
что перевод пятидесяти тысяч строк НЕВОЗМОЖНО ОТРЕЦЕНЗИРОВАТЬ, а
неотрецензированный перевод комментария есть ровно тот класс дефекта, который
называет `doc-truthfulness`: утверждение, пережившее свой предмет. Английский
оригинал, разошедшийся с кодом, вызывает подозрение; правдоподобный русский
перевод, разошедшийся с кодом, — нет.

Исходы: 0 — числа сошлись; 1 — находка; 2 — считать не по чему. Находка
объявляется раньше беспредметности: одно беспредметное дерево не маскирует
находку в другом.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "check-01-comment-language-does-not-grow"
LEDGER = "docs/comment-language.yaml"
KEYS = ("files", "blocks", "lines")
TREES = _core.PRODUCTS + (_core.WORKSPACE,)
_REV = re.compile(r"^[0-9a-f]{40}$")


def declared(text):
    """{дерево: {ключ: значение}} из блока `ceiling:`.

    Форма: `ceiling:`, под ним по два пробела имя дерева, под ним по четыре —
    `rev:` (только у продукта) и три числа. Разбор строгий: строка внутри блока,
    не подошедшая ни под одну форму, — ошибка разбора, а не молчаливый пропуск,
    иначе опечатка в имени ключа делала бы число необъявленным без единого слова.
    """
    res, bad, inside, tree = {}, [], False, None
    for n, raw in enumerate(text.split("\n"), 1):
        if raw.startswith("ceiling:"):
            inside = True
            continue
        if not inside:
            continue
        if raw[:1] not in (" ", "\t", "#", ""):
            inside = False
            continue
        s = raw.split("#", 1)[0].rstrip()
        if not s.strip():
            continue
        m2 = re.match(r"^  (\w+):\s*$", s)
        m4 = re.match(r"^    (\w+):\s*(\S+)\s*$", s)
        if m2 and m2.group(1) in TREES:
            tree = m2.group(1)
            res.setdefault(tree, {})
        elif m4 and tree and m4.group(1) in KEYS and m4.group(2).isdigit():
            res[tree][m4.group(1)] = int(m4.group(2))
        elif m4 and tree and m4.group(1) == "rev":
            res[tree]["rev"] = m4.group(2).strip("\"'")
        elif re.match(r"^  \w+:", s) and not m2:
            tree = None   # поле ведомости вне деревьев (`predicate` и т. п.)
        else:
            bad.append("строка %d «%s»" % (n, raw.strip()))
    return res, bad


def nums(m):
    return {"files": len(m["files"]), "blocks": m["blocks"], "lines": m["lines"]}


def fmt(d):
    return ", ".join("%s=%d" % (k, d[k]) for k in KEYS)


def main():
    root = _lib.workspace_root()
    findings, voids, census = [], [], []

    text = _lib.read(root, LEDGER) if os.path.exists(os.path.join(root, LEDGER)) else None
    if text is None:
        _lib.void(NAME, "ведомость %s не прочитана — сверять число не с чем" % LEDGER)
        return 2
    want, bad = declared(text)
    if bad:
        _lib.void(NAME, "ведомость %s не разобрана в блоке `ceiling:`: %s"
                  % (LEDGER, "; ".join(bad)))
        return 2
    lacking = []
    for t in TREES:
        miss = [k for k in KEYS if k not in want.get(t, {})]
        if t in _core.PRODUCTS and "rev" not in want.get(t, {}):
            miss.append("rev")
        if miss:
            lacking.append("%s: %s" % (t, ", ".join(miss)))
    if lacking:
        _lib.void(NAME, "ведомость %s не объявляет %s — храповика нет"
                  % (LEDGER, "; ".join(lacking)))
        return 2
    if "rev" in want[_core.WORKSPACE]:
        findings.append(
            "workspace: у воркспейса в ведомости стоит `rev`, а судится он по "
            "рабочей копии точным числом — поле без предмета читается как "
            "закрепление, которого нет")
    for t in _core.PRODUCTS:
        if not _REV.match(want[t]["rev"]):
            findings.append(
                "%s: `rev: %s` — не полная ревизия (40 знаков): сокращённая "
                "неоднозначна со временем, а имя ветки движется" % (t, want[t]["rev"]))

    m = _core.measure(root)
    if "void" in m:
        _lib.void(NAME, "%s — храповик считать не по чему" % m["void"])
        return 2
    if m["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном из четырёх деревьев; "
                        "«находок 0» здесь означало бы «ноль прочитанного»")
        return 2
    parsefail = list(m["parsefail"])

    for tm in m["trees"]:
        t, got, dec = tm["tree"], nums(tm), want[tm["tree"]]
        if t == _core.WORKSPACE:
            census.append("%s (рабочая копия): осмотрено `.go` %d; замерено %s; "
                          "объявлено %s" % (t, tm["walked"], fmt(got), fmt(dec)))
            for k in KEYS:
                if got[k] > dec[k]:
                    findings.append(
                        "%s: %s замерено %d, объявлено %d — РОСТ на %d. Новая или "
                        "изменённая проза комментария в нашем Go пишется по-русски "
                        "(`ban22-comment-prose-ru`). Поднять число в ведомости вместо "
                        "правки комментария значит снять храповик"
                        % (t, k, got[k], dec[k], got[k] - dec[k]))
                elif got[k] < dec[k]:
                    findings.append(
                        "%s: %s замерено %d, объявлено %d — ведомость ПРОСРОЧЕНА на %d. "
                        "У воркспейса потолок затягивается тем же изменением, которым "
                        "файл приведён к виду; иначе он прощает возврат английского в "
                        "уже вычищенное место" % (t, k, got[k], dec[k], dec[k] - got[k]))
            continue

        repo, trunk_rev, pin_decl = tm["repo"], tm["rev"], dec["rev"]
        pin = _core.resolve(repo, pin_decl) if _REV.match(pin_decl) else None
        if pin is None:
            voids.append("%s: закреплённой ревизии %s в клоне %s нет — подтянуть "
                         "ствол клона (`git fetch`), сверять не с чем"
                         % (t, pin_decl, repo))
            continue
        if pin != trunk_rev and not _core.is_ancestor(repo, pin, trunk_rev):
            if _core.is_ancestor(repo, trunk_rev, pin):
                # Потомок ствола — это либо ствол клона, который не подтянули, либо
                # коммит ветки поверх ствола. Без сети их не различить, и ни то,
                # ни другое не зелёное: после подтягивания ствола не-предок станет
                # находкой «не на стволе».
                voids.append("%s: ствол клона %s (%s) ПОЗАДИ закреплённой ревизии %s — "
                             "ссылку не тянули либо ревизия есть коммит ветки поверх "
                             "ствола; подтянуть ствол клона и прогнать заново"
                             % (t, _core.TRUNK_REF, trunk_rev[:11], pin[:11]))
            else:
                findings.append(
                    "%s: закреплённая ревизия %s НЕ НА СТВОЛЕ %s (%s): точкой отсчёта "
                    "стал коммит, которого в стволе нет, — числа о нём о продукте не "
                    "говорят" % (t, pin[:11], _core.TRUNK_REF, trunk_rev[:11]))
            continue
        if pin == trunk_rev:
            at_pin = got
        else:
            pm = _core.measure_tree(repo, t, pin)
            if "void" in pm:
                voids.append("%s: на закреплённой ревизии %s — %s" % (t, pin[:11], pm["void"]))
                continue
            parsefail.extend(pm["parsefail"])
            at_pin = nums(pm)
        slack = dict((k, dec[k] - got[k]) for k in KEYS)
        census.append("%s: закреплено %s, замерено на нём %s, объявлено %s; ствол %s %s, "
                      "замерено %s; запас %s"
                      % (t, pin[:11], fmt(at_pin), fmt(dec), _core.TRUNK_REF,
                         trunk_rev[:11], fmt(got),
                         ", ".join("%s=%d" % (k, max(0, slack[k])) for k in KEYS)))
        for k in KEYS:
            if at_pin[k] != dec[k]:
                findings.append(
                    "%s: %s на закреплённой ревизии %s замерено %d, объявлено %d — "
                    "ведомость НЕ ВОСПРОИЗВОДИТСЯ: число есть утверждение о названной "
                    "ревизии, и объявленное сверх замера прощает ухудшение, которого "
                    "никто не мерил" % (t, k, pin[:11], at_pin[k], dec[k]))
            if got[k] > dec[k]:
                findings.append(
                    "%s: %s на стволе %s замерено %d, закреплено %d — РОСТ на %d. Новая "
                    "или изменённая проза комментария в нашем Go пишется по-русски "
                    "(`ban22-comment-prose-ru`). Перезакрепить ревизию ради роста значит "
                    "снять храповик" % (t, k, trunk_rev[:11], got[k], dec[k], got[k] - dec[k]))

    if parsefail:
        # Отказ разбора — НЕ находка и НЕ зелёное. Лексер, переставший понимать
        # файл, занижает все три числа молча, и потолок зеленеет от слепоты.
        voids.append("отказов разбора %d, первый: %s — при недочитанном дереве "
                     "числа меньше настоящих" % (len(parsefail), parsefail[0]))

    _lib.census("%s: деревьев %d; осмотрено `.go` %d на стволах и в рабочей копии "
                "воркспейса; снято порождённых %d, ввезённых %d; %s"
                % (NAME, len(m["trees"]), m["walked"], m["generated"], m["vendored"],
                   "; ".join(census)))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        _lib.fail(NAME, "перепись координат — `python3 scripts/comment-language-gate/"
                        "list-findings.py --coords`")
        return 1
    if voids:
        for v in voids:
            _lib.void(NAME, v)
        return 2
    _lib.passed(NAME, "храповик сошёлся: у продукта числа воспроизводятся на "
                      "закреплённых ревизиях и на стволе не выросли, у воркспейса "
                      "совпали точно")
    return 0


if __name__ == "__main__":
    sys.exit(main())
