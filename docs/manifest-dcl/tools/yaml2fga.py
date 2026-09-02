#!/usr/bin/env python3
"""Манифест DCL → блоки типов OpenFGA DSL.

Вопрос, на который отвечает эксперимент: породит ли YAML модель, ДОСЛОВНО
совпадающую с той, что уже загружена в iam. Не «похожую» — совпадающую:
модель есть контракт, и лишнее отношение в ней это лишнее право.
"""
import re
import sys

import yaml

SUBJECTS = "[user, service_account, group#member]"
# `create` НЕ порождает глагола модели: объекта в момент создания ещё нет,
# и право спрашивается на РОДИТЕЛЕ отношением editor. Замер по живой модели:
# v_create встречается 1 раз на 27 типов (registry_registry), тогда как
# v_get/v_list/v_update/v_delete — по 27. Первая редакция генератора
# производила v_create на каждом типе; сверка с моделью это и поймала.
CLASS_VERB = {"get": "v_get", "list": "v_list",
              "update": "v_update", "delete": "v_delete"}
# operate и dataAccess не заводят СВОЕГО глагола модели: они ложатся на
# существующие. Иначе манифест плодил бы отношения, которых модель не знает.
CLASS_FALLBACK = {"operate": "v_update", "dataAccess": "v_get"}


def fga_type(module, resource, object_type=None):
    if object_type:
        m, r = object_type.split(".", 1)
    else:
        m, r = module, resource
    return f"{m}_" + re.sub(r"(?<!^)(?=[A-Z])", "_", r).lower()


def known_types(path="live-objecttypes.txt"):
    try:
        return {l.strip() for l in open(path, encoding="utf-8") if l.strip()}
    except FileNotFoundError:
        return None


def emit(path):
    d = yaml.safe_load(open(path, encoding="utf-8"))
    mod = d["module"]
    cat = known_types()
    out = []
    for r in d["resources"]:
        parent = r.get("parent", "project")
        verbs = r["verbs"]
        # какие глаголы модели нужны этому ресурсу — ВЫВОДЯТСЯ из классов
        need = set()
        for v in verbs:
            cls = v if isinstance(v, str) else (v.get("class") or v["name"])
            g = CLASS_VERB.get(cls) or CLASS_FALLBACK.get(cls)
            if g:
                need.add(g)
        if not need:
            continue                       # ресурс без пообъектной адресации
        # Ресурс, которого нет в каталоге типов, объектом НЕ является: право
        # на него спрашивается на родителе (так устроена quota). Породить ему
        # тип значило бы завести адресуемую сущность, которой нет.
        dotted = r.get("objectType") or f"{mod}.{r['name']}"
        if cat is not None and dotted not in cat:
            continue
        t = fga_type(mod, r["name"], r.get("objectType"))
        lines = [f"type {t}", "  relations"]
        # Комментарий блока — не декорация: в живой модели он несёт
        # самоистекающий маркер, который стережёт гейт («появится
        # производитель — маркер обязан быть снят»). Потерять его при
        # перегенерации значило бы снять условие, о котором никто не решал.
        for c in (r.get("doc") or "").rstrip("\n").split("\n"):
            if c.strip():
                lines.append(f"    # {c}")
        # структурный указатель на родителя + каскад сверху
        if parent in ("project", "account", "cluster"):
            lines.append(f"    define {parent}: [{parent}]")
            lines.append(f"    define super_admin: super_admin from {parent}"
                         if parent == "project" else
                         f"    define super_admin: admin from {parent}"
                         if parent == "account" else
                         f"    define super_admin: any_admin from {parent}")
        # ярусы
        # Состав субъектов и набор ярусов — не константа. У административного
        # ресурса кластера в живой модели НЕТ группы среди субъектов и НЕТ
        # яруса editor вовсе: viewer наследуется прямо от admin. Манифест
        # обязан это объявлять, иначе генератор расширит доступ молча.
        subj = r.get("subjects") or ["user", "service_account", "group#member"]
        sset = "[" + ", ".join(subj) + "]"
        tiers = r.get("tiers") or ["admin", "editor", "viewer"]
        prev = "super_admin"
        for tier in tiers:
            lines.append(f"    define {tier}: {sset} or {prev}")
            prev = tier
        # глаголы — в каноническом порядке модели
        # Отношение, не выводимое ни из одного действия: его не породить из
        # глаголов by construction. Объявляется дословно — иначе генератор
        # СНИМЕТ его при перегенерации, и это будет тихая потеря.
        for rel in (r.get("relations") or []):
            lines.append(f"    define {rel['name']}: {rel['definition']}")
        for g in ("v_get", "v_list", "v_create", "v_update", "v_delete"):
            if g in need:
                lines.append(f"    define {g}: {SUBJECTS} or super_admin")
        out.append((t, "\n".join(lines)))
    return out


if __name__ == "__main__":
    # Блоки разделяются ОДНОЙ пустой строкой, файл кончается одним переводом.
    # Лишний хвостовой перевод — единственное, чем первая редакция расходилась
    # с моделью побайтово: содержимое совпадало, а файл не был идентичен.
    print("\n\n".join(b for _, b in emit(sys.argv[1])))
