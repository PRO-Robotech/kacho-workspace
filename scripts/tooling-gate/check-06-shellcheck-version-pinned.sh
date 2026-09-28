#!/usr/bin/env bash
# check-06 — версия анализатора shell пиннится и объявлена ОДИН раз, а каждый
# шаг, который его зовёт, исполняет запиннутую, а не системную.
#
# Что запрещает эта проверка (#297). Прежде версию выбирал образ ранера
# (`apt-get install shellcheck`), и вердикт принадлежал не дереву, а картинке:
# анализатор одной версии находит на объявлении функции под `trap` один код,
# другой — другой, на каждой строке её тела. Локальный прогон при этом зелен, а
# конвейер красен на том же файле без единой правки между.
#
# Утверждения ниже; третье — контроль в обратную сторону:
#   1. значение версии объявлено РОВНО ОДИН раз (иначе задания исполнят
#      разные версии, и расхождение будет невидимым);
#   2. каждое задание, зовущее `shellcheck`, СНАЧАЛА ставит запиннутую (иначе
#      берёт из образа — то есть ту же лотерею, только тише);
#   3. установка печатает установленную версию (вердикт обязан нести с собой,
#      чем он получен);
#   4. задание, поставившее пин, НЕ ставит анализатор вторым способом (ws#464):
#      `apt-get install … shellcheck` рядом с пином кладёт версию дистрибутива в
#      /usr/bin, и пин действует только по побочному обстоятельству — порядку
#      PATH на образе. Установка «только при отсутствии» (шаг под
#      `command -v shellcheck`) рядом с пином не срабатывает никогда и находкой не
#      является, но считается — перепись называет, сколько установок осмотрено,
#      а не только сколько заданий. Установка узнаётся по ЛОГИЧЕСКОЙ строке шага
#      (`\`-перенос сводится: многострочная `apt-get install -y \` + `shellcheck`
#      — обычная форма блока `run: |`) и по закрытому перечню менеджеров пакетов,
#      включая npm/yarn/pnpm, gem, dnf/yum, apk, zypper, pacman, nix-env, uv
#      (круг 1: многострочная форма и npm проходили молча).
set -uo pipefail

name="check-06-shellcheck-version-pinned"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Корень берётся тем же способом, что у соседей набора: `TOOLING_GATE_ROOT`
# переопределяет его, и этим пользуется инъекция. Без этого проверка судила бы
# СВОЁ дерево при любой песочнице — то есть отвечала бы всегда одно и то же.
# shellcheck source=/dev/null
. "$here/_lib.sh" 2>/dev/null || true
root="$(python3 "$here/../lib/gate_root.py" TOOLING_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2

python3 - "$root" "$name" <<'PY'
import re, sys, pathlib

root = pathlib.Path(sys.argv[1]); name = sys.argv[2]
wf_dir = root / ".github" / "workflows"
files = sorted(wf_dir.glob("*.y*ml")) if wf_dir.is_dir() else []
if not files:
    print(f"[VOID] {name} — процессов не найдено, проверять нечего", file=sys.stderr)
    sys.exit(2)

findings = []
declared_total = 0
jobs_calling = 0
jobs_installing = 0
prints_version = 0
installs_pinned = 0
installs_other = 0
installs_conditional = 0

# Вторая установка — менеджером пакетов. Судится исполняемая строка шага, не
# комментарий: слова `apt-get install shellcheck` стоят и в объяснениях.
MANAGERS = ("apt-get", "apt", "aptitude", "snap", "brew", "pip", "pip3", "pipx", "uv",
            "conda", "mamba", "cabal", "stack", "npm", "yarn", "pnpm", "gem", "dnf", "yum",
            "apk", "zypper", "pacman", "port", "nix-env", "choco", "scoop", "winget")
OTHER_INSTALL = re.compile(
    r"(?<![\w-])(?:" + "|".join(re.escape(m) for m in MANAGERS) + r")(?![\w-])"
    r"[^\n#]*(?<!\S)(?:install|add|i|-S\w*)(?!\S)[^\n#]*\bshellcheck(?:-py)?\b",
    re.I)


def logical(step):
    """Текст шага со сведёнными `\\`-переносами: команда, продолженная на следующую
    строку, — одна строка, и установка через перенос не выпадает из предиката."""
    return re.sub(r"\\\n[ \t]*", " ", step)


def steps_of(block):
    """Шаги задания: текст от `      - ` до следующего такого же, без строк-комментариев."""
    out, cur = [], None
    for line in block.split("\n"):
        if re.match(r"^\s{4,8}- ", line):
            if cur is not None:
                out.append("\n".join(cur))
            cur = [line]
        elif cur is not None:
            cur.append(line)
    if cur is not None:
        out.append("\n".join(cur))
    return ["\n".join(l for l in st.split("\n") if not l.strip().startswith("#")) for st in out]

# Разбор построчный, а не YAML-ом: предмет — ТЕКСТ шага (`run:`), и он всё равно
# читается строками. YAML тут дал бы ложную точность, а зависимость — лишнюю.
for f in files:
    text = f.read_text(encoding="utf-8")
    declared_total += len(re.findall(r'^\s*SHELLCHECK_VERSION:\s*"?[0-9]', text, re.M))

    # Задание — блок от `  <имя>:` на двух пробелах до следующего такого же.
    blocks = re.split(r'^(?=  [A-Za-z0-9_-]+:\s*$)', text, flags=re.M)
    for b in blocks:
        # Дефис списка обязателен в шаблоне: шаг пишется `- run: shellcheck …`,
        # и без него распознавались только МНОГОСТРОЧНЫЕ `run: |`. Проба на
        # синтетике это и показала — «заданий, зовущих анализатор, 0» на файле,
        # который его зовёт.
        calls = re.search(r'^\s*-?\s*run:.*\bshellcheck\b|^\s+shellcheck\b', b, re.M)
        if not calls:
            continue
        jobs_calling += 1
        installs = "shellcheck-v${SHELLCHECK_VERSION}" in b or "SHELLCHECK_VERSION}/shellcheck" in b
        head = (b.strip().splitlines() or ["?"])[0].strip().rstrip(":")
        second = []
        for st in steps_of(b):
            if "SHELLCHECK_VERSION}/shellcheck" in st or "shellcheck-v${SHELLCHECK_VERSION}" in st:
                installs_pinned += 1
            m = OTHER_INSTALL.search(logical(st))
            if m:
                if "command -v shellcheck" in st:
                    installs_conditional += 1
                else:
                    installs_other += 1
                    second.append(m.group(0).strip())
        if installs and second:
            findings.append(
                f"{f.name}: задание «{head}» ставит пин и ставит анализатор ВТОРЫМ способом "
                f"(`{second[0]}`) — вердикт принадлежит порядку PATH на образе, а не пину")
        if installs:
            jobs_installing += 1
            if "shellcheck --version" in b:
                prints_version += 1
            else:
                findings.append(f"{f.name}: задание ставит пин, но не печатает установленную версию")
        else:
            findings.append(
                f"{f.name}: задание «{head}» зовёт shellcheck, "
                f"не поставив запиннутую — исполнится версия образа ранера"
            )

if declared_total == 0:
    findings.append("версия анализатора не объявлена нигде — пина нет вовсе")
elif declared_total > 1:
    findings.append(
        f"значение версии объявлено {declared_total} раз(а): два объявления разойдутся молча, "
        f"и задания исполнят разные версии"
    )

print(f"[CENSUS] {name}: процессов прочитано {len(files)}; заданий, зовущих анализатор, "
      f"{jobs_calling}; из них ставят пин {jobs_installing}; печатают версию {prints_version}; "
      f"объявлений значения {declared_total}; установок осмотрено "
      f"{installs_pinned + installs_other + installs_conditional} (пиннутых {installs_pinned}, "
      f"прочих {installs_other}, условных {installs_conditional})")

for f_ in findings:
    print(f"[FAIL] {name} — {f_}", file=sys.stderr)
if findings:
    print(f"[FAIL] {name} — находок {len(findings)}", file=sys.stderr)
    sys.exit(1)
print(f"[PASS] {name} — осмотрено заданий {jobs_calling}, находок 0")
PY
