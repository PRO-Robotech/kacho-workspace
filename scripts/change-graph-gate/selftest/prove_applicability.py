#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Инъекция для производителя свидетельства освобождений (`applicability.py`).

ПРЕДМЕТ. Производитель отвечает на вопрос реестра `docs/changes/policy.yaml` §3:
«какое значение у поля evidence, на котором стоит предикат освобождения». Ноль
здесь означает ОСВОБОЖДЕНИЕ роли от вердикта, поэтому ноль, полученный на
непрочитанном дереве, дороже любого красного: он молча снимает обязанность.
Приёмка `check-verifier` 2026-09-22 предъявила прежней форме (строка оболочки
`git ls-files … | wc -l` в каждом `holders.yaml`) шесть таких нолей — N1, N2,
E1, E2, H1, I5. Каждый из них здесь повторён и обязан дать ОТКАЗ (код 2, пустой
stdout) либо ненулевое число, но не «0».

ВХОД НАСТОЯЩИЙ. Реестр и пакеты берутся из отслеживаемого `docs/changes/`
рабочего дерева: предикаты, роли и два живых пакета (`issue-2713` без документов
замысла, `standalone-iam` с ними) — те же, что судит `check-04`. Меняется ровно
один факт мира — cutover-коммиты в §1 реестра переписаны на корни песочницы:
настоящих коммитов в песочнице нет, и без этой подстановки производитель честно
отказал бы на КАЖДОМ опыте, то есть не доказал бы ничего. Сторона дерева
продукта синтетическая: линии с миграцией, с контрактом, из двух полос и из
одной — каждая отличается от законного близнеца одним фактом.

ОДИН ФАКТ НА ИНЪЕКЦИЮ, РЯДОМ — ЗАКОННЫЙ БЛИЗНЕЦ. Без близнеца производитель,
отказывающий на всём, прошёл бы все инъекции.

РЕЕСТР И ПРОИЗВОДИТЕЛЬ СВЕРЕНЫ В ОБЕ СТОРОНЫ. Предикат, чьё поле производитель
вычислить не умеет, делает освобождение по нему непроверяемым; поле, которого не
судит ни один предикат, — мёртвая ветвь производителя. Обе — находки.

    python3 scripts/change-graph-gate/selftest/prove_applicability.py

Исходов три: 0 — все утверждения прошли; 1 — есть провалившееся; 2 — проба
беспредметна (реестр не прочитан либо утверждений ноль).
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
ROOT = os.path.abspath(os.environ.get("CG_GATE_ROOT", os.path.join(GATE_DIR, "..", "..")))
PRODUCER = os.path.join(GATE_DIR, "applicability.py")

sys.path.insert(0, GATE_DIR)
import applicability as producer_module  # noqa: E402

WORKSPACE = "PRO-Robotech/kacho-workspace"
PRODUCT = "PRO-Robotech/kacho"
REAL_WITHOUT_DOCS = "docs/changes/issue-2713"
REAL_WITH_DOCS = "docs/changes/standalone-iam"

PASSED = []
FAILED = []


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        sys.stdout.write("  OK   %s\n" % name)
    else:
        FAILED.append(name)
        sys.stdout.write("  FAIL %s\n       %s\n" % (name, detail))
    sys.stdout.flush()


def git(cwd, *args):
    out = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("git %s в %s: %s" % (" ".join(args), cwd, out.stderr.strip()))
    return out.stdout.strip()


def init_repo(path):
    os.makedirs(path, exist_ok=True)
    git(path, "init", "-q", "-b", "main")
    # Подпись — в конфиге выброшенного клона: он живёт до конца пробы и на origin
    # не попадает никогда; без неё коммит на ранере без ~/.gitconfig отказывает.
    git(path, "config", "user.name", "cg-applicability probe")
    git(path, "config", "user.email", "probe@invalid")
    git(path, "config", "commit.gpgsign", "false")


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def commit(repo, message):
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--allow-empty", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def run(cwd, *args, env=None):
    """(код, stdout, stderr) производителя. Окружение клонов снимается: проба
    не должна зависеть от того, куда указывают переменные разработчика."""
    base = {k: v for k, v in os.environ.items()
            if not k.startswith("KACHO_HOME_") and k != "KACHO_MONOREPO"
            and not k.startswith("GIT_")}
    base.update(env or {})
    out = subprocess.run([sys.executable, PRODUCER] + list(args), cwd=cwd, env=base,
                         capture_output=True, text=True)
    return out.returncode, out.stdout, out.stderr


def field(cwd, name, package, rev="HEAD", env=None):
    return run(cwd, "field", name, "--package", package, "--rev", rev, env=env)


def expect_value(title, result, value):
    rc, out, err = result
    check(title, rc == 0 and out.strip() == str(value),
          "ожидалось число %s с кодом 0, получено код %d stdout %r stderr %r"
          % (value, rc, out, err.strip()[-300:]))


def expect_refusal(title, result, code=2):
    rc, out, err = result
    check(title, rc == code and out.strip() == "",
          "ожидался отказ кодом %d с пустым stdout, получено код %d stdout %r stderr %r"
          % (code, rc, out, err.strip()[-300:]))


# ── МИР ──────────────────────────────────────────────────────────────────────

def tracked_changes_tree():
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "--", "docs/changes/"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return [line for line in out.stdout.split("\n") if line]


def build_product(tmp):
    """Синтетическая линия продукта. Каждая голова отличается от близнеца одним фактом."""
    repo = os.path.join(tmp, "product")
    init_repo(repo)
    write(repo, "README.md", "cutover\n")
    heads = {"cutover": commit(repo, "cutover")}
    write(repo, "gateway/a.go", "package a\n")
    heads["base"] = base = commit(repo, "base")

    # одна полоса, без предмета миграций и контракта; близнецы по форме пути
    write(repo, "gateway/b.go", "package a\n")
    write(repo, "docs/migrations.md", "слово migrations в имени файла, не каталог\n")
    write(repo, "proto/README.md", "каталог proto без .proto\n")
    heads["plain"] = plain = commit(repo, "plain")

    write(repo, "services/vpc/internal/migrations/0001_init.sql", "select 1;\n")
    heads["mig"] = commit(repo, "migration")
    git(repo, "checkout", "-q", plain)
    write(repo, "proto/kacho/cloud/vpc/v1/x.proto", "syntax = \"proto3\";\n")
    heads["proto"] = commit(repo, "proto")
    git(repo, "branch", "proto-lane", heads["proto"])  # голова линии опубликована веткой

    # две полосы, сведённые слиянием
    git(repo, "checkout", "-q", "-b", "lane-a", base)
    write(repo, "gateway/lane_a.go", "package a\n")
    heads["lane_a"] = commit(repo, "lane a")
    git(repo, "checkout", "-q", "-b", "lane-b", base)
    write(repo, "gateway/lane_b.go", "package a\n")
    heads["lane_b"] = commit(repo, "lane b")
    git(repo, "checkout", "-q", "-b", "wave", base)
    git(repo, "merge", "-q", "--no-ff", "-m", "merge lane a", "lane-a")
    git(repo, "merge", "-q", "--no-ff", "-m", "merge lane b", "lane-b")
    heads["wave"] = git(repo, "rev-parse", "HEAD")

    # одна полоса, слившая в себя ствол — предикат ошибается в строгую сторону
    git(repo, "checkout", "-q", "-b", "trunk", base)
    write(repo, "gateway/trunk.go", "package a\n")
    commit(repo, "trunk moves")
    git(repo, "checkout", "-q", "-b", "sync", base)
    write(repo, "gateway/sync.go", "package a\n")
    commit(repo, "lane work")
    git(repo, "merge", "-q", "--no-ff", "-m", "sync trunk into lane", "trunk")
    heads["sync"] = git(repo, "rev-parse", "HEAD")

    # линия, чьи ревизии в клоне ЕСТЬ, но растут не из cutover-коммита: клон не
    # опознаётся как клон продукта, хотя обе ревизии разрешаются
    git(repo, "checkout", "-q", "--orphan", "stray")
    git(repo, "rm", "-q", "-rf", "--cached", ".")
    git(repo, "clean", "-q", "-fdx")
    write(repo, "x.sql", "select 1;\n")
    heads["stray_base"] = commit(repo, "stray base")
    write(repo, "y.sql", "select 2;\n")
    heads["stray_head"] = commit(repo, "stray head")

    # полоса, влитая в ствол КОММИТОМ СЛИЯНИЯ, и её ветка снята: голова остаётся
    # предком ствола (п.4 решения владельца 2026-09-22) — опыт L1 приёмки
    git(repo, "checkout", "-q", "-f", "-b", "trunk2", base)
    write(repo, "gateway/trunk2.go", "package a\n")
    commit(repo, "trunk2 moves")
    git(repo, "checkout", "-q", "-b", "landed-lane", base)
    write(repo, "gateway/landed.go", "package a\n")
    heads["landed"] = commit(repo, "landed lane")
    git(repo, "checkout", "-q", "trunk2")
    git(repo, "merge", "-q", "--no-ff", "-m", "merge landed lane", "landed-lane")
    git(repo, "branch", "-q", "-D", "landed-lane")

    # голова только в локальной ветке и объект без ссылки — опыт L2 приёмки
    git(repo, "checkout", "-q", "-b", "local-only", base)
    write(repo, "gateway/local.go", "package a\n")
    heads["local_only"] = commit(repo, "local only")
    heads["dangling"] = git(repo, "commit-tree", heads["plain"] + "^{tree}", "-p", base,
                            "-m", "dangling")
    git(repo, "checkout", "-q", "-f", "main")

    # «опубликовать» = ссылка refs/remotes/, как после fetch в клоне конвейера;
    # local-only намеренно не публикуется, landed-lane снята
    for name in git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/").split("\n"):
        if name and name != "local-only":
            git(repo, "update-ref", "refs/remotes/origin/" + name, "refs/heads/" + name)
    return repo, heads


def rewrite_cutovers(policy_text, policy, ws_cut, product_cut):
    text = policy_text
    for entry in policy.get("repositories") or []:
        old = str(entry.get("cutover_commit"))
        new = ws_cut if entry.get("repo") == WORKSPACE else product_cut
        text = text.replace(old, new)
    return text


def manifest(change_id, head=None, base=None, extra_hashes="", home_line=None):
    lines = ["schema_version: 1", "change_id: %s" % change_id, "coordinates:",
             "  repositories:", "    - repo: %s" % WORKSPACE, "      role: package-home"]
    if home_line:
        lines += ["      base_sha: %s" % home_line[0], "      head_sha: %s" % home_line[1]]
    if head:
        lines += ["    - repo: %s" % PRODUCT, "      role: subject-tree",
                  "      base_sha: %s" % base, "      head_sha: %s" % head]
    lines += ["hashes:", "  acceptance_sha256: null", "  design_sha256: null"]
    if extra_hashes:
        lines.append(extra_hashes)
    return "\n".join(lines) + "\n"


def holders_for(package, policy, role_rows_override=None, holders_override=None):
    """Точное множество ролей реестра: всё, что реестр позволяет освободить на
    пакете без документов и на линии без миграций/контракта/слияний, — освобождено
    канонической строкой; остальное применимо. Выведено из РЕЕСТРА, а не выписано."""
    change_id = package.rsplit("/", 1)[-1]
    by_role = {}
    for pred in policy.get("applicability_predicates") or []:
        by_role.setdefault(pred["role"], pred)
    rows, holders = {}, {}
    for role in sorted(policy.get("review_authority") or {}):
        pred = by_role.get(role)
        if pred is None:
            rows[role] = {"status": "applicable", "holder": "human-" + role}
            holders["human-" + role] = {"kind": "human-external", "owner": role}
            continue
        rows[role] = {
            "status": "not-applicable",
            "predicate_id": pred["id"],
            "evidence_field": pred["evidence_field"],
            "evidence_value": 0,
            "evidence_command": producer_module.canonical_command(pred["evidence_field"], package),
        }
    rows.update(role_rows_override or {})
    holders.update(holders_override or {})
    holders = {k: v for k, v in holders.items() if v is not None}
    doc = {"schema_version": 1, "change_id": change_id, "role_applicability": rows,
           "required_holders": holders}
    return yaml.safe_dump(doc, allow_unicode=True, sort_keys=True)


class World:
    """Песочница дома пакетов: корень-cutover, реестр и пакеты, ветка на опыт."""

    def __init__(self, tmp, product_heads):
        self.repo = os.path.join(tmp, "ws")
        init_repo(self.repo)
        write(self.repo, "README.md", "cutover\n")
        self.cutover = commit(self.repo, "cutover")
        self.product_heads = product_heads
        self.n = 0

    def branch(self, start, mutate):
        """Коммит поверх start после mutate(корень); возвращает SHA."""
        self.n += 1
        git(self.repo, "checkout", "-q", "-f", "-B", "w%d" % self.n, start)
        git(self.repo, "clean", "-q", "-fdx")
        mutate(self.repo)
        return commit(self.repo, "опыт %d" % self.n)


def remove(root, rel):
    path = os.path.join(root, rel)
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.exists(path):
        os.remove(path)


# ── ОПЫТЫ ────────────────────────────────────────────────────────────────────

def prove(tmp):
    files = tracked_changes_tree()
    if not files or "docs/changes/policy.yaml" not in files:
        sys.stderr.write("[VOID] реестр docs/changes/policy.yaml в отслеживаемом дереве %s "
                         "не найден — доказывать не на чем\n" % ROOT)
        return None
    with open(os.path.join(ROOT, "docs/changes/policy.yaml"), encoding="utf-8") as fh:
        policy_text = fh.read()
    policy = yaml.safe_load(policy_text)

    sys.stdout.write("=== реестр и производитель сверены в обе стороны ===\n")
    registry_fields = {p["evidence_field"] for p in policy["applicability_predicates"]}
    known = set(producer_module.FIELDS)
    check("каждое поле реестра производитель умеет вычислить",
          registry_fields <= known, "не умеет: %s" % sorted(registry_fields - known))
    check("каждое поле производителя судит хотя бы один предикат реестра",
          known <= registry_fields, "мёртвые ветви: %s" % sorted(known - registry_fields))
    check("каждый предикат освобождает роль из review_authority",
          all(p["role"] in (policy.get("review_authority") or {})
              for p in policy["applicability_predicates"]),
          "роли без полномочий: %s" % sorted(p["role"] for p in policy["applicability_predicates"]
                                             if p["role"] not in policy["review_authority"]))

    product, heads = build_product(tmp)
    world = World(tmp, heads)
    ws = world.repo
    real = rewrite_cutovers(policy_text, policy, world.cutover, heads["cutover"])

    def real_world(root):
        for rel in files:
            src = os.path.join(ROOT, rel)
            if os.path.isfile(src):
                with open(src, encoding="utf-8") as fh:
                    write(root, rel, fh.read())
        write(root, "docs/changes/policy.yaml", real)
    w1 = world.branch(world.cutover, real_world)
    env = {"KACHO_HOME_KACHO": product}

    sys.stdout.write("=== контроль на живых пакетах ===\n")
    for name, package, value in (
            ("design_documents_referenced", REAL_WITHOUT_DOCS, 0),
            ("exposure_subject_documents_referenced", REAL_WITHOUT_DOCS, 0),
            ("design_documents_referenced", REAL_WITH_DOCS, 1),
            ("exposure_subject_documents_referenced", REAL_WITH_DOCS, 2)):
        expect_value("C %s %s -> %d" % (package, name, value), field(ws, name, package, w1), value)

    sys.stdout.write("=== документы: одно-фактный дефект и законный близнец ===\n")
    pkg = REAL_WITHOUT_DOCS
    rev = world.branch(w1, lambda r: write(r, pkg + "/design.md", "# замысел\n"))
    expect_value("I1 design.md в корне пакета -> design 1", field(ws, "design_documents_referenced", pkg, rev), 1)
    expect_value("I1 design.md в корне пакета -> exposure 1", field(ws, "exposure_subject_documents_referenced", pkg, rev), 1)
    rev = world.branch(w1, lambda r: write(r, pkg + "/design.md", ""))
    expect_value("I2 ПУСТОЙ design.md освобождения не покупает -> 1", field(ws, "design_documents_referenced", pkg, rev), 1)
    rev = world.branch(w1, lambda r: write(r, pkg + "/acceptance.md", "# приёмка\n"))
    expect_value("I3 только acceptance.md -> exposure 1 (союз)", field(ws, "exposure_subject_documents_referenced", pkg, rev), 1)
    expect_value("I3 только acceptance.md -> design 0 (законно)", field(ws, "design_documents_referenced", pkg, rev), 0)
    rev = world.branch(w1, lambda r: write(r, pkg + "/notes.md", "# замысел\n"))
    expect_value("T1 близнец: тот же текст под именем notes.md -> 0", field(ws, "design_documents_referenced", pkg, rev), 0)
    rev = world.branch(w1, lambda r: write(r, pkg + "/reviews/design.md", "# замысел\n"))
    expect_value("T2 близнец: design.md не в корне пакета -> 0", field(ws, "exposure_subject_documents_referenced", pkg, rev), 0)

    sys.stdout.write("=== N1/N2: корня нет — числа нет ===\n")
    expect_refusal("N1 несуществующий корень docs/changes/issue-2731 -> отказ",
                   field(ws, "design_documents_referenced", "docs/changes/issue-2731", w1))
    expect_refusal("N1 опечатка буквой docs/changes/issue-27l3 -> отказ",
                   field(ws, "exposure_subject_documents_referenced", "docs/changes/issue-27l3", w1))
    expect_refusal("N1 путь не формы docs/changes/<id> -> находка",
                   field(ws, "design_documents_referenced", "docs/changes/", w1), code=1)

    def reviews_only(r):
        write(r, "docs/changes/zz-reviews-only/reviews/post-diff/x/a.yaml", "a: 1\n")
    rev = world.branch(w1, reviews_only)
    expect_refusal("N1 корень есть, манифеста нет -> отказ (hashes не читается)",
                   field(ws, "design_documents_referenced", "docs/changes/zz-reviews-only", rev))

    def wrong_id(r):
        write(r, "docs/changes/zz-wrong-id/change.yaml", manifest("zz-other"))
    rev = world.branch(w1, wrong_id)
    expect_refusal("N2 change_id манифеста не совпадает с каталогом -> находка",
                   field(ws, "design_documents_referenced", "docs/changes/zz-wrong-id", rev), code=1)

    sys.stdout.write("=== E1/E2: чужой клон и вне git ===\n")
    foreign = os.path.join(tmp, "foreign")
    init_repo(foreign)
    commit(foreign, "чужая история")
    expect_refusal("E1 исполнено в чужом клоне без реестра -> отказ",
                   field(foreign, "design_documents_referenced", REAL_WITH_DOCS))
    expect_refusal("E1 исполнено в клоне продукта -> отказ",
                   field(product, "design_documents_referenced", REAL_WITH_DOCS))
    orphan = os.path.join(tmp, "orphan")
    init_repo(orphan)
    real_world(orphan)
    commit(orphan, "те же файлы, другая история")
    expect_refusal("E1 клон с реестром, но без cutover-коммита дома -> отказ",
                   field(orphan, "design_documents_referenced", REAL_WITH_DOCS))
    git(ws, "checkout", "-q", "-f", "--orphan", "detached-history")
    git(ws, "rm", "-q", "-rf", "--cached", ".")
    git(ws, "clean", "-q", "-fdx")
    real_world(ws)
    unrelated = commit(ws, "те же файлы в истории, не растущей из cutover")
    expect_refusal("E1 cutover-коммит в клоне есть, но не предок ревизии -> отказ",
                   field(ws, "design_documents_referenced", REAL_WITH_DOCS, unrelated))
    nogit = os.path.join(tmp, "nogit")
    os.makedirs(nogit)
    expect_refusal("E2 исполнено вне git -> отказ, код не теряется",
                   field(nogit, "design_documents_referenced", REAL_WITHOUT_DOCS))
    git(ws, "checkout", "-q", "-f", w1)
    expect_value("E близнец: исполнено в доме пакетов -> число",
                 field(ws, "design_documents_referenced", REAL_WITHOUT_DOCS), 0)

    sys.stdout.write("=== H1: клауза hashes входит в число ===\n")

    def hash_named(value):
        def mutate(r):
            path = os.path.join(r, pkg, "change.yaml")
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            new, hits = re.subn(r"(?m)^(  design_sha256:).*$", r"\1 " + value, text, count=1)
            if hits != 1:
                raise RuntimeError("строки design_sha256 в %s нет — опыт не ставится" % path)
            write(r, pkg + "/change.yaml", new)
        return mutate
    rev = world.branch(w1, hash_named("'" + "a" * 64 + "'"))
    expect_value("H1 hashes.design_sha256 задан, файла нет -> design 1",
                 field(ws, "design_documents_referenced", pkg, rev), 1)
    expect_value("H1 hashes.design_sha256 задан, файла нет -> exposure 1",
                 field(ws, "exposure_subject_documents_referenced", pkg, rev), 1)
    rev = world.branch(w1, hash_named("''"))
    expect_value("H1 пустая строка в отпечатке — тоже название -> 1",
                 field(ws, "design_documents_referenced", pkg, rev), 1)
    rev = world.branch(w1, hash_named("null"))
    expect_value("H1 близнец: отпечаток null, файла нет -> 0",
                 field(ws, "design_documents_referenced", pkg, rev), 0)

    sys.stdout.write("=== I5: читается коммит, а не индекс и не рабочее дерево ===\n")
    # Пакет БЕЗ отпечатка в hashes: у `standalone-iam` отпечаток задан, и клауза
    # hashes дала бы 1 при любом чтении — опыт менял бы два факта, а не один.
    with_design = world.branch(w1, lambda r: write(r, pkg + "/design.md", "# замысел\n"))
    git(ws, "checkout", "-q", "-f", with_design)
    git(ws, "rm", "-q", "--cached", pkg + "/design.md")
    expect_value("I5 design.md снят из индекса, коммит его несёт -> 1",
                 field(ws, "design_documents_referenced", pkg), 1)
    git(ws, "checkout", "-q", "-f", w1)
    write(ws, pkg + "/design.md", "# не закоммичен\n")
    git(ws, "add", pkg + "/design.md")
    expect_value("I5 близнец: design.md в индексе, но не в коммите -> 0",
                 field(ws, "design_documents_referenced", pkg), 0)
    git(ws, "reset", "-q", "--hard", w1)
    git(ws, "clean", "-q", "-fdx")
    expect_refusal("REV ревизия до появления пакетов -> отказ",
                   field(ws, "design_documents_referenced", pkg, world.cutover))
    expect_refusal("REV ревизия не разрешается -> отказ",
                   field(ws, "design_documents_referenced", pkg, "no-such-rev"))

    sys.stdout.write("=== дерево продукта: линия из манифеста, клон по cutover ===\n")

    def line(name, head, base=None):
        def mutate(r):
            write(r, "docs/changes/%s/change.yaml" % name,
                  manifest(name, head=head, base=base or heads["base"]))
        return mutate
    lines = {}
    for key in ("plain", "mig", "proto", "wave", "sync"):
        lines[key] = world.branch(w1, line("zz-" + key, heads[key]))
    for key, fname, value in (
            ("plain", "migrations_touched", 0), ("plain", "proto_files_touched", 0),
            ("plain", "lane_merges_in_change", 0),
            ("mig", "migrations_touched", 1), ("proto", "proto_files_touched", 1),
            ("wave", "lane_merges_in_change", 2), ("sync", "lane_merges_in_change", 1)):
        expect_value("L %s: %s -> %d" % (key, fname, value),
                     field(ws, fname, "docs/changes/zz-" + key, lines[key], env=env), value)
    rev = world.branch(w1, lambda r: write(r, "docs/changes/zz-nohead/change.yaml",
                                           manifest("zz-nohead")))
    expect_refusal("L манифест без головы -> отказ: линии нет",
                   field(ws, "lane_merges_in_change", "docs/changes/zz-nohead", rev, env=env))
    expect_refusal("L клон продукта не найден -> отказ",
                   field(ws, "migrations_touched", "docs/changes/zz-plain", lines["plain"]))
    expect_refusal("L переменная указывает на чужой клон -> отказ",
                   field(ws, "migrations_touched", "docs/changes/zz-plain", lines["plain"],
                         env={"KACHO_HOME_KACHO": foreign}))
    rev = world.branch(w1, line("zz-ghost", "b" * 40))
    expect_refusal("L головы нет в клоне -> отказ",
                   field(ws, "proto_files_touched", "docs/changes/zz-ghost", rev, env=env))
    rev = world.branch(w1, line("zz-stray", heads["stray_head"], base=heads["stray_base"]))
    expect_refusal("L ревизии линии в клоне есть, но cutover продукта не предок базы -> отказ",
                   field(ws, "migrations_touched", "docs/changes/zz-stray", rev, env=env))
    rev = world.branch(w1, line("zz-empty", heads["plain"], base=heads["plain"]))
    expect_refusal("L пустая линия base == head -> отказ: знаменатель обхода ноль (дифф)",
                   field(ws, "migrations_touched", "docs/changes/zz-empty", rev, env=env))
    expect_refusal("L пустая линия base == head -> отказ: знаменатель обхода ноль (коммиты)",
                   field(ws, "lane_merges_in_change", "docs/changes/zz-empty", rev, env=env))
    rev = world.branch(w1, line("zz-crossed", heads["lane_a"], base=heads["lane_b"]))
    expect_refusal("L база не предок головы -> находка",
                   field(ws, "lane_merges_in_change", "docs/changes/zz-crossed", rev, env=env), code=1)

    sys.stdout.write("=== линии: опубликованность головы и полосы в двух репозиториях ===\n")
    for key, title in (("local_only", "L2 голова только в локальной ветке, не опубликована"),
                       ("dangling", "L2 голова — объект без ссылки")):
        rev = world.branch(w1, line("zz-" + key.replace("_", "-"), heads[key]))
        expect_refusal("%s -> отказ: клон конвейера её не несёт" % title,
                       field(ws, "lane_merges_in_change",
                             "docs/changes/zz-" + key.replace("_", "-"), rev, env=env))
    rev = world.branch(w1, line("zz-landed", heads["landed"]))
    expect_value("L1 полоса влита коммитом слияния, ветка снята -> число: голова — предок ствола",
                 field(ws, "lane_merges_in_change", "docs/changes/zz-landed", rev, env=env), 0)
    git(ws, "update-ref", "refs/remotes/origin/w1", w1)

    def two_lines(r):
        write(r, "docs/changes/zz-two/change.yaml",
              manifest("zz-two", head=heads["plain"], base=heads["base"],
                       home_line=(world.cutover, w1)))
    rev = world.branch(w1, two_lines)
    expect_value("W4 линии в двух репозиториях, обе линейны -> 1: полос две",
                 field(ws, "lane_merges_in_change", "docs/changes/zz-two", rev, env=env), 1)
    expect_value("W4 близнец: те же линии, поле о диффе продукта -> 0 (сумма по линиям)",
                 field(ws, "migrations_touched", "docs/changes/zz-two", rev, env=env), 0)
    git(ws, "checkout", "-q", "-f", lines["plain"])
    os.makedirs(os.path.join(ws, "project"), exist_ok=True)
    os.symlink(product, os.path.join(ws, "project", "kacho"))
    expect_value("L близнец: клон на месте по умолчанию project/kacho -> число",
                 field(ws, "lane_merges_in_change", "docs/changes/zz-plain"), 0)
    remove(ws, "project")

    sys.stdout.write("=== verify: сверка освобождений пакета с реестром ===\n")
    only_policy = world.branch(world.cutover, lambda r: write(r, "docs/changes/policy.yaml", real))
    target = "docs/changes/zz-verify"
    other = "docs/changes/zz-other"

    def verify_world(override=None, extra=None, holders=None):
        def mutate(r):
            for pk in (target, other):
                write(r, pk + "/change.yaml", manifest(pk.rsplit("/", 1)[-1],
                                                      head=heads["plain"], base=heads["base"]))
            write(r, target + "/holders.yaml", holders_for(target, policy, override, holders))
            write(r, target + "/reviews/post-diff/go-style-reviewer/x.yaml", "verdict: accepted\n")
            if extra:
                extra(r)
        return world.branch(only_policy, mutate)

    def verify(rev, e=env):
        return run(ws, "verify", "--rev", rev, env=e)

    def expect_code(title, result, code, needle=None):
        rc, _, err = result
        ok = rc == code and (needle is None or needle in err)
        check(title, ok, "ожидался код %d%s, получено %d; stderr %r"
              % (code, " и %r в выводе" % needle if needle else "", rc, err.strip()[-400:]))

    released = sorted(r for r, row in yaml.safe_load(holders_for(target, policy))
                      ["role_applicability"].items() if row["status"] == "not-applicable")
    check("V предпосылка: реестр позволяет освободить на синтетическом пакете хотя бы одну роль",
          bool(released), "освобождать нечего — опыты verify вакуумны")
    design_row = "design-reviewer" if "design-reviewer" in released else released[0]

    expect_code("V близнец: пакет сходится с реестром -> 0", verify(verify_world()), 0)
    typo = yaml.safe_load(holders_for(target, policy))["role_applicability"][design_row]
    typo["evidence_command"] = producer_module.canonical_command(typo["evidence_field"], other)
    expect_code("V N2 команда называет СУЩЕСТВУЮЩИЙ чужой пакет -> находка",
                verify(verify_world({design_row: typo})), 1, "каноническ")
    wrong = dict(yaml.safe_load(holders_for(target, policy))["role_applicability"][design_row])
    wrong["evidence_value"] = 1
    expect_code("V записанное значение не совпало с пересчитанным -> находка",
                verify(verify_world({design_row: wrong})), 1, "evidence_value")
    expect_code("V документ появился при заявленном освобождении -> находка",
                verify(verify_world(extra=lambda r: write(r, target + "/design.md", "#\n")
                                    if design_row == "design-reviewer"
                                    else write(r, target + "/acceptance.md", "#\n"))), 1, "ложен")
    rows = yaml.safe_load(holders_for(target, policy))["role_applicability"]
    missing_role = "wave-reviewer" if "wave-reviewer" in rows else sorted(rows)[-1]

    def drop_role(r):
        doc = yaml.safe_load(holders_for(target, policy))
        del doc["role_applicability"][missing_role]
        write(r, target + "/holders.yaml", yaml.safe_dump(doc, allow_unicode=True))
    expect_code("V роль реестра %s без строки -> находка" % missing_role,
                verify(verify_world(extra=drop_role)), 1, missing_role)
    expect_code("V строка роли, которой нет в реестре -> находка",
                verify(verify_world({"ghost-reviewer": {"status": "applicable"}})), 1, "ghost-reviewer")
    unreg = dict(rows[design_row], predicate_id="no-such-predicate")
    expect_code("V предикат не зарегистрирован -> находка",
                verify(verify_world({design_row: unreg})), 1, "не зарегистрирован")
    foreign_pred = [p for p in policy["applicability_predicates"] if p["role"] != design_row][0]
    stolen = dict(rows[design_row], predicate_id=foreign_pred["id"])
    expect_code("V предикат чужой роли -> находка",
                verify(verify_world({design_row: stolen})), 1, "освобождает роль")
    expect_code("V освобождённая роль оставила запись в пакете -> находка",
                verify(verify_world(extra=lambda r: write(
                    r, target + "/reviews/design/%s/x.yaml" % design_row, "a: 1\n"))), 1, "записи")
    expect_code("V близнец: запись ПРИМЕНИМОЙ роли в пакете -> 0",
                verify(verify_world(extra=lambda r: write(
                    r, target + "/reviews/post-diff/go-style-reviewer/y.yaml", "a: 1\n"))), 0)
    expect_code("V освобождение по дереву продукта не пересчитать (клона нет) -> 2, не 0",
                verify(verify_world(), e={}), 2)
    expect_code("V находка РЯДОМ с непересчитанным -> по-прежнему находка",
                verify(verify_world({design_row: wrong}), e={}), 1)
    expect_code("V пакетов с holders.yaml нет -> 2, а не «находок 0»", verify(only_policy), 2)

    sys.stdout.write("=== verify: каждая роль освобождена либо держится (опыты S1, W7) ===\n")

    def prose(holders_text):
        def mutate(r):
            write(r, "docs/changes/zz-prose/change.yaml", manifest("zz-prose"))
            write(r, "docs/changes/zz-prose/holders.yaml",
                  "schema_version: 1\nchange_id: zz-prose\n" + holders_text)
        return world.branch(only_policy, mutate)
    every_role = "required_holders:\n" + "".join(
        "  h-%s:\n    owner: %s\n" % (role, role) for role in sorted(policy["review_authority"]))
    expect_code("V S1 пакет без role_applicability и без держателей -> находка, а не 2",
                verify(prose("")), 1, "держать её некому")
    expect_code("V близнец: пакет без раздела, каждая роль держится -> 0",
                verify(prose(every_role)), 0)
    lone = [r for r in sorted(policy["review_authority"]) if r != "wave-reviewer"]
    expect_code("V S1 пакет без раздела, у одной роли держателя нет -> находка",
                verify(prose("required_holders:\n" + "".join(
                    "  h-%s:\n    owner: %s\n" % (r, r) for r in lone))), 1, "wave-reviewer")
    expect_code("V W7 освобождённая роль держит держателя в required_holders -> находка",
                verify(verify_world(holders={"h-released": {"kind": "human-external",
                                                             "owner": design_row}})),
                1, "держит в required_holders")
    applicable = sorted(r for r in rows if rows[r]["status"] == "applicable")
    check("V предпосылка: на синтетическом пакете есть применимая роль", bool(applicable),
          "применимых ролей нет — опыты о держателях вакуумны")
    expect_code("V применимая роль без держателя -> находка",
                verify(verify_world(holders={"human-" + applicable[0]: None})), 1,
                "держателя с этим owner")
    expect_code("V строка называет держателя чужой роли -> находка",
                verify(verify_world(holders={"human-" + applicable[0]: {
                    "kind": "human-external", "owner": applicable[-1]}})), 1, "называет держателя")
    expect_code("V держатель без owner -> находка",
                verify(verify_world(holders={"h-anon": {"kind": "human-external"}})), 1, "без owner")
    expect_code("V держатель роли, которой нет в реестре -> находка",
                verify(verify_world(holders={"h-ghost": {"owner": "ghost-reviewer"}})), 1,
                "ghost-reviewer")
    return True


def main():
    tmp = tempfile.mkdtemp(prefix="cg-applicability-")
    try:
        done = prove(tmp)
    except (RuntimeError, OSError, KeyError) as exc:
        # Опыт, который не удалось поставить, — находка пробы, а не «прошло»:
        # недоставленная инъекция неотличима от молчащей.
        check("опыт поставлен", False, "%s: %s" % (type(exc).__name__, exc))
        done = True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    total = len(PASSED) + len(FAILED)
    sys.stdout.write("\nprove_applicability: утверждений %d · прошло %d · провалено %d\n"
                     % (total, len(PASSED), len(FAILED)))
    if done is None or total == 0:
        return 2
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
