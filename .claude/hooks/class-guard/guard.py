#!/usr/bin/env python3
"""class-guard — слой активации скилов на КАЖДОЙ правке файла.

Что это. Хук `PostToolUse` на Write/Edit/MultiEdit: прогоняет по только что
записанному файлу предикаты тех классов из скилов `code-authoring`,
`gate-authoring`, `measurement-discipline`, `verdict-and-landing`, чей вердикт
зависит ТОЛЬКО от содержимого этого файла. Таких 32 из 138 — 23 %. Остальные три
четверти требуют модуля, прогона, суждения или знания намерения и в момент записи
файла ненаблюдаемы; хук о них не заявляет.

Единица «32» и единица «138» — РАЗНЫЕ, и это названо: 32 — классы гейта (A1…G1,
знаменатель выводится из `PREDICATES_BY_ROLE`, см. ниже); 138 — записи классов в
четырёх скилах, каждая посчитана предикатом своего скила на `workspace@55d64bc`
(51 + 35 + 33 + 19). Прежняя редакция называла «29 предикатов на 32 класса из 136»
— три числа, из которых два были неверны, а первое считало не то, что второе.

Что он НЕ делает. Не блокирует запись (правка уже произошла — PostToolUse
срабатывает после). Не выносит вердикт о готовности. Не заменяет ревью.

Инварианты собственного устройства — те же, что он проверяет у других:
  · читает ИСПОЛНЯЕМУЮ часть, а не текст: Go — go/ast; shell/python/yaml —
    после снятия комментариев, литералов и тел heredoc; markdown — без
    огороженных блоков;
  · печатает ПЕРЕПИСЬ: сколько предикатов прогнано, сколько кандидатов формы
    рассмотрено, сколько узлов/строк осмотрено. «Ноль находок» отличимо от
    «ноль прочитанного»;
  · падает ГРОМКО на своей поломке и на неразобранном входе — молчаливого
    пропуска нет ни в одной ветке;
  · послабления самоистекают: запись, которой нечего исключать, — находка;
  · ведёт счётчик срабатываний: «ноль за всю жизнь» становится заметно.

Код возврата: 0 — сказать нечего; 2 — есть что сказать (stderr доезжает до
автора). Оба случая — без блокировки.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import text_predicates as tp  # noqa: E402

try:
    import yaml as _yaml
except Exception:  # noqa: BLE001
    _yaml = None

CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "kacho-class-guard"

# Журнал и счётчик лежат ВНУТРИ каталога гейта, а не в корне проекта.
#
# Причина — радиус, а не вкус: артефакт, чьё место задано корнем проекта, требует строки
# в `.gitignore` того корня, куда каталог попадёт, — и эту строку кто-то обязан не
# забыть. Внутри каталога их накрывает собственный `.gitignore`, который переезжает
# вместе с ними, — по построению, без списка, который надо вести.
#
# Прежняя редакция обосновывала это раскаткой оснастки по репозиториям (`cp -R` в
# каждое репо). Механизма раскатки НЕТ — он снят решением владельца 2026-08-02 вместе
# со скриптом, и оснастка живёт в единственном экземпляре в воркспейсе
# (`.claude/rules/ai-tooling.md` §«Модель распространения»). Вывод от снятия механизма
# не изменился, изменилось основание: копирование каталога остаётся обычным делом
# (worktree агента, ручной перенос), и локальный игнор к нему устойчив.
STATE = HERE / ".state"
BUILD_BUDGET_S = 90
RUN_BUDGET_S = 20

# Классы, чей вердикт даёт СОБЫТИЕ инструмента, а не содержимое файла.
MIGRATION_DIR = ("migrations/", "/migrations/")

# --- Знаменатель переписи ---------------------------------------------------
#
# ЕДИНИЦА — КЛАСС, и она одна на числитель и знаменатель. Прежняя редакция несла
# рукописную константу `TOTAL_PREDICATES = 29` при 32 распознаваемых
# идентификаторах класса: числитель считал классы (ветви диспетчера), знаменатель —
# число, которое кто-то однажды записал рукой. Расхождение печаталось на каждом
# прогоне и не могло быть замечено ничем, потому что сверять было не с чем.
#
# Поэтому знаменатель ВЫВОДИТСЯ ИЗ РЕАЛИЗАЦИИ: он равен длине карты «класс → сколько
# предикатов этой роли файла», а карта — то же самое, что диспетчер использует для
# счёта прогнанного. Разойтись они больше не могут: рукой правится только одно место,
# и его же читает `render`.
#
# Классы Go живут в `goast/main.go` (A1…A11), классы текста — в `text_predicates.py`,
# событийный G1 — в `analyse`. Перечень сверяется гейтом самоописания (см. `prove.sh`
# §«знаменатель выведен из реализации»): он читает идентификаторы классов из ОБОИХ
# исходников и требует, чтобы множество совпало с этим.
PREDICATES_BY_ROLE: dict[str, tuple[str, ...]] = {
    "go":          ("A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11"),
    "shell":       ("B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9",
                    "B10", "B11", "B12", "B13", "B14", "B15"),
    "python":      ("C1",),
    "newman-json": ("C1",),
    "yaml":        ("D1", "D2"),
    "markdown":    ("E1",),
    "ts":          ("F1",),
    "sql":         ("G1",),
}
# Единица знаменателя — КЛАСС, а не «ветвь диспетчера»: C1 достижим двумя ролями
# файла (питоновский кейс и порождённая коллекция), и считать его дважды значило бы
# менять единицу между числителем и знаменателем.
ALL_CLASSES: tuple[str, ...] = tuple(sorted(
    {c for cs in PREDICATES_BY_ROLE.values() for c in cs},
    key=lambda c: (c[0], int(c[1:])),
))
TOTAL_PREDICATES = len(ALL_CLASSES)


# ---------------------------------------------------------------------------
# Собственная поломка — громко, всегда
# ---------------------------------------------------------------------------


class GuardBroken(Exception):
    """Сломан сам гейт. Отличается и от находки, и от неразобранного входа.

    Три исхода не сливаются: находка — дефект в правленом файле; неразобранный
    вход — факт о файле (объявляется, не глотается); сломанный гейт — факт о
    самом гейте. Слить последние два значило бы построить мягкий проход, не
    различающий настройку и сбой, — ровно тот класс, который гейт ловит.
    """

    def __init__(self, *parts: str) -> None:
        super().__init__("\n".join(p for p in parts if p))


def die_loud(msg: str, detail: str = "") -> None:
    print("╔══ CLASS-GUARD СЛОМАН ═══════════════════════════════════════════", file=sys.stderr)
    print(f"║ {msg}", file=sys.stderr)
    for line in detail.strip().split("\n")[:12]:
        print(f"║   {line}", file=sys.stderr)
    print("║ Предикаты по этой правке НЕ прогонялись. Это не «чисто».", file=sys.stderr)
    print("╚═════════════════════════════════════════════════════════════════", file=sys.stderr)
    sys.exit(2)


# ---------------------------------------------------------------------------
# Go-часть: сборка кэшируется по содержимому исходников
# ---------------------------------------------------------------------------


def goast_binary() -> Path:
    src = HERE / "goast"
    files = sorted(p for p in src.glob("*.go")) + [src / "go.mod"]
    h = hashlib.sha256()
    for p in files:
        h.update(p.read_bytes())
    key = h.hexdigest()[:16]
    binp = CACHE / key / "goast"
    if binp.exists():
        return binp
    if shutil.which("go") is None:
        raise GuardBroken(
            "инструмент `go` не найден в PATH — предикаты A1…A11 (Go) не прогнать.\n"
            "Это НАСТРОЙКА, а не сбой: молча пропустить одиннадцать предикатов нельзя."
        )
    binp.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GOFLAGS="-mod=mod", CGO_ENABLED="0")
    try:
        r = subprocess.run(
            ["go", "build", "-o", str(binp), "."],
            cwd=str(src), env=env, capture_output=True, text=True, timeout=BUILD_BUDGET_S,
        )
    except subprocess.TimeoutExpired:
        raise GuardBroken(f"сборка goast не уложилась в {BUILD_BUDGET_S}s")
    if r.returncode != 0:
        raise GuardBroken("сборка goast провалилась", (r.stderr or r.stdout))
    return binp


def run_goast(path: str) -> tuple[list[dict], dict, list[str]]:
    binp = goast_binary()
    try:
        r = subprocess.run([str(binp), path], capture_output=True, text=True, timeout=RUN_BUDGET_S)
    except subprocess.TimeoutExpired:
        raise GuardBroken(f"разбор {path} не уложился в {RUN_BUDGET_S}s")
    if r.returncode not in (0,):
        raise GuardBroken(f"goast вышел с кодом {r.returncode}", r.stderr)
    findings, census, unparsed = [], {}, []
    for line in r.stdout.splitlines():
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            raise GuardBroken("goast выдал не-JSON", line[:200])
        if d["kind"] == "finding":
            findings.append(d)
        elif d["kind"] == "census":
            census = d
        else:
            unparsed.append(f"{d['file']}: {d['err']}")
    return findings, census, unparsed


# ---------------------------------------------------------------------------
# Диспетчер по роли файла
# ---------------------------------------------------------------------------


def classify(path: str) -> str:
    p = path.lower()
    name = os.path.basename(p)
    if p.endswith(".go"):
        return "go"
    if p.endswith((".sh", ".bash")) or name in ("makefile", "gnumakefile") or p.endswith(".mk"):
        return "shell"
    if p.endswith(".py"):
        return "python"
    if p.endswith((".yaml", ".yml")):
        return "yaml"
    if p.endswith(".md"):
        return "markdown"
    if p.endswith((".ts", ".tsx", ".js", ".jsx")):
        return "ts"
    if p.endswith(".sql"):
        return "sql"
    if p.endswith(".json") and "/newman/" in p:
        return "newman-json"
    return ""


def analyse(path: str, tool: str) -> tuple[list[tp.Finding], dict]:
    """Возвращает находки и перепись. Перепись печатается ВСЕГДА."""
    kind = classify(path)
    census: dict = {"kind": kind, "predicates_total": TOTAL_PREDICATES}
    findings: list[tp.Finding] = []

    # --- G1: вердикт из СОБЫТИЯ инструмента, содержимое не нужно ------------
    if path.endswith(".sql") and any(m in path for m in MIGRATION_DIR):
        census["predicates_run"] = census.get("predicates_run", 0) + 1
        census["considered"] = {"G1": 1}
        if tool in ("Edit", "MultiEdit"):
            findings.append(tp.Finding(
                "G1", "правка применённой миграции", path, 1, f"инструмент: {tool}",
                "применённая миграция — уже случившийся факт в каждой поднятой базе; её правка "
                "меняет ИСТОРИЮ, которая нигде не переигрывается, и расходится с состоянием стенда",
                "новая миграция следующим номером; применённую не трогать (core ban #5)",
                "code-authoring §«Порядок операций внутри кода» → «Порядок снятия ресурса»",
            ))

    if not kind:
        census.setdefault("predicates_run", 0)
        census["note"] = "тип файла вне набора предикатов"
        return findings, census

    try:
        raw = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        raise GuardBroken(f"файл не прочитался: {path}", str(e))

    if kind == "go":
        f, c, unparsed = run_goast(path)
        # Если вход не разобрался, ни один предикат не исполнился. Печатать «прогнано
        # 11» рядом со строкой «предикаты не прогнаны» — это ровно расхождение текста
        # с поведением, из-за которого следующий читатель «чинит» верное под неверное.
        census.update({
            "predicates_run": 0 if unparsed else len(PREDICATES_BY_ROLE["go"]),
            "test_files": c.get("test_files", 0),
            "nodes": c.get("nodes", 0),
            "decls": c.get("decls", 0),
            "comments": c.get("comments", 0),
            "considered": c.get("considered") or {},
            "unparsed": unparsed,
            "disabled": c.get("disabled") or [],
        })
        for d in f:
            findings.append(tp.Finding(
                d["class"], d["title"], d["file"], d["line"], d["symbol"],
                d["why"], d["fix"], d["section"],
            ))
        return findings, census

    if kind == "shell":
        src = tp.Source(path, raw, tp.strip_shell(raw))
        findings += tp.b_shell(src)
    elif kind == "python":
        src = tp.Source(path, raw, tp.strip_hash(raw))
        findings += tp.c_newman(src)
    elif kind == "newman-json":
        # Порождённая коллекция — тоже вход правки: её правят руками, когда чинят
        # кейс «по-быстрому». Комментариев в JSON нет, поэтому сырой текст и есть код.
        src = tp.Source(path, raw, raw.split("\n"))
        findings += tp.c_newman(src, from_json=True)
    elif kind == "yaml":
        src = tp.Source(path, raw, tp.strip_hash(raw))
        findings += tp.d_yaml(src, _yaml)
    elif kind == "markdown":
        src = tp.Source(path, raw, tp.strip_md(raw))
        findings += tp.e_markdown(src)
    elif kind == "ts":
        src = tp.Source(path, raw, tp.strip_c_like(raw))
        findings += tp.f_typescript(src)
    else:  # sql — только событийный предикат выше
        census["predicates_run"] = census.get("predicates_run", 0)
        return findings, census

    census.update({
        # Число прогнанного берётся ОТТУДА ЖЕ, откуда знаменатель, — иначе они снова
        # разойдутся, и никто этого не заметит.
        "predicates_run": len(PREDICATES_BY_ROLE[kind]),
        "lines": len(src.code_lines),
        "considered": src.considered,
        "declared_skips": src.declared_skips,
    })
    return findings, census


# ---------------------------------------------------------------------------
# Послабления с предикатом снятия
# ---------------------------------------------------------------------------


def apply_allowances(path: str, findings: list[tp.Finding]) -> tuple[list[tp.Finding], list[tp.Finding]]:
    """Снимает объявленные послабления и ВОЗВРАЩАЕТ просроченные как находки.

    Послабление живо, пока у него есть предмет. Запись, которой больше нечего
    исключать, — это ложное утверждение о дереве, и следующий читатель унаследует
    её как слепую зону (gate-authoring §«Послабление несёт предикат снятия»).
    Предикат снятия здесь — ВНЕШНИЙ по отношению к записи факт: сработал ли
    предикат на этом файле сейчас.
    """
    fp = HERE / "allow.json"
    if not fp.exists():
        return findings, []
    try:
        doc = json.loads(fp.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise GuardBroken("allow.json не разобрался — послабления в неизвестном состоянии", str(e))
    entries = doc.get("entries", [])
    # Сверка по СУФФИКСУ пути: хук получает абсолютный путь, а запись пишется
    # репо-относительной, чтобы пережить и standalone-клон, и рабочую копию.
    def hits(entry) -> bool:
        pe = entry.get("path") or ""
        return bool(pe) and (path == pe or path.endswith("/" + pe.lstrip("./")))

    kept, stale = [], []
    for f in findings:
        if any(hits(e) and e.get("class") == f.cls for e in entries):
            continue
        kept.append(f)
    fired_classes = {f.cls for f in findings}
    for e in entries:
        if not hits(e):
            continue  # о чужих файлах эта правка ничего не доказывает
        if e.get("class") not in fired_classes:
            stale.append(tp.Finding(
                "ALLOW", "послабление пережило свой предмет", str(fp), 1,
                f'{e.get("path")} :: {e.get("class")}',
                "запись исключает то, чего в файле больше нет: она перестала быть послаблением "
                "и стала ложным утверждением о дереве, которое унаследует следующий читатель",
                "снять запись из allow.json",
                "gate-authoring §«Послабление несёт предикат снятия на ВНЕШНЕМ факте»",
            ))
    return kept, stale


# ---------------------------------------------------------------------------
# Счётчик срабатываний: «ноль за всю жизнь» обязано быть заметно
# ---------------------------------------------------------------------------


def bump_stats(path: str, kind: str, n_find: int, ms: int, census: dict) -> str | None:
    st = {"runs": 0, "findings": 0, "since": int(time.time())}
    logp = STATE / "class-guard.log"
    statp = STATE / "class-guard.stats.json"
    try:
        logp.parent.mkdir(parents=True, exist_ok=True)
        with logp.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "ts": int(time.time()), "path": path, "kind": kind,
                "findings": n_find, "ms": ms,
                "considered": census.get("considered") or {},
            }, ensure_ascii=False) + "\n")
        if statp.exists():
            st.update(json.loads(statp.read_text(encoding="utf-8")))
        st["runs"] += 1
        st["findings"] += n_find
        statp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    except OSError:
        # Журнал — не решение о доступе; его отказ не должен глушить находки.
        # Но и молчать нельзя: возвращаем строку, она попадёт в вывод.
        return "журнал class-guard недоступен для записи — счётчик срабатываний не ведётся"
    if st["runs"] >= 200 and st["findings"] == 0:
        return (f"class-guard прогнан {st['runs']} раз и не сработал НИ РАЗУ. "
                "Ноль срабатываний — это подозрение, а не заслуга: проверь инъекцией, "
                "что он вообще способен упасть (README §«Инъекция»).")
    return None


# ---------------------------------------------------------------------------
# Вывод
# ---------------------------------------------------------------------------


def render(path: str, findings: list[tp.Finding], census: dict, ms: int, notes: list[str]) -> str:
    out: list[str] = []
    out.append("╔══ class-guard ══════════════════════════════════════════════════")
    if findings:
        out.append(f"║ {len(findings)} находка(-ок) в {path}")
        out.append("║")
        for f in findings:
            out.append(f"║ [{f.cls}] {f.title}")
            out.append(f"║   где: {f.file}:{f.line}   {f.symbol}")
            out.append(f"║   что: {f.why}")
            out.append(f"║   как: {f.fix}")
            out.append(f"║   норма: {f.section}")
            out.append("║")
    for n in notes:
        out.append(f"║ ⚠ {n}")
        out.append("║")
    # перепись — ОТДЕЛЬНОЕ утверждение, печатается всегда, когда гейт говорит
    cons = census.get("considered") or {}
    cons_s = ", ".join(f"{k}:{v}" for k, v in sorted(cons.items())) or "—"
    scope = census.get("nodes") or census.get("lines") or 0
    unit = "узлов" if census.get("nodes") else "строк кода"
    out.append(f"║ перепись: предикатов прогнано {census.get('predicates_run', 0)} из {TOTAL_PREDICATES} "
               f"(единица — класс); осмотрено {scope} {unit}; кандидатов формы — {cons_s}; {ms} мс")
    if census.get("test_files"):
        out.append(f"║ объявленная предпосылка: {census['test_files']} файл(ов) _test.go/testdata "
                   "выведены из корпуса «прод-дерево» (A1…A3, A6…A8, A10)")
    for s in census.get("declared_skips") or []:
        out.append(f"║ объявленный пропуск: {s}")
    for u in census.get("unparsed") or []:
        out.append(f"║ ВХОД НЕ РАЗОБРАЛСЯ (предикаты не прогнаны): {u}")
    for d in census.get("disabled") or []:
        out.append(f"║ предикат ВЫКЛЮЧЕН: {d}")
    out.append("╚═════════════════════════════════════════════════════════════════")
    return "\n".join(out)


def main() -> None:
    t0 = time.time()
    try:
        payload = json.load(sys.stdin)
    except Exception as e:  # noqa: BLE001
        die_loud("вход хука не разобрался как JSON", str(e))
        return
    tool = payload.get("tool_name", "")
    if tool not in ("Write", "Edit", "MultiEdit"):
        sys.exit(0)
    path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not path or not os.path.exists(path):
        sys.exit(0)

    try:
        findings, census = analyse(path, tool)
        findings, stale = apply_allowances(path, findings)
        findings += stale
    except GuardBroken as e:
        die_loud(str(e).split("\n")[0], "\n".join(str(e).split("\n")[1:]))
        return
    except Exception as e:  # noqa: BLE001 — собственная поломка, но громкая
        import traceback
        die_loud(f"необработанная ошибка гейта: {type(e).__name__}: {e}",
                 traceback.format_exc())
        return

    ms = int((time.time() - t0) * 1000)
    notes = []
    warn = bump_stats(path, census.get("kind", ""), len(findings), ms, census)
    if warn:
        notes.append(warn)
    # Три исхода — три РАЗНЫХ канала, и это не оформление.
    #
    #  · находка / неразобранный вход / просроченное послабление → stderr + код 2:
    #    автор обязан это увидеть немедленно;
    #  · прогнал и чисто → stdout + код 0: строка переписи попадает в стенограмму,
    #    поэтому «прогнал и чисто» ОТЛИЧИМО от «не запускался вовсе», но контекст
    #    автора не расходуется на рутину;
    #  · тип файла вне набора → молчание с кодом 0: гейт НИЧЕГО не утверждал.
    #
    # Слить первый со вторым значило бы кричать на каждой правке; слить второй с
    # третьим — построить молчание, неотличимое от невыполнения, то есть ровно тот
    # мягкий проход, который гейт и ловит.
    if findings or notes or census.get("unparsed"):
        print(render(path, findings, census, ms, notes), file=sys.stderr)
        sys.exit(2)
    if census.get("predicates_run", 0) > 0:
        cons = census.get("considered") or {}
        cons_s = ", ".join(f"{k}:{v}" for k, v in sorted(cons.items())) or "нет"
        scope = census.get("nodes") or census.get("lines") or 0
        unit = "узлов" if census.get("nodes") else "строк кода"
        skips = "; ".join(census.get("declared_skips") or [])
        line = (f"class-guard: {os.path.basename(path)} — находок нет · предикатов "
                f"{census['predicates_run']}/{TOTAL_PREDICATES} · осмотрено {scope} {unit} · "
                f"кандидатов формы {cons_s} · {ms} мс")
        if skips:
            line += f" · объявленный пропуск: {skips}"
        print(line)
    sys.exit(0)


if __name__ == "__main__":
    main()
