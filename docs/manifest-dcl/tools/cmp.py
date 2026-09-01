#!/usr/bin/env python3
"""Сверка порождённой из YAML модели с живой — ДОСЛОВНО, строка в строку."""
import importlib.util, sys
sp=importlib.util.spec_from_file_location("y2f","yaml2fga.py")
y=importlib.util.module_from_spec(sp); sp.loader.exec_module(y)
live={}; cur=None
for l in open('live-model.fga',encoding='utf-8').read().split('\n'):
    if l.startswith('type '): cur=l[5:].strip(); live[cur]=[]
    elif cur is not None:
        if l.startswith('condition ') or (l and not l[0].isspace() and not l.startswith('type')): cur=None
        elif l.strip().startswith('define '): live[cur].append(l.strip())
mine={t:[x.strip() for x in b.split('\n') if x.strip().startswith('define ')]
      for t,b in y.emit(sys.argv[1] if len(sys.argv)>1 else '../vpc.manifest.yaml')}
ok=diff=0; out=[]
for t in sorted(mine):
    b=live.get(t)
    if b is None: out.append(f'✗ {t}: типа нет в модели'); diff+=1; continue
    if mine[t]==b: ok+=1; continue
    diff+=1; out.append(f'✗ {t}')
    out += [f'     ЛИШНЕЕ: {x}' for x in mine[t] if x not in b]
    out += [f'     НЕ ДАЛ: {x}' for x in b if x not in mine[t]]
print(f'типов произведено {len(mine)} · совпало ДОСЛОВНО {ok} · расходится {diff}')
print('\n'.join(out))
if not mine: print('✗ произведено НОЛЬ типов — сверять нечего'); sys.exit(2)
sys.exit(0 if diff==0 else 1)
