#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Внешняя проба извлекает фактический блок захвата и cleanup; локально не исполнять.
import hashlib, json, pathlib, subprocess, sys, tempfile
source=pathlib.Path(sys.argv[1]).read_text()
start=source.index('if [ -n "$OPERATOR_DEF" ]; then', source.rindex('red_collect "$RUN_RC"'))
end=source.index('\n}', start)
block=source[start:end]
a=source.index('cleanup() {\n'); b=source.index('\n}\n# shellcheck disable=SC2329', a)+2
cleanup=source[a:b]
setup=r'''
set -uo pipefail
MODE=$1; RUN_RC=$2; TRACE=$3; BOX=$4
mkdir "$BOX"
OPERATOR_DEF=reviewed; OPERATOR_UID=; OPERATOR_NS_UID=
OPERATOR_HELPER=fixture; NSNAME=testns; POD=testpod
DONE=0; BG=; TMPREF=; CREATED=1; KEEP_H=; EXPIRES=none
T0=0; T1=0; T2=0; PROFILE=fixture
say() { printf '%s\n' "$*"; }
now() { printf '0'; }
guard_write() { return 0; }
kc() {
  local stage
  case "$*" in
    '-n testns get job run -o json') stage=job;;
    '-n testns get pod testpod -o json') stage=pod;;
    'get ns testns -o json') stage=namespace;;
    '-n testns logs testpod -c run') stage=logs;;
    'delete ns testns --wait=true --timeout=300s') printf 'DELETE\n' >> "$TRACE"; [ "$MODE" != cleanupfail ]; return $?;;
    'get ns testns --ignore-not-found -o name') printf 'ABSENCE\n' >> "$TRACE"; [ "$MODE" != absencefail ]; return $?;;
    *) printf 'unexpected kc: %s\n' "$*" >&2; return 99;;
  esac
  printf '%s\n' "$stage" >> "$TRACE"
  [ "$MODE" != "$stage" ] || return 77
  if [ "$MODE" = malformed ] && [ "$stage" = job ]; then printf '{'; return 0; fi
  if [ "$stage" = logs ]; then printf 'retained log\n'; else printf '{"metadata":{"uid":"namespace-uid"}}\n'; fi
}
python3() {
  local action=$2
  printf '%s\n' "$action" >> "$TRACE"
  if [ "$action" = complete ]; then return 0; fi
  [ "$action" = capture ] || return 99
  [ "$MODE" != capture ] || return 78
  command python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$BOX/operator-job.json" || return
  printf 'job-uid\n'
}
jq() { printf 'jq\n' >> "$TRACE"; [ "$MODE" != jq ] || return 79; printf 'namespace-uid\n'; }
'''
program=setup+'\n'+cleanup+'\ntrap \'cleanup; printf "TRAP_UID=%s\\n" "$OPERATOR_UID"\' EXIT\n'+block+'\n'
print('EXTRACTED_BLOCK_SHA256', hashlib.sha256(block.encode()).hexdigest())
print('EXTRACTED_CLEANUP_SHA256', hashlib.sha256(cleanup.encode()).hexdigest())
failures = []
with tempfile.TemporaryDirectory(prefix='operator-capture-probe-') as temporary:
    root=pathlib.Path(temporary)
    cases=[(x,0,69) for x in ['job','pod','namespace','logs','capture','jq','malformed']]+[('valid',0,0),('valid-nonzero',7,7),('cleanupfail',0,0),('absencefail',0,0)]
    for i,(mode,run_rc,expected) in enumerate(cases):
        try:
            trace=root/f'trace-{i}'; box=root/f'box-{i}'
            result=subprocess.run(['bash','-c',program,'probe',mode,str(run_rc),str(trace),str(box)],capture_output=True,text=True,timeout=10)
            events=trace.read_text().splitlines()
            assert result.returncode==expected,(mode,result.returncode,result.stdout,result.stderr)
            assert not box.exists(),(mode,'box retained')
            assert events.count('DELETE')==1,(mode,events)
            if expected==69:
                assert 'TRAP_UID=\n' in result.stdout and 'cleanup ещё не подтверждён' not in result.stdout
                assert 'complete' not in events
            else:
                assert 'TRAP_UID=job-uid\n' in result.stdout and 'cleanup ещё не подтверждён' in result.stdout
                assert ('complete' in events)==(mode not in ['cleanupfail','absencefail']),(mode,events)
            print(json.dumps({'mode':mode,'run_rc':run_rc,'actual_rc':result.returncode,'events':events,'stdout':result.stdout,'stderr':result.stderr}),flush=True)
        except Exception as error:
            failures.append(mode)
            print(json.dumps({'mode': mode, 'failure': repr(error)}), flush=True)
print(f'CAPTURE_CHAIN_PASS {len(cases)-len(failures)}/{len(cases)}')
sys.exit(bool(failures))
