import pathlib,os,subprocess,tarfile,io,hashlib,json,sys,time
ws=pathlib.Path('/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace'); repo=ws/'tmp/area-ci-truth-tests';audit=ws/'tmp/area-ci-audit/docs-truth-tester';env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')};env['GOWORK']='off';env['TMPDIR']='/var/tmp/area-ci-truth-tests'
rev=sys.argv[1];label=sys.argv[2];stage=pathlib.Path('/var/tmp/area-ci-truth-tests')/('generation-'+label);stage.mkdir()
archive=subprocess.check_output(['git','-C',str(repo),'archive',rev,'proto','go.mod','go.sum'],env=env)
with tarfile.open(fileobj=io.BytesIO(archive)) as f:f.extractall(stage,filter='data')
tpl=(stage/'proto/buf.gen.yaml').read_bytes();prefix,sep,_=tpl.partition(b'\ninputs:');assert sep;decl=prefix+b'\ninputs:\n  - directory: .\n    paths:\n      - corelib/subscription\n';(stage/'proto/buf.gen.yaml').write_bytes(decl)
assert (stage/'proto/buf.gen.yaml').read_bytes().partition(b'\ninputs:')[0]==prefix
start=time.time();r=subprocess.run(['buf','generate'],cwd=stage/'proto',env=env,capture_output=True);(audit/(label+'-generation.stdout')).write_bytes(r.stdout);(audit/(label+'-generation.stderr')).write_bytes(r.stderr)
expected=['subscription.pb.go','subscription_service.pb.go','subscription_service.pb.gw.go','subscription_service_grpc.pb.go'];outputs=sorted(x for x in (stage/'pkg/api').rglob('*') if x.is_file()) if (stage/'pkg/api').exists() else [];actual=sorted(x.name for x in outputs)
record={'source_sha':rev,'command':['buf','generate'],'cwd':str(stage/'proto'),'GOWORK':'off','TMPDIR':env['TMPDIR'],'git_environment_sanitized':True,'archive_sha256':hashlib.sha256(archive).hexdigest(),'plugin_prefix_sha256':hashlib.sha256(prefix).hexdigest(),'buf_version':subprocess.check_output(['buf','--version'],env=env,text=True).strip(),'go_version':subprocess.check_output(['go','version'],env=env,cwd=stage,text=True).strip(),'rc':r.returncode,'elapsed_seconds':time.time()-start,'expected_names':sorted(expected),'output_names':actual,'outputs':{str(x.relative_to(stage/'pkg')):hashlib.sha256(x.read_bytes()).hexdigest() for x in outputs}}
(audit/(label+'-generation.json')).write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2));r.check_returncode();assert actual==sorted(expected)
corelib=ws/'project/corelib';core_sha='34bc8104a832b67e53c868646ab2b1e0ac4c8562';differences=[]
for output in outputs:
 rel=str(output.relative_to(stage/'pkg'));baseline=subprocess.check_output(['git','-C',str(corelib),'show',core_sha+':'+rel],env=env)
 if baseline!=output.read_bytes():differences.append(rel)
record['corelib_baseline_sha']=core_sha;record['differs_from_corelib_baseline']=differences
(audit/(label+'-generation.json')).write_text(json.dumps(record,indent=2)+'\n');print('differs_from_corelib_baseline',differences)
