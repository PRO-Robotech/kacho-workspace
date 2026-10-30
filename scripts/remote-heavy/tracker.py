#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Bounded readonly pre-push inputs; never imports or executes product Python.

Only captured comments (the review inventory) and holder states (the declared
ledger) can be replayed. API output is data, never a command or a jq program.
"""
import ast
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys

MAX_BYTES = 16 * 1024 * 1024
TASK = re.compile(r'^(PRO-Robotech/[a-zA-Z0-9_.-]+)#([1-9][0-9]*)$')
COMMENT_JQ = '.[] | {id, html_url, created_at, body, user: {login: .user.login}}'


def require(value, message):
    if not value:
        raise ValueError(message)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def inventory(root, sha):
    # Same declared records and task/address forms as review-event-silence.
    # safe_load is data parsing; product modules and judges are never executed.
    import yaml
    tasks = set()
    files = git(root, 'ls-tree', '-r', '--name-only', sha, 'docs/specs/reviews').splitlines()
    for name in files:
        if not (len(name.split('/')) == 5 and name.endswith('.yaml')):
            continue
        doc = yaml.safe_load(git(root, 'show', sha + ':' + name))
        require(isinstance(doc, dict), 'review record is not a mapping')
        subject = doc.get('subject') or {}
        task = subject.get('task') if isinstance(subject, dict) else None
        if isinstance(task, str) and TASK.fullmatch(task):
            tasks.add(task)
        ev = doc.get('event') or {}
        if isinstance(ev, dict):
            for field in ('url', 'issue_api_url'):
                value = ev.get(field)
                if not isinstance(value, str):
                    continue
                for rx in (r'^https://github\.com/(PRO-Robotech/[\w.-]+)/issues/(\d+)(?:#.*)?$',
                           r'^https://api\.github\.com/repos/(PRO-Robotech/[\w.-]+)/issues/(\d+)$'):
                    m = re.fullmatch(rx, value.strip())
                    if m:
                        tasks.add(m[1] + '#' + m[2])
    require(tasks, 'empty review task inventory')
    # Evaluate only literal declarations, names and string concatenation. This
    # resolves the consumer's own ledger, including named holder constants and
    # update blocks, without importing code from a branch on the credential host.
    tree = ast.parse(git(root, 'show', sha + ':.github/scripts/newman-suite-debt.py'))
    declarations = {}

    def literal(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            return literal(declarations[node.id])
        if isinstance(node, (ast.Tuple, ast.List)):
            return tuple(literal(x) for x in node.elts)
        if isinstance(node, ast.Dict):
            return {literal(k): literal(v) for k, v in zip(node.keys, node.values)}
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return literal(node.left) + literal(node.right)
        raise ValueError('unsupported holder inventory declaration; refuse incomplete capture')

    ledgers = {}
    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            names = node.targets if isinstance(node, ast.Assign) else [node.target]
            for name in names:
                if isinstance(name, ast.Name) and node.value is not None:
                    declarations[name.id] = node.value
                    if name.id in ('PRODUCER_LEDGER', 'SCENARIO_DEBT'):
                        ledgers[name.id] = literal(node.value)
        elif (isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
              and isinstance(node.value.func, ast.Attribute)
              and isinstance(node.value.func.value, ast.Name)
              and node.value.func.value.id in ('PRODUCER_LEDGER', 'SCENARIO_DEBT')):
            call = node.value
            require(call.func.attr == 'update' and len(call.args) == 1 and not call.keywords,
                    'unsupported ledger mutation')
            ledgers[call.func.value.id].update(literal(call.args[0]))
    require(set(ledgers) == {'PRODUCER_LEDGER', 'SCENARIO_DEBT'}, 'missing holder ledger')
    holders = set()
    for name, rows in ledgers.items():
        for row in rows.values():
            require(isinstance(row, tuple) and len(row) == (3 if name == 'PRODUCER_LEDGER' else 2),
                    'malformed holder ledger row')
            holder = row[-1]
            require(isinstance(holder, str), 'non-string holder')
            m = re.match(r'^(PRO-Robotech/[a-z0-9][a-z0-9-]*#[1-9][0-9]*)', holder)
            if m:
                holders.add(m[1])
    require(holders, 'empty holder inventory')
    return {'comments': sorted(tasks), 'states': sorted(holders)}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def endpoint(task):
    m = TASK.fullmatch(task)
    require(m is not None, 'foreign task')
    return 'repos/' + m[1] + '/issues/' + m[2]


def api(path):
    # Response headers carry actual pagination. Never print API bodies/stderr:
    # comments may contain private context; authentication stays on this host.
    p = subprocess.run(['gh', 'api', '--include', path], capture_output=True, timeout=60)
    require(p.returncode == 0, 'readonly API capture failed: ' + path)
    require(len(p.stdout) <= MAX_BYTES, 'API response exceeds byte bound')
    raw = p.stdout.decode('utf-8').replace('\r\n', '\n')
    headers, sep, body = raw.partition('\n\n')
    require(sep and re.match(r'^HTTP/\S+ 200\b', headers), 'missing successful API headers')
    links = [line.split(':', 1)[1].strip() for line in headers.splitlines()
             if line.lower().startswith('link:')]
    require(len(links) <= 1, 'ambiguous pagination headers')
    nxt = re.findall(r'<([^>]+)>;\s*rel="next"', links[0] if links else '')
    require(len(nxt) <= 1, 'ambiguous next page')
    return json.loads(body), (nxt[0] if nxt else None)


def capture(root, sha, out):
    inv = inventory(root, sha)
    snap = {'schema': 1, 'repo': 'PRO-Robotech/kaname', 'head': sha,
            'tree': git(root, 'rev-parse', sha + '^{tree}'), 'inventory': inv,
            'started': now(), 'comments': {}, 'states': {}}
    for task in inv['comments']:
        pages = []
        for number in range(1, 201):
            path = endpoint(task) + '/comments?per_page=100&page=' + str(number)
            data, nxt = api(path)
            require(isinstance(data, list), 'comments response is not an array')
            # Store only consumer fields; pagination remains an explicit chain.
            rows = [{k: row[k] for k in ('id', 'html_url', 'created_at', 'body')} |
                    {'user': {'login': row['user']['login']}} for row in data]
            pages.append({'page': number, 'next': nxt, 'records': rows})
            require(sum(len(json.dumps(p)) for p in pages) <= MAX_BYTES, 'task byte bound')
            if nxt is None:
                break
            require(nxt == 'https://api.github.com/' + endpoint(task) +
                    '/comments?per_page=100&page=' + str(number + 1), 'unexpected pagination target')
        else:
            raise ValueError('pagination exceeds page bound')
        snap['comments'][task] = pages
    for task in inv['states']:
        data, nxt = api(endpoint(task))
        require(nxt is None, 'issue object unexpectedly paginated')
        snap['states'][task] = {k: data[k] for k in ('number', 'state', 'html_url', 'updated_at')}
    snap['completed'] = now()
    validate(snap, root, sha)
    raw = json.dumps(snap, ensure_ascii=False, separators=(',', ':')).encode()
    require(len(raw) <= MAX_BYTES, 'snapshot exceeds byte bound')
    pathlib.Path(out).write_bytes(raw)
    print('tracker snapshot: tasks %d, holders %d, bytes %d, source %s tree %s' %
          (len(inv['comments']), len(inv['states']), len(raw), sha, snap['tree']))


def timestamp(value):
    require(isinstance(value, str), 'timestamp missing')
    require(datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).tzinfo is not None,
            'timestamp lacks timezone')


def issue_urls(task, suffix=''):
    """REST issue endpoints also return PRs; preserve their canonical html_url."""
    repo, number = task.split('#')
    return {f'https://github.com/{repo}/{kind}/{number}{suffix}'
            for kind in ('issues', 'pull')}


def validate(snap, root, sha):
    require(type(snap.get('schema')) is int and snap['schema'] == 1 and snap.get('repo') == 'PRO-Robotech/kaname', 'foreign schema/repo')
    require(snap.get('head') == sha and snap.get('tree') == git(root, 'rev-parse', sha + '^{tree}'),
            'source binding mismatch')
    timestamp(snap.get('started')); timestamp(snap.get('completed'))
    require(snap['started'] <= snap['completed'], 'capture time order')
    inv = inventory(root, sha)
    require(snap.get('inventory') == inv, 'source inventory mismatch')
    for kind in ('comments', 'states'):
        require(isinstance(snap.get(kind), dict) and set(snap[kind]) == set(inv[kind]),
                'missing/foreign ' + kind + ' task')
    ids = set()
    for task, pages in snap['comments'].items():
        require(isinstance(pages, list) and 1 <= len(pages) <= 200, 'missing/truncated pages')
        for number, page in enumerate(pages, 1):
            expected = ('https://api.github.com/' + endpoint(task) + '/comments?per_page=100&page=' +
                        str(number + 1)) if number < len(pages) else None
            require(page.get('page') == number and page.get('next') == expected, 'incomplete pagination')
            rows = page.get('records')
            require(isinstance(rows, list) and len(rows) <= 100, 'malformed comment page')
            for row in rows:
                require(isinstance(row, dict) and type(row.get('id')) is int and row['id'] > 0,
                        'malformed comment id')
                require(row['id'] not in ids, 'duplicate comment id'); ids.add(row['id'])
                require(row.get('html_url') in issue_urls(task, '#issuecomment-' + str(row['id'])),
                        'foreign comment')
                require(isinstance(row.get('body'), str) and isinstance(row.get('user'), dict)
                        and isinstance(row['user'].get('login'), str) and row['user']['login'],
                        'malformed comment body/user')
                timestamp(row.get('created_at'))
    for task, row in snap['states'].items():
        require(isinstance(row, dict) and type(row.get('number')) is int
                and row['number'] == int(task.split('#')[1])
                and row.get('html_url') in issue_urls(task)
                and row.get('state') in ('open', 'closed'), 'missing/foreign/malformed holder state')
        timestamp(row.get('updated_at'))


def load(path):
    raw = pathlib.Path(path).read_bytes()
    require(len(raw) <= MAX_BYTES, 'snapshot exceeds byte bound')
    return raw, json.loads(raw)


def main(args):
    mode, root, sha, path, *argv = args
    if mode == 'capture':
        capture(root, sha, path)
        return
    raw, snap = load(path)
    require(git(root, 'rev-parse', 'HEAD') == sha, 'checked-out source mismatch')
    if mode == 'validate':
        validate(snap, root, sha)
        pathlib.Path(path + '.sha256').write_text(hashlib.sha256(raw).hexdigest())
        return
    require(mode == 'replay', 'unsupported mode')
    require(pathlib.Path(path + '.sha256').read_text() == hashlib.sha256(raw).hexdigest(),
            'snapshot changed after validation')
    require(snap.get('head') == sha and snap.get('tree') == git(root, 'rev-parse', 'HEAD^{tree}'),
            'source binding mismatch')
    if len(argv) == 5 and argv[:2] == ['api', '--paginate'] and argv[3:] == ['--jq', COMMENT_JQ]:
        m = re.fullmatch(r'repos/(PRO-Robotech/[\w.-]+)/issues/([1-9][0-9]*)/comments\?per_page=100', argv[2])
        require(m is not None, 'uncaptured comments invocation')
        task = m[1] + '#' + m[2]
        require(task in snap['comments'], 'uncaptured comments task')
        for page in snap['comments'][task]:
            for row in page['records']:
                print(json.dumps(row, ensure_ascii=False))
    elif len(argv) == 4 and argv[0] == 'api' and argv[2:] == ['--jq', '.state']:
        m = re.fullmatch(r'repos/(PRO-Robotech/[\w.-]+)/issues/([1-9][0-9]*)', argv[1])
        require(m is not None, 'uncaptured state invocation')
        task = m[1] + '#' + m[2]
        require(task in snap['states'], 'uncaptured state task')
        print(snap['states'][task]['state'])
    else:
        raise ValueError('uncaptured gh invocation')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except Exception as error:
        # Do not include API bodies, source contents or credentials in diagnostics.
        print('gh tracker snapshot: refused (' + type(error).__name__ + ')', file=sys.stderr)
        sys.exit(4)
