#!/usr/bin/env python3
"""Целостность ролей: каждое право роли обязано существовать в контракте.

Ради этого роль и пишется полями, а не строкой `vpc.network.*`. Строку
проверить нечем: она годна по форме при снятом глаголе. Поля сверяются с
перечнем ресурсов, поэтому снятие глагола роняет валидацию в тот же заход.

Печатает объём осмотренного: «ноль находок» обязано быть отличимо от
«ноль прочитанного».
"""
import sys
import yaml

CANON = {"get", "list", "create", "update", "delete"}
LEVELS = {"project", "account", "cluster"}


# Действия, читаемые ЛЮБЫМ аутентифицированным. Считаются и печатаются
# всегда: рост их числа обязан быть заметен, потому что каждое такое
# действие отвечает «да» каждому, а по форме записи неотличимо от гейта.
def public_reads(raw):
    out = []
    for r in raw.get("resources", []):
        for v in r.get("verbs", []):
            if isinstance(v, dict) and "readableByAnyTenant" in v:
                out.append((r["name"], v["name"], v["readableByAnyTenant"]))
    return out


def verb_props(v):
    """Действие манифеста → (имя, класс, internal, admin)."""
    if isinstance(v, str):
        return v, v, False, False
    n = v["name"]
    cls = v.get("class") or (n if n in CANON else None)
    return n, cls, bool(v.get("internal")), False


def load(path):
    d = yaml.safe_load(open(path, encoding="utf-8"))
    mod = d["module"]
    res = {}
    for r in d["resources"]:
        res[r["name"]] = {n: (c, i, a) for n, c, i, a in map(verb_props, r["verbs"])}
    return d, mod, res


def object_types(path="live-objecttypes.txt"):
    try:
        return {l.strip() for l in open(path, encoding="utf-8") if l.strip()}
    except FileNotFoundError:
        return None


def check(path):
    d, mod, res = load(path)
    err = []
    # Имя ресурса обязано совпасть с именем ТИПА, которым его адресует селектор.
    # Не совпало и не объявлено — селектор инертен целиком: привязка создаётся,
    # читается и выглядит действующей, а прав не даёт ни одного.
    raw_doc = yaml.safe_load(open(path, encoding="utf-8"))
    for r in raw_doc.get("resources", []):
        if "catalog" in r:
            err.append(f"{r.get('name')}: ключ catalog снят — он равнялся "
                       f"parent: cluster и давал 26 «справочников» вместо "
                       f"пяти; признак чтения всеми стоит на ДЕЙСТВИИ")
    pubs = public_reads(raw_doc)
    # Имя переменной цикла НЕ `res`: им зовётся словарь ресурсов, и затенение
    # проявилось бы за шестьдесят строк отсюда, в разборе классов.
    for pub_res, pub_verb, why in pubs:
        if not isinstance(why, str) or len(why.strip()) < 16:
            err.append(f"{pub_res}.{pub_verb}: readableByAnyTenant требует "
                       f"обоснования "
                       f"словами — это чтение доступно КАЖДОМУ "
                       f"аутентифицированному без выдачи")

    cat = object_types()
    if cat is None:
        print("⚠ каталога типов нет рядом — ось objectType НЕ проверена")
    else:
        raw = yaml.safe_load(open(path, encoding="utf-8"))
        n_typed = 0
        for r in raw["resources"]:
            decl = r.get("objectType")
            want = decl or f"{mod}.{r['name']}"
            if want in cat:
                n_typed += 1
                continue
            if decl:
                err.append(f"{r['name']}: objectType «{decl}» каталогу типов "
                           f"неизвестен")
            elif any(t.startswith(mod + ".") and
                     t.split(".", 1)[1].rstrip("s") == r["name"].rstrip("s")
                     for t in cat):
                other = next(t for t in cat if t.startswith(mod + ".")
                             and t.split(".", 1)[1].rstrip("s") == r["name"].rstrip("s"))
                err.append(f"{r['name']}: каталог называет тип «{other}» — "
                           f"объяви objectType, иначе селектор инертен")
        print(f"каталог типов: {len(cat)} имён · адресуемых ресурсов модуля "
              f"{n_typed} из {len(res)}")
    seen_ids, seen_names = set(), set()
    n_grants = n_verbs = n_bind = 0

    for role in d.get("roles", []):
        rid = role.get("id")
        if not rid:
            err.append("роль без id"); continue
        if rid in seen_ids:
            err.append(f"{rid}: id повторяется")
        seen_ids.add(rid)
        if not role.get("name"):
            err.append(f"{rid}: нет имени — роль выдают люди, им нужно слово")
        nm = role.get("name")
        if nm in seen_names:
            err.append(f"{rid}: имя «{nm}» уже носит другая роль")
        seen_names.add(nm)

        # `assignableAt` снят: системная роль по правилу продукта выдаётся
        # где угодно («a SYSTEM role is assignable anywhere», миграция 0072).
        # Ограничение есть только у кастомных ролей, а манифест их не заводит.
        if role.get("assignableAt"):
            err.append(f"{rid}: ключ assignableAt снят — системная роль "
                       f"выдаётся на любом уровне")
        allows_internal = bool(role.get("includesInternal"))

        for g in role.get("grants", []):
            n_grants += 1
            if g.get("module") != mod:
                err.append(f"{rid}: чужой модуль «{g.get('module')}» в манифесте {mod}")
                continue
            rname = g.get("resource")
            has_verbs, has_classes = "verbs" in g, "classes" in g
            if has_verbs == has_classes:
                err.append(f"{rid}/{rname}: ровно одно из verbs|classes, не оба и не ноль")
                continue

            if rname == "*":
                if has_verbs:
                    err.append(f"{rid}: resource:\"*\" сочетается только с classes — "
                               f"поимённый глагол на всех ресурсах бессмыслен")
                    continue
                targets = list(res)
            else:
                if rname not in res:
                    err.append(f"{rid}: ресурса «{rname}» в модуле нет")
                    continue
                targets = [rname]

            if has_classes:
                for cls in g["classes"]:
                    hit = 0
                    for t in targets:
                        for vn, (vc, vi, va) in res[t].items():
                            if vc != cls:
                                continue
                            # рост по классу НЕ захватывает плоскость исполнения
                            # и административные действия: без этого
                            # classes:[get] выдал бы internalGetReference
                            if vi or va:
                                continue
                            hit += 1
                            n_verbs += 1
                    if hit == 0:
                        err.append(f"{rid}/{rname}: класс «{cls}» не покрывает "
                                   f"ни одного действия — право пустое")
            else:
                for vn in g["verbs"]:
                    t = targets[0]
                    if vn not in res[t]:
                        err.append(f"{rid}: {mod}.{t}.{vn} — такого действия нет "
                                   f"в контракте (снято или опечатка)")
                        continue
                    _, vi, va = res[t][vn]
                    if vi and not allows_internal:
                        err.append(f"{rid}: {mod}.{t}.{vn} внутреннее, а роль не "
                                   f"объявила includesInternal")
                    n_verbs += 1

        for v_ in (role.get("grants") or []):
            pass
        if role.get("seedTo") or role.get("bindings"):
            err.append(f"{rid}: ключи seedTo и bindings сняты — выдача при "
                       f"установке объявляется в разделе seed.groups[].grant")

    # Право, которого не несёт НИ ОДНА преднастроенная роль: выдать его можно
    # только кастомной ролью. Это законно, но обязано быть видно — иначе
    # «поверхность есть, звать её некому» неотличимо от продуманного решения.
    granted = set()
    for role in d.get("roles", []):
        for g in role.get("grants", []):
            tgt = list(res) if g.get("resource") == "*" else [g.get("resource")]
            if "verbs" in g:
                for vn in g["verbs"]:
                    granted.add((tgt[0], vn))
            else:
                for t in tgt:
                    for vn, (vc, vi, va) in res.get(t, {}).items():
                        if vc in g.get("classes", []) and not vi and not va:
                            granted.add((t, vn))
    orphans = sorted(f"{mod}.{t}.{v}" for t, vs in res.items()
                     for v in vs if (t, v) not in granted)

    # Ключ схемы обязан ОСТАТЬСЯ СТРОКОЙ после разбора. YAML превращает
    # `on`, `off`, `yes`, `no`, `y`, `n` в логические значения: файл валиден,
    # глазом читается верно, а словарь получает ключ `True`. Поймано на
    # `grant.on`, которое валидатор молча не находил.
    def scan_keys(node, path="")  :
        if isinstance(node, dict):
            for k, v in node.items():
                if not isinstance(k, str):
                    err.append(f"{path}: ключ «{k}» разобран как "
                               f"{type(k).__name__}, а не строка — в YAML это "
                               f"логический литерал (on/off/yes/no/y/n)")
                scan_keys(v, f"{path}.{k}" if path else str(k))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                scan_keys(v, f"{path}[{i}]")
    scan_keys(yaml.safe_load(open(path, encoding="utf-8")))

    # ── Раздел seed: форма ДОСЛОВНО по CreateAccessBinding ──────────────
    seed = d.get("seed") or {}
    role_ids = {r.get("id") for r in d.get("roles", [])}

    for dead in ("serviceAccount", "seedTo", "bindings"):
        if seed.get(dead) or any(r.get(dead) for r in d.get("roles", [])):
            err.append(f"seed/{dead}: ключ снят — выдачи объявляются в "
                       f"seed.accessBindings по форме CreateAccessBinding")

    sas = seed.get("serviceAccounts") or []
    sa_names, seen = set(), set()
    for a_ in sas:
        nm = a_.get("name")
        if not nm or not a_.get("account"):
            err.append("seed.serviceAccounts: нужны name и account")
        if nm in seen:
            err.append(f"seed.serviceAccounts: «{nm}» объявлена дважды")
        seen.add(nm); sa_names.add(nm)
        # `description` обязателен ВСЕГДА, как у группы: разное требование
        # к однородным вещам — само по себе расхождение. Поле названо как
        # в продукте (`service_accounts.description`), не синонимом.
        if a_.get("purpose"):
            err.append(f"seed.serviceAccounts[{nm}]: ключ purpose снят — "
                       f"поле продукта называется description")
        if not a_.get("description"):
            err.append(f"seed.serviceAccounts[{nm}]: нет description — "
                       f"под что эта личность")

    grp_names = set()
    for g in seed.get("groups", []):
        who = g.get("name", "?")
        grp_names.add(who)
        for req in ("name", "account", "description"):
            if not g.get(req):
                err.append(f"seed.groups[{who}]: нет «{req}»")
        if g.get("grant") or g.get("grants"):
            err.append(f"seed.groups[{who}]: выдача переехала в "
                       f"seed.accessBindings — там субъект назван явно")
        # `openTo` снят: предмета не было. Вступление гейтится правом
        # `v_update` на объекте группы (RPC addMember), отдельного
        # разрешения в продукте не существует. Поле объявляло возможность,
        # которой нет, и валидатор требовал его заполнять.
        if "openTo" in g:
            err.append(f"seed.groups[{who}]: ключ openTo снят — вступление "
                       f"гейтится правом v_update на самой группе, "
                       f"отдельного разрешения нет")

    # Выдача по контракту: subjects[] 1..32 · roleId · scopeType · scopeId ·
    # target (ОБЯЗАТЕЛЕН: «target is required; use target.allInScope{}»).
    granted_to = set()
    for b in seed.get("accessBindings", []):
        subs = b.get("subjects") or []
        tag = b.get("roleId", "?")
        if not 1 <= len(subs) <= 32:
            err.append(f"seed.accessBindings[{tag}]: субъектов {len(subs)} — "
                       f"контракт требует 1..32")
        for sb in subs:
            t, nm = sb.get("type"), sb.get("name")
            if t not in ("group", "serviceAccount", "user"):
                err.append(f"seed.accessBindings[{tag}]: тип субъекта «{t}» "
                           f"вне закрытого набора")
            elif t == "group" and nm not in grp_names:
                err.append(f"seed.accessBindings[{tag}]: группы «{nm}» посев "
                           f"не заводит")
            elif t == "serviceAccount" and nm not in sa_names:
                err.append(f"seed.accessBindings[{tag}]: записи «{nm}» посев "
                           f"не заводит")
            granted_to.add((t, nm))
        if b.get("roleId") not in role_ids:
            err.append(f"seed.accessBindings[{tag}]: роли в манифесте нет")
        if b.get("scopeType") != "iam.cluster":
            err.append(f"seed.accessBindings[{tag}]: scopeType обязан быть "
                       f"iam.cluster — выдачи на аккаунт и проект заводит iam "
                       f"при их создании, а не установка модуля")
        if b.get("scopeId") != "cluster_kacho_root":
            err.append(f"seed.accessBindings[{tag}]: scopeId якоря кластера — "
                       f"cluster_kacho_root")
        if b.get("target") not in ("allInScope", "resources"):
            err.append(f"seed.accessBindings[{tag}]: target ОБЯЗАТЕЛЕН по "
                       f"контракту — allInScope либо resources")
        if b.get("target") == "resources" and not b.get("resources"):
            err.append(f"seed.accessBindings[{tag}]: target: resources без "
                       f"перечня — назови resources[]")

    for g in sorted(grp_names):
        if ("group", g) not in granted_to:
            err.append(f"seed.groups[{g}]: заведена и ничего не несёт — "
                       f"выдай ей роль либо не заводи")

    for j_ in seed.get("joins", []):
        sa_ref = j_.get("serviceAccount")
        gr_ref = j_.get("group")
        tag = (gr_ref or {}).get("name", "?") if isinstance(gr_ref, dict) else str(gr_ref)
        # Адрес — ПАРА (аккаунт, имя): так и группа, и запись уникальны
        # в продукте. Одно имя не адресует, а «модуль/группа» смешивает
        # того, кто завёл, с тем, где лежит.
        for label, ref in (("serviceAccount", sa_ref), ("group", gr_ref)):
            if not isinstance(ref, dict):
                err.append(f"seed.joins[{tag}]: {label} адресуется парой "
                           f"(account, name) — одно имя не адресует")
            elif not ref.get("account") or not ref.get("name"):
                err.append(f"seed.joins[{tag}]: у {label} нет "
                           f"{'account' if not ref.get('account') else 'name'}")
        if isinstance(sa_ref, dict) and sa_ref.get("name") not in sa_names:
            err.append(f"seed.joins[{tag}]: записи «{sa_ref.get('name')}» "
                       f"посев не заводит")
        # `declaredBy` снят: группа ищется по паре среди ВСЕХ манифестов,
        # а порядок установки выводится из самих вступлений.
        if j_.get("declaredBy"):
            err.append(f"seed.joins[{tag}]: ключ declaredBy снят — группа "
                       f"находится по паре (account, name), а порядок "
                       f"установки выводится из вступлений")
        if not j_.get("why"):
            err.append(f"seed.joins[{tag}]: не сказано, ЗАЧЕМ вступаем")

    print(f"seed: учётных записей {len(sas)} · групп {len(grp_names)} · "
          f"выдач {len(seed.get('accessBindings', []))} · "
          f"вступлений {len(seed.get('joins', []))}")

    print(f"читают ВСЕ аутентифицированные: действий {len(pubs)}"
          + (" — " + ", ".join(f"{r}.{v}" for r, v, _ in pubs) if pubs else ""))
    print(f"осмотрено: ролей {len(d.get('roles', []))} · выдач {n_grants} · "
          f"действий в правах {n_verbs} · "
          f"ресурсов модуля {len(res)} · "
          f"прав всего {sum(len(v) for v in res.values())}")
    print(f"без преднастроенной роли: {len(orphans)}"
          + (" — только кастомной ролью" if orphans else ""))
    for o in orphans:
        print(f"     · {o}")
    if not d.get("roles"):
        print("✗ ролей ноль — проверять нечего, это не «чисто»")
        return 2
    for e in err:
        print(f"  ✗ {e}")
    print("ВЕРДИКТ:", "целостно" if not err else f"нарушений {len(err)}")
    return 0 if not err else 1


if __name__ == "__main__":
    sys.exit(check(sys.argv[1] if len(sys.argv) > 1 else "../vpc.manifest.yaml"))
