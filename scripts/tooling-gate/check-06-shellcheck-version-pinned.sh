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
# Утверждений три, и третье — контроль в обратную сторону:
#   1. значение версии объявлено РОВНО ОДИН раз (иначе два задания исполнят
#      разные версии, и расхождение будет невидимым);
#   2. каждое задание, зовущее `shellcheck`, СНАЧАЛА ставит запиннутую (иначе
#      берёт из образа — то есть ту же лотерею, только тише);
#   3. установка печатает установленную версию (вердикт обязан нести с собой,
#      чем он получен).
set -uo pipefail

name="check-06-shellcheck-version-pinned"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Корень берётся тем же способом, что у соседей набора: `TOOLING_GATE_ROOT`
# переопределяет его, и этим пользуется инъекция. Без этого проверка судила бы
# СВОЁ дерево при любой песочнице — то есть отвечала бы всегда одно и то же.
# shellcheck source=/dev/null
. "$here/_lib.sh" 2>/dev/null || true
root="${TOOLING_GATE_ROOT:-$(cd "$here/../.." && pwd)}"

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
        if installs:
            jobs_installing += 1
            if "shellcheck --version" in b:
                prints_version += 1
            else:
                findings.append(f"{f.name}: задание ставит пин, но не печатает установленную версию")
        else:
            head = (b.strip().splitlines() or ["?"])[0]
            findings.append(
                f"{f.name}: задание «{head.strip().rstrip(':')}» зовёт shellcheck, "
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
      f"объявлений значения {declared_total}")

for f_ in findings:
    print(f"[FAIL] {name} — {f_}", file=sys.stderr)
if findings:
    print(f"[FAIL] {name} — находок {len(findings)}", file=sys.stderr)
    sys.exit(1)
print(f"[PASS] {name} — осмотрено заданий {jobs_calling}, находок 0")
PY
