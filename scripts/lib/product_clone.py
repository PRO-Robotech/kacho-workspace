#!/usr/bin/env python3
"""product_clone — клон репозитория продукта для наборов, сверяющих стволы. ЕДИНСТВЕННЫЙ способ.

ЗАЧЕМ ОДИН СПОСОБ (ws#1083). Порядок поиска жил тремя копиями — в
`crossrepo-gate`, `foundation-candidates` и `comment-language-gate` — и копии
разошлись: только первая читала `KACHO_MONOREPO`, две другие из копии полосы под
`tmp/` (там `project/` нет) уходили в VOID, а хук отправки выходил на VOID нулём.

ПОРЯДОК, сильнейшее первым:
  1. `KACHO_HOME_<ИМЯ>` — дом, названный явно;
  2. `KACHO_MONOREPO` — дерево монорепо (`kacho`) он называет сам, соседние
     стволы ищутся РЯДОМ с ним и принимаются, только если их `origin` опознан
     как `PRO-Robotech/<имя>`: каталог без опознания — совпадение имени, не клон;
  3. `<корень>/project/<имя>` — условие, положенное в саму копию;
  4. `<каноническая копия>/project/<имя>` — копия полосы (связанная копия или
     клон под `<воркспейс>/tmp/`) видит клоны канонической копии воркспейса.
     Каноническая копия выводится, только если корень — ВЕРШИНА своей рабочей
     копии git: песочница, лежащая внутри чужого репозитория, иначе взяла бы его
     клоны вместо своих синтетических. Правило подъёма — то же, что у
     `scripts/lib/ws-home.sh`: общий каталог git, затем внешний `<X>`, у которого
     корень лежит под `<X>/tmp/` и есть `<X>/.git`.

Третий пункт стоит раньше четвёртого: своё условие копии сильнее соседнего.

Держат порядок инъекции наборов-потребителей (ось «копия полосы» у каждого:
дефект — клоны только у канонической копии, исход не VOID; близнец — у
канонической копии клонов нет, исход VOID).

Вызов из python: `product_clone.clone(root, name)` → путь либо None.
Вызов из bash:   `python3 <этот файл> <корень> <имя>` — печатает путь; клона нет —
пустой вывод и код 2.
"""
import os
import subprocess
import sys

MONOREPO = "kacho"


def is_clone(path):
    return bool(path) and os.path.exists(os.path.join(path, ".git"))


def _git(path, *args):
    out = subprocess.run(["git", "-C", path] + list(args), capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def origin_is(path, name):
    """`origin` клона опознан как `PRO-Robotech/<name>` — https и ssh одинаково."""
    url = _git(path, "remote", "get-url", "origin")
    if not url:
        return False
    if url.endswith(".git"):
        url = url[:-4]
    return url.rstrip("/").endswith("PRO-Robotech/" + name)


def canonical(root):
    """Каноническая копия воркспейса для `root` либо None. Порядок — шапка, п. 4."""
    root = os.path.realpath(root)
    top = _git(root, "rev-parse", "--show-toplevel")
    if not top or os.path.realpath(top) != root:
        return None
    common = _git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return None
    start = os.path.dirname(common) if os.path.basename(common) == ".git" else root
    ws, a = os.path.realpath(start), os.path.realpath(start)
    while a not in ("/", ""):
        if os.path.basename(a) == "tmp" and os.path.exists(os.path.join(os.path.dirname(a), ".git")):
            ws = os.path.dirname(a)
        a = os.path.dirname(a)
    return ws


def clone(root, name):
    """Путь клона репозитория продукта либо None. Порядок — шапка."""
    env = os.environ.get("KACHO_HOME_" + name.upper().replace("-", "_"))
    if is_clone(env):
        return env
    mono = os.environ.get("KACHO_MONOREPO")
    if is_clone(mono):
        if name == MONOREPO:
            return mono
        sibling = os.path.join(os.path.dirname(os.path.abspath(mono)), name)
        if is_clone(sibling) and origin_is(sibling, name):
            return sibling
    own = os.path.join(root, "project", name)
    if is_clone(own):
        return own
    ws = canonical(root)
    if ws:
        guess = os.path.join(ws, "project", name)
        if is_clone(guess):
            return guess
    return None


def main(argv):
    if len(argv) != 3:
        print("product_clone: нужно два аргумента — корень и имя репозитория", file=sys.stderr)
        return 2
    path = clone(argv[1], argv[2])
    if not path:
        return 2
    print(os.path.abspath(path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
