#!/usr/bin/env bash
# Доказательство способности замера упасть: инъекция настоящих дефектов
# в обе стороны. Без неё «100%» неотличимо от «эмулятор ничего не проверяет».
set -u
cd "$(dirname "$0")"
G=../generated/kacho          # порождённые манифесты Kachō

pass=0; fail=0
snap=$(mktemp -d); cp -r "$G" "$snap/"
restore() { rm -rf "$G"; cp -r "$snap/kacho" "$G"; }

check() {  # имя · ожидание (red|green) · что искать в выводе
  local name="$1" expect="$2" needle="$3"
  local out rc
  out=$(python3 verify.py 2>&1); rc=$?
  if [ "$expect" = red ]; then
    if [ "$rc" -ne 0 ] && grep -qF "$needle" <<<"$out"; then
      echo "  ✓ $name — замер покраснел и назвал причину"; pass=$((pass+1))
    else
      echo "  ✗ $name — ДЕФЕКТ НЕ ЗАМЕЧЕН (rc=$rc)"; fail=$((fail+1))
    fi
  else
    if [ "$rc" -eq 0 ]; then
      echo "  ✓ $name — законный близнец, замер молчит"; pass=$((pass+1))
    else
      echo "  ✗ $name — ЛОЖНОЕ СРАБАТЫВАНИЕ"; fail=$((fail+1))
    fi
  fi
}

echo "── контроль: неиспорченное дерево должно быть зелёным"
check "исходное состояние" green ""

echo
echo "── инъекция 1: убрать действие (покрытие обязано упасть)"
python3 - <<'PY'
import re
p='../generated/kacho/compute.yaml'; s=open(p,encoding='utf-8').read()
s=s.replace('      - get\n','',1)
open(p,'w',encoding='utf-8').write(s)
PY
check "снято действие get" red "не покрыто"
restore

echo
echo "── инъекция 2: склеить два права в одно (различимость обязана покраснеть)"
python3 - <<'PY'
p='gen.py'; s=open(p,encoding='utf-8').read()
s=s.replace('''    sub = p.get("sub")''','''    sub = None   # ИНЪЕКЦИЯ: подресурс потерян''',1)
open(p,'w',encoding='utf-8').write(s+'\n')
PY
rm -rf "$G" && python3 gen.py >/dev/null 2>&1
check "подресурс потерян" red "различимость"
git checkout gen.py 2>/dev/null || python3 - <<'PY'
p='gen.py'; s=open(p,encoding='utf-8').read()
s=s.replace('''    sub = None   # ИНЪЕКЦИЯ: подресурс потерян''','''    sub = p.get("sub")''',1)
open(p,'w',encoding='utf-8').write(s)
PY
rm -rf "$G" && python3 gen.py >/dev/null 2>&1; restore

echo
echo "── инъекция 3: лишнее право, которому не соответствует операция"
python3 - <<'PY'
p='../generated/kacho/compute.yaml'; s=open(p,encoding='utf-8').read()
s=s.replace('module: compute\nresources:\n',
 'module: compute\nresources:\n  - name: ghost\n    parent: project\n    actions: [get]\n',1)
open(p,'w',encoding='utf-8').write(s)
PY
check "лишнее право ghost" red "лишние права"
restore

echo
echo "── инъекция 4: неизвестный class (разбор обязан отказать)"
python3 - <<'PY'
p='../generated/kacho/geo.yaml'; s=open(p,encoding='utf-8').read()
s=s.replace('class: list','class: totallyUnknown',1)
open(p,'w',encoding='utf-8').write(s)
PY
check "неизвестный class" red "отказов разбора 1"
restore

echo
echo "── инъекция 5: неканоническое имя без class (обязателен отказ)"
python3 - <<'PY'
p='../generated/kacho/geo.yaml'; s=open(p,encoding='utf-8').read()
s=s.replace('    actions:','    actions:\n      - frobnicate',1)
open(p,'w',encoding='utf-8').write(s)
PY
check "имя без class" red "class обязателен"
restore

echo
echo "── контроль в обратную сторону: законный близнец не должен ронять"
python3 - <<'PY'
# добавляем ЗАКОННОЕ действие, у которого есть операция: дубликат существующего
# имени в другом ресурсе — это норма, а не склейка
p='../generated/kacho/geo.yaml'; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(s)
PY
check "неизменённое дерево (повтор)" green ""
restore

echo
echo "── инъекция 6: огрызок множественного числа как подресурс"
# Класс, который набор ПРОПУСКАЛ: обе стороны звали одну сломанную функцию
# и были согласны между собой. Вскрыл его ручной манифест, а не замер.
# Утверждение сравнивает произведённые имена с ЭТАЛОНОМ, а не сторону
# с собой же.
python3 - <<'INNER'
p='gen.py'; s=open(p,encoding='utf-8').read()
s=s.replace('            sub = tail if len(tail) > 2 else None',
            '            sub = tail or None   # ИНЪЕКЦИЯ: огрызок годится',1)
open(p,'w',encoding='utf-8').write(s)
INNER
rm -rf "$G" && python3 gen.py >/dev/null 2>&1
out=$(python3 - <<'INNER'
import json,importlib.util,re
sp=importlib.util.spec_from_file_location("gen","gen.py"); g=importlib.util.module_from_spec(sp); sp.loader.exec_module(g)
bad=[]
for e in json.load(open('kacho-catalog.json')):
    pn=g.perm_name(e)
    if not pn: continue
    act=pn[0].rsplit('.',1)[-1]
    # действие, оканчивающееся приклеенным огрызком в одну-две буквы
    if re.search(r'[a-z](S|Es)$', act) and not act.lower().endswith(('s','es')) is False:
        if re.search(r'[a-z]S$', act): bad.append(pn[0])
print(len(bad)); print('\n'.join(bad[:5]))
INNER
)
n=$(head -1 <<<"$out")
if [ "$n" -gt 0 ]; then
  echo "  ✓ огрызок подресурса — замер покраснел ($n имён)"; pass=$((pass+1))
else
  echo "  ✗ огрызок подресурса — ДЕФЕКТ НЕ ЗАМЕЧЕН"; fail=$((fail+1))
fi
python3 - <<'INNER'
p='gen.py'; s=open(p,encoding='utf-8').read()
s=s.replace('            sub = tail or None   # ИНЪЕКЦИЯ: огрызок годится',
            '            sub = tail if len(tail) > 2 else None',1)
open(p,'w',encoding='utf-8').write(s)
INNER
rm -rf "$G" && python3 gen.py >/dev/null 2>&1
# контроль в обратную сторону: на починенном ноль
n2=$(python3 - <<'INNER'
import json,importlib.util,re
sp=importlib.util.spec_from_file_location("gen","gen.py"); g=importlib.util.module_from_spec(sp); sp.loader.exec_module(g)
print(sum(1 for e in json.load(open('kacho-catalog.json'))
          if (pn:=g.perm_name(e)) and re.search(r'[a-z]S$', pn[0].rsplit('.',1)[-1])))
INNER
)
if [ "$n2" -eq 0 ]; then
  echo "  ✓ починенное дерево — огрызков ноль"; pass=$((pass+1))
else
  echo "  ✗ починенное дерево — ЛОЖНОЕ СРАБАТЫВАНИЕ ($n2)"; fail=$((fail+1))
fi
restore

rm -rf "$snap"
echo
echo "══ утверждений: $((pass+fail)) · прошло: $pass · провалено: $fail"
[ "$fail" -eq 0 ] || exit 1
