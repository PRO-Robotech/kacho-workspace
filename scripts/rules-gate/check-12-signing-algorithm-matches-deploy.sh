#!/usr/bin/env bash
# check-12 — АЛГОРИТМ ПОДПИСИ, НАЗВАННЫЙ КОРПУСОМ, — ТОТ, КОТОРЫМ ПЛАТФОРМА ПОДПИСЫВАЕТ.
#
# Предмет: боевая посадка у корпуса — кортеж «authMode=production + mTLS +
# sslmode=require + <подпись токена>» (`00-kacho-core.md` запись
# `ban16-production-posture`, `security.md` записи `sec-dev-stand-in-production-mode`
# и `sec-e2e-uses-real-issuance`). Корпус называл подпись «RS256», а служба
# доступа своего умолчания не имеет (`authn.token-signing.algorithm`: «выбор
# подписи — решение установки»), и каждый профиль посадки продукта выбирает
# ES256 (измерено на стенде 2026-10-10: ключ EC, alg ES256, use sig; ws#994).
# Исполнитель, сверяющий стенд с нормой, получал «не та подпись» на исправном
# стенде либо «та» на чужом.
#
# ОТКУДА ИСТИНА. Не из памяти и не из этого файла: из СТВОЛА дерева продукта —
# `deploy/helm/umbrella/values*.yaml`, ключ `tokenSigning.algorithm` в каждом
# профиле, где он непуст. Ствол разрешается общим резолвом
# `scripts/docs-gate/_lib.py` (индекс припаркованной копии стволом не является).
# Дерево продукта — `KACHO_MONOREPO`, иначе `project/kacho` у ОСНОВНОЙ копии
# воркспейса (общий git-каталог), чтобы полоса в своём worktree судила тем же
# продуктом, что и основная копия.
#
# ЧТО ТАКОЕ УТВЕРЖДЕНИЕ КОРПУСА. Строка области (`corpus_scope.py`), у которой в
# части ДО `red:` есть якорь подписи — `authMode=production`, «подпис…», «sign…»,
# «авториз…», «токен»/«token», «выпуск»/«issuance» — и имя алгоритма JWS (`RS|ES|PS|HS` + 256/384/512, `EdDSA`). Каждое такое имя
# обязано входить в множество алгоритмов профилей. Якорь шире слова «подпись»
# намеренно: «авторизоваться RS256 через выпуск» — то же утверждение о подписи
# платформы, сказанное через выпуск токена. Законные близнецы:
#   * имя алгоритма в красной колонке («red: anonymous/HS256/…») — это нарушение,
#     а не утверждение о платформе;
#   * имя сразу после «forged»/«поддельный» («forged HS256 ⇒ 401») — утверждение
#     об отказе подделке, а не о подписи платформы.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 без предмета (`[VOID]`): нет
# дерева продукта, ствол не разрешён, ни один профиль не объявляет алгоритм.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=check-12-signing-algorithm-matches-deploy
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] $NAME — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}

# Основная копия воркспейса: родитель общего git-каталога. Из worktree полосы
# `--show-toplevel` отдал бы саму полосу, где клона продукта нет.
common="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
main_ws="$( [ -n "$common" ] && dirname "$common" || echo "$SELF_DIR/../.." )"
MONO="${KACHO_MONOREPO:-$main_ws/project/kacho}"

if [ ! -d "$MONO" ]; then
    echo "[VOID] $NAME — дерева продукта нет ($MONO): алгоритм подписи посадки выводить не из чего"
    exit 2
fi

python3 - "$root" "$SELF_DIR" "$MONO" <<'PY'
import os, re, subprocess, sys
root, here, mono = sys.argv[1], sys.argv[2], sys.argv[3]
NAME = "check-12-signing-algorithm-matches-deploy"
sys.path.insert(0, here)
sys.path.insert(0, os.path.join(here, "..", "docs-gate"))
import corpus_scope
import _lib as docs_lib
import yaml

ref = docs_lib.trunk(mono)
if not ref:
    print("[VOID] %s — ствол дерева продукта (%s) не разрешён: судить по индексу "
          "припаркованной копии значило бы судить не посадку" % (NAME, mono))
    sys.exit(2)

profiles = sorted(p for p in docs_lib.trunk_files(mono, ref, "deploy/helm/umbrella")
                  if re.fullmatch(r"deploy/helm/umbrella/values[^/]*\.ya?ml", p))


def algorithms(node, found):
    if isinstance(node, dict):
        ts = node.get("tokenSigning")
        if isinstance(ts, dict):
            alg = ts.get("algorithm")
            if isinstance(alg, str) and alg.strip():
                found.add(alg.strip())
        for v in node.values():
            algorithms(v, found)
    elif isinstance(node, list):
        for v in node:
            algorithms(v, found)


deployed = {}
for p in profiles:
    text = docs_lib.trunk_show(mono, ref, p)
    if text is None:
        continue
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError:
        print("КРАСНОЕ ПРОФИЛЬ НЕ РАЗБИРАЕТСЯ %s@%s — алгоритм посадки из него не выведен" % (p, ref))
        sys.exit(1)
    found = set()
    algorithms(doc, found)
    for a in found:
        deployed.setdefault(a, []).append(os.path.basename(p))

if not deployed:
    print("[VOID] %s — ни один профиль посадки (%d файлов deploy/helm/umbrella/values*.yaml "
          "на %s) не объявляет tokenSigning.algorithm: сверять корпус не с чем"
          % (NAME, len(profiles), ref))
    sys.exit(2)

rels = corpus_scope.files(root)
if rels is None or not rels:
    print("[VOID] %s — область корпуса пуста либо корень %s не git-репозиторий" % (NAME, root))
    sys.exit(2)

ALG = re.compile(r"(?<![A-Za-z0-9])((?:RS|ES|PS|HS)(?:256|384|512)|EdDSA)(?![A-Za-z0-9])")
ANCHOR = re.compile(r"authMode=production|подпис|\bsign|авториз|токен|\btoken|issuance|выпуск", re.I)
# Подделка — не подпись платформы: «forged HS256 ⇒ 401» утверждает отказ.
FORGED = re.compile(r"(?:forged|поддел\w*|поддельн\w*)\s+$", re.I)

n_lines = n_claims = 0
finds = []
for rel in rels:
    for i, line in enumerate(corpus_scope.lines(root, rel), 1):
        n_lines += 1
        norm = re.split(r"\bred:", line, maxsplit=1)[0]
        if not ANCHOR.search(norm):
            continue
        algs = [m.group(1) for m in ALG.finditer(norm)
                if not FORGED.search(norm[:m.start()])]
        if not algs:
            continue
        n_claims += 1
        for a in algs:
            if a not in deployed:
                finds.append((rel, i, a))

decl = "; ".join("%s — %s" % (a, ", ".join(sorted(ps))) for a, ps in sorted(deployed.items()))
for rel, i, a in finds:
    print("КРАСНОЕ ПОДПИСЬ НЕ ТА %s:%d — корпус называет %s, а профили посадки на стволе "
          "продукта подписывают: %s" % (rel, i, a, decl))
print("корень %s; продукт %s@%s, профилей %d, объявляют алгоритм: %s; осмотрено: файлов %d, "
      "строк %d, утверждений о подписи %d; находок %d"
      % (root, mono, ref, len(profiles), decl, len(rels), n_lines, n_claims, len(finds)))
sys.exit(1 if finds else 0)
PY
