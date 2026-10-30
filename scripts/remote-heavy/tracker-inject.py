#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""External-only controls for the captured-input producer and closed replay."""
import copy
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('tracker', pathlib.Path(__file__).with_name('tracker.py'))
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
passed = 0


def check(name, action, reject=False):
    global passed
    try:
        action()
    except (ValueError, KeyError, TypeError):
        if not reject:
            raise
    else:
        if reject:
            raise AssertionError(name + ': accepted forbidden input')
    passed += 1
    print('tracker control: ' + name + ' PASS')


with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    def git(*args):
        return t.git(root, *args)
    git('init', '-q')
    (root / 'docs/specs/reviews/subject').mkdir(parents=True)
    (root / '.github/scripts').mkdir(parents=True)
    (root / 'docs/specs/reviews/subject/record.yaml').write_text(
        'subject:\n  task: PRO-Robotech/kaname#456\nevent:\n'
        '  url: https://github.com/PRO-Robotech/kacho/issues/1271#issuecomment-1\n')
    (root / 'docs/specs/reviews/subject/pr.yaml').write_text(
        'subject:\n  task: PRO-Robotech/kaname#153\n')
    (root / '.github/scripts/newman-suite-debt.py').write_text(
        '_HOLDER = "PRO-Robotech/kaname#155 — held"\n'
        'PRODUCER_LEDGER = {"x": ("A", "reason", _HOLDER)}\n'
        'SCENARIO_DEBT = {}\nSCENARIO_DEBT.update({"y": ("reason", "PRO-Robotech/kaname#925 — held")})\n')
    git('add', '.')
    git('-c', 'core.hooksPath=/dev/null', '-c', 'user.name=Snapshot Control',
        '-c', 'user.email=control@example.invalid', 'commit', '-qm', 'snapshot control')
    sha = git('rev-parse', 'HEAD')
    inv = t.inventory(root, sha)
    assert inv == {'comments': ['PRO-Robotech/kacho#1271', 'PRO-Robotech/kaname#153', 'PRO-Robotech/kaname#456'],
                   'states': ['PRO-Robotech/kaname#155', 'PRO-Robotech/kaname#925']}
    check('source declaration inventory', lambda: t.inventory(root, sha))
    snapshot = {'schema': 1, 'repo': 'PRO-Robotech/kaname', 'head': sha,
                'tree': git('rev-parse', 'HEAD^{tree}'), 'inventory': inv,
                'started': t.now(), 'completed': t.now(), 'comments': {}, 'states': {}}
    for task in inv['comments']:
        snapshot['comments'][task] = [{'page': 1, 'next': None, 'records': []}]
    for task in inv['states']:
        snapshot['states'][task] = {'number': int(task.split('#')[1]), 'state': 'open',
                                   'html_url': 'https://github.com/' + task.replace('#', '/issues/'),
                                   'updated_at': '2026-10-30T12:00:00Z'}
    task = inv['comments'][0]
    # GitHub comment shape, projected to the unchanged judge's consumed fields.
    record = {'id': 1, 'html_url': 'https://github.com/PRO-Robotech/kacho/issues/1271#issuecomment-1',
              'created_at': '2026-10-30T12:00:00Z', 'body': 'control body', 'user': {'login': 'control'}}
    snapshot['comments'][task] = [
        {'page': 1, 'next': 'https://api.github.com/' + t.endpoint(task) + '/comments?per_page=100&page=2', 'records': [record]},
        {'page': 2, 'next': None, 'records': []}]
    check('lawful complete pagination and states', lambda: t.validate(snapshot, root, sha))
    def changed(name, modify):
        bad = copy.deepcopy(snapshot)
        modify(bad)
        check(name, lambda: t.validate(bad, root, sha), True)
    changed('missing required comment task', lambda s: s['comments'].pop(task))
    changed('truncated pagination', lambda s: s['comments'][task].pop())
    changed('missing holder state', lambda s: s['states'].pop(inv['states'][0]))
    changed('foreign holder state', lambda s: s['states'][inv['states'][0]].update(html_url='https://github.com/foreign/repo/issues/155'))
    changed('malformed API record', lambda s: s['comments'][task][0]['records'][0].update(body=None))
    changed('wrong source binding', lambda s: s.update(tree='0' * 40))
    changed('foreign comment record', lambda s: s['comments'][task][0]['records'][0].update(html_url='https://github.com/PRO-Robotech/kaname/issues/456#issuecomment-1'))
    changed('missing inventory task', lambda s: s['inventory']['comments'].pop())
    changed('foreign extra holder', lambda s: s['states'].update({'PRO-Robotech/kaname#986': {}}))
    # Coordinates captured from the genuine GitHub issue-comments API for PR153
    # (independent review actual-pr-comment-coordinates.json); other fields below
    # remain explicit test data. Preserve the real URL rather than normalizing it.
    pr_task = 'PRO-Robotech/kaname#153'
    pr_record = dict(record, id=5710508705,
                     html_url='https://github.com/PRO-Robotech/kaname/pull/153#issuecomment-5710508705')
    snapshot['comments'][pr_task][0]['records'] = [pr_record]
    check('lawful genuine PR comment coordinates', lambda: t.validate(snapshot, root, sha))
    for name, url in (
            ('PR foreign repository', 'https://github.com/foreign/kaname/pull/153#issuecomment-5710508705'),
            ('PR wrong task number', 'https://github.com/PRO-Robotech/kaname/pull/154#issuecomment-5710508705'),
            ('PR wrong comment ID', 'https://github.com/PRO-Robotech/kaname/pull/153#issuecomment-5710508706')):
        changed(name, lambda s, url=url: s['comments'][pr_task][0]['records'][0].update(html_url=url))
    holder = inv['states'][0]
    pr_holder = copy.deepcopy(snapshot)
    pr_holder['states'][holder]['html_url'] = 'https://github.com/' + holder.replace('#', '/pull/')
    check('lawful PR holder REST state', lambda: t.validate(pr_holder, root, sha))
    changed('holder float number', lambda s: s['states'][holder].update(number=155.0))
    changed('holder bool number', lambda s: s['states'][holder].update(number=True))
    changed('bool schema', lambda s: s.update(schema=True))
    for name, url in (
            ('PR holder foreign repository', 'https://github.com/foreign/kaname/pull/155'),
            ('PR holder wrong task number', 'https://github.com/PRO-Robotech/kaname/pull/156')):
        changed(name, lambda s, url=url: s['states'][holder].update(html_url=url))
    path = str(root / 'snapshot.json')
    pathlib.Path(path).write_text(json.dumps(snapshot))
    t.main(['validate', str(root), sha, path])
    check('lawful captured state replay', lambda: t.main(['replay', str(root), sha, path, 'api',
          'repos/PRO-Robotech/kaname/issues/155', '--jq', '.state']))
    check('lawful captured comments replay', lambda: t.main(['replay', str(root), sha, path, 'api', '--paginate',
          'repos/PRO-Robotech/kacho/issues/1271/comments?per_page=100', '--jq', t.COMMENT_JQ]))
    for argv in ([ 'api', 'repos/PRO-Robotech/kaname/issues/986', '--jq', '.state'],
                 ['api', 'repos/PRO-Robotech/kaname/issues/155', '--jq', '.body'],
                 ['api', '--method', 'POST', 'repos/PRO-Robotech/kaname/issues/155'],
                 ['pr', 'list'], ['auth', 'token'],
                 ['api', '--paginate', 'repos/PRO-Robotech/kacho/issues/1271/comments?per_page=100', '--jq', '.[]']):
        check('uncaptured invocation ' + ' '.join(argv[:2]),
              lambda argv=argv: t.main(['replay', str(root), sha, path, *argv]), True)
    pathlib.Path(path).write_text(json.dumps(snapshot) + ' ')
    check('transport modified after validation', lambda: t.main(['replay', str(root), sha, path,
          'api', 'repos/PRO-Robotech/kaname/issues/155', '--jq', '.state']), True)
    # Producer exercises actual gh subprocess/headers, with credential-free local
    # API double. Complete and truncated responses use the same producer route.
    bindir = root / 'bin'; bindir.mkdir()
    fake = bindir / 'gh'
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys
p=sys.argv[-1]
print('HTTP/2 200 OK')
if '/comments?' in p:
 if p.endswith('page=1'):
  print('Link: <https://api.github.com/'+(p.rsplit('page=',1)[0]+'page=2')+'>; rel="next"')
  print(); print('[]')
 elif os.getenv('TRUNCATED'):
  sys.exit(1)
 else:
  print(); print('[]')
else:
 repo,num=p.removeprefix('repos/').split('/issues/')
 print(); print(json.dumps(dict(number=int(num),state='open',html_url='https://github.com/'+repo+'/issues/'+num,updated_at='2026-10-30T12:00:00Z')))
''')
    fake.chmod(0o755)
    os.environ['PATH'] = str(bindir) + ':' + os.environ['PATH']
    check('producer complete header pagination', lambda: t.capture(root, sha, path))
    os.environ['TRUNCATED'] = '1'
    check('producer rejects failed next page', lambda: t.capture(root, sha, path), True)
print('tracker inject: assertions %d, passed %d, failed 0' % (passed, passed))
