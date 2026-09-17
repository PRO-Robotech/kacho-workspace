from pathlib import Path
import subprocess,os,hashlib,json,difflib,re,collections,time

ws=Path('/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace')
repo=ws/'tmp/area-ci-truth-tests'
audit=ws/'tmp/area-ci-audit/docs-truth-tester'
temp=Path('/var/tmp/area-ci-truth-tests')
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
env.update(GOWORK='off',TMPDIR=str(temp))
base='e58e6f581e858df6a9ffd3c25d93cbfcc1800128'
candidate='88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0'
def sha(b): return hashlib.sha256(b).hexdigest()
def git(*args): return subprocess.check_output(['git','-C',str(repo),*args],env=env)
def source(rev,path): return git('show',rev+':'+path)
paths=[f'internal/repohygiene/{x}' for x in ['catalogreachability_test.go','grpcmountparity_test.go','subscriptionformshape.go','subscriptionformshape_injection_test.go']]+['proto/corelib/subscription/subscription.proto']
changed=git('diff','--name-only',base,candidate).decode().splitlines()
assert sorted(changed)==sorted(paths),(changed,paths)
assert git('status','--porcelain')==b''
diff=git('diff','--no-ext-diff','--no-color',base,candidate,'--',*paths)
(audit/'candidate-full.diff').write_bytes(diff)
record={'source_base':base,'source_candidate':candidate,'changed_paths':changed,'source_diff_sha256':sha(diff),'source_bytes':{},'history_regions':[]}
before={p:source(base,p) for p in paths};after={p:source(candidate,p) for p in paths}
for p in paths:
    record['source_bytes'][p]={'before_sha256':sha(before[p]),'after_sha256':sha(after[p])}
    directive=lambda b:[x for x in b.decode().splitlines() if re.match(r'\s*(//go:|//line |/\*line |// \+build )',x) or '#cgo' in x]
    assert directive(before[p])==directive(after[p]),p
record['directives_unchanged']=True
def paragraph(b,index):
    lines=b.splitlines(keepends=True)
    def prose(x): return x.lstrip().startswith(b'//') and x.strip()!=b'//'
    lo=hi=index
    while lo>0 and prose(lines[lo-1]):lo-=1
    while hi+1<len(lines) and prose(lines[hi+1]):hi+=1
    return b''.join(lines[lo:hi+1]),lo+1,hi+1
markers=['89242e6b','bdafe2c4','af0ca8f3','94352d9c','Это измерено, а не предположено: сделав первую ветвь носителя']
for p in paths[:4]:
    for marker in markers:
        for index,line in enumerate(before[p].splitlines()):
            if marker.encode() in line:
                region,lo,hi=paragraph(before[p],index)
                assert after[p].count(region)==1,(p,marker)
                record['history_regions'].append({'path':p,'marker':marker,'baseline_lines':[lo,hi],'sha256':sha(region),'unchanged':True})
assert len(record['history_regions'])==6
analyzer=paths[2]
start='// # Единицы счёта:'.encode()
end='// # Требование к тексту'.encode()
def section(b):return b[b.index(start):b.index(end)]
assert section(before[analyzer])==section(after[analyzer])
record['issue1439_count_section_sha256']=sha(section(before[analyzer]))
holder='internal/repohygiene/subscriptionreason_test.go'
assert source(base,holder)==source(candidate,holder)
record['immutable_holder_sha256']=sha(source(candidate,holder))
assert record['immutable_holder_sha256']=='9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35'
addendum='internal/repohygiene/subscriptionformshape_test.go'
assert source(base,addendum)==source(candidate,addendum)
record['untouched_addendum_source_sha256']=sha(source(candidate,addendum))
old='''  // Ветвление здесь потому, что запретить прозой значение, которое допускает
  // собственный тип, невозможно. Пустая нагрузка НИКОГДА не означает «у предмета
  // не осталось полей»: подставить пустой объект вместо признака недоступности
  // в этой форме просто негде.
'''.encode()
new='''  // Ветвление объявляет две альтернативы, но само по себе не требует выбрать
  // ветвь или заполнить `state`. Пустая нагрузка НИКОГДА не означает «у предмета
  // не осталось полей»: недоступность состояния передаётся отдельной ветвью
  // `state_unavailable`, а не пустым объектом вместо неё.
'''.encode()
proto=paths[4]
assert before[proto].count(old)==1
assert before[proto].replace(old,new,1)==after[proto]
record['canonical_proto_exact_four_comment_lines']=True
stages=[temp/'generation-baseline',temp/'generation-candidate-independent']
record['descriptors']=[]
for label,stage in zip(['baseline','candidate'],stages):
    output=audit/(label+'-semantic-descriptor.pb')
    cmd=['buf','build','--path','corelib/subscription','--as-file-descriptor-set','--exclude-source-info','-o',str(output)]
    start=time.time();run=subprocess.run(cmd,cwd=stage/'proto',env=env,capture_output=True)
    (audit/(label+'-descriptor.stdout')).write_bytes(run.stdout)
    (audit/(label+'-descriptor.stderr')).write_bytes(run.stderr)
    entry={'command':cmd,'cwd':str(stage/'proto'),'source_sha': 'b5fa093341f1fdbe96adfc6a9555482690968253' if label=='baseline' else candidate,'GOWORK':'off','sanitized_git_env':True,'rc':run.returncode,'elapsed_seconds':time.time()-start,'stdout_sha256':sha(run.stdout),'stderr_sha256':sha(run.stderr)}
    run.check_returncode();b=output.read_bytes();assert len(b)>0
    entry.update(bytes=len(b),sha256=sha(b));record['descriptors'].append(entry)
assert (audit/'baseline-semantic-descriptor.pb').read_bytes()==(audit/'candidate-semantic-descriptor.pb').read_bytes()
record['semantic_descriptors_byte_equal']=True
pb=Path('pkg/api/corelib/subscription/subscription.pb.go')
gdiff=''.join(difflib.unified_diff((stages[0]/pb).read_text().splitlines(keepends=True),(stages[1]/pb).read_text().splitlines(keepends=True),fromfile='baseline/subscription.pb.go',tofile='candidate/subscription.pb.go'))
(audit/'generated-independent.diff').write_text(gdiff)
record['generated_diff_sha256']=sha(gdiff.encode())
# Generated projection must be precisely the canonical four comment lines, with Go indentation.
oldGo=old.replace(b'  //',b'\t//');newGo=new.replace(b'  //',b'\t//')
assert (stages[0]/pb).read_bytes().count(oldGo)==1
assert (stages[0]/pb).read_bytes().replace(oldGo,newGo,1)==(stages[1]/pb).read_bytes()
record['generated_projection_exact_four_comment_lines']=True
rows=[json.loads(x) for x in (audit/'addendum-baseline-selection.stdout').read_text().splitlines()]
top=[x for x in (audit/'addendum-baseline-list.stdout').read_text().splitlines() if x.startswith('Test')]
actions=collections.Counter(x['Action'] for x in rows if x.get('Test'))
run=[x['Test'] for x in rows if x['Action']=='run'];passed=[x['Test'] for x in rows if x['Action']=='pass' and x.get('Test')]
assert len(top)>0 and len(run)>0 and sorted(top)==sorted(x for x in run if '/' not in x) and sorted(run)==sorted(passed) and len(set(run))==len(run) and not actions['fail'] and not actions['skip']
assert any(x=='TestSubscriptionShapeReasonContract' for x in top)
names=''.join(x+'\n' for x in sorted(run)).encode();(audit/'addendum-baseline-names.txt').write_bytes(names)
record['addendum_baseline']={'source':candidate,'list_count':len(top),'run':len(run),'pass':len(passed),'fail':actions['fail'],'skip':actions['skip'],'names_sha256':sha(names),'holder_sha256':record['immutable_holder_sha256']}
(audit/'candidate-postdiff-checks.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'changed_files':len(changed),'protected_history_regions':len(record['history_regions']),'semantic_descriptor_bytes':record['descriptors'][0]['bytes'],'semantic_descriptor_sha256':record['descriptors'][0]['sha256'],'generated_exact_comment_projection':True,'immutable_holder_sha256':record['immutable_holder_sha256'],'addendum_baseline':record['addendum_baseline']},indent=2))
