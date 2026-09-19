import os,sys,pathlib,subprocess,json,time,hashlib
w=pathlib.Path('/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/tmp/area-ci-truth-tests')
audit=w.parent/'area-ci-audit/docs-truth-tester'
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
env['GOWORK']='off';env['TMPDIR']='/var/tmp/area-ci-truth-tests'
name=sys.argv[1];cmd=sys.argv[2:];start=time.time();head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=w,env=env,text=True).strip()
r=subprocess.run(cmd,cwd=w,env=env,capture_output=True)
(audit/(name+'.stdout')).write_bytes(r.stdout);(audit/(name+'.stderr')).write_bytes(r.stderr)
record={'command':cmd,'cwd':str(w),'head':head,'GOWORK':'off','TMPDIR':env['TMPDIR'],'sanitized_git_env':True,'rc':r.returncode,'elapsed_seconds':time.time()-start,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()}
(audit/(name+'.json')).write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record));print(r.stderr.decode()[-1500:]);sys.exit(r.returncode)
