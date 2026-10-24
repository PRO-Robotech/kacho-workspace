#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Closed operator validation inventory and producer evidence (#1361).

Existing stand-report repositories retain their original path. Operator evidence
is exact-source only: no carry, local exception, caller-supplied green counters,
or replacement of a hosted job by a cluster job. Missing evidence is unread.
"""
import base64
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, urlencode

import yaml


INVENTORY = {
    'PRO-Robotech/kaname-iam-operator': {
        'test.yml:test': ('cluster-job', 'go-json-v1'),
        'lint.yml:lint': ('cluster-job', 'completion'),
        'inject.yml:inject': ('cluster-job', 'iam-injection-v1'),
        'docker-build.yml:docker-build-amd64': ('github-hosted', 'completion'),
        'integration.yml:integration': ('github-hosted', 'go-v1'),
        'test-e2e.yml:test-e2e': ('github-hosted', 'go-v1'),
    },
    'PRO-Robotech/registry-operator': {
        'ci.yml:generate': ('cluster-job', 'completion'),
        'ci.yml:test': ('cluster-job', 'go-v1'),
        'ci.yml:injections': ('cluster-job', 'injection-v1'),
        'ci.yml:lint': ('cluster-job', 'completion'),
        'ci.yml:chart': ('cluster-job', 'operator-chart-v1'),
        'ci.yml:zot': ('cluster-job', 'go-v1'),
        'ci.yml:kind-e2e': ('github-hosted', 'go-v1'),
        'ci.yml:docker': ('github-hosted', 'completion'),
        'charts.yml:render': ('cluster-job', 'charts-v1'),
        'charts.yml:ct': ('cluster-job', 'completion'),
        'charts.yml:admission': ('github-hosted', 'admission-v1'),
        'charts.yml:kaname-manifest': ('cluster-job', 'go-v1'),
        'integration-kaname.yml:kaname': ('github-hosted', 'go-v1'),
    },
    'PRO-Robotech/vault-operator': {
        'test.yml:test': ('cluster-job', 'go-ginkgo-v1'),
        'lint.yml:lint': ('cluster-job', 'completion'),
        'vulncheck.yml:govulncheck': ('cluster-job', 'completion'),
        'docker-build.yml:docker-build-amd64': ('github-hosted', 'completion'),
        'test-e2e.yml:test-e2e': ('github-hosted', 'ginkgo-v2'),
        'test-e2e.yml:test-e2e-pipeline': ('github-hosted', 'go-v1'),
        'test-e2e.yml:load': ('github-hosted', 'go-v1'),
    },
}


class Unread(Exception):
    """No trustworthy complete evidence exists for the requested subject."""


def require(condition, message):
    if not condition:
        raise Unread(message)


def digest(value):
    if not isinstance(value, bytes):
        value = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(value).hexdigest()


def command(argv, cwd=None):
    result = subprocess.run(argv, cwd=cwd, text=True, capture_output=True, timeout=120)
    require(result.returncode == 0, 'producer command failed: ' + argv[0])
    return result.stdout


def git(co, *args):
    return command(['git', *args], co).strip()


def api(repo, endpoint, raw=False):
    # The executable override is the same fixture seam as stand-report.sh.
    # Raw job logs retain ANSI bytes for the parser; they are never printed.
    output = command([os.environ.get('STAND_REPORT_GH', 'gh'), 'api'] +
                     (['--allow-escape-sequences'] if raw else []) +
                     ['repos/' + repo + '/' + endpoint])
    return output if raw else json.loads(output)


def pages(repo, endpoint, key):
    items = []
    for page in range(1, 101):
        sep = '&' if '?' in endpoint else '?'
        data = api(repo, endpoint + sep + urlencode({'per_page': 100, 'page': page}))
        batch = data.get(key)
        require(isinstance(batch, list), 'malformed paginated API ' + key)
        items.extend(batch)
        if len(batch) < 100:
            require(len(items) == data.get('total_count'), 'incomplete API census ' + key)
            return items
    raise Unread('API pagination exceeds supported bound')


def load_workflow(text):
    # PyYAML's YAML 1.1 treats `on` as True; only normalize that well-known key.
    document = yaml.safe_load(text)
    require(isinstance(document, dict), 'workflow is not a mapping')
    if True in document:
        document['on'] = document.pop(True)
    require(isinstance(document.get('jobs'), dict), 'workflow has no jobs')
    return document


def match(pattern, value):
    require(isinstance(pattern, str) and not re.search(r'[!+?\[\]{}$]', pattern),
            'unsupported trigger pattern ' + str(pattern))
    regex = re.escape(pattern).replace(r'\*\*', '.*').replace(r'\*', '[^/]*')
    return re.fullmatch(regex, value) is not None


def eligibility(doc, branch, changed, observed=False):
    trigger = doc.get('on')
    if isinstance(trigger, list):
        require('push' in trigger, 'workflow has no push trigger')
        return
    require(isinstance(trigger, dict) and 'push' in trigger, 'workflow has no push trigger')
    push = trigger['push'] or {}
    require(isinstance(push, dict), 'unsupported push trigger')
    require(set(push) <= {'branches', 'branches-ignore', 'paths', 'paths-ignore', 'tags', 'tags-ignore'},
            'unsupported push filter')
    for included, excluded, values in [('branches', 'branches-ignore', [branch]),
                                       ('paths', 'paths-ignore', changed)]:
        require(not (included in push and excluded in push), 'conflicting trigger filters')
        if included in push:
            patterns = push[included]
            require(isinstance(patterns, list) and patterns, 'empty trigger filter')
            for pattern in patterns:
                match(pattern, '')  # Validate syntax even for an observed run.
            require((observed and included == 'paths') or any(match(p, v) for p in patterns for v in values),
                    'push does not trigger ' + included)
        if excluded in push:
            patterns = push[excluded]
            require(isinstance(patterns, list) and patterns, 'empty exclusion filter')
            for pattern in patterns:
                match(pattern, '')
            require((observed and excluded == 'paths-ignore') or any(not any(match(p, v) for p in patterns) for v in values),
                    'push excluded by ' + excluded)
    require('branches' in push or 'branches-ignore' in push or
            not ({'tags', 'tags-ignore'} & set(push)), 'tag-only workflow')


def definition(doc, key):
    job = doc['jobs'][key]
    require(isinstance(job, dict) and not ({'strategy', 'uses'} & set(job)),
            'matrix/reusable required job is unsupported')
    require(job.get('if') in (None, "github.event_name == 'push'", "${{ github.event_name == 'push' }}"),
            'unsupported required job condition')
    require(job.get('runs-on') in ('ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04'),
            'required job is not a supported hosted VM')
    steps = job.get('steps')
    require(isinstance(steps, list) and steps, 'required job has no steps')
    checkout = steps[0]
    require(isinstance(checkout, dict) and
            checkout.get('uses', '').startswith('actions/checkout@'), 'primary checkout is not first')
    require(not ({'ref', 'repository', 'path', 'sparse-checkout'} & set(checkout.get('with', {}))),
            'overridden source checkout is unsupported')
    return {'job': job, 'env': doc.get('env', {}), 'defaults': doc.get('defaults', {})}


def gitlab_helper():
    import importlib.util
    spec = importlib.util.spec_from_file_location('operator_gitlab', Path(__file__).with_name('operator-gitlab.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected(co, head, base, ref, push_before=None, forge=None):
    if forge is not None:
        return gitlab_helper().expected(co, head, base, ref, forge,
            INVENTORY['PRO-Robotech/registry-operator'], git, require, digest, yaml.safe_load)
    require(git(co, 'rev-parse', 'HEAD') == head, 'checkout SHA differs')
    require(not git(co, 'status', '--porcelain', '--untracked-files=all'), 'checkout is dirty')
    url = git(co, 'remote', 'get-url', 'origin')
    found = re.search(r'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$', url)
    repo = found.group(1) if found else ''
    require(repo in INVENTORY, 'operator repository is outside the closed inventory')
    require(ref.startswith('refs/heads/') and len(ref) > 11, 'source must be an explicit branch ref')
    base_sha = git(co, 'rev-parse', base)
    changed = []
    if push_before:
        require(re.fullmatch('[0-9a-f]{40}', push_before) is not None, 'push-before is not a SHA')
        remote = git(co, 'ls-remote', '--refs', 'origin', ref).split()
        require(remote == [push_before, ref] and push_before != head, 'push-before is not current remote head')
        changed = git(co, 'diff', '--name-only', push_before, head).splitlines()
    definitions, actual = {}, set()
    for path in sorted((Path(co) / '.github/workflows').glob('*.y*ml')):
        raw = path.read_bytes()
        doc = load_workflow(raw)
        push = doc.get('on', {}).get('push') if isinstance(doc.get('on'), dict) else None
        filtered = isinstance(push, dict) and bool({'paths', 'paths-ignore'} & set(push))
        observed = False
        if filtered and not push_before:
            runs = pages(repo, 'actions/workflows/' + quote(path.name) + '/runs?' +
                         urlencode({'event': 'push', 'head_sha': head, 'branch': ref[11:]}), 'workflow_runs')
            observed = any(r.get('event') == 'push' and r.get('head_sha') == head and
                           r.get('head_branch') == ref[11:] and
                           r.get('path') == '.github/workflows/' + path.name for r in runs)
            require(observed, 'path-filtered workflow needs verified --push-before or observed exact push run')
        for key in doc['jobs']:
            name = path.name + ':' + key
            # Only this explicit tag-only publication job is outside validation.
            if repo.endswith('/registry-operator') and name == 'charts.yml:publish':
                require(doc['jobs'][key].get('if') == "startsWith(github.ref, 'refs/tags/registry-instance-') || startsWith(github.ref, 'refs/tags/registry-platform-')",
                        'publication exclusion no longer tag-only')
                continue
            actual.add(name)
            require(name in INVENTORY[repo], 'undeclared workflow job ' + name)
            eligibility(doc, ref[11:], changed, observed)
            item = definition(doc, key)
            executor, parser = INVENTORY[repo][name]
            definitions[name] = {'executor': executor, 'parser': parser,
                                 'definition': item, 'definition_digest': digest(item),
                                 'workflow_digest': digest(raw),
                                 'name': item['job'].get('name', key)}
    require(actual == set(INVENTORY[repo]), 'missing workflow jobs')
    return {'schema': 'operator-stand-v1', 'repo': repo, 'head': head,
            'tree': git(co, 'rev-parse', 'HEAD^{tree}'), 'base': base,
            'base_sha': base_sha, 'ref': ref, 'push_before': push_before,
            'source': 'operator-full', 'full': True,
            'ledger': list(INVENTORY[repo]), 'jobs': list(INVENTORY[repo]),
            'definitions': definitions}


def source_markers(text, expected, key, run_id, attempt):
    records, positions = [], []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        # API job logs have a timestamp prefix. Do not parse printed shell source.
        line = re.sub(r'^\d{4}-\d\d-\d\dT\S+ ', '', line)
        if line.startswith('OPERATOR_SOURCE_V1 '):
            records.append(json.loads(line[len('OPERATOR_SOURCE_V1 '):]))
            positions.append(index)
    require(len(records) == 2, 'missing/duplicate actual source producer records')
    for phase, record in zip(('before', 'after'), records):
        require(record == {'phase': phase, 'head': expected['head'], 'tree': expected['tree'],
                           'tracked_clean': True, 'run_id': run_id,
                           'run_attempt': attempt, 'job': key}, 'source provenance mismatch')
    return '\n'.join(lines[positions[0] + 1:positions[1]])


def census(text, parser):
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    lines = [re.sub(r'^\d{4}-\d\d-\d\dT\S+ ', '', line) for line in text.splitlines()]
    if parser == 'completion':
        return None
    if parser == 'go-ginkgo-v1':
        return {'go_entries': census(text, 'go-v1'), 'ginkgo_specs': census(text, 'ginkgo-v2')}
    if parser == 'go-json-v1':
        runs, passed, packages, completed, empty = Counter(), Counter(), Counter(), Counter(), Counter()
        no_tests = set()
        for line in lines:
            if not line.startswith('{'):
                continue
            event = json.loads(line)
            require(isinstance(event, dict) and 'Action' in event and 'Package' in event,
                    'unknown JSON test output')
            action, package, test = event['Action'], event['Package'], event.get('Test')
            require(action != 'fail' and not (action == 'skip' and test), 'Go JSON failed/skipped case')
            if action == 'output' and not test and '[no test files]' in event.get('Output', ''):
                no_tests.add(package)
            if action == 'skip' and not test:
                empty[package] += 1
            if action == 'start' and not test:
                packages[package] += 1
            if action == 'pass' and not test:
                completed[package] += 1
            if action == 'run' and test:
                runs[(package, test)] += 1
            if action == 'pass' and test:
                passed[(package, test)] += 1
        require(runs and runs == passed and packages and packages == completed + empty and
                set(empty) <= no_tests,
                'Go JSON case/package census incomplete')
        return sum(runs.values())
    if parser == 'go-v1':
        selected, passed, failed, skipped = Counter(), Counter(), Counter(), Counter()
        for line in lines:
            start = re.fullmatch(r'=== RUN\s+(\S+)', line)
            end = re.fullmatch(r'\s*--- (PASS|FAIL|SKIP): (\S+) \([0-9.]+s\)', line)
            if start:
                selected[start[1]] += 1
            if end:
                {'PASS': passed, 'FAIL': failed, 'SKIP': skipped}[end[1]][end[2]] += 1
        require(selected and selected == passed and not failed and not skipped,
                'Go case census incomplete/failed/skipped')
        return sum(selected.values())
    if parser == 'ginkgo-v2':
        ran = re.findall(r'^Ran (\d+) of (\d+) Specs in [0-9.]+ seconds$', '\n'.join(lines), re.M)
        outcomes = re.findall(r'^SUCCESS!.*? (\d+) Passed \| (\d+) Failed \| (\d+) Pending \| (\d+) Skipped$',
                              '\n'.join(lines), re.M)
        require(ran and len(ran) == len(outcomes), 'missing Ginkgo census')
        for (executed, total), (passed, failed, pending, skipped) in zip(ran, outcomes):
            require(int(total) > 0 and executed == total == passed and
                    (failed, pending, skipped) == ('0', '0', '0'), 'Ginkgo incomplete/failed/skipped')
        return sum(int(total) for _, total in ran)
    if parser == 'admission-v1':
        rows = re.findall(r'^admission: passed (\d+), failed (\d+), not executed (\d+)$',
                          '\n'.join(lines), re.M)
        require(len(rows) == 1, 'missing/duplicate admission census')
        passed, failed, missing = map(int, rows[0])
        require(passed > 0 and failed == 0 and missing == 0, 'admission cases not all executed')
        return passed
    if parser == 'injection-v1':
        rows = re.findall(r'^inject: rows (\d+), proven (\d+), failed (\d+)$', '\n'.join(lines), re.M)
        require(len(rows) == 1, 'missing/duplicate native injection census')
        selected, proven, failed = map(int, rows[0])
        require(selected > 0 and selected == proven and failed == 0, 'injections incomplete/failed')
        return selected
    if parser == 'iam-injection-v1':
        summaries = re.findall(r'^инъекций (\d+) · находок (\d+)$', '\n'.join(lines), re.M)
        rows = re.findall(r'^[^\t]+\tGREEN\tRED\t[^\n]+$', '\n'.join(lines), re.M)
        require(len(summaries) == 1 and int(summaries[0][0]) > 0 and
                int(summaries[0][0]) == len(rows) and summaries[0][1] == '0',
                'IAM injection census incomplete/failed')
        return len(rows)
    if parser == 'charts-v1':
        total = 0
        for expression in (r'^charts: passed (\d+), failed (\d+)$',
                           r'^route-namespace: checks passed (\d+), failed (\d+)$'):
            rows = re.findall(expression, '\n'.join(lines), re.M)
            require(len(rows) == 1, 'missing/duplicate chart native census')
            passed, failed = map(int, rows[0])
            require(passed > 0 and failed == 0, 'chart cases failed/empty')
            total += passed
        return total
    if parser == 'operator-chart-v1':
        wanted = {'helm-lint', 'config', 'netpol-positive', 'netpol-missing', 'netpol-open',
                  'values-positive', 'values-prefix-platform', 'values-prefix-registry', 'digest-required'}
        rows = [json.loads(line[len('OPERATOR_CASE_V1 '):]) for line in lines
                if line.startswith('OPERATOR_CASE_V1 ')]
        require(len(rows) == len(wanted) and {row.get('name') for row in rows} == wanted and
                all(row.get('outcome') == 'pass' for row in rows), 'chart assertions incomplete/failed')
        return len(rows)
    raise Unread('unsupported native census parser ' + parser)


def verify_image_builds(repo, name, target, job):
    image_files = {
        ('PRO-Robotech/vault-operator', 'docker-build.yml:docker-build-amd64'):
            {'./Dockerfile', './Dockerfile.vaultsecret', './Dockerfile.bucket'},
        ('PRO-Robotech/kaname-iam-operator', 'docker-build.yml:docker-build-amd64'): {'./Dockerfile'},
        ('PRO-Robotech/registry-operator', 'ci.yml:docker'): {'Dockerfile', 'Dockerfile.iam-proxy'},
    }.get((repo, name))
    if image_files:
        builds = [step for step in target['definition']['job']['steps']
                  if step.get('uses', '').startswith('docker/build-push-action@')]
        require(len(builds) == len(image_files) and
                {step.get('with', {}).get('file') for step in builds} == image_files,
                'image build inventory differs')
        names = Counter(step.get('name') or 'Run ' + step['uses'] for step in builds)
        observed = [step for step in job.get('steps', []) if step.get('name') in names]
        require(Counter(step['name'] for step in observed) == names and
                len({step['number'] for step in observed}) == len(observed) and
                all(step.get('status') == 'completed' and step.get('conclusion') == 'success'
                    for step in observed), 'required image build skipped/missing/failed')



def verify_vault_runtime(repo, name, target, job):
    required = {
        'test-e2e.yml:test-e2e-pipeline': ('Running pipeline e2e', 'make test-e2e-pipeline'),
        'test-e2e.yml:load': ('Running the load measurement', 'make test-load'),
    }.get(name) if repo == 'PRO-Robotech/vault-operator' else None
    if required is None:
        return
    step_name, invocation = required
    source = target['definition']
    steps = source['job']['steps']
    selected = [step for step in steps if step.get('name') == step_name]
    require(len(selected) == 1 and selected[0].get('run', '').strip() == invocation and
            not selected[0].get('if'), 'Vault runtime command differs or is conditional')
    require(all('LOAD_WINDOW' not in scope.get('env', {}) for scope in
                [source, source['job']] + steps) and
            all('LOAD_WINDOW' not in step.get('run', '') for step in steps),
            'Vault load window override is forbidden')
    if name.endswith(':test-e2e-pipeline'):
        require(steps[0].get('with', {}).get('fetch-depth') == 0, 'legacy history is unavailable')
    observed = [step for step in job.get('steps', []) if step.get('name') == step_name]
    require(len(observed) == 1 and observed[0].get('status') == 'completed' and
            observed[0].get('conclusion') == 'success', 'Vault runtime step skipped/missing/failed')


VAULT_PIPELINE_TESTS = {
    'TestPipelineE2E', 'TestSecretPipelineE2E', 'TestS3BucketPipelineE2E',
    'TestGuestOnOperatorMountE2E', 'TestOwnershipE2E', 'TestTemplateRoleE2E',
    'TestOneVaultTokenPerProcessE2E', 'TestUpgradeFromLegacyKeepsVaultByteForByte',
} | {'TestOwnershipE2E/' + suffix for suffix in (
    'a_policy_that_exists_before_the_claim_keeps_its_body',
    'a_second_claim_with_the_same_transit_key_never_configures_it',
    'a_hand-made_mount_is_not_adopted_by_a_claim_that_waited_for_its_kubeconfig',
    'names_are_compared_the_way_Vault_resolves_them',
    'the_ledger_removes_what_left_spec',
    'enforce_keeps_an_escalation_out_of_Vault;_the_twin_is_written',
)}


def vault_pipeline_inventory(files):
    """Закрытая форма текущего Go suite; неизвестный build tag/вложение — отказ."""
    require(isinstance(files, dict) and files, 'Vault pipeline sources missing')
    required = set()
    for path, raw in sorted(files.items()):
        require(re.fullmatch(r'test/e2e_pipeline/[a-z0-9_]+_test\.go', path),
                'unsupported pipeline source path')
        text = raw.decode('utf-8')
        tags = re.findall(r'^//go:build (.+)$', text, re.M)
        require(tags in (['e2e'], ['e2e && load']), 'unsupported pipeline build tags')
        if tags == ['e2e && load']:
            require(path.endswith('/load_test.go'), 'unexpected load-only source')
            continue
        names = re.findall(r'^func (Test[A-Za-z0-9_]+)\(t \*testing\.T\) \{', text, re.M)
        require(len(names) == len(re.findall(r'^func Test', text, re.M)),
                'unsupported pipeline test declaration')
        require(len(names) == len(set(names)) and not (set(names) & required),
                'duplicate pipeline test declaration')
        required.update(names)
        runs = re.findall(r'\b\w+\.Run\s*\((?!\s*\))', text)
        if runs:
            require(path.endswith('/ownership_test.go') and
                    names == ['TestGuestOnOperatorMountE2E', 'TestOwnershipE2E'],
                    'unsupported pipeline subtest owner')
            body = text.split('func TestOwnershipE2E(t *testing.T) {', 1)[1]
            literals = re.findall(r'^\tt\.Run\("([^"\\\n]+)", func\(t \*testing\.T\) \{', body, re.M)
            require(len(runs) == len(literals) and literals, 'unsupported dynamic/nested pipeline subtest')
            children = ['TestOwnershipE2E/' + re.sub(r'\s', '_', name) for name in literals]
            require(len(children) == len(set(children)), 'duplicate pipeline subtest')
            required.update(children)
    require(VAULT_PIPELINE_TESTS <= required, 'baseline pipeline tests were removed')
    return required


def vault_pipeline_source(repo, head):
    """Источник — GitHub exact commit, никогда не наблюдаемый native лог."""
    prefix = 'test/e2e_pipeline/'
    entries = api(repo, 'contents/' + prefix.rstrip('/') + '?' + urlencode({'ref': head}))
    require(isinstance(entries, list) and entries, 'pipeline source directory missing')
    require(all(x.get('type') == 'file' for x in entries), 'nested pipeline source tree unsupported')
    files = {}
    for entry in entries:
        path = entry.get('path', '')
        if not path.endswith('_test.go'):
            continue
        require(path.startswith(prefix) and path not in files, 'pipeline source path differs/duplicated')
        item = api(repo, 'contents/' + quote(path, safe='/') + '?' + urlencode({'ref': head}))
        require(item.get('type') == 'file' and item.get('path') == path and
                item.get('encoding') == 'base64', 'pipeline source blob unavailable')
        raw = base64.b64decode(item['content'])
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        require(blob == item.get('sha') == entry.get('sha'), 'pipeline source blob identity differs')
        files[path] = raw
    return vault_pipeline_inventory(files), digest({path: digest(raw) for path, raw in files.items()})


def verify_vault_native(repo, name, log, pipeline_tests=None):
    if repo != 'PRO-Robotech/vault-operator' or name not in (
            'test-e2e.yml:load', 'test-e2e.yml:test-e2e-pipeline'):
        return
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    log = '\n'.join(re.sub(r'^\d{4}-\d\d-\d\dT\S+ ', '', line) for line in log.splitlines())
    if name.endswith(':test-e2e-pipeline'):
        require(isinstance(pipeline_tests, set) and VAULT_PIPELINE_TESTS <= pipeline_tests,
                'source-bound pipeline inventory required')
        required = pipeline_tests
    else:
        required = {'TestLoadThousandClaimsE2E'}
    selected = Counter(re.findall(r'^=== RUN\s+(\S+)$', log, re.M))
    require(selected == Counter({test: 1 for test in required}), 'Vault native test inventory differs')
    census(log, 'go-v1')
    if name.endswith(':test-e2e-pipeline'):
        return
    ready = re.findall(r'1000 claims Ready in ([0-9hms.]+)', log)
    require(len(ready) == 1, 'load readiness census missing/duplicated')
    duration = re.fullmatch(r'(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?', ready[0])
    require(duration is not None and any(duration.groups()), 'unknown readiness duration')
    seconds = sum(float(value or 0) * scale for value, scale in zip(duration.groups(), (3600, 60, 1)))
    require(seconds <= 600, 'load readiness deadline exceeded')
    rows = re.findall(r'window ([0-9hms.]+): ([0-9.]+) passes \(([0-9.]+) per claim, limit ([0-9.]+)\), '
                      r'([0-9.]+) Vault calls \(([0-9.]+) per claim\), (-?[0-9]+) new tokens, RSS ([0-9]+) MiB', log)
    require(len(rows) == 1, 'load measurement missing/duplicated')
    window, passes, per_claim, limit, calls, calls_per_claim, tokens, rss = rows[0]
    require(window == '10m0s' and float(limit) == 1.2 and float(per_claim) <= 1.2 and
            int(tokens) == 0 and int(rss) <= 256, 'load steady-window bounds differ/failed')
    elapsed = re.findall(r'^--- PASS: TestLoadThousandClaimsE2E \(([0-9.]+)s\)$', log, re.M)
    require(len(elapsed) == 1 and float(elapsed[0]) >= 600, 'load test duration is below the steady window')


def hosted(expected, name):
    repo, head = expected['repo'], expected['head']
    wf, key = name.split(':')
    target = expected['definitions'][name]
    contents = api(repo, 'contents/.github/workflows/' + quote(wf) + '?' + urlencode({'ref': head}))
    raw = base64.b64decode(contents['content'])
    require(digest(raw) == target['workflow_digest'], 'workflow at source differs from expected')
    require(digest(definition(load_workflow(raw), key)) == target['definition_digest'], 'job definition differs')
    commit = api(repo, 'git/commits/' + head)
    require(commit['tree']['sha'] == expected['tree'], 'source tree differs')
    runs = pages(repo, 'actions/workflows/' + quote(wf) + '/runs?' +
                 urlencode({'event': 'push', 'head_sha': head, 'branch': expected['ref'][11:]}), 'workflow_runs')
    candidates = [r for r in runs if r.get('head_sha') == head and r.get('event') == 'push'
                  and r.get('head_branch') == expected['ref'][11:]]
    require(candidates, 'no eligible push run for ' + name)
    run = max(candidates, key=lambda r: (r['run_number'], r['id']))
    require(run.get('path') == '.github/workflows/' + wf and
            run.get('repository', {}).get('full_name') == repo, 'run workflow/repository mismatch')
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'latest workflow run is not completed/success')
    attempt = run['run_attempt']
    jobs = pages(repo, f"actions/runs/{run['id']}/attempts/{attempt}/jobs", 'jobs')
    selected = [j for j in jobs if j.get('name') == target['name']]
    require(len(selected) == 1, 'missing/duplicate expected hosted job')
    job = selected[0]
    require(job.get('head_sha') == head and job.get('run_attempt') == attempt and
            job.get('run_id') == run['id'], 'job source/run/attempt mismatch')
    require(job.get('status') == 'completed' and job.get('conclusion') == 'success', 'hosted job is not green')
    verify_image_builds(repo, name, target, job)
    verify_vault_runtime(repo, name, target, job)
    require(job.get('runner_group_name') == 'GitHub Actions' and
            'self-hosted' not in job.get('labels', []), 'runner is not GitHub hosted')
    check_url = job.get('check_run_url', '')
    prefix = 'https://api.github.com/repos/' + repo + '/check-runs/'
    require(check_url.startswith(prefix), 'job check-run association missing')
    check = api(repo, 'check-runs/' + check_url[len(prefix):])
    require(check.get('head_sha') == head and check.get('status') == 'completed' and
            check.get('conclusion') == 'success', 'check-run aggregation is not green')
    log = api(repo, f"actions/jobs/{job['id']}/logs", raw=True)
    native = source_markers(log, expected, key, run['id'], attempt)
    count = census(native, target['parser'])
    pipeline_tests, source_digest = None, None
    if repo == 'PRO-Robotech/vault-operator' and name == 'test-e2e.yml:test-e2e-pipeline':
        pipeline_tests, source_digest = vault_pipeline_source(repo, head)
    verify_vault_native(repo, name, native, pipeline_tests)
    return {'executor': 'github-hosted', 'run_id': run['id'], 'run_attempt': attempt,
            'job_id': job['id'], 'cases': count, 'log_digest': digest(log.encode()),
            **({'native_source_digest': source_digest} if source_digest else {})}


def registry():
    # Архив scripts не является checkout. Канонический launcher передаёт его
    # исходный workspace; это привязка репозитория, не произвольный путь реестра.
    explicit = 'LANDING_PRECHECK_WS' in os.environ
    source = os.environ['LANDING_PRECHECK_WS'] if explicit else str(Path(__file__).parent)
    require(bool(source), 'workspace binding is empty')
    path = Path(source).resolve()
    require(path.is_dir(), 'workspace binding is not a directory')
    root = Path(git(str(path), 'rev-parse', '--show-toplevel')).resolve()
    require(not explicit or path == root, 'workspace binding is not the repository root')
    origin = git(str(root), 'remote', 'get-url', 'origin')
    require(origin in {
        'git@github.com:PRO-Robotech/kacho-workspace.git',
        'https://github.com/PRO-Robotech/kacho-workspace.git',
        'https://github.com/PRO-Robotech/kacho-workspace',
    }, 'workspace repository differs')
    common = git(str(root), 'rev-parse', '--path-format=absolute', '--git-common-dir')
    return Path(common).parent / 'tmp/operator-stand-registry'


def read_json(path):
    return json.loads(Path(path).read_text())


def save_new(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as stream:
        json.dump(data, stream, sort_keys=True, indent=2)
        stream.write('\n')


def canonical_argv(script):
    """The only admitted transport: exact bytes in the existing make route."""
    require(isinstance(script, bytes) and script and b'\x00' not in script, 'invalid script bytes')
    payload = base64.b64encode(script).decode('ascii')
    return ['make', '--eval', 'operator-evidence:; @printf %s ' + payload +
            ' | base64 -d | bash', 'operator-evidence']


def command_script(argv):
    require(isinstance(argv, list) and len(argv) == 4 and
            argv[:2] == ['make', '--eval'] and argv[3] == 'operator-evidence',
            'command is outside the closed operator transport')
    match = re.fullmatch(r'operator-evidence:; @printf %s ([A-Za-z0-9+/]+={0,2}) \| base64 -d \| bash', argv[2])
    require(match is not None, 'command wrapper or encoding differs')
    script = base64.b64decode(match[1], validate=True)
    require(canonical_argv(script) == argv, 'noncanonical command encoding')
    return script


def candidate_definition(exp, script, argv_file, pins_file):
    """Capture an independently reviewed command definition before execution.

    This local registry trusts the same user, like the existing validation cache;
    it is not cryptographic attestation against a malicious same-user process.
    Reviews bind the complete definition, not just an informal group label.
    """
    jobs = {name: item['definition_digest'] for name, item in exp['definitions'].items()
            if item['executor'] == 'cluster-job'}
    argv, pins = read_json(argv_file), read_json(pins_file)
    require(isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv), 'invalid command argv')
    require(isinstance(pins, dict) and pins, 'missing tool pins')
    require(command_script(argv) == Path(script).read_bytes(), 'executed payload differs from reviewed script')
    definition = {'head': exp['head'], 'tree': exp['tree'], 'repo': exp['repo'], 'jobs': jobs,
                  'script_digest': digest(Path(script).read_bytes()), 'argv': argv,
                  'command_digest': digest(argv), 'tools': pins,
                  'runner_digest': digest((Path(__file__).parent / 'remote-heavy/run.sh').read_bytes())}
    return definition


def register(exp, script, argv_file, pins_file, review_file):
    definition = candidate_definition(exp, script, argv_file, pins_file)
    identity = digest(definition)
    review = read_json(review_file)
    require(review.get('role') == 'check-verifier' and review.get('verdict') == 'accept' and
            review.get('definition_digest') == identity and review.get('blocking') == [],
            'independent review must accept this exact command/workflow/pin definition')
    save_new(registry() / 'definitions' / (identity + '.json'), {'definition': definition, 'review': review})
    return identity


def get_definition(identity):
    require(re.fullmatch('[0-9a-f]{64}', identity) is not None, 'invalid registered definition ID')
    record = read_json(registry() / 'definitions' / (identity + '.json'))
    require(digest(record['definition']) == identity, 'registered definition changed')
    require(record['review'].get('definition_digest') == identity and
            record['review'].get('verdict') == 'accept' and record['review'].get('blocking') == [],
            'registered command review is missing')
    definition = record['definition']
    require(record['review'].get('role') == 'check-verifier', 'registered reviewer role differs')
    require(definition['command_digest'] == digest(definition['argv']) and
            definition['script_digest'] == digest(command_script(definition['argv'])),
            'registered executed payload differs')
    return definition


def cluster(exp, name, identity, uid):
    definition = get_definition(identity)
    require(re.fullmatch('[0-9a-f-]{36}', uid) is not None, 'invalid Job UID')
    receipt = read_json(registry() / 'receipts' / (uid + '.json'))
    require(receipt['definition_id'] == identity, 'receipt belongs to another definition')
    require((definition['repo'], definition['head'], definition['tree']) ==
            (exp['repo'], exp['head'], exp['tree']), 'cluster source differs')
    require(definition['jobs'].get(name) == exp['definitions'][name]['definition_digest'],
            'cluster check definition differs')
    require(receipt['runner_digest'] == definition['runner_digest'], 'runner changed since registration')
    job, pod, namespace = receipt['job'], receipt['pod'], receipt['namespace']
    require(job['metadata']['uid'] == uid, 'Job identity differs')
    require(namespace['metadata']['name'] == job['metadata']['namespace'] == pod['metadata']['namespace'],
            'namespace association differs')
    require(any(owner.get('uid') == uid and owner.get('kind') == 'Job'
                for owner in pod['metadata'].get('ownerReferences', [])), 'pod owner differs')
    require(pod['spec'].get('hostUsers') is False and
            job['spec']['template']['spec'].get('hostUsers') is False, 'admitted userns differs')
    containers = [c for c in pod['spec']['containers'] if c['name'] == 'run']
    require(len(containers) == 1, 'missing run container')
    # remote-heavy's fixed prefix is bash -c PREP run; kubelet doubles dollars.
    actual = [arg.replace('$$', '$') for arg in containers[0]['command'][4:]]
    require(actual == definition['argv'] and digest(actual) == definition['command_digest'],
            'admitted command differs from reviewed command')
    statuses = [s for s in pod['status']['containerStatuses'] if s['name'] == 'run']
    require(len(statuses) == 1 and statuses[0]['state'].get('terminated', {}).get('exitCode') == 0,
            'run container did not terminate successfully')
    require('@sha256:' in statuses[0].get('imageID', ''), 'resolved container image missing')
    require(receipt['cleanup'] == {'namespace_uid': namespace['metadata']['uid'], 'absent': True},
            'cleanup was not captured by producer')
    text = receipt['log']
    require(digest(text.encode()) == receipt['log_digest'], 'retained log differs')
    boundaries = re.findall(r'^REMOTE_SOURCE_V1 (before|after) ([0-9a-f]{40}) ([0-9a-f]{40}) (clean|dirty)$', text, re.M)
    require(boundaries == [('before', exp['head'], exp['tree'], 'clean'),
                           ('after', exp['head'], exp['tree'], 'clean')], 'missing/dirty source boundaries')
    before = text.index('REMOTE_SOURCE_V1 before ')
    after = text.index('REMOTE_SOURCE_V1 after ')
    group_positions = [m.start() for m in re.finditer(r'^OPERATOR_GROUP_V1 ', text, re.M)]
    require(group_positions and before < min(group_positions) and after > max(group_positions),
            'source boundaries do not enclose every group')
    active, chunks, seen = None, {}, set()
    for line in text.splitlines():
        if line.startswith('OPERATOR_GROUP_V1 '):
            record = json.loads(line[len('OPERATOR_GROUP_V1 '):])
            group = record.get('job')
            require(group in definition['jobs'], 'unregistered cluster group')
            if record.get('phase') == 'begin':
                require(active is None and group not in seen, 'overlapping/duplicate group')
                active, chunks[group] = group, []
                seen.add(group)
            else:
                require(record.get('phase') == 'end' and active == group and
                        type(record.get('rc')) is int and record['rc'] == 0, 'group incomplete/failed')
                active = None
        elif active:
            chunks[active].append(line)
    require(active is None and seen == set(definition['jobs']), 'cluster census does not cover all registered jobs')
    count = census('\n'.join(chunks[name]), exp['definitions'][name]['parser'])
    return {'executor': 'cluster-job', 'job_uid': uid, 'cases': count,
            'definition_id': identity, 'log_digest': receipt['log_digest']}


def validate_expected(exp, head, repo=None, base=None):
    native = exp.get('forge') is not None
    if native:
        gitlab_helper().descriptor(exp['forge'], require)
        require(exp.get('operator_kind') == 'registry-operator' and exp.get('repo') == exp['forge']['path'], 'native operator identity differs')
    require(exp.get('schema') == 'operator-stand-v1' and (native or exp.get('repo') in INVENTORY), 'invalid operator expectation')
    require(exp.get('head') == head, 'expected source differs')
    require(not repo or exp['repo'] == repo, 'repository differs')
    require(not base or exp['base'] == base, 'base differs')
    inventory = (gitlab_helper().inventory(INVENTORY['PRO-Robotech/registry-operator']) if native else INVENTORY[exp['repo']])
    require(exp.get('jobs') == list(inventory) and exp.get('ledger') == list(inventory) and
            set(exp.get('definitions', {})) == set(inventory), 'expected inventory differs')
    require(exp.get('full') is True and exp.get('source') == 'operator-full', 'operator selection must be full')
    for name, (executor, parser) in inventory.items():
        target = exp['definitions'][name]
        require(target.get('executor') == executor and target.get('parser') == parser,
                'executor/census applicability differs')
        require(digest(target['definition']) == target['definition_digest'], 'expected definition is malformed')


def capture(identity, job_file, pod_file, namespace_file, log_file):
    definition = get_definition(identity)
    runner_digest = digest((Path(__file__).parent / 'remote-heavy/run.sh').read_bytes())
    require(runner_digest == definition['runner_digest'], 'capture runner differs from reviewed runner')
    job, pod, namespace = map(read_json, (job_file, pod_file, namespace_file))
    uid = job['metadata']['uid']
    require(re.fullmatch('[0-9a-f-]{36}', uid) is not None, 'invalid captured Job UID')
    # Never retain env values or API managed-fields/annotations that can contain credentials.
    def metadata(value):
        return {key: value[key] for key in ('name', 'namespace', 'uid', 'ownerReferences') if key in value}
    def spec(value):
        containers = [{key: c[key] for key in ('name', 'image', 'command', 'securityContext') if key in c}
                      for c in value['containers']]
        return {'hostUsers': value.get('hostUsers'), 'securityContext': value.get('securityContext'),
                'containers': containers}
    raw_log = Path(log_file).read_text()
    record = {'definition_id': identity, 'runner_digest': runner_digest,
              'job': {'metadata': metadata(job['metadata']),
                      'spec': {'template': {'spec': spec(job['spec']['template']['spec'])}}},
              'pod': {'metadata': metadata(pod['metadata']), 'spec': spec(pod['spec']),
                      'status': {'containerStatuses': pod['status'].get('containerStatuses', [])}},
              'namespace': {'metadata': metadata(namespace['metadata'])},
              'log': raw_log, 'log_digest': digest(raw_log.encode()), 'cleanup': None}
    save_new(registry() / 'receipts' / (uid + '.pending'), record)
    return uid


def complete(uid, namespace_uid):
    require(re.fullmatch('[0-9a-f-]{36}', uid) is not None, 'invalid completion UID')
    path = registry() / 'receipts' / (uid + '.pending')
    record = read_json(path)
    require(record['namespace']['metadata']['uid'] == namespace_uid, 'deleted namespace identity differs')
    record['cleanup'] = {'namespace_uid': namespace_uid, 'absent': True}
    save_new(path.with_suffix('.json'), record)
    path.unlink()


def check(exp, report, head, repo=None, base=None, cluster_only=False):
    validate_expected(exp, head, repo, base)
    require(report.get('head') == head and report.get('mode') == ('cluster' if cluster_only else 'full'),
            'report source/mode differs')
    wanted = [name for name in exp['jobs'] if not cluster_only or
              exp['definitions'][name]['executor'] == 'cluster-job']
    suites = report.get('suites')
    require(isinstance(suites, list) and len(suites) == len(wanted), 'report is truncated')
    require(len({s.get('job') for s in suites}) == len(suites) and
            {s.get('job') for s in suites} == set(wanted), 'missing/duplicate/unexpected jobs')
    results = {}
    for suite in suites:
        name = suite['job']
        require('carried_from' not in suite, 'operator evidence cannot be carried')
        executor = exp['definitions'][name]['executor']
        require(suite.get('executor') == executor, 'wrong executor for ' + name)
        if executor == 'gitlab-job':
            results[name] = gitlab_helper().job_evidence(exp, name, census, require)
        elif executor == 'github-hosted':
            results[name] = hosted(exp, name)
        else:
            results[name] = cluster(exp, name, suite.get('definition_id', ''), suite.get('job_uid', ''))
    return results


def main(args):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    expect = sub.add_parser('expect')
    for flag in ('checkout', 'head', 'base'):
        expect.add_argument('--' + flag, required=True)
    expect.add_argument('--source-ref')
    expect.add_argument('--push-before')
    expect.add_argument('--draft')
    expect.add_argument('--forge', help='trusted native forge descriptor JSON')
    verify = sub.add_parser('check')
    verify.add_argument('report')
    for flag in ('head', 'expect'):
        verify.add_argument('--' + flag, required=True)
    verify.add_argument('--pr-base')
    verify.add_argument('--pr-repo')
    cluster_verify = sub.add_parser('cluster-check')
    cluster_verify.add_argument('report')
    cluster_verify.add_argument('--head', required=True)
    cluster_verify.add_argument('--expect', required=True)
    argv = sub.add_parser('argv')
    argv.add_argument('--script', required=True)
    candidate = sub.add_parser('definition')
    for flag in ('expect', 'script', 'argv', 'pins'):
        candidate.add_argument('--' + flag, required=True)
    enroll = sub.add_parser('register')
    for flag in ('expect', 'script', 'argv', 'pins', 'review'):
        enroll.add_argument('--' + flag, required=True)
    authorize = sub.add_parser('authorize')
    for flag in ('definition', 'head', 'argv'):
        authorize.add_argument('--' + flag, required=True)
    collect = sub.add_parser('capture')
    for flag in ('definition', 'job', 'pod', 'namespace', 'log'):
        collect.add_argument('--' + flag, required=True)
    completed = sub.add_parser('complete')
    completed.add_argument('--uid', required=True)
    completed.add_argument('--namespace-uid', required=True)
    opts = parser.parse_args(args)
    if opts.action == 'expect':
        ref = opts.source_ref or git(opts.checkout, 'symbolic-ref', 'HEAD')
        print(json.dumps(expected(opts.checkout, opts.head, opts.base, ref, opts.push_before, read_json(opts.forge) if opts.forge else None), indent=2))
    elif opts.action == 'argv':
        print(json.dumps(canonical_argv(Path(opts.script).read_bytes())))
    elif opts.action == 'definition':
        definition = candidate_definition(read_json(opts.expect), opts.script, opts.argv, opts.pins)
        print(json.dumps({'definition': definition, 'definition_digest': digest(definition)}, indent=2))
    elif opts.action == 'register':
        print(register(read_json(opts.expect), opts.script, opts.argv, opts.pins, opts.review))
    elif opts.action == 'authorize':
        definition = get_definition(opts.definition)
        require(definition['head'] == opts.head and definition['argv'] == read_json(opts.argv),
                'invocation is not the reviewed source/command')
        require(definition['runner_digest'] == digest((Path(__file__).parent / 'remote-heavy/run.sh').read_bytes()),
                'runner changed since review')
    elif opts.action == 'capture':
        print(capture(opts.definition, opts.job, opts.pod, opts.namespace, opts.log))
    elif opts.action == 'complete':
        complete(opts.uid, opts.namespace_uid)
    else:
        only_cluster = opts.action == 'cluster-check'
        results = check(read_json(opts.expect), read_json(opts.report), opts.head,
                        getattr(opts, 'pr_repo', None), getattr(opts, 'pr_base', None), only_cluster)
        for job, evidence in results.items():
            print('CENSUS\t' + job + '\t' + json.dumps(evidence, sort_keys=True))
        print('VERDICT\t' + ('cluster-ready (hosted outstanding)' if only_cluster else 'green') + '\tкод 0')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (Unread, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('VOID\t' + str(error))
        print('VERDICT\tunread\tкод 2')
        sys.exit(2)
