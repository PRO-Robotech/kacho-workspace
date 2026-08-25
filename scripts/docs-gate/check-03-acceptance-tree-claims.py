#!/usr/bin/env python3
"""check-03 — число, которое приёмка объявляет замером по дереву, меряется.

Что запрещает эта проверка. Приёмка живёт дольше дерева, о котором написана, и
её числа тихо переживают свой предмет: клетка говорит «шесть», предикат клетки
отвечает «три», и увидеть это может только тот, кто повторит замер руками. За
одну ночь 2026-08-11 в приёмке XC-7 так устарели шесть утверждений сразу —
перечень сервисов, две отметки остатка, предикат, потерявший различающую силу, и
два числа, у которых предмет исчез. Ни одно не было ошибкой автора на момент
письма; все шесть стали ложью, потому что число о дереве нечем удержать.

Механизм. Приёмка ведёт таблицу ЗАКРЕПЛЁННЫХ утверждений: строка объявляет
идентификатор `Дn`, величину, **ревизию** дерева продукта и **число**. Гейт
берёт число ИЗ ДОКУМЕНТА и меряет его сам — тем предикатом, который зарегистрирован
здесь под тем же идентификатором. Расхождение — находка с обоими числами.

Почему число читается из документа, а не хранится здесь. Хранимое здесь число
дало бы два места об одном предмете: правка документа не роняла бы ничего, и
гейт стерёг бы собственную копию. Читаемое — связывает документ с деревом
напрямую: соврать можно только там, где это увидит проверка.

Почему замер привязан к РЕВИЗИИ, а не к вершине ветки. Число на своей ревизии
верно навсегда, поэтому гейт не краснеет от движения дерева и не превращается в
беговую дорожку. Он краснеет ровно в двух случаях: утверждение неверно на той
ревизии, которую само называет, — или документ перестал его нести.

Почему ревизия обязана быть ДОСТИЖИМА из `main` продукта. «Резолвится здесь» и
«резолвится у всех» — разные факты, и закрепляют именно второй. Вершина локальной
рабочей копии выглядит ревизией ровно как всякая другая — `git rev-parse HEAD`
печатает её первой, — но живёт только в этой копии: у следующего читателя её нет,
а в свежей выкладке дерева нет и подавно, поэтому повторить замер нечем ни
человеку, ни гейту. Класс наблюдался целиком: двенадцать закреплений стояли на
коммите, которого на `main` продукта нет, и обнаружилось это лишь прогоном на
клоне `main`. Поэтому достижимость проверяется здесь — там, где закрепление
пишут, а не там, где оно потом краснеет. База — `origin/main`, иначе `main`;
если не резолвится ни та, ни другая, ось объявляется НЕосмотренной переписью, а
не считается пройденной.

Самоистечение — в обе стороны:

  * идентификатор объявлен документом, а предиката под него здесь нет →
    находка: приёмка закрепила то, чего никто не мерит;
  * предикат зарегистрирован здесь, а строки в документе больше нет → находка:
    закрепление потеряло предмет и укроет следующее число, которое здесь заведут.

Предпосылка. Нужны оба дерева — воркспейс (документ) и монорепо продукта
(предикаты). Монорепо ищется так же, как в наборе vault-gate: `KACHO_MONOREPO`,
иначе `project/kacho` от корня воркспейса. Нет монорепо, нет документа, нет
таблицы — VOID, а не успех: «нечего мерить» никогда не то же самое, что «сошлось».

Исходы: 0 — все закрепления сошлись; 1 — находки (каждая с обоими числами);
2 — предпосылки нет.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-03-acceptance-tree-claims"

# Документ, чьи закрепления здесь зарегистрированы. Второй документ добавляется
# своей записью — перечень предикатов общий, ключ составной.
DOC = "docs/specs/sub-phase-XC-7-iam-unified-contour-acceptance.md"

# Строка таблицы закреплений:
#   | **Д1** | <величина> | `<ревизия>` | **<число>** | <предикат словами> |
ROW = re.compile(
    r"^\|\s*\*\*(Д\d+)\*\*\s*\|"          # идентификатор закрепления
    r"([^|]*)\|"                           # величина
    r"\s*`([0-9a-f]{7,40})`\s*\|"          # ревизия дерева продукта
    r"\s*\*\*(\d+)\*\*\s*\|",              # число, объявленное документом
    re.M,
)


def _git(repo, args):
    out = subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)
    return [line for line in out.stdout.split("\n") if line]


def base_ref(repo):
    """Ревизия, относительно которой судится ДОСТИЖИМОСТЬ закрепления.

    Порядок намеренный: сперва `origin/main` — общая истина, потом локальная
    `main`. Обратный порядок судил бы по вершине чужой рабочей копии, а она
    расходится: ровно так и родился класс, который эта проверка теперь ловит.
    """
    for ref in ("refs/remotes/origin/main", "refs/heads/main"):
        out = _git(repo, ["rev-parse", "--verify", "--quiet", ref])
        if out:
            return ref, out[0]
    return None, None


def reachable(repo, rev, base):
    """Достижим ли `rev` из `base`: True · False · None (ответа нет).

    Третье значение обязательно и НЕ сливается с False: «не предок» и «спросить
    не удалось» — разные факты, и молча выдать второе за первое значило бы
    произвести находку там, где её никто не мерил.
    """
    r = subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", rev, base],
                       capture_output=True)
    if r.returncode == 0:
        return True
    if r.returncode == 1:
        return False
    return None


def _prod_go(paths):
    """Прод-код: только `.go` и только не-тестовый.

    Отсечь `.md` здесь обязательно: документация цитирует те же имена, и без
    отсечения гейт считал бы объяснение механизма его применением — ровно тот
    класс, который он же и ловит.
    """
    return [p for p in paths if p.endswith(".go") and not p.endswith("_test.go")]


def _files_matching(repo, rev, pattern, pathspec):
    """Прод-файлы, где встречается литерал `pattern`."""
    out = _git(repo, ["grep", "-l", "-e", pattern, rev, "--"] + pathspec)
    return _prod_go([line.split(":", 1)[1] for line in out])


def _lines_matching(repo, rev, pattern, pathspec):
    """Вхождения литерала `pattern` в прод-файлах (строками, а не файлами)."""
    out = _git(repo, ["grep", "-e", pattern, rev, "--"] + pathspec)
    hits = []
    for line in out:
        rest = line.split(":", 1)[1]
        path = rest.split(":", 1)[0]
        if path.endswith(".go") and not path.endswith("_test.go"):
            hits.append(rest)
    return hits


def _services(paths):
    return sorted({p.split("/")[1] for p in paths if p.startswith("services/")})


def _named(repo, rev, suffix, pathspec=None):
    paths = _git(repo, ["ls-tree", "-r", "--name-only", rev, "--"] + (pathspec or []))
    return [p for p in paths if p.endswith(suffix)]


# ── Предикаты. Каждый возвращает (число, чем оно получено словами) ────────────
#
# Каждый предикат отвечает РАЗНЫМИ числами на разных ревизиях дерева — это
# проверено на пяти (`cf69249ed`, `5cad2f9e0`, `563f92852`, `e2941effc`,
# `4d26e3300`) и есть контроль в обе стороны: предикат, отвечающий одно и то же
# всегда, закреплением не является.

def p_serve(repo, rev):
    f = _files_matching(repo, rev, "servicehost.Serve(", ["services/"])
    s = _services(f)
    return len(s), "сервисов с вызовом servicehost.Serve( в прод-коде: %s" % (", ".join(s) or "—")


def p_serve_surface(repo, rev):
    f = _files_matching(repo, rev, "servicehost.ServeSurface(", ["services/"])
    s = _services(f)
    return len(s), "сервисов с вызовом servicehost.ServeSurface(: %s" % (", ".join(s) or "—")


def p_surface_decl(repo, rev):
    h = _lines_matching(repo, rev, "servicecontract.Surface{", ["services/"])
    return len(h), "объявлений servicecontract.Surface{ в прод-коде services/"


def p_http_server(repo, rev):
    f = _files_matching(repo, rev, "http.Server{", ["services/"])
    return len(f), "прод-файлов services/ с литералом http.Server{"


def p_map_wrapper(repo, rev):
    f = [p for p in _named(repo, rev, "/permission_map.go", ["services/"])
         if not p.endswith("_test.go")]
    return len(f), "файлов services/**/permission_map.go (не тесты)"


def p_service_ctor(repo, rev):
    h = _lines_matching(repo, rev, "grpcsrv.NewServer(", ["services/"])
    return len(h), "вхождений grpcsrv.NewServer( в прод-коде services/"


def p_edge_ctor(repo, rev):
    h = _lines_matching(repo, rev, "grpc.NewServer(", ["gateway/"])
    return len(h), "вхождений grpc.NewServer( в прод-коде gateway/"


def p_boot_gate(repo, rev):
    return len(_named(repo, rev, "internal/fgaboot/gate.go")), "копий internal/fgaboot/gate.go"


def p_peer_consumers(repo, rev):
    f = _files_matching(repo, rev, '"github.com/PRO-Robotech/kacho/pkg/peer"', ["services/"])
    return len(f), "прод-файлов services/, импортирующих pkg/peer (сервисов: %d)" % len(_services(f))


def p_narrowers(repo, rev):
    h = _lines_matching(repo, rev, "Narrowers:", ["services/"])
    return len(h), "проводок Narrowers: в прод-коде services/"


def p_catalog_copies(repo, rev):
    return len(_named(repo, rev, "permission_catalog.json")), "экземпляров permission_catalog.json"


def p_selfmade_admin_gate(repo, rev):
    """Определение самодельного административного рубежа (предмет в-12).

    Единица — ОБЪЯВЛЕНИЕ функции, а не упоминание имени: имя встречается и в
    комментариях соседнего файла, объясняющих этот же рубеж, и счёт по имени
    считал бы объяснение носителем (`testing.md` §«Гейт на класс», п. 4).

    Закрепление истекает САМО и в нужную сторону: рубеж снимут — предикат даст
    **0**, закрепление покраснеет, и приёмка обязана будет записать снятие. Пока
    оно зелёное, «рубеж жив» — измеренное утверждение, а не впечатление.
    """
    h = _lines_matching(repo, rev, "func assertAdminAccess(", ["services/"])
    return len(h), "объявлений func assertAdminAccess( в прод-коде services/"


# Реестр закреплений: идентификатор из документа → предикат.
# Ревизию и число берёт документ, а не этот перечень: две копии числа разошлись
# бы молча, и гейт стерёг бы свою.
CLAIMS = {
    "Д1": p_serve,
    "Д2": p_serve,
    "Д3": p_serve_surface,
    "Д4": p_surface_decl,
    "Д5": p_http_server,
    "Д6": p_http_server,
    "Д7": p_map_wrapper,
    "Д8": p_map_wrapper,
    "Д9": p_service_ctor,
    "Д10": p_edge_ctor,
    "Д11": p_boot_gate,
    "Д12": p_boot_gate,
    "Д13": p_peer_consumers,
    "Д14": p_narrowers,
    "Д15": p_catalog_copies,
    "Д16": p_selfmade_admin_gate,
}


def monorepo(root):
    # `.git` РАБОЧЕЙ КОПИИ — ФАЙЛ, А НЕ КАТАЛОГ, и требовать каталог значит не
    # признавать рабочую копию монорепо ВОВСЕ. Проверка объявляла, что ищет
    # монорепо «так же, как vault-gate», а тот принимает обе формы
    # (`scripts/vault-gate/_lib.sh`). Расхождение делало проверку беспредметной
    # у всякого, кто работает из рабочей копии, — то есть у всех, — и набор
    # выходил кодом 1 при НУЛЕ находок, останавливая отправку любой ветки.
    env = os.environ.get("KACHO_MONOREPO")
    if env and os.path.exists(os.path.join(env, ".git")):
        return env
    guess = os.path.join(root, "project", "kacho")
    if os.path.exists(os.path.join(guess, ".git")):
        return guess
    return None


def main():
    root = _lib.workspace_root()
    if DOC not in _lib.tracked(root, DOC):
        _lib.void(NAME, "документ %s в индексе не найден — закреплять нечего" % DOC)
        return 2

    repo = monorepo(root)
    if repo is None:
        _lib.void(NAME, "монорепо продукта не найдено (ни KACHO_MONOREPO, ни project/kacho) — "
                        "предикаты закреплений мерить не на чем")
        return 2

    text = _lib.read(root, DOC)
    rows = ROW.findall(text)
    if not rows:
        _lib.void(NAME, "в %s нет ни одной строки закрепления (`| **Дn** | … | `<ревизия>` | "
                        "**<число>** | …`) — предмета нет" % DOC)
        return 2

    head = _git(repo, ["rev-parse", "--short", "HEAD"])
    ref, base = base_ref(repo)
    findings = []
    seen = []
    lines = []
    unjudged = 0
    for cid, subject, rev, declared in rows:
        seen.append(cid)
        subject = subject.strip()
        declared = int(declared)
        pred = CLAIMS.get(cid)
        if pred is None:
            findings.append("%s — документ закрепил «%s», а предиката под этим идентификатором "
                            "в гейте нет: закреплённым числом это не является" % (cid, subject))
            continue
        if not _git(repo, ["cat-file", "-t", rev + "^{commit}"]):
            findings.append("%s — ревизия %s в дереве продукта не резолвится: замер, названный на "
                            "ней, повторить нечем" % (cid, rev))
            continue
        # Резолвится ЗДЕСЬ и резолвится У ВСЕХ — разные вещи, и вторая как раз та,
        # ради которой закрепление пишут. Вершина локальной рабочей копии выглядит
        # ревизией ровно как всякая другая, но живёт только в ней: у следующего
        # читателя её нет, а в свежей выкладке нет и подавно. Класс наблюдался
        # целиком — двенадцать закреплений на коммите, которого на `main` нет.
        if base is not None:
            near = reachable(repo, rev, base)
            if near is False:
                findings.append("%s — ревизия %s резолвится здесь, но НЕ достижима из %s: "
                                "закрепление на ней повторить может только эта рабочая копия, "
                                "а свежая выкладка дерева его не увидит вовсе" % (cid, rev, ref))
                continue
            if near is None:
                unjudged += 1
        got, how = pred(repo, rev)
        lines.append("  %-4s %s @%s: документ **%d**, дерево %d — %s"
                     % (cid, subject[:52], rev, declared, got, how))
        if got != declared:
            findings.append("%s «%s» @%s — документ объявляет **%d**, предикат даёт **%d** (%s)"
                            % (cid, subject, rev, declared, got, how))

    expired = [c for c in CLAIMS if c not in seen]

    # Достижимость судится не всегда, и это обязано быть НАПЕЧАТАНО: «находок ноль»
    # при неосмотренной оси читается как «ось чиста», хотя её никто не открывал.
    if base is None:
        judged = ("достижимость ревизий НЕ судилась — ни origin/main, ни main в дереве "
                  "продукта не резолвятся")
    elif unjudged:
        judged = ("достижимость судилась из %s, без ответа осталось закреплений %d"
                  % (ref, unjudged))
    else:
        judged = "достижимость каждой ревизии проверена из %s" % ref

    _lib.census(
        "%s: документ %s; строк закрепления %d; предикатов в реестре %d; дерево продукта %s "
        "(HEAD %s); ревизий в закреплениях %d; %s"
        % (NAME, DOC, len(rows), len(CLAIMS), repo, head[0] if head else "?",
           len({r[2] for r in rows}), judged)
    )
    for line in lines:
        print(line)

    for cid in sorted(expired):
        findings.append("%s — предикат зарегистрирован, а строки закрепления в документе больше "
                        "нет: закрепление потеряло предмет и укроет следующее число, которое "
                        "здесь заведут" % cid)

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        _lib.fail(NAME, "закреплений, не сошедшихся с деревом: %d из %d" % (len(findings), len(rows)))
        return 1

    _lib.passed(NAME, "все %d закреплений сошлись с деревом продукта на названных ими ревизиях"
                      % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
