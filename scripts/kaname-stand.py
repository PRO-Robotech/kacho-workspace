#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Kaname-only staged evidence. Native counters retain their original units."""
import argparse
import base64
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, urlencode

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('operator_evidence', Path(__file__).with_name('operator-stand.py'))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
require = common.require
REPO = 'PRO-Robotech/kaname'
HOSTED = ('e2e-newman.yml:stand', 'e2e-newman.yml:stand-ceremony',
          'e2e-newman.yml:chart-own', 'docker-build.yml:image')


def job_definition(doc, key):
    # Kaname сохраняет собственные changed-job conditions и shard matrix.
    # Условие не объявляется истинным по source: actual job всё равно обязана исполниться.
    job = doc['jobs'][key]
    require(isinstance(job, dict) and 'uses' not in job, 'unexpanded reusable job')
    require(job.get('runs-on') in ('ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04'),
            'unsupported job runner')
    require('strategy' not in job or key == 'integrationshard', 'unexpected matrix job')
    steps = job.get('steps')
    require(isinstance(steps, list) and steps, 'missing job steps')
    require(steps[0].get('uses', '').startswith('actions/checkout@'), 'primary checkout must be first')
    require(not ({'ref', 'repository', 'path', 'sparse-checkout'} & set(steps[0].get('with', {}))),
            'overridden primary checkout')
    return {'job': job, 'env': doc.get('env', {}), 'defaults': doc.get('defaults', {})}


def expected(checkout, head, base, ref):
    """Не исполняет workflow и не подменяет отсутствующий cluster route."""
    co = Path(checkout)
    require(common.git(co, 'rev-parse', 'HEAD') == head, 'checkout differs')
    require(not common.git(co, 'status', '--porcelain', '--untracked-files=all'), 'dirty checkout')
    require(re.fullmatch(r'(?:https://github.com/|git@github.com:)PRO-Robotech/kaname(?:\.git)?',
                         common.git(co, 'remote', 'get-url', 'origin')), 'wrong repository')
    require(ref.startswith('refs/heads/') and len(ref) > 11, 'explicit source branch required')
    workflows = {}
    for filename in ('ci.yml', 'e2e-newman.yml', 'docker-build.yml'):
        raw = (co / '.github/workflows' / filename).read_bytes()
        workflows[filename] = (common.load_workflow(raw), common.digest(raw))
    ci = workflows['ci.yml'][0]
    shards = ci['jobs']['integrationshard']
    matrix = shards.get('strategy', {}).get('matrix', {})
    require(set(matrix) == {'shard'}, 'unreviewed integration matrix axes')
    values = matrix['shard']
    require(isinstance(values, list) and values and all(type(x) is int for x in values)
            and len(values) == len(set(values)), 'invalid shard matrix')
    require('integrationshard' in ci['jobs']['integration'].get('needs', []),
            'integration aggregate lost its producer')
    definitions = {}
    names = [('ci.yml:unit', 'ci.yml:unit', None)]
    names += [(f'ci.yml:integrationshard[shard={v}]', 'ci.yml:integrationshard', i)
              for i, v in enumerate(values)]
    names += [(name, name, None) for name in HOSTED]
    for name, source, index in names:
        filename, key = source.split(':')
        doc, wf_digest = workflows[filename]
        definition = job_definition(doc, key)
        require('uses' not in definition['job'], 'reusable job needs an explicit reviewed expansion')
        definitions[name] = {'workflow_job': source, 'executor': 'github-hosted' if name in HOSTED else 'external',
                             'definition': definition, 'definition_digest': common.digest(definition),
                             'workflow_digest': wf_digest, 'matrix_index': index,
                             'matrix_total': len(values) if index is not None else None}
    return {'schema': 'kaname-stand-v1', 'repo': REPO, 'head': head,
            'tree': common.git(co, 'rev-parse', 'HEAD^{tree}'), 'base': base,
            'base_sha': common.git(co, 'rev-parse', base), 'ref': ref,
            'logical_jobs': ['ci.yml:unit', 'ci.yml:integration', *HOSTED],
            'jobs': list(definitions), 'definitions': definitions,
            'unsupported_external': list(HOSTED), 'full': True}


def groups(text):
    """Читает реальные границы старого производителя, включая красные соседние группы."""
    result, active = {}, None
    for line in text.splitlines():
        if line.startswith('GROUP_BEGIN '):
            name = line.removeprefix('GROUP_BEGIN ')
            require(active is None and name not in result, 'overlapping or duplicate group')
            active = name
            result[name] = []
        elif line.startswith('GROUP_END '):
            match = re.fullmatch(r'GROUP_END (\S+) rc=(\d+)', line)
            require(match and match[1] == active and match[2] == '0', 'failed or mismatched group')
            active = None
        elif active is not None:
            result[active].append(line)
    require(active is None and result, 'truncated or absent group framing')
    return {name: '\n'.join(lines) for name, lines in result.items()}


def go_json(text):
    """Skipped не превращаются в passed; сохраняются имена для проверки applicability."""
    outcomes, started, packages, test_packages, package_started = {}, set(), {}, set(), set()
    for line in text.splitlines():
        if not line.startswith('{'):
            continue
        event = json.loads(line)
        action, package, test = event.get('Action'), event.get('Package'), event.get('Test')
        require(isinstance(package, str) and package, 'missing Go package')
        if not test:
            if action == 'start':
                require(package not in package_started, 'duplicate package start')
                package_started.add(package)
            if action in ('pass', 'fail', 'skip'):
                require(package not in packages, 'duplicate package completion')
                packages[package] = action
            continue
        test_packages.add(package)
        key = package + '/' + test
        if action == 'run':
            require(key not in started, 'duplicate test start')
            started.add(key)
        elif action in ('pass', 'fail', 'skip'):
            require(key in started and key not in outcomes, 'unstarted/duplicate test completion')
            outcomes[key] = action
    require(started and started == set(outcomes), 'incomplete Go test census')
    require(package_started and package_started == set(packages), 'incomplete package census')
    require(packages and all(outcome != 'fail' for outcome in packages.values()), 'failed Go package')
    require(all(outcome != 'fail' for outcome in outcomes.values()), 'failed Go test')
    require(test_packages <= set(packages), 'test package has no completion')
    counts = Counter(outcomes.values())
    require(counts['pass'] > 0, 'no passed tests')
    return {'unit': 'Go test events including subtests', 'passed': counts['pass'],
            'failed': counts['fail'], 'skipped': counts['skip'],
            'skipped_ids': sorted(k for k, value in outcomes.items() if value == 'skip'),
            'packages': len(packages)}


def integration(text, index, total):
    """Обычный go test сообщает пакеты; число отдельных тестов неизвестно."""
    planned = re.findall(r'^исполняется в шарде (\d+): (\d+)$', text, re.M)
    require(len(planned) == 1 and int(planned[0][0]) == index, 'wrong/missing integration shard')
    layout = re.findall(r'^=== РАСКЛАДКА ПО ШАРДАМ \((\d+)\) ===$', text, re.M)
    require(layout == [str(total)], 'wrong shard denominator')
    packages = re.findall(r'^ok\s+(\S+)\s+\d+(?:\.\d+)?s\s*$', text, re.M)
    require(len(packages) == len(set(packages)) == int(planned[0][1]) > 0,
            'missing/duplicate package result')
    require(not re.search(r'^FAIL(?:\s|$)|^\?\s|\(cached\)', text, re.M), 'failed/unexecuted/cached package')
    require(text.count('интеграция: зелёный (код go test 0)') == 1, 'missing native integration verdict')
    return {'unit': 'Go packages', 'passed': len(packages), 'packages': sorted(packages),
            'test_cases': None, 'matrix_index': index, 'matrix_total': total}


def remote_log(text, exp, argv):
    """Imported evidence: исходный журнал, не задним числом произведённый receipt."""
    sources = re.findall(r'^SOURCE ([0-9a-f]{40}) TREE ([0-9a-f]{40})$', text, re.M)
    require(sources == [(exp['head'], exp['tree'])], 'executed source differs')
    header = re.findall(r'^HEAD ([0-9a-f]{40}) class=(\S+) at=\S+ dir=.+$', text, re.M)
    require(len(header) == 1 and header[0][0] == exp['head'], 'transport source differs')
    namespaces = re.findall(r'^remote-heavy: \[([^]]+)\] ns \1 создано:', text, re.M)
    require(len(namespaces) == 1, 'missing/duplicate namespace producer')
    ns = namespaces[0]
    require(text.count(f'remote-heavy: [{ns}] ns {ns} снято') == 1, 'native cleanup is unproven')
    require(len(re.findall(r'^remote-heavy: \[' + re.escape(ns) +
                          r'\] команда завершилась кодом 0 за \d+ с', text, re.M)) == 1,
            'missing successful remote command completion')
    # Bash %q представляет настоящие argv. Разбор выполняет отдельный reviewed importer;
    # здесь принимается лишь исходная строка точного argv, полученная producer capture.
    require(isinstance(argv, str) and argv and text.splitlines().count(argv) == 1,
            'exact executed command line is missing')
    require(argv.startswith(f'remote-heavy: [{ns}] команда начата через '), 'not a producer command line')
    return {'kind': 'imported-native-remote-heavy', 'namespace': ns,
            'source': sources[0], 'log_digest': common.digest(text.encode()),
            'command_line_digest': common.digest(argv.encode()),
            'cleanup_kind': 'runner-observed-namespace-delete-wait', 'groups': groups(text)}


def integration_union(texts, selected_packages):
    """Каждый отобранный пакет должен завершиться ровно в одном реальном шарде."""
    require(isinstance(selected_packages, list) and selected_packages
            and all(isinstance(p, str) and p for p in selected_packages)
            and len(selected_packages) == len(set(selected_packages)), 'invalid selected package inventory')
    require(isinstance(texts, list) and texts, 'missing integration shards')
    results = [integration(raw, index, len(texts)) for index, raw in enumerate(texts)]
    combined = [package for result in results for package in result['packages']]
    require(len(combined) == len(set(combined)), 'package executed in multiple shards')
    require(set(combined) == set(selected_packages), 'selected/executed package union differs')
    for raw in texts:
        selected = re.findall(r'^отобрано\s+: (\d+)\s*$', raw, re.M)
        planned = re.findall(r'^в плане пакетов\s+: (\d+) из (\d+), каждый ровно в одном шарде$', raw, re.M)
        require(selected == [str(len(selected_packages))]
                and planned == [(str(len(selected_packages)), str(len(selected_packages)))],
                'native selected/planned denominator differs')
    return {'unit': 'Go packages', 'passed': len(combined), 'test_cases': None,
            'packages': sorted(combined), 'shards': results}


def import_candidate(exp, packet_file):
    """Исторические факты принимаются отдельным review, не как runtime attestation."""
    packet = common.read_json(packet_file)
    require(packet.get('kind') == 'imported-native-remote-heavy', 'wrong imported provenance kind')
    require(packet.get('head') == exp['head'] and packet.get('tree') == exp['tree'], 'import source differs')
    require(set(packet.get('runs', {})) == {'core', 'platform'}, 'incomplete external run census')
    artifacts, parsed = {}, {}
    for name, run in packet['runs'].items():
        require(set(run) == {'log', 'script', 'command_line', 'runner', 'auxiliary'}, 'unreviewed import shape')
        artifacts[name] = {}
        for label in ('log', 'script', 'runner'):
            raw = Path(run[label]).read_bytes()
            require(raw, 'empty imported artifact')
            artifacts[name][label] = common.digest(raw)
        auxiliary = run['auxiliary']
        require(isinstance(auxiliary, dict), 'missing auxiliary artifact census')
        artifacts[name]['auxiliary'] = {key: common.digest(Path(path).read_bytes())
                                         for key, path in auxiliary.items()}
        parsed[name] = remote_log(Path(run['log']).read_text(), exp, run['command_line'])
        artifacts[name]['command_line'] = run['command_line']
    core, platform = parsed['core']['groups'], parsed['platform']['groups']
    require(set(core) == {'build', 'vet', 'vet-integration', 'unit-verdict-self', 'unit',
                          'unit-verdict', 'listfilter', 'manifest'}, 'core group inventory differs')
    n = len([d for d in exp['definitions'].values() if d['matrix_index'] is not None])
    require(set(platform) == {'platform-tests', 'platform-verdict', 'canon', 'catalog',
                              *(f'integration-{i}' for i in range(n))}, 'platform group inventory differs')
    unit = go_json(core['unit'])
    integration_result = integration_union([platform[f'integration-{i}'] for i in range(n)],
                                            packet['selected_packages'])
    # Review обязан сверить отбор пакетов и applicability short SKIP по исходным
    # producer scripts/workflows. Содержимое audit тоже входит в неизменяемую подпись.
    audit = Path(packet['applicability_audit']).read_bytes()
    require(audit, 'short/integration applicability audit missing')
    return {'kind': packet['kind'], 'repo': exp['repo'], 'head': exp['head'], 'tree': exp['tree'],
            'expected_digest': common.digest(exp), 'artifacts': artifacts,
            'applicability_audit_digest': common.digest(audit),
            'selected_packages': packet['selected_packages'],
            'unit': unit, 'integration': integration_result,
            'cleanup': {name: {'namespace': run['namespace'], 'kind': run['cleanup_kind']}
                        for name, run in parsed.items()}}


def register_import(exp, packet_file, review_file):
    candidate = import_candidate(exp, packet_file)
    identity = common.digest(candidate)
    review = common.read_json(review_file)
    require(review.get('role') == 'check-verifier' and review.get('verdict') == 'accept'
            and review.get('candidate_digest') == identity and review.get('blocking') == [],
            'independent exact imported evidence review missing')
    require(review.get('claims') == ['source-and-command-binding', 'native-verdict-and-cleanup',
                                    'selected-package-partition', 'short-skip-applicability'],
            'import review omits required factual bindings')
    common.save_new(common.registry() / 'kaname-imports' / (identity + '.json'),
                    {'candidate': candidate, 'review': review})
    return identity


def newman_tables(text, waves):
    """Native aggregate_verdict rows; denominators come from reviewed selected waves."""
    require(isinstance(waves, list) and waves and all(isinstance(w, list) and w
            and len(w) == len(set(w)) for w in waves), 'invalid Newman selected waves')
    tables, rows, active = [], [], False
    for line in text.splitlines():
        if re.fullmatch(r'RESOURCE\s+ASSERT\s+FAILED\s+REQUESTS\s+UNANSWERED\s+RC\s+NOTE\s*', line):
            require(not active, 'truncated Newman table')
            active, rows = True, []
        elif active and line.startswith('TOTAL:'):
            total = re.fullmatch(r'TOTAL: (\d+)/(\d+) коллекций отчиталось — (\d+) запрос\(ов\), '
                                 r'(\d+) без ответа, (\d+) утверждени\(й\), (\d+) упавших, '
                                 r'(\d+) немых отчёт\(ов\)', line)
            require(total is not None, 'malformed native Newman total')
            reported, expected_count, requests, unanswered, assertions, failed, silent = map(int, total.groups())
            require(len(tables) < len(waves), 'unexpected Newman wave')
            expected_names = waves[len(tables)]
            require([r['name'] for r in rows] == expected_names, 'Newman selected/executed collections differ')
            require(reported == expected_count == len(rows), 'missing Newman collection')
            require(not (unanswered or failed or silent), 'Newman failed/unanswered/empty collection')
            require(assertions == sum(r['assertions'] for r in rows)
                    and requests == sum(r['requests'] for r in rows), 'Newman native totals differ')
            tables.append({'collections': rows, 'assertions': assertions, 'requests': requests})
            active = False
        elif active:
            row = re.fullmatch(r'(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*', line)
            require(row is not None, 'Newman row failed, missing, or malformed')
            name, assertions, failed, requests, unanswered, rc = row.groups()
            require(int(assertions) > 0 and int(requests) > 0
                    and int(failed) == int(unanswered) == int(rc) == 0,
                    'Newman collection failed/unexecuted')
            rows.append({'name': name, 'assertions': int(assertions), 'requests': int(requests)})
    require(not active and len(tables) == len(waves), 'missing/truncated Newman waves')
    return {'unit': 'Newman assertions', 'passed': sum(t['assertions'] for t in tables),
            'requests': sum(t['requests'] for t in tables), 'waves': tables}


def checkout_source(log, head):
    # Только native command/result actions/checkout, не echoed HEAD_SHA environment.
    lines = [re.sub(r'^\d{4}-\d\d-\d\dT\S+Z ', '', line) for line in log.splitlines()]
    observed = [lines[i + 1] for i, line in enumerate(lines[:-1])
                if re.fullmatch(r'\[command\]/\S*/git log -1 --format=%H', line)]
    require(observed == [head], 'native checkout source differs/missing/duplicated')
    return '\n'.join(lines)


def hosted_capture(exp, name, event):
    require(name in HOSTED and event in ('push', 'workflow_dispatch'), 'unsupported hosted subject/event')
    repo, head = exp['repo'], exp['head']
    filename, key = name.split(':')
    target = exp['definitions'][name]
    content = common.api(repo, 'contents/.github/workflows/' + quote(filename) + '?' + urlencode({'ref': head}))
    raw = base64.b64decode(''.join(content['content'].split()), validate=True)
    require(common.digest(raw) == target['workflow_digest'], 'hosted workflow differs')
    require(common.digest(job_definition(common.load_workflow(raw), key)) == target['definition_digest'],
            'hosted job definition differs')
    require(common.api(repo, 'git/commits/' + head)['tree']['sha'] == exp['tree'], 'hosted source tree differs')
    runs = common.pages(repo, 'actions/workflows/' + quote(filename) + '/runs?' +
                        urlencode({'event': event, 'head_sha': head, 'branch': exp['ref'][11:]}), 'workflow_runs')
    candidates = [r for r in runs if r.get('head_sha') == head and r.get('event') == event
                  and r.get('head_branch') == exp['ref'][11:]]
    require(candidates, 'no eligible hosted run')
    run = max(candidates, key=lambda r: (r['run_number'], r['id']))
    require(run.get('repository', {}).get('full_name') == repo
            and run.get('path') == '.github/workflows/' + filename, 'run source repository/workflow differs')
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success', 'latest hosted run not green')
    attempt = run['run_attempt']
    jobs = common.pages(repo, f"actions/runs/{run['id']}/attempts/{attempt}/jobs", 'jobs')
    selected = [j for j in jobs if j.get('name') == target['definition']['job'].get('name', key)]
    require(len(selected) == 1, 'expected hosted job missing/duplicated')
    job = selected[0]
    require(job.get('run_id') == run['id'] and job.get('run_attempt') == attempt and job.get('head_sha') == head,
            'job source/run/attempt differs')
    require(job.get('status') == 'completed' and job.get('conclusion') == 'success', 'hosted job incomplete/red')
    require(job.get('runner_group_name') == 'GitHub Actions'
            and re.fullmatch(r'GitHub Actions \d+', job.get('runner_name', ''))
            and job.get('labels') == [target['definition']['job']['runs-on']], 'not a known hosted VM')
    steps = job.get('steps', [])
    require(steps and len({s['number'] for s in steps}) == len(steps), 'missing/duplicate API step inventory')
    checkouts = [s for s in steps if s.get('name', '').startswith('Run actions/checkout@')]
    require(len(checkouts) == 1 and checkouts[0].get('conclusion') == 'success', 'primary checkout did not complete')
    log = common.api(repo, f"actions/jobs/{job['id']}/logs", raw=True)
    native = checkout_source(log, head)
    require('##[group]Runner Image Provisioner' in native and '##[group]Operating System' in native,
            'hosted VM setup evidence absent')
    return {'run': run, 'job': job, 'native': native, 'log_digest': common.digest(log.encode()),
            'source': head, 'event': event}


def hosted_verdict(exp, name, captured, cleanup_review):
    """Закрытый reviewed VM-disposal contract дополняет реальные API/native факты."""
    target = exp['definitions'][name]
    require(cleanup_review.get('role') == 'check-verifier' and cleanup_review.get('verdict') == 'accept'
            and cleanup_review.get('blocking') == []
            and cleanup_review.get('expected_digest') == common.digest(exp)
            and cleanup_review.get('job') == name
            and cleanup_review.get('temporary_resources') == 'job-vm-only'
            and cleanup_review.get('transitive_source_review') is True,
            'reviewed transitive hosted cleanup boundary missing')
    job, native = captured['job'], captured['native']
    by_name = {}
    for step in job['steps']:
        by_name.setdefault(step['name'], []).append(step)
    def passed_step(label):
        selected = by_name.get(label, [])
        require(len(selected) == 1 and selected[0].get('status') == 'completed'
                and selected[0].get('conclusion') == 'success', 'required hosted step missing/skipped/red: ' + label)
    if name == 'docker-build.yml:image':
        # Публикация в исходной ветке может быть неприменима. Это только build predicate.
        passed_step('сборка образа')
        passed_step('сверка опубликованного — доказательство инъекцией в обе стороны')
        census = {'unit': 'required image build job', 'passed': 1, 'publication': 'separate-delivery-gate'}
    else:
        waves = []
        for step in target['definition']['job']['steps']:
            run = step.get('run', '')
            if './scripts/run.sh --service ' in run:
                services = re.findall(r'--service ([a-z0-9-]+)(?=\s|$)', run)
                require(services and len(services) == run.count('--service '), 'unsupported service selection')
                require(isinstance(step.get('name'), str), 'test step has no stable name')
                passed_step(step['name'])
                waves.append(services)
            if 'python3 .github/scripts/stand-assert.py ||' in run:
                passed_step(step['name'])
                count = re.findall(r'^перепись: утверждений (\d+) · находок (\d+) · условие не создано у (\d+) проверок$',
                                   native, re.M)
                require(len(count) == 1 and int(count[0][0]) > 0 and count[0][1:] == ('0', '0'),
                        'stand assertions missing/failed/unexecuted')
        census = newman_tables(native, waves)
    return {'executor': 'github-hosted', 'run_id': job['run_id'], 'run_attempt': job['run_attempt'],
            'job_id': job['id'], 'head': exp['head'], 'event': captured['event'],
            'census': census, 'log_digest': captured['log_digest'],
            'cleanup_kind': 'github-hosted-vm-disposal', 'cleanup_review_digest': common.digest(cleanup_review)}


def staged_report(exp, import_id, reviews=None, events=None, external_only=False):
    require(re.fullmatch('[0-9a-f]{64}', import_id) is not None, 'invalid import identity')
    admitted = common.read_json(common.registry() / 'kaname-imports' / (import_id + '.json'))
    candidate = admitted['candidate']
    require(common.digest(candidate) == import_id and candidate['expected_digest'] == common.digest(exp),
            'imported evidence belongs to another expectation/source')
    require(admitted['review'].get('candidate_digest') == import_id
            and admitted['review'].get('verdict') == 'accept' and admitted['review'].get('blocking') == [],
            'stored imported review differs')
    jobs = {'ci.yml:unit': {'executor': 'external', 'census': candidate['unit'], 'import_id': import_id}}
    for name, definition in exp['definitions'].items():
        if definition['matrix_index'] is not None:
            index = definition['matrix_index']
            jobs[name] = {'executor': 'external', 'census': candidate['integration']['shards'][index],
                          'import_id': import_id}
    if not external_only:
        require(isinstance(reviews, dict) and set(reviews) == set(HOSTED)
                and isinstance(events, dict) and set(events) == set(HOSTED), 'incomplete hosted contract inventory')
        for name in HOSTED:
            captured = hosted_capture(exp, name, events[name])
            jobs[name] = hosted_verdict(exp, name, captured, common.read_json(reviews[name]))
    require(set(jobs) == (set(exp['jobs']) - set(HOSTED) if external_only else set(exp['jobs'])),
            'staged report denominator differs')
    return {'schema': 'kaname-staged-report-v1', 'repo': exp['repo'], 'head': exp['head'],
            'tree': exp['tree'], 'base': exp['base'], 'expected_digest': common.digest(exp),
            'stage': 'external-ready' if external_only else 'full-stand',
            'full': not external_only, 'jobs': jobs, 'logical_jobs': exp['logical_jobs'],
            'import_id': import_id, 'hosted_reviews': reviews, 'events': events,
            'mandatory_ci': 'separate-ci-read-required', 'image_publication': 'separate-delivery-gate'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['expect', 'import-candidate', 'register-import', 'report', 'check'])
    parser.add_argument('report_file', nargs='?')
    parser.add_argument('--checkout')
    parser.add_argument('--head')
    parser.add_argument('--base')
    parser.add_argument('--ref')
    parser.add_argument('--expected', '--expect', dest='expected')
    parser.add_argument('--draft', choices=['true', 'false'])
    parser.add_argument('--pr-base')
    parser.add_argument('--pr-repo')
    parser.add_argument('--packet')
    parser.add_argument('--review')
    parser.add_argument('--import-id')
    parser.add_argument('--hosted-reviews')
    parser.add_argument('--events')
    parser.add_argument('--external-only', action='store_true')
    args = parser.parse_args()
    if args.action == 'expect':
        if not args.ref and args.checkout:
            args.ref = common.git(args.checkout, 'symbolic-ref', 'HEAD')
        require(all((args.checkout, args.head, args.base, args.ref)), 'expect requires exact checkout/head/base/ref')
        result = expected(args.checkout, args.head, args.base, args.ref)
    else:
        require(args.expected, 'expected file required')
        exp = common.read_json(args.expected)
        require(exp.get('schema') == 'kaname-stand-v1' and exp.get('repo') == REPO, 'invalid expected scope')
        if args.action == 'import-candidate':
            result = import_candidate(exp, args.packet)
        elif args.action == 'register-import':
            result = {'import_id': register_import(exp, args.packet, args.review)}
        elif args.action == 'report':
            result = staged_report(exp, args.import_id,
                                   common.read_json(args.hosted_reviews) if args.hosted_reviews else None,
                                   common.read_json(args.events) if args.events else None, args.external_only)
        else:
            require(args.head == exp['head'] and (not args.pr_base or args.pr_base == exp['base'])
                    and (not args.pr_repo or args.pr_repo == REPO), 'requested source/base/repository differs')
            previous = common.read_json(args.report_file)
            require(previous.get('full') is (not args.external_only), 'wrong requested evidence stage')
            fresh = staged_report(exp, previous['import_id'], previous['hosted_reviews'], previous['events'],
                                  args.external_only)
            require(previous == fresh, 'saved report differs from latest actual evidence')
            result = {'verdict': 'external-ready' if args.external_only else 'full-stand',
                      'head': args.head, 'executions': len(fresh['jobs'])}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except (common.Unread, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('VOID\t' + str(error))
        sys.exit(2)
