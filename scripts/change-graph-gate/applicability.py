#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Производитель свидетельства освобождений и сверка освобождений пакета с реестром.

ЗАЧЕМ. Реестр освобождений `docs/changes/policy.yaml` (§3) требует, чтобы
«неприменимо» опиралось на зарегистрированный предикат и на evidence, которое
этот предикат выполняет. Предикат называет ПОЛЕ и условие на его значение, но
до этого файла число поля производила строка оболочки, записанная в
`holders.yaml` каждого пакета: `git ls-files <путь> | wc -l`. Приёмка
`check-verifier` 2026-09-22 предъявила этой форме шесть опытов, и на каждом она
давала НОЛЬ, то есть освобождение:

    N1  корня пакета нет                  -> `git ls-files` молча пуст, 0
    N2  опечатка в идентификаторе пакета  -> считается чужой (пустой) путь, 0
    E1  команда исполнена в чужом клоне    -> там этих путей нет, 0
    E2  команда исполнена вне git          -> код 128 теряется в трубе, `wc` печатает 0
    H1  `hashes.design_sha256` задан, файла нет -> формула из note уже, чем записанная, 0
    I5  файл снят из индекса, коммит его несёт  -> поле читало индекс, а не коммит, 0

Все шесть — один класс: НОЛЬ НЕПРОЧИТАННОГО ДЕРЕВА ВЫДАН ЗА НОЛЬ НАХОДОК. Здесь
он закрыт устройством, а не оговоркой:

* **число есть только у прочитанного.** Вне git, в клоне без реестра, в клоне,
  чей cutover-коммит из `policy.yaml` §1 не предок ревизии, на ревизии без корня
  пакета, без манифеста пакета — числа нет вовсе: stdout пуст, код 2, причина
  строкой `[UNREAD]`. Подставить такой ответ в `$(…)` и получить «0» нельзя.
* **ревизия названа.** Дом пакетов читается `git ls-tree`/`git show` на
  коммите `--rev` (по умолчанию HEAD — коммит, который судят), индекс и рабочее
  дерево не читаются вовсе. Разрешённый SHA печатается в переписи.
* **клауза `hashes` входит в число.** Документ считается НАЗВАННЫМ, если его
  файл отслеживается в корне пакета ИЛИ его отпечаток задан в
  `hashes.<документ>_sha256` манифеста. Пустая строка в отпечатке тоже считается
  названием: отсутствие заявляется предикатом, а не изображается пустым полем.
* **ревизии линии берутся из манифеста, а не из командной строки.** Для полей
  о дереве продукта `base_sha`/`head_sha` читаются из `change.yaml` на
  названной ревизии дома, клон продукта опознаётся по своему cutover-коммиту
  (предок базы), база обязана быть предком головы. Опечатке негде случиться.
* **опечатку в самой команде ловит сверка, а не производитель.** Режим
  `verify` не исполняет строку `evidence_command` из пакета — он пересчитывает
  поле для ТОГО пакета, в каталоге которого лежит `holders.yaml`, и требует,
  чтобы записанная команда совпала с канонической формой. Команда, называющая
  чужой пакет, — находка (N2), даже если чужой пакет существует.

РЕЖИМЫ.

    applicability.py field <поле> --package docs/changes/<id> [--rev REV] [--home DIR]
        stdout — одно целое; перепись — stderr строкой [CENSUS].
    applicability.py verify [--rev REV] [--home DIR]
        сверка освобождений КАЖДОГО пакета ревизии с реестром; её зовёт
        `check-04-package-releases-reproduce.sh`.

Клон продукта: `KACHO_HOME_<ИМЯ>` (для `PRO-Robotech/kacho` ещё
`KACHO_MONOREPO`), затем `<дом>/project/<имя>`. Кандидат принимается только
если несёт cutover-коммит своего репозитория из `policy.yaml` §1 предком базы:
имя каталога ничего не доказывает. Ревизии линии обязаны быть достижимы в
клоне; ветка, снятая без слияния, делает число непроизводимым — это «не
выполнилось», а не ноль.

Коды: 0 — число произведено (verify: пакеты сверены, находок нет); 1 — находка
(форма пакета неверна; verify: освобождение не воспроизводится или ложно);
2 — дерево не прочитано, числа нет (verify: сверять нечего либо часть
освобождений пересчитать не удалось). Порядок в verify несущий: находка
объявляется раньше беспредметности, иначе одна непересчитанная строка
маскировала бы настоящую находку.
"""

import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover — предпосылка, объявляется кодом 2
    yaml = None

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_UNREAD = 2

HOME_REPO = "PRO-Robotech/kacho-workspace"
POLICY_PATH = "docs/changes/policy.yaml"
PACKAGES_ROOT = "docs/changes"
PACKAGE_PATH = re.compile(r"^docs/changes/([a-z0-9][a-z0-9.-]*[a-z0-9]|[a-z0-9])$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
PRODUCER = "scripts/change-graph-gate/applicability.py"

# Документы замысла пакета: (имя файла в корне пакета, ключ отпечатка в hashes).
ACCEPTANCE = ("acceptance.md", "acceptance_sha256")
DESIGN = ("design.md", "design_sha256")

# Поля о дереве продукта: pathspec отбора по `git diff --name-only base...head`.
DIFF_FIELDS = {
    "migrations_touched": ("*/migrations/*", "*.sql"),
    "proto_files_touched": ("*.proto",),
}
DOCUMENT_FIELDS = {
    "acceptance_documents_referenced": (ACCEPTANCE,),
    "design_documents_referenced": (DESIGN,),
    "exposure_subject_documents_referenced": (ACCEPTANCE, DESIGN),
}
LANE_FIELD = "lane_merges_in_change"
FIELDS = sorted(list(DIFF_FIELDS) + list(DOCUMENT_FIELDS) + [LANE_FIELD])


class Unread(Exception):
    """Дерево не прочитано: числа нет, и это не ноль."""


class Finding(Exception):
    """Предмет прочитан и неверен по форме."""


def census(text):
    sys.stderr.write("[CENSUS] %s\n" % text)


def git(cwd, *args):
    """(код, stdout, stderr). Трубы нет: код возврата не теряется."""
    try:
        out = subprocess.run(["git", "-C", cwd] + list(args),
                             capture_output=True, text=True, check=False)
    except OSError as exc:
        return 127, "", str(exc)
    return out.returncode, out.stdout, out.stderr.strip()


def canonical_command(field, package):
    """Единственная форма `evidence_command`, которую принимает сверка."""
    return "python3 %s field %s --package %s --rev HEAD" % (PRODUCER, field, package)


def normalize(text):
    return " ".join(str(text).split())


# ── ДОМ ПАКЕТОВ НА НАЗВАННОЙ РЕВИЗИИ ─────────────────────────────────────────

class Home:
    """Клон дома пакетов, опознанный реестром и cutover-коммитом, на ревизии."""

    def __init__(self, home_dir, rev):
        if yaml is None:
            raise Unread("разборщик YAML недоступен — манифесты и реестр читать нечем")
        rc, top, err = git(home_dir, "rev-parse", "--show-toplevel")
        if rc != 0:
            raise Unread("%s — не git-дерево (git: %s); дом пакетов не прочитан"
                         % (home_dir, err or "код %d" % rc))
        self.top = top.strip()
        rc, sha, _ = git(self.top, "rev-parse", "--verify", "--quiet", rev + "^{commit}")
        if rc != 0:
            raise Unread("ревизия %r в %s не разрешается в коммит" % (rev, self.top))
        self.sha = sha.strip()
        self.policy = self.load_yaml(POLICY_PATH, missing=(
            "в ревизии %s нет %s — это не дом пакетов (чужой клон?)"))
        if not isinstance(self.policy, dict):
            raise Finding("%s на %s — не отображение" % (POLICY_PATH, self.sha))
        self.cutovers = {}
        for entry in self.policy.get("repositories") or []:
            if isinstance(entry, dict) and entry.get("repo"):
                self.cutovers[str(entry["repo"])] = str(entry.get("cutover_commit") or "")
        cutover = self.cutovers.get(HOME_REPO, "")
        if not SHA40.match(cutover):
            raise Finding("%s не называет cutover-коммит %s" % (POLICY_PATH, HOME_REPO))
        rc, _, _ = git(self.top, "merge-base", "--is-ancestor", cutover, self.sha)
        if rc == 1:
            raise Unread("cutover %s… не предок ревизии %s — ревизия вне DAG дома пакетов"
                         % (cutover[:12], self.sha[:12]))
        if rc != 0:
            raise Unread("cutover-коммита %s… нет в клоне %s — это не клон %s"
                         % (cutover[:12], self.top, HOME_REPO))
        self._files = None

    def load_yaml(self, path, missing):
        rc, text, _ = git(self.top, "show", "%s:%s" % (self.sha, path))
        if rc != 0:
            raise Unread(missing % (self.sha[:12], path))
        try:
            return yaml.safe_load(text)
        except yaml.YAMLError as exc:
            raise Finding("%s на %s не разбирается: %s" % (path, self.sha[:12], exc))

    def files(self):
        """Отслеживаемые пути `docs/changes/` НА КОММИТЕ, не в индексе."""
        if self._files is None:
            rc, out, err = git(self.top, "ls-tree", "-r", "--name-only", self.sha,
                               "--", PACKAGES_ROOT + "/")
            if rc != 0:
                raise Unread("ls-tree %s не прочитан: %s" % (self.sha[:12], err))
            self._files = [line for line in out.split("\n") if line]
        return self._files


class Package:
    """Пакет изменения на ревизии дома: корень, манифест, отслеживаемые файлы."""

    def __init__(self, home, package):
        match = PACKAGE_PATH.match(package or "")
        if not match:
            raise Finding("путь пакета %r не имеет формы docs/changes/<id>" % package)
        self.home = home
        self.path = package
        self.change_id = match.group(1)
        prefix = package + "/"
        self.files = [f for f in home.files() if f.startswith(prefix)]
        if not self.files:
            raise Unread("корня %s нет на ревизии %s: ноль здесь — непрочитанное "
                         "дерево, а не ноль находок" % (prefix, home.sha[:12]))
        self.manifest = home.load_yaml(prefix + "change.yaml", missing=(
            "на ревизии %s нет %s — клауза hashes не читается, числа нет"))
        if not isinstance(self.manifest, dict):
            raise Finding("%schange.yaml — не отображение" % prefix)
        if str(self.manifest.get("change_id")) != self.change_id:
            raise Finding("change_id манифеста %r не совпадает с каталогом %r"
                          % (self.manifest.get("change_id"), self.change_id))
        hashes = self.manifest.get("hashes")
        if hashes is None:
            hashes = {}
        if not isinstance(hashes, dict):
            raise Finding("%schange.yaml: hashes — не отображение" % prefix)
        self.hashes = hashes

    def document(self, spec):
        """(назван ли документ, файл отслеживается, отпечаток задан)."""
        name, key = spec
        has_file = (self.path + "/" + name) in self.files
        has_hash = key in self.hashes and self.hashes[key] is not None
        return has_file or has_hash, has_file, has_hash

    def ranges(self):
        """[(repo, base, head)] — репозитории манифеста, названные с головой."""
        coords = self.manifest.get("coordinates") or {}
        repos = coords.get("repositories") if isinstance(coords, dict) else None
        out = []
        for entry in repos or []:
            if not isinstance(entry, dict) or "head_sha" not in entry:
                continue
            repo, base, head = (str(entry.get("repo") or ""), str(entry.get("base_sha") or ""),
                                str(entry.get("head_sha") or ""))
            if not repo or not SHA40.match(base) or not SHA40.match(head):
                raise Finding("манифест %s: репозиторий %r назван с головой, но base/head "
                              "не 40 hex" % (self.path, repo))
            out.append((repo, base, head))
        if not out:
            raise Unread("манифест %s не называет ни одного репозитория с head_sha — "
                         "линии нет, диффа нет, числа нет" % self.path)
        return out


# ── КЛОН РЕПОЗИТОРИЯ ЛИНИИ ───────────────────────────────────────────────────

def clone_candidates(home, repo):
    if repo == HOME_REPO:
        return [(home.top, "дом пакетов")]
    name = repo.rsplit("/", 1)[-1]
    env = "KACHO_HOME_" + re.sub(r"[^A-Za-z0-9]", "_", name).upper()
    out = []
    if os.environ.get(env):
        out.append((os.environ[env], "$" + env))
    if repo == "PRO-Robotech/kacho" and os.environ.get("KACHO_MONOREPO"):
        out.append((os.environ["KACHO_MONOREPO"], "$KACHO_MONOREPO"))
    out.append((os.path.join(home.top, "project", name), "project/" + name))
    return out


def resolve_line(home, repo, base, head):
    """Клон, несущий cutover своего репозитория предком базы, и обе ревизии."""
    cutover = home.cutovers.get(repo, "")
    if not SHA40.match(cutover):
        raise Finding("%s §1 не называет cutover-коммит репозитория %s" % (POLICY_PATH, repo))
    rejected = []
    for path, label in clone_candidates(home, repo):
        rc, top, _ = git(path, "rev-parse", "--show-toplevel")
        if rc != 0:
            rejected.append("%s (%s): не git-дерево" % (label, path))
            continue
        top = top.strip()
        missing = [s for s in (base, head)
                   if git(top, "cat-file", "-e", s + "^{commit}")[0] != 0]
        if missing:
            rejected.append("%s (%s): нет ревизий %s" % (label, top, ", ".join(m[:12] for m in missing)))
            continue
        rc, _, _ = git(top, "merge-base", "--is-ancestor", cutover, base)
        if rc != 0:
            rejected.append("%s (%s): cutover %s… не предок базы — не клон %s"
                            % (label, top, cutover[:12], repo))
            continue
        rc, _, _ = git(top, "merge-base", "--is-ancestor", base, head)
        if rc != 0:
            raise Finding("%s: база %s… не предок головы %s… — диапазон не линия изменения"
                          % (repo, base[:12], head[:12]))
        return top
    raise Unread("клон %s с ревизиями линии не найден: %s" % (repo, "; ".join(rejected)))


# ── ПОЛЯ ─────────────────────────────────────────────────────────────────────

def measure(home, package, field):
    """(значение, перепись). Unread/Finding вместо числа, никогда не «0 по умолчанию»."""
    if field in DOCUMENT_FIELDS:
        value = 0
        parts = []
        for spec in DOCUMENT_FIELDS[field]:
            named, has_file, has_hash = package.document(spec)
            value += 1 if named else 0
            parts.append("%s: файл %s, hashes.%s %s" % (
                spec[0], "да" if has_file else "нет", spec[1], "задан" if has_hash else "нет"))
        return value, ("ревизия %s · пакет %s: отслеживаемых файлов %d · %s"
                       % (home.sha, package.path, len(package.files), " · ".join(parts)))
    if field in DIFF_FIELDS or field == LANE_FIELD:
        value = 0
        parts = []
        for repo, base, head in package.ranges():
            top = resolve_line(home, repo, base, head)
            if field == LANE_FIELD:
                rc, total, err = git(top, "rev-list", "--count", "%s..%s" % (base, head))
                rc2, merges, err2 = git(top, "rev-list", "--merges", "--count",
                                        "%s..%s" % (base, head))
                if rc != 0 or rc2 != 0:
                    raise Unread("%s: rev-list не прочитан: %s" % (repo, err or err2))
                if int(total) == 0:
                    raise Unread("%s: в %s..%s нет коммитов — знаменатель обхода ноль"
                                 % (repo, base[:12], head[:12]))
                value += int(merges)
                parts.append("%s %s..%s: коммитов %d, слияний %d"
                             % (repo, base[:12], head[:12], int(total), int(merges)))
            else:
                rc, allpaths, err = git(top, "diff", "--name-only", "%s...%s" % (base, head))
                if rc != 0:
                    raise Unread("%s: diff не прочитан: %s" % (repo, err))
                total = [p for p in allpaths.split("\n") if p]
                if not total:
                    raise Unread("%s: дифф %s...%s пуст — знаменатель обхода ноль"
                                 % (repo, base[:12], head[:12]))
                rc, picked, err = git(top, "diff", "--name-only", "%s...%s" % (base, head),
                                      "--", *DIFF_FIELDS[field])
                if rc != 0:
                    raise Unread("%s: diff с отбором не прочитан: %s" % (repo, err))
                hit = [p for p in picked.split("\n") if p]
                value += len(hit)
                parts.append("%s %s...%s: путей диффа %d, отобрано %d"
                             % (repo, base[:12], head[:12], len(total), len(hit)))
        return value, "ревизия дома %s · пакет %s · %s" % (home.sha, package.path, " · ".join(parts))
    raise Finding("поле %r производителю неизвестно; известные: %s" % (field, ", ".join(FIELDS)))


def cmd_field(args):
    try:
        home = Home(args.home, args.rev)
        package = Package(home, args.package)
        value, text = measure(home, package, args.field)
    except Unread as exc:
        sys.stderr.write("[UNREAD] %s\n" % exc)
        return EXIT_UNREAD
    except Finding as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        return EXIT_FINDING
    census(text)
    sys.stdout.write("%d\n" % value)
    return EXIT_OK


# ── СВЕРКА ОСВОБОЖДЕНИЙ ПАКЕТОВ С РЕЕСТРОМ ───────────────────────────────────

def role_records(package, holders, role):
    """Следы роли в пакете: каталог с именем роли либо свидетельство её держателя."""
    coords = []
    for holder in (holders.get("required_holders") or {}).values():
        if isinstance(holder, dict) and holder.get("owner") == role and holder.get("evidence_coordinate"):
            coords.append(package.path + "/" + str(holder["evidence_coordinate"]).strip("/") + "/")
    out = []
    for path in package.files:
        inner = path[len(package.path) + 1:]
        if role in inner.split("/")[:-1] or any(path.startswith(c) for c in coords):
            out.append(inner)
    return out


def verify_package(home, predicates, roles, holders_path):
    """(находки, непрочитанное, освобождений пересчитано) по одному пакету."""
    findings, unread, done = [], [], 0
    package_path = holders_path.rsplit("/", 1)[0]
    try:
        package = Package(home, package_path)
    except (Unread, Finding) as exc:
        return ["%s: %s" % (package_path, exc)], [], 0
    holders = home.load_yaml(holders_path, missing="на %s нет %s")
    if not isinstance(holders, dict):
        return ["%s — не отображение" % holders_path], [], 0
    if str(holders.get("change_id")) != package.change_id:
        findings.append("%s: change_id %r не совпадает с каталогом %r"
                        % (holders_path, holders.get("change_id"), package.change_id))
    table = holders.get("role_applicability")
    if not isinstance(table, dict):
        return findings, [], None
    for role in sorted(roles - set(table)):
        findings.append("%s: роль реестра %s без строки role_applicability" % (package.path, role))
    for role in sorted(set(table) - roles):
        findings.append("%s: строка %s есть, роли в review_authority нет" % (package.path, role))
    for role in sorted(set(table) & roles):
        row = table[role] if isinstance(table[role], dict) else {}
        status = row.get("status")
        where = "%s · %s" % (package.path, role)
        if status == "applicable":
            continue
        if status != "not-applicable":
            findings.append("%s: статус %r — ни applicable, ни not-applicable" % (where, status))
            continue
        pid = row.get("predicate_id")
        pred = predicates.get(pid)
        if pred is None:
            findings.append("%s: предикат %r не зарегистрирован в %s" % (where, pid, POLICY_PATH))
            continue
        if pred.get("role") != role:
            findings.append("%s: предикат %s освобождает роль %s, а не эту"
                            % (where, pid, pred.get("role")))
            continue
        field = pred.get("evidence_field")
        if row.get("evidence_field") != field:
            findings.append("%s: evidence_field %r, а предикат %s судит %r"
                            % (where, row.get("evidence_field"), pid, field))
            continue
        canonical = canonical_command(field, package.path)
        if normalize(row.get("evidence_command", "")) != canonical:
            findings.append("%s: evidence_command не в канонической форме — записано %r, "
                            "ожидается %r" % (where, normalize(row.get("evidence_command", "")),
                                              canonical))
        records = role_records(package, holders, role)
        if records:
            findings.append("%s: освобождённая роль оставила в пакете записи (%s) — предмет "
                            "был, ложно освобождение" % (where, ", ".join(records)))
        try:
            value, _ = measure(home, package, field)
        except Unread as exc:
            unread.append("%s: освобождение не пересчитано — %s" % (where, exc))
            continue
        except Finding as exc:
            findings.append("%s: %s" % (where, exc))
            continue
        done += 1
        if row.get("evidence_value") != value:
            findings.append("%s: evidence_value %r, пересчитано на %s — %d"
                            % (where, row.get("evidence_value"), home.sha[:12], value))
        if pred.get("satisfied_when") != "equals" or value != pred.get("value"):
            findings.append("%s: предикат %s ложен — %s = %d, освобождает только %s %r"
                            % (where, pid, field, value, pred.get("satisfied_when"),
                               pred.get("value")))
    return findings, unread, done


def cmd_verify(args):
    try:
        home = Home(args.home, args.rev)
    except Unread as exc:
        sys.stderr.write("[UNREAD] %s\n" % exc)
        return EXIT_UNREAD
    except Finding as exc:
        sys.stderr.write("[FAIL] %s\n" % exc)
        return EXIT_FINDING
    predicates = {}
    for p in home.policy.get("applicability_predicates") or []:
        if isinstance(p, dict) and p.get("id"):
            predicates[p["id"]] = p
    roles = set(home.policy.get("review_authority") or {})
    try:
        holders_files = sorted(f for f in home.files()
                               if re.match(r"^docs/changes/[^/]+/holders\.yaml$", f))
    except Unread as exc:
        sys.stderr.write("[UNREAD] %s\n" % exc)
        return EXIT_UNREAD
    findings, unread = [], []
    judged, prose, done = [], [], 0
    for path in holders_files:
        try:
            f, u, d = verify_package(home, predicates, roles, path)
        except (Unread, Finding) as exc:
            findings.append("%s: %s" % (path, exc))
            continue
        findings += f
        unread += u
        if d is None:
            prose.append(path.split("/")[2])
        else:
            judged.append(path.split("/")[2])
            done += d
    census("ревизия %s · ролей реестра %d · предикатов %d · пакетов с holders.yaml %d: "
           "сверено %d (%s), без раздела role_applicability %d (%s) · освобождений "
           "пересчитано %d, не пересчитано %d · находок %d"
           % (home.sha, len(roles), len(predicates), len(holders_files), len(judged),
              ", ".join(judged) or "—", len(prose), ", ".join(prose) or "—",
              done, len(unread), len(findings)))
    for line in findings:
        sys.stderr.write("[FAIL] %s\n" % line)
    for line in unread:
        sys.stderr.write("[UNREAD] %s\n" % line)
    if findings:
        return EXIT_FINDING
    if not judged:
        sys.stderr.write("[UNREAD] ни одного пакета с разделом role_applicability на %s — "
                         "сверять нечего, это не «находок 0»\n" % home.sha[:12])
        return EXIT_UNREAD
    if unread:
        return EXIT_UNREAD
    return EXIT_OK


def main(argv):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="mode", required=True)
    pf = sub.add_parser("field")
    pf.add_argument("field")
    pf.add_argument("--package", required=True)
    pf.add_argument("--rev", default="HEAD")
    pf.add_argument("--home", default=os.getcwd())
    pv = sub.add_parser("verify")
    pv.add_argument("--rev", default="HEAD")
    pv.add_argument("--home", default=os.getcwd())
    args = parser.parse_args(argv)
    if args.mode == "field":
        return cmd_field(args)
    return cmd_verify(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
