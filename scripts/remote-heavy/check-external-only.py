#!/usr/bin/env python3
"""Finite strict-routing controls; invoked only inside an external test job."""
import os
import pathlib
import select
import subprocess
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'rituals'))
import _probe as P
ROOT=pathlib.Path(__file__).resolve().parents[2]

def body(pr):
    w=pathlib.Path(pr.tmp);repo=w/'repo';repo.mkdir()
    env=dict(pr.env);env.pop('KACHO_HEAVY_EXTERNAL_ONLY',None)
    def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],env=env,text=True).strip()
    git('init','-q','-b','1531-probe');git('remote','add','origin','https://github.com/PRO-Robotech/kaname.git')
    (repo/'f').write_text('fixture\n');git('add','.');git('commit','-qm','fixture')
    mem=w/'meminfo';mem.write_text('MemTotal: 100663296 kB\nMemAvailable: 99639296 kB\n')
    bins=w/'payload-bin';bins.mkdir();sentinel=w/'local-payload';remote=w/'remote-called'
    (bins/'go').write_text('#!/bin/sh\ntouch "$SENTINEL"\nexit 0\n');(bins/'go').chmod(0o755)
    mock=w/'remote.sh';mock.write_text('''#!/bin/bash
[ "${1:-}" != --request ] || { echo '1000 1000'; exit 0; }
if [ "${1:-}" = --available ]; then
 [ -z "${STRICT_FIFO:-}" ] || printf '%s' "$KACHO_HEAVY_EXTERNAL_ONLY" > "$STRICT_FIFO"
 exit "${AVAIL_RC:-0}"
fi
printf '%s\\n' "$@" > "$REMOTE_CALLED"
exit 17
''')
    env.update(HEAVY_SLOT_MEMINFO=str(mem),HEAVY_SLOT_DIR=str(w/'slots'),HEAVY_SLOT_BUDGET_MIB='64',HEAVY_SLOT_LIMIT_MIB='100000',HEAVY_SLOT_GUARD_S='1',HEAVY_SLOT_POLL_S='1',HEAVY_SLOT_CHECK_S='1',HEAVY_SLOT_REMOTE_RUN=str(mock),SENTINEL=str(sentinel),REMOTE_CALLED=str(remote),PATH=str(bins)+':'+env['PATH'])
    slot=ROOT/'scripts/heavy-slot.sh'
    def call(args,changes=None,remove=()):
        e=dict(env);e.update(changes or {})
        for k in remove:e.pop(k,None)
        return subprocess.run(['bash',str(slot),*args],cwd=repo,env=e,text=True,capture_output=True,timeout=20)
    def blocked(label,args,code,changes=None,remove=()):
        sentinel.unlink(missing_ok=True);p=call(args,changes,remove)
        pr.ok(label,p.returncode==code and not sentinel.exists() and ('external-only' in p.stderr or 'KACHO_HEAVY_EXTERNAL_ONLY' in p.stderr),p.stderr)
    # Child strict mode is observed through a FIFO, not a polling loop.
    fifo=w/'strict-fifo';os.mkfifo(fifo);fd=os.open(fifo,os.O_RDONLY|os.O_NONBLOCK);queue=w/'enq';queue.mkdir()
    enq=call(['--external-only','--enqueue',str(queue),'integration','--','go','version'],{'AVAIL_RC':'69','STRICT_FIFO':str(fifo)})
    ready=select.select([fd],[],[],10)[0];mode=os.read(fd,8) if ready else b'';os.close(fd)
    pr.ok('enqueue propagates strict mode',enq.returncode==0 and mode==b'1',enq.stderr)
    for code in (69,124):blocked('unavailable '+str(code),['--external-only','integration','--','go','version'],code,{'AVAIL_RC':str(code)})
    blocked('missing route',['--external-only','docker','--','go','version'],77,{'AVAIL_RC':'69'})
    blocked('missing mechanism',['--external-only','integration','--','go','version'],77,remove=('HEAVY_SLOT_REMOTE_RUN',))
    blocked('explicit local conflict',['--external-only','--local','explicit local reason','integration','--','go','version'],64)
    blocked('environment mode',['integration','--','go','version'],69,{'KACHO_HEAVY_EXTERNAL_ONLY':'1','AVAIL_RC':'69'})
    blocked('invalid environment',['integration','--','go','version'],64,{'KACHO_HEAVY_EXTERNAL_ONLY':'yes'})
    (w/'slots/queue').mkdir(parents=True,exist_ok=True);(w/'slots/queue/000000000007').write_text('external_only=1\n')
    blocked('resume preserves ticket restriction',['--resume','7','integration','--','go','version'],69,{'AVAIL_RC':'69'})
    sentinel.unlink(missing_ok=True);p=call(['--external-only','integration','--','go','version'])
    pr.ok('lawful remote profile admitted',p.returncode==17 and remote.exists() and not sentinel.exists(),p.stderr)
    p=call(['--external-only','--route','integration','--','go','version'])
    pr.ok('route remains read only',p.returncode==0 and '\texternal\t' in p.stdout and not sentinel.exists(),p.stderr)
    sentinel.unlink(missing_ok=True);p=call(['integration','--','go','version'],{'AVAIL_RC':'69'})
    pr.ok('legacy unavailable fallback unchanged',p.returncode==0 and sentinel.exists(),p.stderr)
    # A normal source hook stays eligible for the remote pre-push protocol.
    hooks=repo/'scripts/hooks';hooks.mkdir(parents=True);hook=hooks/'pre-push';hook.write_text('#!/bin/sh\nexit 0\n');hook.chmod(0o755)
    git('add','.');git('commit','-qm','hook fixture');stub=repo/'.git/hooks/pre-push';stub.write_text('#!/bin/sh\nexit 0\n');stub.chmod(0o755)
    p=call(['--external-only','--route','ci-local','--','git','push','origin','HEAD:refs/heads/1531'])
    pr.ok('normal remote push route admitted',p.returncode==0 and '\texternal\t' in p.stdout,p.stderr)
    receipts=list(queue.glob('*.rc'))
    pr.ok('enqueued strict child terminal without fallback',len(receipts)==1 and receipts[0].read_text().strip()=='69','receipts '+str(receipts))

if __name__=='__main__':sys.exit(P.main('strict-external',body))
