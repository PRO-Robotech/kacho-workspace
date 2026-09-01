#!/usr/bin/env bash
# Доказательство способности валидатора ролей упасть И СМОЛЧАТЬ.
# Инъекция в обе стороны: дефект краснеет с координатой, законный близнец молчит.
#
# Пробы привязываются к тому, что ЖИВЁТ в схеме. Прежняя редакция правила ключи
# `bindings`/`at`/`in`, и когда те были сняты, четыре пробы стали зелёными на
# сломанном — фикстура истекла вместе со своим предметом, а утверждение осталось.
set -u
cd "$(dirname "$0")"
SRC="${1:-../vpc.manifest.yaml}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0

probe() {  # имя · правка python · red|green · что искать
  cp "$SRC" "$T/m.yaml"
  python3 -c "
p='$T/m.yaml'; s=open(p,encoding='utf-8').read()
$2
open(p,'w',encoding='utf-8').write(s)" || { echo "  ✗ $1 — ПРАВКА НЕ ПРИМЕНИЛАСЬ"; fail=$((fail+1)); return; }
  out=$(python3 roles.py "$T/m.yaml" 2>&1); rc=$?
  if [ "$3" = red ]; then
    if [ "$rc" -ne 0 ] && grep -qF "$4" <<<"$out"; then
      echo "  ✓ $1 — упал и назвал причину"; pass=$((pass+1))
    else
      echo "  ✗ $1 — НЕ ЗАМЕЧЕНО (rc=$rc)"; fail=$((fail+1))
    fi
  else
    if [ "$rc" -eq 0 ]; then echo "  ✓ $1 — законный близнец, молчит"; pass=$((pass+1))
    else echo "  ✗ $1 — ЛОЖНОЕ СРАБАТЫВАНИЕ"; echo "$out" | grep '✗' | head -2 | sed 's/^/      /'; fail=$((fail+1)); fi
  fi
}

echo "── контроль: неиспорченный манифест"
probe "исходное состояние" "pass" green ""

echo
echo "── целостность: право пережило свой глагол"
probe "глагол снят из контракта" \
  "s=s.replace('      - {name: updateRule,', '      - {name: updateRuleXX,',1)" \
  red "такого действия нет"
probe "переименование согласованное" \
  "s=s.replace('name: updateRule,','name: updateRuleZ,').replace('updateRule, updateRules','updateRuleZ, updateRules')" \
  green ""
probe "ресурса нет в модуле" \
  "s=s.replace('        resource: routeTable','        resource: routeTables',1)" \
  red "в модуле нет"

echo
echo "── плоскости не смешиваются"
probe "internal без объявления" \
  "s=s.replace('        resource: securityGroup\n        verbs: [get, list]','        resource: network\n        verbs: [get, list, internalGet]',1)" \
  red "внутреннее"
probe "воскрешённый ключ assignableAt" \
  "s=s.replace('  - id: vpc.viewer','  - id: vpc.viewer\n    assignableAt: [project]',1)" \
  red "assignableAt снят"

echo
echo "── форма выдачи прав"
probe "класс не покрывает ничего" \
  "s=s.replace('        classes: [get, list]','        classes: [get, list, dataAccess]',1)" \
  red "право пустое"
probe "поимённый глагол на всех ресурсах" \
  "s=s.replace('        resource: \"*\"\n        classes: [get, list]','        resource: \"*\"\n        verbs: [get]',1)" \
  red "только с classes"
probe "роль без имени" \
  "s=s.replace('    name: Наблюдатель сети\n','',1)" \
  red "нет имени"

echo
echo "── SEED: форма выдачи по контракту CreateAccessBinding"
probe "ключ-логический литерал (on)" \
  "s=s.replace('      scopeType: iam.cluster','      on: iam.cluster',1)" \
  red "логический литерал"
probe "субъект не назван" \
  "s=s.replace('        - {type: group, name: vpc-internal-consumers}\n','',1)" \
  red "субъектов 0"
probe "субъект — группа, которой посев не заводит" \
  "s=s.replace('{type: group, name: vpc-internal-consumers}','{type: group, name: nosuch}',1)" \
  red "посев не заводит"
probe "тип субъекта вне закрытого набора" \
  "s=s.replace('{type: group, name: vpc-internal-consumers}','{type: robot, name: vpc-internal-consumers}',1)" \
  red "вне закрытого набора"
probe "target не назван — контракт требует явно" \
  "s=s.replace('      target: allInScope        # и будущие интерфейсы с адресами тоже\n','',1)" \
  red "target ОБЯЗАТЕЛЕН"
probe "scopeType не кластерный" \
  "s=s.replace('      scopeType: iam.cluster','      scopeType: iam.account',1)" \
  red "iam.cluster"
probe "роли выдачи в манифесте нет" \
  "s=s.replace('      roleId: vpc.internalConsumer','      roleId: vpc.nosuchRole',1)" \
  red "роли в манифесте нет"
probe "группа заведена и никому не выдана" \
  "s=s.replace('    - subjects:\n        - {type: group, name: cloud-network-admins}\n      roleId: vpc.addressPoolAdmin\n      scopeType: iam.cluster\n      scopeId: cluster_kacho_root\n      target: allInScope        # и будущие пулы тоже\n','',1)" \
  red "ничего не несёт"
probe "адрес группы одним именем" \
  "s=s.replace('      group:          {account: system, name: module-quota-readers}','      group: module-quota-readers',1)" \
  red "адресуется парой"
probe "у группы нет аккаунта" \
  "s=s.replace('      group:          {account: system, name: module-quota-readers}','      group:          {name: module-quota-readers}',1)" \
  red "нет account"
probe "вступает запись, которой посев не заводит" \
  "s=s.replace('{account: system, name: kacho-vpc}','{account: system, name: kacho-ghost}',1)" \
  red "посев не заводит"
probe "воскрешённый ключ declaredBy" \
  "s=s.replace('      why: читает пределы','      declaredBy: iam\n      why: читает пределы',1)" \
  red "declaredBy снят"
probe "группа в ДРУГОМ аккаунте — законно" \
  "s=s.replace('      group:          {account: system, name: module-quota-readers}','      group:          {account: tenant-a, name: module-quota-readers}',1)" \
  green ""
probe "вступление без причины" \
  "s=s.replace('      why: читает пределы квот на пути мутации, перед списанием','',1)" \
  red "ЗАЧЕМ вступаем"
probe "запись без description" \
  "s=s.replace('      description: >\n        Личность модуля на пути запроса','      x: >\n        Личность модуля на пути запроса',1)" \
  red "нет description"
probe "воскрешённый ключ purpose" \
  "s=s.replace('    - name: kacho-vpc\n      account: system','    - name: kacho-vpc\n      account: system\n      purpose: путь запроса',1)" \
  red "ключ purpose снят"
probe "воскрешённый скаляр serviceAccount" \
  "s=s.replace('seed:\n','seed:\n  serviceAccount: {name: kacho-vpc, account: system}\n',1)" \
  red "ключ снят"
probe "выдача внутри группы (старая форма)" \
  "s=s.replace('    - name: vpc-internal-consumers\n      account: system','    - name: vpc-internal-consumers\n      account: system\n      grants: [{roleId: vpc.internalConsumer}]',1)" \
  red "переехала в"
probe "воскрешённый ключ openTo" \
  "s=s.replace('      description: Администраторы адресного пространства облака.','      description: Администраторы адресного пространства облака.\n      openTo: humans',1)" \
  red "openTo снят"

echo
echo "── законные близнецы множественности"
probe "две записи, обе с description" \
  "s=s.replace('    - name: kacho-vpc\n      account: system','    - name: kacho-vpc-worker\n      account: system\n      description: фоновые сверки и уборка просроченного\n    - name: kacho-vpc\n      account: system',1)" \
  green ""
probe "два субъекта в одной выдаче" \
  "s=s.replace('        - {type: group, name: vpc-internal-consumers}','        - {type: group, name: vpc-internal-consumers}\n        - {type: serviceAccount, name: kacho-vpc}',1)" \
  green ""
probe "две выдачи одной группе" \
  "s=s.replace('      target: allInScope        # и будущие интерфейсы с адресами тоже','      target: allInScope\n    - subjects:\n        - {type: group, name: vpc-internal-consumers}\n      roleId: vpc.viewer\n      scopeType: iam.cluster\n      scopeId: cluster_kacho_root\n      target: allInScope',1)" \
  green ""

echo
echo "── ЧТЕНИЕ ВСЕМИ: признак справочника"
probe "воскрешённый ключ catalog" \
  "s=s.replace('  - name: addressPool\n    parent: cluster','  - name: addressPool\n    parent: cluster\n    catalog: true',1)" \
  red "catalog снят"
probe "чтение всеми без обоснования" \
  "s=s.replace('      - {name: getUtilization,','      - {name: getUtilization, readableByAnyTenant: true,',1)" \
  red "требует обоснования"
probe "обоснование односложное" \
  "s=s.replace('      - {name: getUtilization,','      - {name: getUtilization, readableByAnyTenant: надо,',1)" \
  red "требует обоснования"
probe "обоснование словами — законно" \
  "s=s.replace('      - {name: getUtilization,','      - {name: getUtilization, readableByAnyTenant: перечень занятости пулов нужен каждому,',1)" \
  green ""

echo
echo "── тип объекта"
probe "имя разошлось с каталогом типов" \
  "s=s.replace('  - name: subnet\n','  - name: subnets\n',1)" \
  red "объяви objectType"
probe "объявлено явно" \
  "s=s.replace('  - name: subnet\n    parent: project','  - name: subnets\n    objectType: vpc.subnet\n    parent: project',1).replace('resource: subnet\n','resource: subnets\n')" \
  green ""

echo
echo "── перепись отличает пустоту от чистоты"
probe "ролей ноль" \
  "s=s.split('roles:')[0]+'roles: []\n'" \
  red "ролей ноль"

echo
echo "══ утверждений: $((pass+fail)) · прошло: $pass · провалено: $fail"
[ "$fail" -eq 0 ] || exit 1
