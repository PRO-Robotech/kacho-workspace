#!/usr/bin/env python3
"""docfresh — ловит класс «утверждение документа пережило свой предмет».

ПРЕДМЕТ. Документ говорит о дереве: называет файл, маршрут, переменную окружения,
цель сборки, метод. Предмет меняется — документ молчит. Ни один механизм обоих
репозиториев такое не читает: генераторы сверяют КОД с proto, `check-doc-commands`
читает один вид координаты в одном каталоге, `check-13` сверяет связность приёмок,
а не их содержание. Проза производится ЦЕЛИКОМ вручную (`Code generated` — ноль
вхождений на 1022 документа), поэтому устареть может каждое её утверждение.

ЧТО ЭТО НЕ ЕСТЬ. Это не «свежесть документа». Хук резолвит ПЯТЬ видов машинной
координаты; утверждение без координаты («владелец — storage», «проверка идёт до
authz») предмета для резолва не имеет и составляет большинство прозы. Резолв
доказывает существование ИМЕНИ, а не истинность абзаца вокруг. Перепись поэтому
называет, сколько координат распознано, а не сколько строк прочитано.

МОМЕНТ. `PostToolUse` видит ОДНУ правку, а документ устаревает от правки в другом
месте. Отсюда три режима на одном коде:
  A — правлен LIVE-документ  → проверить его координаты;
  B — правлен файл дерева    → обратный индекс «кто меня называет» → НАЗВАТЬ эти
                                документы (их обычно 0–2), не вываливая их
                                посторонние расхождения: совет не про сделанное
                                читается как шум и снимается вместе с хуком;
  C — `Stop`                 → объединение затронутого за ход ПЛЮС исчезнувшие
                                пути ПЛЮС файлы, изменённые мимо Write/Edit
                                (сверка с `git status`, а не с текстом команды).

ОТКАЗ ВМЕСТО МОЛЧАНИЯ. Предикат, чьё основание истины не покрывает предмет,
объявляется отказанным ПОИМЁННО и в счёт не идёт. Ноль от непрогнанного предиката
— это «не измерено», а не «чисто». Go-символ отказан по этой причине: основание
покрывает только пакеты двух репозиториев, поэтому `time.Sleep` и `pgx.ErrNoRows`
попали бы в «не резолвится».

Код возврата: 0 — сказать нечего (перепись на stdout); 2 — есть что сказать
(stderr доезжает до автора). Запись не блокируется ни в одном случае; на `Stop`
код всегда 0 — блокировать конец хода хук не вправе.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Журнал хода, базовая линия и снимок дерева. `DOCFRESH_STATE` переопределяет
# каталог ТОЛЬКО для инъекции: иначе доказательство оси удалений пришлось бы
# вести, портя рабочее состояние живого хука.
STATE = Path(os.environ.get("DOCFRESH_STATE") or (HERE / ".state"))
# Путь послаблений. `DOCFRESH_ALLOW` переопределяет его ТОЛЬКО для инъекции —
# самоистечение списка иначе недоказуемо: пришлось бы портить рабочий файл.
ALLOW_PATH = Path(os.environ.get("DOCFRESH_ALLOW") or (HERE / "allow.json"))
CACHE_ROOT = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "kacho-docfresh"

GIT_TIMEOUT_S = 30
# Порог «ноль срабатываний за всю жизнь» — как у class-guard. Гейт, не сработавший
# ни разу за столько прогонов, обязан сказать это сам: молчание должно быть
# подозрительным, а не успокаивающим.
SILENT_LIFETIME_ALARM = 300
# Совет длиной в аудит не читают. Сверх этого числа документов отчёт называет
# остаток числом и командой полного обхода, а не печатает его целиком.
MAX_DOCS_SHOWN = 8

# ═══ 1. Корни ════════════════════════════════════════════════════════════════

def workspace_root() -> Path:
    """Корень воркспейса.

    `DOCFRESH_DOC_ROOT` НЕ подменяет корень — он ДОБАВЛЯЕТ каталог к корпусу
    (см. live_docs). Так инъекция пишет пробные документы во временный каталог,
    оставляя основание истины настоящим: подменённое основание доказывало бы,
    что регулярное выражение совпадает само с собой.
    """
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and (Path(env) / ".claude").is_dir():
        return Path(env).resolve()
    return HERE.parent.parent.parent


def monorepo_root(ws: Path) -> Path | None:
    """Дерево продукта. В воркспейсе — под project/kacho; при standalone-клоне
    самого продукта корень репозитория И ЕСТЬ дерево. Признак — наличие предмета
    (`services/`), а не имя каталога."""
    cand = ws / "project" / "kacho"
    if (cand / "services").is_dir():
        return cand
    if (ws / "services").is_dir() and (ws / "proto").is_dir():
        return ws
    return None


def git(root: Path, *args: str) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True, text=True, timeout=GIT_TIMEOUT_S, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if out.returncode != 0:
        return []
    return [ln for ln in out.stdout.split("\n") if ln]


# ═══ 2. Корпус LIVE ══════════════════════════════════════════════════════════
#
# LIVE-документ описывает дерево КАК ОНО ЕСТЬ. Датированная запись (приёмка, план,
# KAC-trail) описывает решение НА ДАТУ и устареть не может по определению — её
# включение дало бы 2754 «находки» шума против 213 сигнала (замер параллельной
# полосы, воспроизведён здесь: см. README §Объём).

LIVE_WS = [
    re.compile(r"^CLAUDE\.md$"),
    re.compile(r"^README\.md$"),
    re.compile(r"^\.claude/rules/[^/]+\.md$"),
    re.compile(r"^obsidian/kacho/(resources|rpc|packages|edges)/[^/]+\.md$"),
    re.compile(r"^obsidian/kacho/(INDEX|README|CLAUDE)\.md$"),
    # Спека-книга 00-04 — описание архитектуры в настоящем времени; остальное в
    # docs/specs (приёмки, планы, тест-планы) — датированная запись.
    re.compile(r"^docs/specs/0[0-4]-[^/]+\.md$"),
    # Агенты и скилы — нормативная инструкция в настоящем времени, то есть
    # LIVE-утверждение о дереве. Прежняя редакция исключала оба каталога «их
    # держит соседний гейт», и это исключение было ШИРЕ своего основания:
    # skills-gate судит утверждения скила О СЕБЕ (форма ссылки на раздел, части
    # записи, совпадение перечня с деревом) и координат не резолвит вовсе.
    # Проверено исполнением: скил `doc-truthfulness` называет держателем своей
    # формы `scripts/skills-gate/check-05-doc-truth-record-parts.sh`, которого в
    # дереве нет, — и ни одна из четырёх проверок skills-gate этого не видит.
    # Делегировать можно ПРЕДИКАТ, а не каталог.
    re.compile(r"^\.claude/agents/[^/]+\.md$"),
    # README хука — тоже утверждение о дереве в настоящем времени, и хук обязан
    # держать собственные утверждения тем же предикатом, что чужие.
    re.compile(r"^\.claude/hooks/[^/]+/README\.md$"),
    re.compile(r"^\.claude/skills/[^/]+/[^/]+\.md$"),
]

LIVE_MONO = [
    re.compile(r"(^|/)README\.md$"),
    re.compile(r"(^|/)docs/architecture/[^/]+\.md$"),
    re.compile(r"(^|/)docs/components/[^/]+\.md$"),
    re.compile(r"(^|/)docs-site/docs/.+\.mdx?$"),
    re.compile(r"(^|/)tests/newman/docs/[^/]+\.md$"),
    re.compile(r"^CLAUDE\.md$"),
]



def _is_live(path: str, pats: list[re.Pattern[str]]) -> bool:
    if "node_modules/" in path:
        return False
    return any(p.search(path) for p in pats)


def live_docs(ws: Path, mono: Path | None) -> list[tuple[str, Path]]:
    """(координатное имя, абсолютный путь) для каждого LIVE-документа."""
    out: list[tuple[str, Path]] = []
    for rel in git(ws, "ls-files", "--cached", "--others", "--exclude-standard"):
        if _is_live(rel, LIVE_WS):
            out.append((rel, ws / rel))
    if mono is not None:
        for rel in git(mono, "ls-files"):
            if _is_live(rel, LIVE_MONO):
                out.append(("project/kacho/" + rel if mono != ws else rel, mono / rel))
    # Каталог пробных документов. Знак равенства с настоящим корпусом полный:
    # координатное имя берётся ОТНОСИТЕЛЬНО этого корня, поэтому проба, лежащая в
    # `<root>/services/nlb/docs/architecture/`, разрешает свои `../`-ссылки против
    # НАСТОЯЩЕГО дерева. Основание истины при этом не подменяется ничем — иначе
    # инъекция доказывала бы, что регулярное выражение совпадает само с собой.
    # Задаётся ТОЛЬКО инъекцией (prove.sh); в работе хука пуст.
    extra = os.environ.get("DOCFRESH_DOC_ROOT")
    if extra and Path(extra).is_dir():
        root = Path(extra)
        for p in sorted(root.rglob("*.md")):
            out.append((str(p.relative_to(root)), p))
    return out


# ═══ 3. Извлечение координат из документа ════════════════════════════════════
#
# Читается ИСПОЛНЯЕМАЯ часть документа, а не текст. Для прозы исполняемое — это
# то, что документ УТВЕРЖДАЕТ; огороженный блок и HTML-комментарий утверждением
# не являются (пример, черновик, вырезанный кусок) и снимаются до разбора. Иначе
# предикат нашёл бы предмет внутри примера, который этот предмет объясняет.

FENCE = re.compile(r"^\s*(```|~~~)")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
INLINE = re.compile(r"`([^`\n]{2,200})`")
BARE_ENV = re.compile(r"\bKACHO_[A-Z0-9_]{2,}")

RE_ROUTE = re.compile(r"^/[a-z][a-z0-9-]*/v\d+(/[^\s]*)?$")
RE_RPC = re.compile(r"^([A-Z][A-Za-z0-9]*(?:Service|IAM))[./]([A-Z][A-Za-z0-9]*(?:/[A-Z][A-Za-z0-9]*)*)$")
RE_MAKE = re.compile(r"^make\s+(?:-C\s+\S+\s+)?([a-zA-Z][a-zA-Z0-9_.-]*)")
RE_PATHY = re.compile(r"^[A-Za-z0-9_.@*-]+(?:/[A-Za-z0-9_.@*-]+)*/?$")
# Одиночное имя файла с известным расширением — тоже координата: документ пишет
# `sync-tooling.sh`, подразумевая корень. Резолв идёт хвостовым совпадением,
# поэтому имя, встречающееся в дереве ХОТЬ ГДЕ, молчит, а не встречающееся нигде
# краснеет. Без этого целый вид цитирования оставался непрочитанным, а «ноль
# находок» по нему был неотличим от «ноль осмотренного».
RE_BARE_FILE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.@-]*\.[A-Za-z0-9]{1,5}$")
# Имена предшествующих полирепо. Они существуют на GitHub, но локально их нет —
# основание истины их не покрывает и судить о них не вправе (см. out_of_coverage).
RE_LEGACY_REPO = re.compile(r"^kacho-[a-z0-9-]+$")


def strip_noncontent(text: str) -> str:
    text = HTML_COMMENT.sub(" ", text)
    kept, fenced = [], False
    for line in text.split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            kept.append("")
            continue
        kept.append("" if fenced else line)
    return "\n".join(kept)


def _norm_path(tok: str, doc_dir: str = "") -> str:
    """Снять ведущее `./` — ИМЕННО его, а не «точку и слэш как символы».

    `lstrip("./")` съедает точку как символ класса и превращает `.claude/rules`
    в `claude/rules`: координата перестаёт резолвиться, и весь каталог оснастки
    читается как несуществующий. Воспроизведено трижды подряд при написании
    предиката, поэтому пара проб на это стоит в prove.sh отдельно.
    """
    # `@` — маркер импорта правил (`@.claude/rules/x.md`), а не часть пути.
    tok = tok.lstrip("@")
    while tok.startswith("./"):
        tok = tok[2:]
    # Ссылка вверх разрешается ОТ КАТАЛОГА ДОКУМЕНТА: `../ARCHITECTURE.md` в
    # `services/nlb/docs/architecture/` — это `services/nlb/docs/ARCHITECTURE.md`,
    # а не отсутствующий корневой файл. Без этого каждая относительная ссылка
    # между соседними документами читалась бы как разрыв.
    if tok.startswith("../") and doc_dir:
        tok = os.path.normpath(os.path.join(doc_dir, tok))
    return tok.rstrip("/")


# Заполнители прозы: документ пишет `/compute/v1/<resource>`, `KACHO_VPC_TLS_SERVER_*`,
# `/iam/v1/groups?account_id=...`. Это ОБРАЗЕЦ, а не координата — резолвить нечего, и
# «не резолвится» на нём было бы ложным обвинением на пустом месте.
PLACEHOLDER = ("<", ">", "…", "...", "?", "*", "|")


def _is_placeholder(tok: str) -> bool:
    return any(m in tok for m in PLACEHOLDER)


def extract(text: str, doc_dir: str = "") -> dict[str, set[str]]:
    body = strip_noncontent(text)
    found: dict[str, set[str]] = {k: set() for k in ("path", "rest", "env", "make", "rpc")}
    for name in BARE_ENV.findall(body):
        # Хвостовое подчёркивание — обрезанное семейство (`KACHO_VPC_DB_*`), а не имя.
        if not name.endswith("_"):
            found["env"].add(name)
    for raw in INLINE.findall(body):
        tok = raw.strip()
        if not tok:
            continue
        m = RE_MAKE.match(tok)
        if m:
            found["make"].add(m.group(1))
            continue
        if RE_ROUTE.match(tok):
            if not _is_placeholder(re.sub(r"\{[^}]*\}", "", tok)):
                found["rest"].add(tok)
            continue
        m = RE_RPC.match(tok)
        if m:
            svc, tail = m.group(1), m.group(2)
            for meth in tail.split("/"):
                found["rpc"].add(f"{svc}.{meth}")
            continue
        if tok.startswith(("http://", "https://", "/")) or " " in tok:
            continue
        if _is_placeholder(tok.replace("*", "")):
            continue
        if "/" in tok:
            if RE_PATHY.match(tok) and _looks_like_repo_path(tok):
                found["path"].add(_norm_path(tok, doc_dir))
        elif RE_BARE_FILE.match(tok) and any(tok.endswith(e) for e in KNOWN_EXT):
            found["path"].add(tok)
    return found


KNOWN_EXT = {
    ".go", ".py", ".sh", ".md", ".mdx", ".sql", ".proto", ".yaml", ".yml", ".json",
    ".ts", ".tsx", ".tpl", ".bats", ".mk", ".txt", ".toml", ".lock", ".js", ".css",
}


def _looks_like_repo_path(tok: str) -> bool:
    """Отличить путь дерева от прочего со слэшем.

    Отвергается: `kacho.cloud.vpc.v1` (нет слэша — сюда не дойдёт), `user:*`,
    `и/или`, `p50/p95`, `A/B`. Признак — либо известное расширение последнего
    сегмента, либо первый сегмент из словаря корней дерева.
    """
    last = tok.rstrip("/").rsplit("/", 1)[-1]
    if any(last.endswith(e) for e in KNOWN_EXT):
        return True
    # `internal/authzfilter.FGAFilter` — квалифицированный символ Go, а не путь.
    # Точка в последнем сегменте при НЕизвестном расширении — признак `pkg.Symbol`.
    # Судить о нём нечем: предикат gosym отказан целиком (см. Truth.enabled), и
    # протаскивать его через полосу путей значило бы обойти собственный отказ.
    if "." in last:
        return False
    first = tok.split("/", 1)[0]
    return first in ROOT_SEGMENTS


ROOT_SEGMENTS = {
    "services", "pkg", "proto", "gateway", "deploy", "internal", "cmd", "tools",
    "docs", "tests", "scripts", "obsidian", ".claude", ".github", "ui-future",
    "project", "migrations", "apps", "collections", "cases",
}


# ═══ 4. Основание истины ═════════════════════════════════════════════════════

RE_HTTP_RULE = re.compile(r"\b(?:get|put|post|patch|delete)\s*:\s*\"([^\"]+)\"")
RE_SERVICE = re.compile(r"^\s*service\s+([A-Za-z0-9_]+)\s*\{")
RE_RPCDECL = re.compile(r"^\s*rpc\s+([A-Za-z0-9_]+)\s*\(")
RE_TARGET = re.compile(r"^([a-zA-Z][a-zA-Z0-9_.%-]*)\s*:(?!=)")
RE_GOROUTE = re.compile(r'"(/[a-z][a-z0-9-]*/v[0-9]+[^"]*)"')
RE_ENVNAME = re.compile(r"\bKACHO_[A-Z0-9_]{2,}")

ENV_PATHSPECS = [
    "*.go", "*.yaml", "*.yml", "*.tpl", "*.sh", "*.json", "*.ts", "*.tsx",
    "*.py", "*.sql", "*.proto", "*.env", "*.mk", "Makefile", "*/Makefile",
    "Dockerfile*", "*/Dockerfile*", "*.bats", "*.tf",
]

COMMENT_HEADS = ("//", "#", "--", "*", "<!--")


def _code_part(line: str) -> str:
    """Грубое снятие комментария со строки основания истины.

    Точность здесь важнее скорости в одну сторону: имя, ВСТРЕЧАЮЩЕЕСЯ ТОЛЬКО В
    КОММЕНТАРИИ, читателем не является — документ, который на него ссылается,
    обещает ручку, которой никто не читает. Разбор грубый (строчные формы, не
    AST) и потому даёт ложные ОТРИЦАНИЯ (пропуск находки), а не ложные
    утверждения; направление ошибки названо намеренно.
    """
    s = line.lstrip()
    if s.startswith(COMMENT_HEADS):
        return ""
    for mark in ("//", " # ", "\t#", " -- "):
        i = line.find(mark)
        if i >= 0:
            line = line[:i]
    return line


def build_truth(ws: Path, mono: Path | None) -> dict:
    t0 = time.time()
    tracked: dict[str, set[str]] = {}
    dirs: dict[str, set[str]] = {}
    for tag, root in (("ws", ws), ("mono", mono)):
        if root is None:
            tracked[tag] = set()
            dirs[tag] = set()
            continue
        files = set(git(root, "ls-files"))
        tracked[tag] = files
        d: set[str] = set()
        for f in files:
            parts = f.split("/")
            for i in range(1, len(parts)):
                d.add("/".join(parts[:i]))
        dirs[tag] = d

    routes: set[str] = set()
    rpcs: set[str] = set()
    if mono is not None:
        for rel in git(mono, "ls-files", "proto"):
            if not rel.endswith(".proto"):
                continue
            try:
                text = (mono / rel).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for route in RE_HTTP_RULE.findall(text):
                routes |= _route_forms(route)
            svc = None
            for line in text.split("\n"):
                m = RE_SERVICE.match(line)
                if m:
                    svc = m.group(1)
                    continue
                m = RE_RPCDECL.match(line)
                if m and svc:
                    rpcs.add(f"{svc}.{m.group(1)}")

    # Не всякий маршрут объявлен в proto. Часть шлюз регистрирует РУКАМИ
    # (`mux.HandleFunc("/iam/v1/auth/login", …)`), и основание истины «только
    # аннотации google.api.http» объявляло бы такие маршруты несуществующими —
    # ложное обвинение на живой поверхности. Берутся строковые литералы Go, из
    # строк со снятым комментарием: маршрут, упомянутый ТОЛЬКО в комментарии,
    # ничего не обслуживает.
    if mono is not None:
        for line in git(mono, "grep", "-h", "-I", "-E",
                        r'"/[a-z][a-z0-9-]*/v[0-9]+', "--", "*.go"):
            for lit in RE_GOROUTE.findall(_code_part(line)):
                routes |= _route_forms(lit)

    targets: set[str] = set()
    for root in (ws, mono):
        if root is None:
            continue
        for rel in git(root, "ls-files"):
            base = rel.rsplit("/", 1)[-1]
            if base != "Makefile" and not base.endswith(".mk"):
                continue
            try:
                text = (root / rel).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for line in text.split("\n"):
                m = RE_TARGET.match(line)
                if m:
                    targets.add(m.group(1))
                elif line.startswith(".PHONY:"):
                    targets.update(line.split(":", 1)[1].split())

    envs: set[str] = set()
    for root in (ws, mono):
        if root is None:
            continue
        for line in git(root, "grep", "-h", "-I", "-E", RE_ENVNAME.pattern, "--", *ENV_PATHSPECS):
            envs.update(RE_ENVNAME.findall(_code_part(line)))

    return {
        "tracked_ws": sorted(tracked["ws"]),
        "tracked_mono": sorted(tracked["mono"]),
        "dirs_ws": sorted(dirs["ws"]),
        "dirs_mono": sorted(dirs["mono"]),
        "routes": sorted(routes),
        "rpcs": sorted(rpcs),
        "targets": sorted(targets),
        "envs": sorted(envs),
        "build_ms": int((time.time() - t0) * 1000),
    }


def _route_forms(route: str) -> set[str]:
    """Маршрут из proto плюс все его предки — документ вправе назвать коллекцию
    (`/vpc/v1/addressPools`), когда proto объявляет элемент."""
    base = re.sub(r"\{[^}]*\}", "*", route).rstrip("/")
    out = {base}
    head = base.split(":", 1)[0]
    out.add(head)
    parts = head.split("/")
    for i in range(3, len(parts)):
        out.add("/".join(parts[: i + 1]))
    return {p for p in out if p.startswith("/")}


# ═══ 5. Резолв ═══════════════════════════════════════════════════════════════

class Truth:
    def __init__(self, raw: dict, ws: Path, mono: Path | None):
        self.ws, self.mono = ws, mono
        self.tracked_ws = set(raw["tracked_ws"])
        self.tracked_mono = set(raw["tracked_mono"])
        self.dirs_ws = set(raw["dirs_ws"])
        self.dirs_mono = set(raw["dirs_mono"])
        self.routes = set(raw["routes"])
        self.rpcs = set(raw["rpcs"])
        self.targets = set(raw["targets"])
        self.envs = set(raw["envs"])
        self.raw = raw
        self._by_base: dict[str, list[str]] | None = None
        self._live_files: dict[str, set[str]] = {}
        self._domains: set[str] | None = None

    # --- предпосылки предикатов -------------------------------------------
    def enabled(self) -> tuple[list[str], list[tuple[str, str]]]:
        """(прогоняемые виды, [(отказанный вид, причина)]).

        Предикат без непустого основания НЕ прогоняется и объявляется поимённо.
        Ноль находок от такого предиката означал бы «не прочитано», а печатался
        бы как «чисто» — тот самый мягкий проход, не различающий сбой и норму.
        """
        on, off = [], []
        for kind, base, why in (
            ("path", self.tracked_ws | self.tracked_mono, "нет ни одного отслеживаемого файла"),
            ("rest", self.routes, "в proto не найдено ни одной аннотации google.api.http"),
            ("rpc", self.rpcs, "в proto не найдено ни одной пары service/rpc"),
            ("make", self.targets, "не найдено ни одной цели Makefile"),
            ("env", self.envs, "не найдено ни одного имени KACHO_* в коде и конфигурации"),
        ):
            (on if base else off).append(kind if base else (kind, why))
        off.append((
            "gosym",
            "основание покрывает только пакеты двух репозиториев дерева; stdlib и "
            "сторонние модули в него не входят, поэтому `time.Sleep` и `pgx.ErrNoRows` "
            "были бы объявлены несуществующими. Предикат отказан целиком, а не сужен",
        ))
        return on, off

    # --- граница покрытия --------------------------------------------------
    #
    # ТРИ исхода на координату, а не два: резолвится · не резолвится · ОСНОВАНИЕ
    # ЕЁ НЕ ПОКРЫВАЕТ. Третий заведён потому, что молчаливое приравнивание чужого
    # к отсутствующему уже провалило один предикат этой же задачи (Go-символ:
    # `time.Sleep` объявлялся несуществующим). Непокрытое не обвиняется и не
    # прячется — оно СЧИТАЕТСЯ и печатается в переписи.
    def out_of_coverage(self, kind: str, coord: str) -> str | None:
        if kind == "path":
            first = coord.split("/", 1)[0]
            if RE_LEGACY_REPO.match(first) and first not in ("kacho-workspace",):
                return "полирепо, которого нет в дереве"
            if first == "kacho-workspace" and not (self.ws / "CLAUDE.md").is_file():
                return "полирепо, которого нет в дереве"
        if kind == "rest":
            svc = coord.split("/")[1] if coord.count("/") >= 2 else ""
            if svc and svc not in self.rest_domains:
                return "домен вне REST-поверхности продукта"
        return None

    @property
    def rest_domains(self) -> set[str]:
        if self._domains is None:
            self._domains = {r.split("/")[1] for r in self.routes if r.count("/") >= 2}
        return self._domains

    # --- резолверы ---------------------------------------------------------
    def resolve(self, kind: str, coord: str) -> bool:
        return getattr(self, "_r_" + kind)(coord)

    def _r_path(self, c: str) -> bool:
        cands = {c}
        if c.startswith("project/kacho/"):
            cands.add(c[len("project/kacho/"):])
        for cand in cands:
            if cand in self.tracked_ws or cand in self.tracked_mono:
                return True
            if cand in self.dirs_ws or cand in self.dirs_mono:
                return True
            if "*" in cand:
                import fnmatch
                if any(fnmatch.fnmatch(p, cand) for p in self.tracked_ws) or \
                   any(fnmatch.fnmatch(p, cand) for p in self.tracked_mono):
                    return True
            # Живая проверка диска: незакоммиченное и игнорируемое существует, но в
            # индексе его нет. Без неё `.claude/settings.local.json` — ложная находка.
            for root in (self.ws, self.mono):
                if root is not None and (root / cand).exists():
                    return True
            if self._suffix_hit(cand):
                return True
        return False

    def _suffix_hit(self, cand: str) -> bool:
        """Путь, записанный ОТНОСИТЕЛЬНО подразумеваемого корня, — не находка.

        Документ оснастки пишет `hooks/vault-reminder.sh`, подразумевая `.claude/`;
        документ скила — `references/audit-round.workflow.js`, подразумевая свой
        каталог. Все три реальны и существуют, поэтому хвостовое совпадение по
        ГРАНИЦЕ СЕГМЕНТА засчитывается за резолв.

        ЦЕНА НАЗВАНА: предикат становится слабее — документ, назвавший неверный
        корень при верном хвосте, теперь молчит. Она платится сознательно, потому
        что ложное обвинение отключает гейт, а пропуск — нет; и потому что цена
        ограничена: хвост всегда ≥2 сегментов (одиночное имя без слэша в
        координаты не попадает вовсе), а обе подтверждённые находки этого класса
        (`sync-tooling.sh`, `kacho-api-gateway/internal/restmux/mux.go`) хвостом
        ни к чему в дереве не приклеиваются и остаются красными — проверено
        исполнением и закреплено парой проб в prove.sh.
        """
        if self._by_base is None:
            self._by_base = {}
            # Каталоги входят наравне с файлами: документ пишет `internal/tenant`
            # и `docs/architecture/`, подразумевая «у каждого сервиса», — предмет
            # существует, просто не под этим корнем.
            for p in (self.tracked_ws | self.tracked_mono | self.dirs_ws | self.dirs_mono):
                self._by_base.setdefault(p.rsplit("/", 1)[-1], []).append(p)
        if "/" not in cand:
            return bool(self._by_base.get(cand))
        tail = "/" + cand
        if "*" in cand:
            import fnmatch
            pat = "*" + tail
            for p in (self.tracked_ws | self.tracked_mono):
                if fnmatch.fnmatch(p, pat):
                    return True
            return False
        for p in self._by_base.get(cand.rsplit("/", 1)[-1], ()):
            if p.endswith(tail):
                return True
        return False

    def _r_rest(self, c: str) -> bool:
        n = re.sub(r"\{[^}]*\}", "*", c).rstrip("/")
        return n in self.routes or n.split(":", 1)[0] in self.routes

    def _r_rpc(self, c: str) -> bool:
        return c in self.rpcs

    def _r_make(self, c: str) -> bool:
        return c in self.targets

    def _r_env(self, c: str) -> bool:
        return c in self.envs


# ═══ 6. Кэш индекса ══════════════════════════════════════════════════════════

def cache_key(ws: Path, mono: Path | None) -> str:
    import hashlib
    h = hashlib.sha256()
    for root in (ws, mono):
        if root is None:
            h.update(b"none|")
            continue
        gd = root / ".git"
        if gd.is_file():  # worktree — .git это файл со ссылкой
            try:
                gd = Path(gd.read_text().split(":", 1)[1].strip())
            except Exception:  # noqa: BLE001
                pass
        for name in ("HEAD", "index"):
            p = gd / name
            try:
                st = p.stat()
                h.update(f"{name}:{st.st_size}:".encode())
                if name == "HEAD":
                    h.update(p.read_bytes())
            except OSError:
                h.update(b"?")
        # Ключ намеренно НЕ включает mtime индекса: `git status` его переписывает,
        # и кэш инвалидировался бы по чужому чтению. Цена — устаревание в пределах
        # коммита; она снята живой доперепроверкой перед КАЖДОЙ находкой (confirm).
    extra = os.environ.get("DOCFRESH_DOC_ROOT", "")
    h.update(extra.encode())
    if extra and Path(extra).is_dir():
        for p in sorted(Path(extra).rglob("*.md")):
            try:
                h.update(f"{p}:{p.stat().st_mtime_ns}".encode())
            except OSError:
                pass
    return h.hexdigest()[:16]


def load_index(ws: Path, mono: Path | None) -> tuple[dict, bool]:
    key = cache_key(ws, mono)
    path = CACHE_ROOT / key / "index.json"
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8")), True
        except Exception:  # noqa: BLE001
            pass
    idx = build_index(ws, mono)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(idx), encoding="utf-8")
    except OSError:
        pass
    return idx, False


def build_index(ws: Path, mono: Path | None) -> dict:
    t0 = time.time()
    truth = build_truth(ws, mono)
    docs = live_docs(ws, mono)
    per_doc: dict[str, dict[str, list[str]]] = {}
    reverse: dict[str, list[str]] = {}
    ncoord = 0
    for name, path in docs:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        found = extract(text, os.path.dirname(name))
        per_doc[name] = {k: sorted(v) for k, v in found.items() if v}
        for kind, coords in found.items():
            ncoord += len(coords)
            for c in coords:
                reverse.setdefault(f"{kind}\t{c}", []).append(name)
    return {
        "truth": truth,
        "per_doc": per_doc,
        "reverse": reverse,
        "docs": [n for n, _ in docs],
        "index_ms": int((time.time() - t0) * 1000),
    }


# ═══ 7. Послабления, самоистекающие ══════════════════════════════════════════

def load_allow() -> list[dict]:
    if not ALLOW_PATH.is_file():
        return []
    try:
        return json.loads(ALLOW_PATH.read_text(encoding="utf-8")).get("entries", [])
    except Exception:  # noqa: BLE001
        return []


def stale_allow(entries: list[dict], reverse: dict) -> list[dict]:
    """Запись, которой больше нечего исключать, — находка.

    Предикат снятия привязан к ВНЕШНЕМУ факту: координата больше не упоминается
    ни одним LIVE-документом. Он не может стать тождественно истинным от правки
    самого послабления — только от правки корпуса.
    """
    return [e for e in entries
            if f"{e.get('kind')}\t{e.get('coordinate')}" not in reverse]


def allowed(entries: list[dict], kind: str, coord: str) -> dict | None:
    for e in entries:
        if e.get("kind") == kind and e.get("coordinate") == coord:
            return e
    return None


# ═══ 8. Живое подтверждение перед обвинением ═════════════════════════════════

def confirm_missing(truth: Truth, kind: str, coord: str) -> bool:
    """Перепроверить нерезолвящуюся координату по ЖИВОМУ дереву.

    Индекс кэшируется в пределах коммита, поэтому свежесозданный предмет ему
    неизвестен. Обвинение стоит дороже молчания, поэтому оно всегда проверяется
    вторым, независимым от кэша способом. Стоимость ограничена ЧИСЛОМ НАХОДОК,
    а не размером дерева.
    """
    if kind == "path":
        cands = {coord}
        if coord.startswith("project/kacho/"):
            cands.add(coord[len("project/kacho/"):])
        for root in (truth.ws, truth.mono):
            if root is None:
                continue
            for cand in cands:
                if (root / cand).exists():
                    return False
            key = str(root)
            if key not in truth._live_files:
                files = set(git(root, "ls-files"))
                for f in list(files):
                    parts = f.split("/")
                    for i in range(1, len(parts)):
                        files.add("/".join(parts[:i]))
                truth._live_files[key] = files
            live = truth._live_files[key]
            for cand in cands:
                tail = "/" + cand
                if cand in live or any(p.endswith(tail) for p in live):
                    return False
        return True
    if kind == "env":
        for root in (truth.ws, truth.mono):
            if root is None:
                continue
            hits = git(root, "grep", "-h", "-I", "-w", "--", coord, *ENV_PATHSPECS)
            if any(_code_part(h).find(coord) >= 0 for h in hits):
                return False
        return True
    if kind == "make":
        for root in (truth.ws, truth.mono):
            if root is None:
                continue
            if git(root, "grep", "-l", "-E", f"^{re.escape(coord)}[[:space:]]*:", "--", "Makefile", "*/Makefile", "*.mk"):
                return False
        return True
    if kind in ("rest", "rpc") and truth.mono is not None:
        needle = coord.split(":", 1)[0] if kind == "rest" else coord.split(".", 1)[1]
        if git(truth.mono, "grep", "-l", "--", needle, "proto"):
            return False
        return True
    return True


# ═══ 9. Проверка документа ═══════════════════════════════════════════════════

def check_docs(names: list[str], idx: dict, truth: Truth, entries: list[dict],
               ws: Path, mono: Path | None, fresh: dict[str, dict] | None = None
               ) -> tuple[list[tuple[str, str, str]], int, int, int]:
    """→ ([(документ, вид, координата)], документов, координат, вне покрытия)"""
    on, _ = truth.enabled()
    findings: list[tuple[str, str, str]] = []
    seen_docs = 0
    seen_coords = 0
    uncovered = 0
    for name in names:
        coords = (fresh or {}).get(name) or idx["per_doc"].get(name)
        if coords is None:
            continue
        seen_docs += 1
        for kind, lst in coords.items():
            if kind not in on:
                continue
            for coord in lst:
                seen_coords += 1
                if truth.resolve(kind, coord):
                    continue
                if truth.out_of_coverage(kind, coord):
                    uncovered += 1
                    continue
                if allowed(entries, kind, coord):
                    continue
                if confirm_missing(truth, kind, coord):
                    findings.append((name, kind, coord))
    return findings, seen_docs, seen_coords, uncovered


# ═══ 10. Журнал хода и счётчик ═══════════════════════════════════════════════

def _state_file(name: str) -> Path:
    return STATE / name


def journal_append(paths: list[str]) -> None:
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        with _state_file("turn.jsonl").open("a", encoding="utf-8") as fh:
            for p in paths:
                fh.write(json.dumps({"p": p, "t": time.time()}) + "\n")
    except OSError:
        pass


def journal_read_and_clear() -> list[str]:
    p = _state_file("turn.jsonl")
    if not p.is_file():
        return []
    out = []
    try:
        for line in p.read_text(encoding="utf-8").split("\n"):
            if line.strip():
                out.append(json.loads(line)["p"])
        p.unlink()
    except Exception:  # noqa: BLE001
        pass
    return sorted(set(out))


def bump_stats(fired: bool) -> dict:
    p = _state_file("stats.json")
    st = {"runs": 0, "fired": 0}
    try:
        if p.is_file():
            st.update(json.loads(p.read_text(encoding="utf-8")))
    except Exception:  # noqa: BLE001
        pass
    st["runs"] = int(st.get("runs", 0)) + 1
    st["fired"] = int(st.get("fired", 0)) + (1 if fired else 0)
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(st), encoding="utf-8")
    except OSError:
        return {"runs": -1, "fired": -1}
    return st


# ═══ 11. Предпосылки самого хука ═════════════════════════════════════════════

def preconditions(ws: Path, mono: Path | None) -> list[str]:
    """Отказы, при которых хук НЕ вправе печатать «находок нет».

    Запрет всегда обоснован фактом о дереве; факт меняется — запрет становится
    ложью. Поэтому факт проверяется, а не подразумевается.
    """
    bad = []
    if mono is None:
        bad.append(
            "дерево продукта не найдено (ожидалось project/kacho/services): основание "
            "истины для маршрутов, методов и большей части путей ПУСТО. «Ноль находок» "
            "здесь означало бы «ноль прочитанного»"
        )
    # Словарь корневых сегментов решает, ЧТО ВООБЩЕ считается координатой-путём.
    # Имя, которому в дереве больше нет предмета, — это не безобидный лишний
    # элемент: он молча расширяет извлечение на прозу («project/delete»), а
    # исчезнувший — молча СУЖАЕТ его, и весь каталог перестаёт осматриваться,
    # оставляя ноль находок неотличимым от ноля прочитанного.
    if mono is not None:
        dirs = set()
        for root in (ws, mono):
            for f in git(root, "ls-files"):
                parts = f.split("/")
                for i in range(1, len(parts)):
                    dirs.add(parts[i - 1])
        orphan = sorted(n for n in ROOT_SEGMENTS if n not in dirs)
        if orphan:
            bad.append(
                "словарь корневых сегментов разошёлся с деревом — предмета нет у: "
                + ", ".join(orphan)
                + ". Пока имя в словаре, оно расширяет извлечение на прозу; пока его нет — "
                "каталог не осматривается вовсе. Привести словарь в соответствие"
            )
    return bad


# ═══ 12. Печать ══════════════════════════════════════════════════════════════

def census_line(idx: dict, truth: Truth, ndocs: int, ncoords: int,
                warm: bool, ms: int, stats: dict, carried: int,
                uncovered: int = 0) -> str:
    on, off = truth.enabled()
    t = truth.raw
    parts = [
        f"осмотрено документов {ndocs} из {len(idx['docs'])} LIVE",
        f"координат рассмотрено {ncoords}, вне покрытия основания {uncovered}",
        f"предикатов прогнано {len(on)} ({','.join(on)}), отказано {len(off)} ({','.join(k for k, _ in off)})",
        f"основание: путей {len(truth.tracked_ws) + len(truth.tracked_mono)}, "
        f"маршрутов {len(truth.routes)}, методов {len(truth.rpcs)}, "
        f"целей {len(truth.targets)}, переменных {len(truth.envs)}",
        f"индекс {len(idx['reverse'])} координат, кэш {'тёплый' if warm else 'холодный'}",
        f"{ms} мс",
    ]
    if carried:
        parts.append(f"с прошлого хода не закрыто {carried}")
    return "docfresh: " + " · ".join(parts)


def render(findings: list[tuple[str, str, str]], stales: list[dict],
           refusals: list[tuple[str, str]], census: str, stats: dict) -> str:
    KIND = {"path": "путь", "rest": "маршрут", "env": "переменная",
            "make": "цель make", "rpc": "метод"}
    out = ["╔══ docfresh ═════════════════════════════════════════════════════"]
    by_doc: dict[str, list[tuple[str, str]]] = {}
    for doc, kind, coord in findings:
        by_doc.setdefault(doc, []).append((kind, coord))
    shown, hidden = sorted(by_doc)[:MAX_DOCS_SHOWN], max(0, len(by_doc) - MAX_DOCS_SHOWN)
    for doc in shown:
        out.append(f"║ {doc}")
        for kind, coord in sorted(by_doc[doc]):
            out.append(f"║     {KIND.get(kind, kind)} `{coord}` — в дереве не резолвится")
    if hidden:
        out.append(f"║ … и ещё {hidden} документ(ов) с расхождением — полный список: "
                   f"`python3 .claude/hooks/docfresh/docfresh.py --sweep`")
    for e in stales:
        out.append(f"║ ПОСЛАБЛЕНИЕ БЕЗ ПРЕДМЕТА: allow.json → {e.get('kind')} "
                   f"`{e.get('coordinate')}` больше не упоминается ни одним LIVE-документом.")
        out.append("║     Запись, которой нечего исключать, — находка: удалить.")
    if findings:
        out.append("║")
        out.append("║ Документ утверждает о дереве то, чего в нём нет. Три исхода:")
        out.append("║   починить утверждение · починить дерево · снять утверждение.")
        out.append("║ Резолв доказывает существование ИМЕНИ, не истинность абзаца вокруг.")
    for kind, why in refusals:
        out.append(f"║ предикат `{kind}` НЕ прогонялся: {why}")
    out.append("║ " + census)
    if stats.get("runs", 0) >= SILENT_LIFETIME_ALARM and stats.get("fired", 0) == 0:
        out.append(f"║ ВНИМАНИЕ: прогнан {stats['runs']} раз и не сработал НИ РАЗУ — "
                   f"проверь предикаты инъекцией (prove.sh), молчание подозрительно.")
    out.append("╚═════════════════════════════════════════════════════════════════")
    return "\n".join(out)


# ═══ 13. Режимы ══════════════════════════════════════════════════════════════

def rel_of(path: str, ws: Path, mono: Path | None) -> str | None:
    """Абсолютный путь → координатное имя, как его пишут документы."""
    try:
        p = Path(path).resolve()
    except OSError:
        return None
    extra = os.environ.get("DOCFRESH_DOC_ROOT")
    if extra:
        try:
            return str(p.relative_to(Path(extra).resolve()))
        except (ValueError, OSError):
            pass
    if mono is not None and mono != ws:
        try:
            return "project/kacho/" + str(p.relative_to(mono))
        except ValueError:
            pass
    try:
        return str(p.relative_to(ws))
    except ValueError:
        return None


def docs_naming(idx: dict, rel: str) -> list[str]:
    """Документы, называющие этот путь — сам или как каталог-предок."""
    if rel is None:
        return []
    cands = {rel}
    if rel.startswith("project/kacho/"):
        cands.add(rel[len("project/kacho/"):])
    # Совпадение — ТОЛЬКО по самому пути, без каталогов-предков.
    #
    # Прежняя редакция поднимала и предков, и это было не «шире, а значит
    # надёжнее»: `project/kacho` называет добрый десяток документов, поэтому
    # правка ЛЮБОГО файла монорепо будила их все. Совет, приходящий на каждую
    # правку и почти всегда не про неё, — это способ, которым хук снимают.
    # Исчезновение КАТАЛОГА ловится другой осью — сверкой корпуса с деревом на
    # `Stop` (vanished_paths), где ему и место.
    out: set[str] = set()
    for c in cands:
        out.update(idx["reverse"].get("path\t" + c, []))
    return sorted(out)


def vanished_since_snapshot(idx: dict, truth: Truth, ws: Path, mono: Path | None
                            ) -> tuple[list[tuple[str, str, str]], bool, int]:
    """Пути, ИСЧЕЗНУВШИЕ из дерева с прошлого хода, которые называет LIVE-документ.

    Закрывает удаление и переименование — единственный момент, когда утверждение
    точно переживает предмет, и при этом ни одно событие инструмента не приходит:
    `PostToolUse` на Write/Edit удаления не видит вовсе.

    Сравнивается СНИМОК, а не весь корпус. Прежняя редакция обходила обратный
    индекс целиком и на каждом конце хода выдавала аудит всего корпуса — 36 КБ
    про правки, которых в этом ходу не было. Совет, который не про сделанное,
    читается как шум и снимается вместе с хуком.
    """
    snap = _state_file("tracked-snapshot.txt")
    cur: set[str] = set()
    for tag, root in (("", ws), ("project/kacho/", mono)):
        if root is None:
            continue
        for f in git(root, "ls-files"):
            cur.add(tag + f)
    try:
        prev = set(snap.read_text(encoding="utf-8").split("\n")) - {""}
        had = True
    except OSError:
        prev, had = set(), False
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        snap.write_text("\n".join(sorted(cur)), encoding="utf-8")
    except OSError:
        pass
    if not had:
        return [], False, 0
    gone = prev - cur
    out = []
    for g in sorted(gone):
        for cand in (g, g[len("project/kacho/"):] if g.startswith("project/kacho/") else g):
            for d in idx["reverse"].get("path\t" + cand, []):
                if not truth.resolve("path", cand) and not truth.out_of_coverage("path", cand):
                    out.append((d, "path", cand))
    return out, True, len(gone)


def sweep() -> int:
    """Обход ВСЕГО корпуса — единственный вход без события инструмента.

    Нужен ровно двум читателям: инъекции (prove.sh) и человеку, которому надо
    назвать объём и число, а не получить совет по одной правке. Хуком не
    используется: в момент правки обход всего корпуса не к месту и не в бюджет.
    """
    t0 = time.time()
    ws = workspace_root()
    mono = monorepo_root(ws)
    bad = preconditions(ws, mono)
    if bad:
        for b in bad:
            sys.stderr.write("[VOID] docfresh: " + b + "\n")
        return 2
    idx, warm = load_index(ws, mono)
    truth = Truth(idx["truth"], ws, mono)
    entries = load_allow()
    _, refusals = truth.enabled()
    findings, nd, nc, unc = check_docs(idx["docs"], idx, truth, entries, ws, mono)
    stales = stale_allow(entries, idx["reverse"])
    ms = int((time.time() - t0) * 1000)
    census = census_line(idx, truth, nd, nc, warm, ms, {}, 0, unc)
    if findings or stales:
        sys.stdout.write(render(findings, stales, refusals, census, {}) + "\n")
        sys.stdout.write(f"[CENSUS] документов с расхождением "
                         f"{len({d for d, _, _ in findings})}, расхождений {len(findings)}\n")
        return 1
    sys.stdout.write("[PASS] " + census + "\n")
    return 0


def main() -> int:
    if "--sweep" in sys.argv:
        return sweep()
    t0 = time.time()
    try:
        event = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        sys.stderr.write("docfresh СЛОМАН: вход не разобран как JSON — "
                         "ни один предикат не прогонялся. Это не «чисто».\n")
        return 2

    ws = workspace_root()
    mono = monorepo_root(ws)
    hook_event = event.get("hook_event_name") or ""
    tool = event.get("tool_name") or ""
    fpath = (event.get("tool_input") or {}).get("file_path") or ""

    bad = preconditions(ws, mono)
    if bad:
        lines = ["╔══ docfresh ОТКАЗЫВАЕТСЯ РАБОТАТЬ ═══════════════════════════════"]
        for b in bad:
            lines.append("║ " + b)
        lines.append("╚═════════════════════════════════════════════════════════════════")
        sys.stderr.write("\n".join(lines) + "\n")
        return 2

    idx, warm = load_index(ws, mono)
    truth = Truth(idx["truth"], ws, mono)
    entries = load_allow()
    _, refusals = truth.enabled()

    if hook_event == "Stop" or tool == "Stop":
        return stop_mode(idx, truth, entries, ws, mono, t0, warm)

    if not fpath:
        return 0

    rel = rel_of(fpath, ws, mono)
    if rel is None:
        return 0
    journal_append([rel])

    live_names = set(idx["docs"])
    fresh: dict[str, dict] = {}
    if rel not in live_names:
        # РЕЖИМ B — правлен файл дерева, не документ.
        #
        # Здесь хук называет ДОКУМЕНТЫ, а НЕ их находки. Разница принципиальная:
        # у документа, разбуженного правкой кода, свои расхождения есть почти
        # всегда, и они к этой правке ОТНОШЕНИЯ НЕ ИМЕЮТ. Вываливать их в ответ на
        # чужую правку — это совет, который читается как шум, а шум снимают вместе
        # с хуком. Что честно можно сказать: «вот кто про этот файл пишет».
        #
        # Чего хук здесь сказать НЕ может и не притворяется: изменила ли правка
        # смысл утверждения. Резолв доказывает существование имени, не истинность
        # абзаца. Ломающее событие для координаты — исчезновение пути; оно приходит
        # не сюда, а на `Stop`, сверкой снимка дерева (vanished_since_snapshot).
        named = docs_naming(idx, rel)
        stats = bump_stats(False)
        ms = int((time.time() - t0) * 1000)
        census = ("docfresh: правлен файл дерева · документов, называющих его, "
                  f"{len(named)} · индекс {len(idx['reverse'])} координат, "
                  f"кэш {'тёплый' if warm else 'холодный'} · {ms} мс")
        if named:
            head = named[:MAX_DOCS_SHOWN]
            body = ("Этот файл назван документами: " + ", ".join(head)
                    + (f" и ещё {len(named) - len(head)}" if len(named) > len(head) else "")
                    + ". Если правка меняла контракт, имя или расположение — их "
                      "утверждения могли пережить свой предмет.")
            sys.stdout.write(json.dumps({
                "hookSpecificOutput": {"hookEventName": "PostToolUse",
                                       "additionalContext": body + " " + census}
            }, ensure_ascii=False) + "\n")
        else:
            sys.stdout.write(census + "\n")
        return 0

    if rel in live_names:
        # Документ читается ЗАНОВО с диска: правка только что произошла, кэш её
        # не видел. Проверять по кэшу значило бы отвечать про прошлое состояние.
        try:
            fresh[rel] = {k: sorted(v) for k, v in
                          extract(Path(fpath).read_text(encoding="utf-8", errors="replace"),
                                  os.path.dirname(rel)).items() if v}
        except OSError:
            fresh[rel] = idx["per_doc"].get(rel, {})
        targets = [rel]

    findings, nd, nc, unc = check_docs(targets, idx, truth, entries, ws, mono, fresh)
    stales = stale_allow(entries, idx["reverse"]) if rel in live_names else []
    carried = _carried_count()
    stats = bump_stats(bool(findings or stales))
    ms = int((time.time() - t0) * 1000)
    census = census_line(idx, truth, nd, nc, warm, ms, stats, carried, unc)

    if findings or stales:
        sys.stderr.write(render(findings, stales, refusals, census, stats) + "\n")
        return 2
    sys.stdout.write(census + "\n")
    return 0


def _carried_count() -> int:
    p = _state_file("pending.json")
    if not p.is_file():
        return 0
    try:
        return len(json.loads(p.read_text(encoding="utf-8")))
    except Exception:  # noqa: BLE001
        return 0


def stop_mode(idx: dict, truth: Truth, entries: list[dict], ws: Path,
              mono: Path | None, t0: float, warm: bool) -> int:
    touched = journal_read_and_clear()

    # Файлы, изменённые МИМО Write/Edit/MultiEdit (перенаправление, sed -i, mv,
    # rm через Bash). Считается ИСХОД по git, а не намерение по тексту команды:
    # разбор команды угадывает, `git status` показывает результат.
    dirty: set[str] = set()
    for root in (ws, mono):
        if root is None:
            continue
        for line in git(root, "status", "--porcelain", "--untracked-files=normal"):
            p = line[3:].split(" -> ")[-1].strip().strip('"')
            r = rel_of(str((root / p)), ws, mono)
            if r:
                dirty.add(r)
    base_path = _state_file("dirty-baseline.json")
    try:
        baseline = set(json.loads(base_path.read_text(encoding="utf-8")))
        had_baseline = True
    except Exception:  # noqa: BLE001
        baseline, had_baseline = set(), False
    unaccounted = sorted(dirty - baseline - set(touched))
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        base_path.write_text(json.dumps(sorted(dirty)), encoding="utf-8")
    except OSError:
        pass

    live_names = set(idx["docs"])
    targets: set[str] = set()
    for rel in list(touched) + unaccounted:
        if rel in live_names:
            targets.add(rel)
        else:
            targets.update(docs_naming(idx, rel))

    findings, nd, nc, unc = check_docs(sorted(targets), idx, truth, entries, ws, mono)

    # Исчезнувшее — отдельная ось: удаление и переименование не приходят ни одним
    # событием инструмента, поэтому ищутся сверкой СНИМКА дерева с нынешним.
    vanished, had_snap, ngone = vanished_since_snapshot(idx, truth, ws, mono)
    vanished = [(d, k, c) for d, k, c in vanished
                if not allowed(entries, k, c) and confirm_missing(truth, k, c)]
    known = {(d, k, c) for d, k, c in findings}
    for f in vanished:
        if f not in known:
            findings.append(f)
            nc += 1

    stales = stale_allow(entries, idx["reverse"])
    _, refusals = truth.enabled()
    stats = bump_stats(bool(findings or stales))
    ms = int((time.time() - t0) * 1000)
    census = census_line(idx, truth, nd or len({d for d, _, _ in findings}), nc, warm, ms, stats, 0, unc)
    census += (f" · за ход затронуто {len(touched)}, мимо Write/Edit {len(unaccounted)}"
               f", исчезло из дерева {ngone}"
               + ("" if had_baseline and had_snap else " (базовая линия установлена этим прогоном)"))

    try:
        STATE.mkdir(parents=True, exist_ok=True)
        _state_file("pending.json").write_text(
            json.dumps([[d, k, c] for d, k, c in findings]), encoding="utf-8")
    except OSError:
        pass

    text = render(findings, stales, refusals, census, stats) if (findings or stales) else census
    # На `Stop` код всегда 0: код 2 не даёт ходу закончиться, то есть мешает работе.
    # Канал — additionalContext (не-ошибочная обратная связь). Текст дублируется в
    # stderr, чтобы находка не пропала, если канал не поддержан этой версией.
    if findings or stales:
        sys.stderr.write(text + "\n")
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": text}
    }, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(
            "╔══ docfresh СЛОМАН ══════════════════════════════════════════════\n"
            f"║ {type(exc).__name__}: {exc}\n"
            "║ Ни один предикат не прогонялся по этой правке. Это не «чисто».\n"
            "╚═════════════════════════════════════════════════════════════════\n")
        sys.exit(2)
