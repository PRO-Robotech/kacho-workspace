import importlib.util, pathlib, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('gate', pathlib.Path('scripts/kaname-stand.py'))
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
e = {'head':'a'*40,'tree':'b'*40}
p = 'remote-heavy: [fixture] '
c = p+'команда начата через 2 с после создания Job: make check '
ls = [p+'ns fixture создано: задача 1524, kaname@'+'a'*12+', профиль ws, срок now',p+'Job: spec сверен с запрошенным — hostUsers false, securityContext как запрошен',p+'Job создан: образ fixture, cpu 1m/1, память 1/1 МиБ',p+'pod run-fixture: spec сверен с запрошенным — hostUsers false, securityContext как запрошен',p+'исходники доставлены: 1 МиБ bundle за 1 с от создания Job',c,'SOURCE '+e['head']+' TREE '+e['tree'],'PRECI_CENSUS {}',p+'команда завершилась кодом 0 за 1 с (всего 3 с от создания Job)',p+'ns fixture снято']
raw = '\n'.join(ls)+'\n'
cases = [('empty','',False),('unbound',raw,False),('source-mismatch',raw.replace('TREE '+'b'*40,'TREE '+'c'*40),True),('head-mismatch','HEAD '+'c'*40+' class=suite at=now dir=/src\n'+raw,True),('head-malformed','HEAD malformed\n'+raw,True),('head-bare','HEAD\n'+raw,True),('head-tab','HEAD\t'+'c'*40+' class=suite at=now dir=/src\n'+raw,True),('head-double',('HEAD '+'a'*40+' class=suite at=now dir=/src\n')*2+raw,True),('missing-completion',raw.replace(ls[8]+'\n',''),True),('missing-cleanup',raw.replace(ls[9]+'\n',''),True),('partial',raw[:raw.index(ls[8])],True),('foreign-namespace',raw+p.replace('[fixture]','[other]')+'something\n',True),('nonzero-and-zero-completions',raw.replace(ls[8],ls[8].replace('кодом 0','кодом 1')+'\n'+ls[8]),True),('conflicting-job-spec',raw.replace(ls[1],ls[1]+'\n'+ls[1].replace('hostUsers false','hostUsers true')),True),('conflicting-pod-spec',raw.replace(ls[3],ls[3]+'\n'+ls[3].replace('hostUsers false','hostUsers true')),True),('duplicate-good-completion',raw+ls[8]+'\n',True),('marker-outside',raw+'PRECI_CENSUS {}\n',True),('wrong-job-order',raw.replace(ls[2]+'\n','').replace(ls[4],ls[4]+'\n'+ls[2]),True)]
failed = 0
for name, txt, bound in cases:
    try:
        g.remote_log(txt,e,c,parse_groups=False,preci_source_bound=bound)
    except g.common.Unread as err:
        print('CONTROL',name,'REJECT',str(err),flush=True)
    else:
        failed += 1; print('CONTROL',name,'UNEXPECTED_ACCEPT',flush=True)
    g.remote_log(raw,e,c,parse_groups=False,preci_source_bound=True)
    print('TWIN',name,'ACCEPT',flush=True)
print('SUMMARY negative_controls='+str(len(cases))+' rejected='+str(len(cases)-failed)+' unexpected_accept='+str(failed)+' lawful_twins='+str(len(cases)),flush=True)
sys.exit(1 if failed else 0)
