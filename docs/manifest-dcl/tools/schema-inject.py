#!/usr/bin/env python3
"""Доказательство, что схема seed умеет ОТВЕРГАТЬ и умеет МОЛЧАТЬ.

Схема, которая ничего не отвергает, неотличима от отсутствующей. Инъекция
в обе стороны: дефект формы обязан краснеть, законный близнец — молчать.
"""
import copy
import sys

import yaml
from jsonschema import Draft202012Validator

import os
_HERE = os.path.dirname(os.path.abspath(__file__))


def _near(*names):
    """Файл ищется рядом со скриптом И на уровень выше: раскладка каталога
    менялась, а замер обязан воспроизводиться из обоих мест."""
    for n in names:
        for d in (_HERE, os.path.dirname(_HERE)):
            f = os.path.join(d, n)
            if os.path.exists(f):
                return f
    raise FileNotFoundError(" | ".join(names))


SCH = yaml.safe_load(open(_near("seed.schema.yaml"), encoding="utf-8"))
BASE = yaml.safe_load(open(_near("vpc.manifest.yaml", "vpc.yaml"),
                           encoding="utf-8"))["seed"]
V = Draft202012Validator(SCH)


def check(name, mutate, expect):
    d = copy.deepcopy(BASE)
    try:
        mutate(d)
    except Exception as e:                      # правка не применилась —
        print(f"  ✗ {name}: ПРАВКА НЕ ПРИМЕНИЛАСЬ ({e})")   # это тоже провал
        return False
    errs = list(V.iter_errors(d))
    red = bool(errs)
    if red == (expect == "red"):
        why = errs[0].message[:64] if errs else "молчит"
        print(f"  ✓ {name} — {why}")
        return True
    print(f"  ✗ {name}: ожидалось {expect}, получено "
          f"{'red' if red else 'green'}")
    return False


CASES = [
    ("контроль: неиспорченный раздел", lambda d: None, "green"),
    # ── форма выдачи
    ("субъектов ноль", lambda d: d["accessBindings"][0].__setitem__("subjects", []), "red"),
    ("субъектов 33", lambda d: d["accessBindings"][0].__setitem__(
        "subjects", [{"type": "group", "name": f"g{i}"} for i in range(33)]), "red"),
    ("тип субъекта вне набора", lambda d: d["accessBindings"][0]["subjects"][0]
        .__setitem__("type", "robot"), "red"),
    ("нет target", lambda d: d["accessBindings"][0].pop("target"), "red"),
    ("target вне набора", lambda d: d["accessBindings"][0].__setitem__("target", "some"), "red"),
    ("scopeType не кластерный", lambda d: d["accessBindings"][0]
        .__setitem__("scopeType", "iam.account"), "red"),
    ("scopeId чужой", lambda d: d["accessBindings"][0].__setitem__("scopeId", "acc123"), "red"),
    ("roleId без модуля", lambda d: d["accessBindings"][0].__setitem__("roleId", "viewer"), "red"),
    ("target: resources без перечня", lambda d: d["accessBindings"][0]
        .__setitem__("target", "resources"), "red"),
    ("resources при allInScope", lambda d: d["accessBindings"][0]
        .__setitem__("resources", [{"type": "vpc.network", "id": "net1"}]), "red"),
    # ── личности
    ("вторая запись без description", lambda d: d["serviceAccounts"]
        .append({"name": "kacho-vpc-worker", "account": "system"}), "red"),
    ("воскрешён purpose", lambda d: d["serviceAccounts"][0]
        .__setitem__("purpose", "путь запроса"), "red"),
    ("account не системный", lambda d: d["serviceAccounts"][0]
        .__setitem__("account", "acc-tenant"), "red"),
    ("имя не DNS-label", lambda d: d["serviceAccounts"][0].__setitem__("name", "Kacho_VPC"), "red"),
    # ── группы
    ("группа без описания", lambda d: d["groups"][0].pop("description"), "red"),
    ("описание односложное", lambda d: d["groups"][0].__setitem__("description", "сеть"), "red"),
    # ── вступления
    ("адрес группы одним именем", lambda d: d["joins"][0]
        .__setitem__("group", "module-quota-readers"), "red"),
    ("у группы нет аккаунта", lambda d: d["joins"][0]["group"].pop("account"), "red"),
    ("воскрешён declaredBy", lambda d: d["joins"][0].__setitem__("declaredBy", "iam"), "red"),
    ("вступление без причины", lambda d: d["joins"][0].pop("why"), "red"),
    ("вступление без имени записи", lambda d: d["joins"][0].pop("serviceAccount"), "red"),
    ("группа в другом аккаунте — законно", lambda d: d["joins"][0]["group"]
        .__setitem__("account", "tenant-a"), "green"),
    # ── снятые ключи названы поимённо
    ("воскрешён serviceAccount", lambda d: d.__setitem__(
        "serviceAccount", {"name": "x", "account": "system"}), "red"),
    ("воскрешён seedTo", lambda d: d.__setitem__("seedTo", [{"group": "x"}]), "red"),
    ("воскрешён bindings", lambda d: d.__setitem__("bindings", []), "red"),
    ("неизвестный ключ", lambda d: d.__setitem__("openTo", "platformModules"), "red"),
    # ── законные близнецы: схема обязана молчать
    ("две записи, обе с description", lambda d: d["serviceAccounts"].append(
        {"name": "kacho-vpc-worker", "account": "system",
         "description": "фоновые сверки и уборка просроченного"}), "green"),
    ("два субъекта в выдаче", lambda d: d["accessBindings"][0]["subjects"]
        .append({"type": "serviceAccount", "name": "kacho-vpc"}), "green"),
    ("выдача перечнем объектов", lambda d: (
        d["accessBindings"][0].__setitem__("target", "resources"),
        d["accessBindings"][0].__setitem__(
            "resources", [{"type": "vpc.network", "id": "net-1"}])), "green"),
    ("модуль без групп и вступлений", lambda d: (
        d.pop("groups"), d.pop("accessBindings"), d.pop("joins")), "green"),
]

ok = sum(check(n, m, e) for n, m, e in CASES)
print(f"\n══ утверждений: {len(CASES)} · прошло: {ok} · "
      f"провалено: {len(CASES) - ok}")
sys.exit(0 if ok == len(CASES) else 1)
