import json
import os
import subprocess
import sys

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

phase = sys.argv[1]
assert phase in ('before', 'after'), phase
head = git('rev-parse', 'HEAD')
assert head == os.environ['GITHUB_SHA'], 'source HEAD differs from event SHA'
assert not git('status', '--porcelain', '--untracked-files=no'), 'tracked source changed'
if phase == 'before':
    assert not git('ls-files', '--others', '--exclude-standard'), 'initial checkout has untracked files'
print('OPERATOR_SOURCE_V1 ' + json.dumps({
    'phase': phase, 'head': head, 'tree': git('rev-parse', 'HEAD^{tree}'),
    'tracked_clean': True, 'run_id': int(os.environ['GITHUB_RUN_ID']),
    'run_attempt': int(os.environ['GITHUB_RUN_ATTEMPT']), 'job': os.environ['GITHUB_JOB'],
}, sort_keys=True))
