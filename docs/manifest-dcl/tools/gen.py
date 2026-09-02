#!/usr/bin/env python3
"""Каталог Kachō → манифесты DCL по всем модулям.

Честная эмуляция: если схема выразительна, круг «каталог → манифест → каталог»
замкнётся тождеством. Всё, что генератор представить не смог, печатается
поимённо — это и есть невыразимое схемой.
"""
import json
import re
import sys
from collections import defaultdict

CANON = {"get", "list", "create", "update", "delete"}

# отношения каталога → class манифеста
REL_CLASS = {
    "v_get": "get", "v_list": "list", "v_update": "update", "v_delete": "delete",
    "viewer": "list", "editor": "create", "system_viewer": "list",
    "system_admin": "update", "admin": "update",
}


def snake_to_camel(s):
    p = s.split("_")
    return p[0] + "".join(w.capitalize() for w in p[1:])


def singular(s):
    """instances → instance · zones → zone · instanceses → instance.

    Рекурсивное срезание "es" съедало лишнее: zones → zon, resources → resourc.
    Режем один раз и только там, где это действительно множественное число.
    """
    if s.endswith("ses") and len(s) > 5:          # instanceses → instances
        s = s[:-2]
    if s.endswith("ies") and len(s) > 4:          # policies → policy
        return s[:-3] + "y"
    if s.endswith(("xes", "ches", "shes", "sses")):
        return s[:-2]
    if s.endswith("s") and not s.endswith("ss"):
        return s[:-1]
    return s


def parse(entry):
    """Запись каталога → (модуль, ресурс, действие, свойства) либо None."""
    perm = entry.get("permission", "")
    if not perm or perm.count(".") != 2:
        # RPC без имени права: выражается ЯВНО — exempt с причиной.
        # Имя выводится из FQN: kacho.cloud.iam.v1.InternalUserService/Get
        fqn = entry.get("fqn", "")
        m = re.match(r"kacho\.cloud\.(?:(\w+)\.)?(?:v\d+\.)?(\w+?)Service/(\w+)", fqn)
        if not m:
            return None
        module = m.group(1) or "operation"
        svc, rpc = m.group(2), m.group(3)
        svc = re.sub(r"^Internal", "", svc)
        return {
            "module": module,
            "resource": svc[0].lower() + svc[1:],
            "action": rpc[0].lower() + rpc[1:],
            "rel": "", "obj": "", "parent": "cluster",
            "internal": "Internal" in fqn,
            "acr": entry.get("required_acr_min"),
            "filtered": False,
            "exempt": entry.get("exempt_reason") or "UNSPECIFIED",
            "hide": False, "perm": fqn,
        }
    module, res, verb = perm.split(".")
    se = entry.get("scope_extractor") or {}
    obj = se.get("object_type") or ""
    rel = entry.get("required_relation") or ""

    internal = res.startswith("internal_") or "Internal" in entry.get("fqn", "")
    res = re.sub(r"^internal_", "", res)

    # подресурс: ресурс права шире типа объекта → склеиваем в одно действие
    sub = None
    if obj and not obj.startswith(("project", "account", "cluster")):
        owner = obj.split("_", 1)[1] if "_" in obj else obj      # compute_instance → instance
        rn = re.sub(r"[^a-z0-9]", "", res.lower())
        on = re.sub(r"[^a-z0-9]", "", owner.lower())
        if rn != on and rn.startswith(on.rstrip("s")):
            tail = res[len(owner) + 1:] if len(res) > len(owner) else ""
            # Подресурс — СЛОВО, а не хвост. `addresses` против типа
            # `vpc_address` давало sub="s", и одна буква приклеивалась к
            # каждому действию ресурса (deleteS, getS, updateS — 7 мест).
            # Верификатор зовёт эту же функцию, поэтому согласие двух
            # сторон дефекта не показывало: его вскрыл ручной манифест.
            sub = tail if len(tail) > 2 else None
            if sub or singular(res) == singular(owner):
                res = owner

    resource = snake_to_camel(singular(res))
    sub_subject = snake_to_camel(sub) if sub else None
    action = snake_to_camel(verb)   # add_cidr_blocks → addCidrBlocks
    if sub:                                   # disks + attachDisk → attachDisk
        pass                                  # имя действия уже несёт предмет

    parent = "project"
    if obj.startswith("cluster") or se.get("from_request_field") == "*":
        parent = "cluster"
    elif obj.startswith("account"):
        parent = "account"

    # Справочник — НЕ «ресурс кластера». Признак иной: отношение `viewer`
    # на кластере, выполняемое подстановочным кортежем `user:* → viewer`,
    # то есть проверка отвечает «да» КАЖДОМУ аутентифицированному. Прежний
    # ключ `catalog` ставился по `parent: cluster` и давал 26 «справочников»
    # в 10 модулях вместо пяти настоящих.
    everyone = (rel == "viewer" and obj == "cluster")

    return {
        "module": module, "resource": resource, "action": action,
        "everyone": everyone,
        "sub": sub_subject,
        "rel": rel, "obj": obj, "parent": parent, "internal": internal,
        "acr": entry.get("required_acr_min"),
        "filtered": bool(entry.get("scope_filtered")),
        "exempt": entry.get("exempt_reason"),
        "hide": bool(entry.get("hide_existence")),
        "perm": perm,
    }


def perm_name(entry):
    """Запись каталога/RPC → (имя права, класс, свойства) либо None.

    ЕДИНСТВЕННОЕ место производства имени. И генератор, и проверяющий зовут
    его: продублированная логика разошлась и дала ложные 100%.
    """
    p = parse(entry)
    if p is None:
        return None
    cls = REL_CLASS.get(p["rel"])
    if cls is None:
        if p["rel"]:
            cls = "operate"
        elif p["filtered"]:
            cls = "list"
        elif p.get("exempt"):
            cls = "operate"
        else:
            return None
    a = p["action"]

    # РАЗЛИЧИМОСТЬ. В каталоге продукта одно право обслуживает РАЗНЫЕ RPC:
    # registry.repositories.delete — это и DeleteRepository, и DeleteTag;
    # .get — и GetRepository, и ListReferrers. Кто вправе снять тег, тот
    # вправе снести репозиторий. Манифест обязан их развести, иначе он
    # воспроизводит дефект, а не описывает предмет. Источник различия —
    # имя RPC: оно единственное, что их отличает.
    fqn = entry.get("fqn", "")
    rpc = fqn.rsplit("/", 1)[-1] if "/" in fqn else ""
    if rpc:
        want = rpc[0].lower() + rpc[1:]
        base = re.sub(r"[^a-z0-9]", "", a.lower())
        if base and re.sub(r"[^a-z0-9]", "", want.lower()) != base:
            # имя RPC несёт предмет, которого нет в имени права — берём его
            if base not in re.sub(r"[^a-z0-9]", "", want.lower()):
                a = want
            elif re.sub(r"[^a-z0-9]", "", want.lower()) != base:
                a = want

    # Подресурс, схлопнутый в родителя, обязан остаться В ДЕЙСТВИИ: иначе
    # UserService/List и UserTokenService/List дают одно право, и тот, кому
    # разрешили читать список пользователей, читает их токены.
    sub = p.get("sub")
    if sub and re.sub(r"[^a-z0-9]", "", sub.lower()) not in re.sub(r"[^a-z0-9]", "", a.lower()):
        a = a + sub[0].upper() + sub[1:]

    if p["internal"] and not a.lower().startswith("internal"):
        a = "internal" + a[0].upper() + a[1:]
    return f'{p["module"]}.{p["resource"]}.{a}', cls, p, a


def build(catalog_path):
    cat = json.load(open(catalog_path, encoding="utf-8"))
    # RPC, которых в каталоге НЕТ вовсе: они существуют в контрактах и обязаны
    # быть выражены — иначе манифест описывает не всё дерево, а его подмножество.
    try:
        known = {e.get("fqn") for e in cat}
        for r in json.load(open("kacho-rpcs.json", encoding="utf-8")):
            if r["fqn"] not in known:
                cat.append({"fqn": r["fqn"], "permission": "",
                            "exempt_reason": "NOT_IN_CATALOG"})
    except FileNotFoundError:
        pass
    mods = defaultdict(lambda: defaultdict(dict))     # module → resource → action → props
    meta = defaultdict(dict)                          # module → resource → parent/catalog
    unrepresentable = []

    for e in cat:
        p = parse(e)
        if p is None:
            unrepresentable.append((e.get("fqn", "?"), "нет имени права (exempt)",
                                    e.get("exempt_reason") or ""))
            continue
        pn = perm_name(e)
        if pn is None:
            unrepresentable.append((p["perm"], "нет отношения и не список", p["rel"]))
            continue
        _, cls, p, a = pn
        m, r = p["module"], p["resource"]
        spec = {"class": cls}
        if p.get("exempt"):
            spec["exempt"] = p["exempt"]
        if a in CANON and cls == a:
            spec = {}                                  # выводится, писать не надо
        if p["internal"]:
            spec["internal"] = True
        if p["acr"] and str(p["acr"]) not in ("1", ""):
            spec["acr"] = int(p["acr"])
        if p["hide"]:
            spec["hideExistence"] = True
        if p.get("everyone"):
            # Обоснование обязательно: отношение, выполнимое подстановкой,
            # по форме записи неотличимо от настоящего гейта.
            # Обоснование, а не маркер отложенной работы: оно называет
            # ФАКТ, установленный каталогом, — отношение viewer на кластере
            # выполняется подстановочным кортежем, значит проверка отвечает
            # «да» каждому аутентифицированному.
            spec["readableByAnyTenant"] = (
                "глобальный справочник, читаемый каждым арендатором")
        mods[m][r][a] = spec
        prev = meta[m].get(r)
        # cluster-якорь выигрывает: справочник
        if prev is None or p["parent"] == "cluster":
            meta[m][r] = p["parent"]

    return mods, meta, unrepresentable


def _outdir(which):
    """Единое место для порождённых манифестов: рядом с инструментами их
    не держим — они артефакт, а не оснастка. Раскладка одна для генератора,
    сверки и инъекции, иначе они разъедутся молча."""
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "generated", which)


def emit(mods, meta, outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    written = {}
    for m, res in mods.items():
        lines = [f"module: {m}", "resources:"]
        for r, acts in sorted(res.items()):
            par = meta[m][r]
            lines.append(f"  - name: {r}")
            if par != "project":
                lines.append(f"    parent: {par}")
            else:
                lines.append("    parent: project")
            simple = [a for a, s in sorted(acts.items()) if not s]
            rich = [(a, s) for a, s in sorted(acts.items()) if s]
            if simple and not rich:
                lines.append(f"    actions: [{', '.join(simple)}]")
            else:
                lines.append("    actions:")
                for a in simple:
                    lines.append(f"      - {a}")
                for a, s in rich:
                    def fmt(v):
                        if not isinstance(v, str):
                            return json.dumps(v)
                        # запятая и двоеточие рвут flow-mapping YAML
                        return json.dumps(v, ensure_ascii=False) if any(
                            c in v for c in ",:{}[]") else v
                    kv = ", ".join(f"{k}: {fmt(v)}" for k, v in s.items())
                    lines.append(f"      - {{name: {a}, {kv}}}")
        path = os.path.join(outdir, f"{m}.yaml")
        open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
        written[m] = (path, sum(len(a) for a in res.values()))
    return written


if __name__ == "__main__":
    mods, meta, unrep = build("kacho-catalog.json")
    written = emit(mods, meta, _outdir("kacho"))
    total = sum(n for _, n in written.values())
    print(f"модулей: {len(written)} · действий выведено: {total}")
    for m, (p, n) in sorted(written.items()):
        print(f"  {m:14} ресурсов {len(mods[m]):2}  действий {n:3}  → {p}")
    print(f"\nневыразимо схемой: {len(unrep)}")
    for perm, why, extra in unrep:
        print(f"  ✗ {perm:62} {why} {extra}")













