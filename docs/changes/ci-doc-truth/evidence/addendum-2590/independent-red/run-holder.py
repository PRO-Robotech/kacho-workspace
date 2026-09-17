"""Независимый внешний holder #2590: controls, census и Go overlay lawful twin."""
from pathlib import Path
import hashlib, json, os, re, shutil, subprocess, time

HERE=Path(__file__).resolve().parent
OUT=Path('/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/tmp/area-ci-audit/issue-2590-independent')
ENV={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
ENV.update(GOWORK='off',TMPDIR=str(HERE/'tmp'),GOFLAGS='-mod=readonly')
names=sorted([
    'TestNoticeReachesTheOperatorWithItsLevelAndText','TestLevelIsTakenUnlocalised',
    'TestCensusIsPrintedEvenWhenNothingWasSaid','TestCensusCountsWhatItPrintedAndWhatItDropped',
    'TestOpenDBRefusesToRunWithoutAPlaceToDeliver','TestOpenDBRefusesADriverThatCannotDeliver'])
pattern='^('+'|'.join(names)+')$'
records=[]
def sha(data):return hashlib.sha256(data).hexdigest()
def run(label,args,cwd=HERE):
    began=time.monotonic();p=subprocess.run([str(x) for x in args],cwd=cwd,env=ENV,capture_output=True,timeout=180)
    (OUT/(label+'.stdout')).write_bytes(p.stdout);(OUT/(label+'.stderr')).write_bytes(p.stderr)
    records.append({'label':label,'argv':[str(x) for x in args],'cwd':str(cwd),'rc':p.returncode,
                    'seconds':time.monotonic()-began,'stdout_sha256':sha(p.stdout),'stderr_sha256':sha(p.stderr)})
    (OUT/'executions.json').write_text(json.dumps(records,indent=2)+'\n')
    return p

baseline=HERE/'inputs/baseline.go';lawful=HERE/'inputs/lawful.go';contract=HERE/'baseline.json'
source=HERE/'checkout/migratorcli/notice_test.go'
assert baseline.read_bytes()==source.read_bytes()
original=source.read_bytes();candidate=lawful.read_bytes()
initial={str(p.relative_to(HERE/'checkout')):sha(p.read_bytes()) for p in (HERE/'checkout').rglob('*') if p.is_file()}
go=Path(shutil.which('go')).resolve()
assert run('go-version',[go,'version']).returncode==0
assert run('build-comparator',[go,'build','-trimpath','-o',HERE/'notice-preservation',HERE/'notice-preservation.go']).returncode==0
assert candidate.count(b'const over = 7')==1
inputs={
    'lawful':(candidate,0,'PASS','EXACT_REPLACEMENT_PRESERVED'),
    'program-token':(candidate.replace(b'const over = 7',b'const over = 8',1),1,'FAIL','PROGRAM_TOKEN_CHANGED'),
    'outside-comment':(candidate+b'\n// unrelated prose\n',1,'FAIL','NOT_EXACT_REPLACEMENT'),
    'old-header':(original,1,'FAIL','NOT_EXACT_REPLACEMENT'),
    'empty':(b'',3,'NOT_EXECUTED','CANDIDATE_EMPTY_INPUT'),
    'no-declarations':(b'package migratorcli_test\n',3,'NOT_EXECUTED','CANDIDATE_NO_DECLARATIONS'),
    'unreadable':(candidate,3,'NOT_EXECUTED','CANDIDATE_UNREADABLE'),
    'malformed':(b'package migratorcli_test\nfunc (\n',3,'NOT_EXECUTED','CANDIDATE_PARSE_FAILED'),
    'directive':(candidate+b'\n//go:generate deliberately-unapproved\n',1,'FAIL','DIRECTIVE_CHANGED'),
}
control_records=[]
for label,(data,rc,status,code) in inputs.items():
    path=HERE/'inputs'/(label+'.go');path.write_bytes(data)
    if label=='unreadable':
        assert os.geteuid()!=0
        path.chmod(0)
        try:path.read_bytes()
        except PermissionError:pass
        else:raise AssertionError('unreadable control is readable')
    try:p=run('control-'+label,[HERE/'notice-preservation','--contract',contract,'--baseline',baseline,'--candidate',path])
    finally:
        if label=='unreadable':path.chmod(0o600)
    result=json.loads(p.stdout)
    assert not p.stderr and p.returncode==rc and result['status']==status and result['code']==code,(label,result)
    control_records.append({'id':label,'input_sha256':sha(data),'expected_rc':rc,'result':result})
    if label in ('lawful','old-header','outside-comment','directive'):
        assert result['baseline_tokens']>0 and result['candidate_tokens']>0
        assert result['baseline_declarations']>0 and result['candidate_declarations']>0
        assert result['tokens_equal'] and result['position_free_ast_equal']
        assert result['baseline_tests']==result['candidate_tests']==names
    if label=='lawful':assert result['directives_equal'] and result['prefix_equal'] and result['suffix_equal'] and result['literal_replacement']

# Live source bytes are read from the exact Git-archive snapshot, not changed.
p=run('current-header-red',[HERE/'notice-preservation','--contract',contract,'--baseline',baseline,'--candidate',source])
current=json.loads(p.stdout)
assert p.returncode==1 and current['status']=='FAIL' and current['code']=='NOT_EXACT_REPLACEMENT'
assert current['tokens_equal'] and current['position_free_ast_equal'] and current['directives_equal']

selection=run('actual-selection',[go,'list','-f','{{.ImportPath}} {{join .TestImports " "}} {{join .XTestImports " "}}','./...'],HERE/'checkout')
assert selection.returncode==0 and not selection.stderr
lines=selection.stdout.decode().splitlines();assert lines and all(line.split() for line in lines)
selected=[line.split()[0] for line in lines if re.search(r'(corelib/pgtest|testcontainers)',line)]
assert selected and 'github.com/PRO-Robotech/corelib/migratorcli' in selected
(OUT/'selected-packages.json').write_text(json.dumps(selected,indent=2)+'\n')

# Overlay substitutes the external lawful test fixture at build time. Checkout
# file and all other product bytes remain the original exact source archive.
overlay=HERE/'lawful-overlay.json'
overlay.write_text(json.dumps({'Replace':{str(source):str(lawful)}})+'\n')
runtime=[]
for label,flags in [('baseline',[]),('lawful-overlay',['-overlay',overlay])]:
    declared=run(label+'-declared',[go,'test',*flags,'./migratorcli','-short','-list',pattern,'-count=1'],HERE/'checkout')
    assert declared.returncode==0 and not declared.stderr
    actual_names=sorted(line for line in declared.stdout.decode().splitlines() if line.startswith('Test'))
    assert actual_names==names
    tested=run(label+'-tests',[go,'test',*flags,'./migratorcli','-short','-run',pattern,'-count=1','-json','-timeout=2m'],HERE/'checkout')
    assert tested.returncode==0 and not tested.stderr
    events=[json.loads(line) for line in tested.stdout.splitlines() if line]
    groups={action:sorted(event['Test'] for event in events if event.get('Test') and event.get('Action')==action) for action in ('run','pass','fail','skip')}
    assert groups['run']==groups['pass']==names and not groups['fail'] and not groups['skip']
    assert any(event.get('Action')=='pass' and not event.get('Test') for event in events)
    runtime.append({'label':label,'declared':actual_names,'events':groups,'counts':{key:len(v) for key,v in groups.items()}})
after={str(p.relative_to(HERE/'checkout')):sha(p.read_bytes()) for p in (HERE/'checkout').rglob('*') if p.is_file()}
assert initial==after
assert source.read_bytes()==original
for record in records:
    for stream in ('stdout','stderr'):assert sha((OUT/(record['label']+'.'+stream)).read_bytes())==record[stream+'_sha256']
for filename in ('notice-preservation.go','run-holder.py','lawful-overlay.json'):
    shutil.copyfile(HERE/filename,OUT/filename)
(OUT/'inputs').mkdir(exist_ok=True)
for p in (HERE/'inputs').glob('*.go'):shutil.copyfile(p,OUT/'inputs'/p.name)
manifest={'status':'SCOPED_HEADER_RED_WITH_VALID_LAWFUL_CONTROL','comparator_author':'e2e_audit, independent of paragraph author',
          'scope_sha256':sha((HERE/'scope.md').read_bytes()),'baseline_contract_sha256':sha(contract.read_bytes()),
          'source_base':'34bc8104a832b67e53c868646ab2b1e0ac4c8562','source_whole_sha256':sha(original),
          'lawful_fixture_sha256':sha(candidate),'comparator_sha256':sha((HERE/'notice-preservation.go').read_bytes()),
          'comparator_binary_sha256':sha((HERE/'notice-preservation').read_bytes()),'driver_sha256':sha(Path(__file__).read_bytes()),
          'go_binary':str(go),'go_binary_sha256':sha(go.read_bytes()),'controls':control_records,
          'current_header_red':current,'selection':{'examined':len(lines),'selected':len(selected),'migratorcli_selected':True},
          'notice_runtime':runtime,'source_archive_files_unchanged':len(initial),'product_source_edited':False,
          'lawful_execution':'external literal fixture via Go overlay; not a landed product change',
          'runtime_db_integration_executed':False,'capture_count':len(records),'captures_verified':True,
          'pending':['root source authorization','worker literal paragraph change','independent candidate review','main/release delivery']}
(OUT/'holder-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'status':manifest['status'],'controls':len(inputs),'tokens':current['baseline_tokens'],
                  'declarations':current['baseline_declarations'],'runtime_counts':[row['counts'] for row in runtime],
                  'selection':manifest['selection'],'captures':len(records),'manifest_sha256':sha((OUT/'holder-manifest.json').read_bytes())}))
