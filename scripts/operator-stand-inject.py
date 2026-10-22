#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""One-fact negative experiments over captured operator producers.

Run through heavy-slot in the external cluster. This file does not authorize a
product run; API fixtures intentionally avoid network and exercise the reader.
"""
import base64
from collections import Counter
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
FIX = HERE / 'operator-stand-fixtures'
SPEC = importlib.util.spec_from_file_location('operator_stand', HERE / 'operator-stand.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class ProducerExperiments(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.co = Path(cls.temp.name) / 'checkout'
        subprocess.run(['git', 'init', '-q', str(cls.co)], check=True)
        (cls.co / 'source.txt').write_text('actual producer fixture\n')
        subprocess.run(['git', '-C', str(cls.co), 'add', 'source.txt'], check=True)
        subprocess.run(['bash', '-c',
                        'source "$1"; sandbox_git_home "$2" && '
                        'sandbox_git -C "$3" commit -qm fixture', 'fixture',
                        str(HERE / 'lib/sandbox-git-home.sh'),
                        str(Path(cls.temp.name) / 'git-home'), str(cls.co)], check=True)
        cls.head = M.git(str(cls.co), 'rev-parse', 'HEAD')
        cls.tree = M.git(str(cls.co), 'rev-parse', 'HEAD^{tree}')
        cls.job = json.loads((FIX / 'iam-job.json').read_text())
        cls.api_run = json.loads((FIX / 'iam-run.json').read_text())
        cls.check_run = json.loads((FIX / 'iam-check.json').read_text())
        cls.env = dict(os.environ, GITHUB_SHA=cls.head, GITHUB_RUN_ID=str(cls.api_run['id']),
                       GITHUB_RUN_ATTEMPT=str(cls.api_run['run_attempt']), GITHUB_JOB='integration')
        cls.before = cls.produce('before')
        cls.after = cls.produce('after')
        cls.native = (FIX / 'iam-go.log').read_text()
        cls.workflow = (FIX / 'iam-integration.yml').read_bytes()
        definition = M.definition(M.load_workflow(cls.workflow), 'integration')
        cls.exp = {'repo': 'PRO-Robotech/kaname-iam-operator', 'head': cls.head, 'tree': cls.tree,
                   'ref': 'refs/heads/' + cls.api_run['head_branch'], 'definitions': {
                       'integration.yml:integration': {'definition': definition,
                           'definition_digest': M.digest(definition),
                           'workflow_digest': M.digest(cls.workflow), 'name': cls.job['name'],
                           'parser': 'go-v1', 'executor': 'github-hosted'}}}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @classmethod
    def produce(cls, phase, env=None):
        return subprocess.check_output(['python3', '-I', str(FIX / 'source-step.py'), phase],
                                       cwd=cls.co, env=env or cls.env, text=True)

    def state(self):
        run, job, check = map(copy.deepcopy, (self.api_run, self.job, self.check_run))
        for item in (run, job, check):
            item['head_sha'] = self.head
        return {'runs': [run], 'jobs': [job], 'check': check,
                'log': self.before + self.native + self.after}

    def invoke(self, state):
        fetched = []
        def api(repo, endpoint, raw=False):
            fetched.append(endpoint)
            if endpoint.startswith('contents/'):
                return {'content': base64.b64encode(self.workflow).decode()}
            if endpoint.startswith('git/commits/'):
                return {'tree': {'sha': self.tree}}
            if endpoint.startswith('check-runs/'):
                return state['check']
            if endpoint.endswith('/logs'):
                return state['log']
            raise AssertionError(endpoint)
        def pages(repo, endpoint, key):
            fetched.append(endpoint)
            return state['runs' if key == 'workflow_runs' else 'jobs']
        with patch.object(M, 'api', api), patch.object(M, 'pages', pages):
            result = M.hosted(self.exp, 'integration.yml:integration')
        self.assertTrue(any('check-runs/' in item for item in fetched))
        self.assertTrue(any(item.endswith('/logs') for item in fetched))
        return result

    def test_actual_source_producer_and_captured_api_shape_positive(self):
        self.assertEqual(self.invoke(self.state())['cases'], 5)

    def test_source_producer_rejects_tracked_dirty(self):
        source = self.co / 'source.txt'
        old = source.read_text()
        try:
            source.write_text('dirty\n')
            result = subprocess.run(['python3', '-I', str(FIX / 'source-step.py'), 'after'],
                                    cwd=self.co, env=self.env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(b'OPERATOR_SOURCE_V1', result.stdout)
        finally:
            source.write_text(old)

    def test_source_producer_ignores_pythonoptimize(self):
        env = dict(self.env, PYTHONOPTIMIZE='2', GITHUB_SHA='0' * 40)
        result = subprocess.run(['python3', '-I', str(FIX / 'source-step.py'), 'before'],
                                cwd=self.co, env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_go_complete_repeated_invocation_positive(self):
        self.assertEqual(M.census(self.native * 2, 'go-v1'), 10)

    def test_go_truncated_repeated_invocation_negative(self):
        with self.assertRaises(M.Unread):
            M.census(self.native + self.native.splitlines()[0] + '\n', 'go-v1')

    def test_go_skipped_negative(self):
        with self.assertRaises(M.Unread):
            M.census(self.native.replace('--- PASS:', '--- SKIP:', 1), 'go-v1')

    def test_go_empty_negative(self):
        with self.assertRaises(M.Unread):
            M.census('ok package [no test files]\n', 'go-v1')

    def test_ginkgo_captured_positive(self):
        self.assertEqual(M.census((FIX / 'vault-ginkgo.log').read_text(), 'ginkgo-v2'), 5)

    def test_ginkgo_skip_negative(self):
        with self.assertRaises(M.Unread):
            M.census('Ran 4 of 5 Specs in 1.0 seconds\nSUCCESS! -- 4 Passed | 0 Failed | 0 Pending | 1 Skipped\n', 'ginkgo-v2')

    def test_unknown_parser_negative(self):
        with self.assertRaises(M.Unread):
            M.census('all good', 'unknown')

    def test_current_push_job_condition_positive(self):
        doc = M.load_workflow(self.workflow)
        doc['jobs']['integration']['if'] = "github.event_name == 'push'"
        M.definition(doc, 'integration')

    def test_matrix_negative(self):
        doc = M.load_workflow(self.workflow)
        doc['jobs']['integration']['strategy'] = {'matrix': {'os': ['ubuntu-latest']}}
        with self.assertRaises(M.Unread):
            M.definition(doc, 'integration')

    def test_overridden_checkout_negative(self):
        doc = M.load_workflow(self.workflow)
        doc['jobs']['integration']['steps'][0]['with'] = {'ref': 'main'}
        with self.assertRaises(M.Unread):
            M.definition(doc, 'integration')

    def test_unknown_condition_negative(self):
        doc = M.load_workflow(self.workflow)
        doc['jobs']['integration']['if'] = 'false'
        with self.assertRaises(M.Unread):
            M.definition(doc, 'integration')

    def test_path_filter_positive_and_nontrigger_negative(self):
        doc = {'on': {'push': {'branches': ['**'], 'paths': ['charts/**']}}}
        M.eligibility(doc, '8-assembly', ['charts/values.yaml'])
        with self.assertRaises(M.Unread):
            M.eligibility(doc, '8-assembly', ['internal/controller.go'])

    def test_unknown_filter_expression_negative(self):
        with self.assertRaises(M.Unread):
            M.eligibility({'on': {'push': {'paths': ['${{ inputs.path }}']}}}, 'main', ['x'])

    def test_paginated_job_not_lost(self):
        batches = [{'jobs': [{}] * 100, 'total_count': 101}, {'jobs': [{}], 'total_count': 101}]
        with patch.object(M, 'api', side_effect=batches):
            self.assertEqual(len(M.pages('org/repo', 'endpoint', 'jobs')), 101)

    def test_paginated_truncation_negative(self):
        with patch.object(M, 'api', return_value={'jobs': [], 'total_count': 1}):
            with self.assertRaises(M.Unread):
                M.pages('org/repo', 'endpoint', 'jobs')

    def test_api_raw_escape_boundary(self):
        raw = (FIX / 'vault-ginkgo.log').read_text()
        def gh(argv, cwd=None):
            if argv[-1].endswith('/logs'):
                M.require('--allow-escape-sequences' in argv, 'gh refused terminal escapes')
                return raw
            self.assertNotIn('--allow-escape-sequences', argv)
            return '{"ok": true}'
        with patch.object(M, 'command', gh):
            self.assertEqual(M.census(M.api('org/repo', 'actions/jobs/1/logs', raw=True), 'ginkgo-v2'), 5)
            self.assertEqual(M.api('org/repo', 'actions/runs/1'), {'ok': True})
            with self.assertRaises(M.Unread): gh(['gh', 'api', 'repos/org/repo/actions/jobs/1/logs'])

    def test_api_error_negative(self):
        with patch.object(M, 'api', side_effect=M.Unread('HTTP403')):
            with self.assertRaises(M.Unread):
                M.hosted(self.exp, 'integration.yml:integration')


class ImageBuildExperiments(unittest.TestCase):
    def test_closed_build_steps(self):
        fixtures = [
            ('kaname-iam-operator', 'docker-build.yml:docker-build-amd64', ['./Dockerfile']),
            ('vault-operator', 'docker-build.yml:docker-build-amd64', ['./Dockerfile', './Dockerfile.vaultsecret', './Dockerfile.bucket']),
            ('registry-operator', 'ci.yml:docker', ['Dockerfile', 'Dockerfile.iam-proxy']),
        ]
        for short, name, files in fixtures:
            repo = 'PRO-Robotech/' + short
            builds = [{'uses': 'docker/build-push-action@v6', 'with': {'file': file}} for file in files]
            target = {'definition': {'job': {'steps': builds}}}
            job = {'steps': [{'name': 'Run docker/build-push-action@v6', 'number': n+2,
                             'status': 'completed', 'conclusion': 'success'} for n in range(len(files))]}
            if short == 'registry-operator':
                captured = json.loads((FIX / 'registry-build-steps.json').read_text())
                M.verify_image_builds(repo, name, target, captured)
                job = {'steps': [step for step in captured['steps'] if step['name'] == 'Run docker/build-push-action@v6']}
            M.verify_image_builds(repo, name, target, job)
            changes = {'missing': lambda j: j['steps'].pop(),
                       'skipped': lambda j: j['steps'][0].update(conclusion='skipped'),
                       'pending': lambda j: j['steps'][0].update(status='in_progress'),
                       'failed': lambda j: j['steps'][0].update(conclusion='failure'),
                       'duplicate': lambda j: j['steps'].append(copy.deepcopy(j['steps'][0]))}
            for change, mutate in changes.items():
                with self.subTest(repo=repo, change=change):
                    M.verify_image_builds(repo, name, target, job)
                    broken = copy.deepcopy(job); mutate(broken)
                    with self.assertRaises(M.Unread): M.verify_image_builds(repo, name, target, broken)
                    print('BUILD_PROBE_V1 ' + json.dumps({'repo':repo,'name':change,'outcome':'rejected','twin':'accepted'}))



class VaultRuntimeExperiments(unittest.TestCase):
    def test_runtime_steps_and_overrides(self):
        repo = 'PRO-Robotech/vault-operator'
        self.assertEqual(Counter(item[0] for item in M.INVENTORY[repo].values()),
                         Counter({'cluster-job': 3, 'github-hosted': 4}))
        for key, label, command in [
            ('test-e2e-pipeline', 'Running pipeline e2e', 'make test-e2e-pipeline'),
            ('load', 'Running the load measurement', 'make test-load'),
        ]:
            name = 'test-e2e.yml:' + key
            target = {'definition': {'env': {}, 'job': {'steps': [
                {'uses': 'actions/checkout@v4', 'with': {'fetch-depth': 0}},
                {'name': label, 'run': command}]}}}
            job = {'steps': [{'name': label, 'number': 4, 'status': 'completed', 'conclusion': 'success'}]}
            changes = {
                'missing': lambda t, j: j['steps'].clear(),
                'skipped': lambda t, j: j['steps'][0].update(conclusion='skipped'),
                'pending': lambda t, j: j['steps'][0].update(status='in_progress'),
                'failed': lambda t, j: j['steps'][0].update(conclusion='failure'),
                'duplicate': lambda t, j: j['steps'].append(copy.deepcopy(j['steps'][0])),
                'command': lambda t, j: t['definition']['job']['steps'][1].update(run=command+' LOAD_WINDOW=1s'),
                'conditional': lambda t, j: t['definition']['job']['steps'][1].update({'if': 'false'}),
                'workflow-env': lambda t, j: t['definition'].update(env={'LOAD_WINDOW': '1s'}),
                'job-env': lambda t, j: t['definition']['job'].update(env={'LOAD_WINDOW': '1s'}),
                'step-env': lambda t, j: t['definition']['job']['steps'][1].update(env={'LOAD_WINDOW': '1s'}),
            }
            if key == 'test-e2e-pipeline':
                changes['shallow'] = lambda t, j: t['definition']['job']['steps'][0]['with'].update({'fetch-depth': 1})
            for change, mutate in changes.items():
                with self.subTest(job=key, change=change):
                    M.verify_vault_runtime(repo, name, target, job)
                    t, j = copy.deepcopy(target), copy.deepcopy(job); mutate(t, j)
                    with self.assertRaises(M.Unread): M.verify_vault_runtime(repo, name, t, j)
                    print('VAULT_RUNTIME_PROBE_V1 ' + json.dumps({'job':key,'name':change,'outcome':'rejected','twin':'accepted'}))

    def test_pipeline_inventory(self):
        repo, name = 'PRO-Robotech/vault-operator', 'test-e2e.yml:test-e2e-pipeline'
        rows = ['=== RUN   ' + test + '\n--- PASS: ' + test + ' (1.00s)\n'
                for test in sorted(M.VAULT_PIPELINE_TESTS)]
        native = ''.join(rows)
        M.verify_vault_native(repo, name, (FIX / 'vault-pipeline-native.log').read_text())
        for index, row in enumerate(rows):
            for change, broken in [('omission', native.replace(row, '')),
                                   ('wrong-name', native.replace(row, row.replace(sorted(M.VAULT_PIPELINE_TESTS)[index], 'TestWrong'))),
                                   ('skip', native.replace(row, row.replace('--- PASS:', '--- SKIP:')))]:
                with self.subTest(case=index, change=change):
                    M.verify_vault_native(repo, name, native)
                    with self.assertRaises(M.Unread): M.verify_vault_native(repo, name, broken)
                    print('VAULT_PIPELINE_PROBE_V1 ' + json.dumps({'case':index,'name':change,'outcome':'rejected','twin':'accepted'}))

    def test_load_measurement(self):
        repo, name = 'PRO-Robotech/vault-operator', 'test-e2e.yml:load'
        native = ('=== RUN   TestLoadThousandClaimsE2E\n'
                  '    load_test.go:183: 1000 claims Ready in 24s\n'
                  '    load_test.go:196: window 10m0s: 1000 passes (1.00 per claim, limit 1.20), '
                  '1000 Vault calls (1.00 per claim), 0 new tokens, RSS 120 MiB\n'
                  '--- PASS: TestLoadThousandClaimsE2E (624.00s)\n')
        M.verify_vault_native(repo, name, (FIX / 'vault-load-native.log').read_text())
        changes = {
            'short-window': native.replace('10m0s', '1s'),
            'ready-seconds': native.replace('Ready in 24s', 'Ready in 601s'),
            'ready-minutes': native.replace('Ready in 24s', 'Ready in 10m1s'),
            'short-elapsed': native.replace('(624.00s)', '(599.00s)'),
            'claims': native.replace('1000 claims Ready', '999 claims Ready'),
            'passes': native.replace('1.00 per claim, limit', '1.30 per claim, limit'),
            'limit': native.replace('limit 1.20', 'limit 3.00'),
            'tokens': native.replace('0 new tokens', '1 new tokens'),
            'rss': native.replace('RSS 120', 'RSS 300'),
            'skip': native.replace('--- PASS:', '--- SKIP:'),
            'missing': '=== RUN   TestLoadThousandClaimsE2E\n--- PASS: TestLoadThousandClaimsE2E (1.00s)\n',
            'duplicate': native + native,
        }
        for change, broken in changes.items():
            with self.subTest(change=change):
                M.census(native, 'go-v1'); M.verify_vault_native(repo, name, native)
                stamped = '\n'.join('2026-10-22T22:00:00.000Z ' + line for line in native.splitlines())
                M.verify_vault_native(repo, name, stamped)
                M.verify_vault_native(repo, name, native.replace('Ready in 24s', 'Ready in 600s'))
                with self.assertRaises(M.Unread): M.verify_vault_native(repo, name, broken)
                print('VAULT_LOAD_PROBE_V1 ' + json.dumps({'name':change,'outcome':'rejected','twin':'accepted'}))


class TransportExperiments(unittest.TestCase):
    def test_exact_transport(self):
        script = b'#!/bin/bash\nprintf "exact newline\\n"\n'
        self.assertEqual(M.command_script(M.canonical_argv(script)), script)

    def test_transport_one_fact_negatives(self):
        script = b'printf test\n'
        argv = M.canonical_argv(script)
        changes = {
            'extra_argument': argv + ['extra'],
            'other_target': argv[:-1] + ['other'],
            'wrapper': argv[:2] + [argv[2].replace('base64 -d', 'base64 --decode')] + argv[3:],
            'encoding_whitespace': argv[:2] + [argv[2].replace(' | base64', '  | base64')] + argv[3:],
            'truncated_payload': argv[:2] + [argv[2].replace(base64.b64encode(script).decode(), 'cA=')] + argv[3:],
            'noncanonical_encoding': M.canonical_argv(b'p'),
        }
        changes['noncanonical_encoding'][2] = changes['noncanonical_encoding'][2].replace('cA==', 'cB==')
        for name, broken in changes.items():
            with self.subTest(name=name):
                self.assertEqual(M.command_script(argv), script)
                with self.assertRaises((M.Unread, ValueError)): M.command_script(broken)
                print('TRANSPORT_PROBE_V1 ' + json.dumps({'name': name, 'outcome': 'rejected', 'twin': 'accepted'}))

    def test_registered_payload_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'runner.sh'; script.write_bytes(b'printf original\n')
            argv = root / 'argv.json'; argv.write_text(json.dumps(M.canonical_argv(script.read_bytes())))
            pins = root / 'pins.json'; pins.write_text('{"helm":"v3.18.4"}')
            exp = {'head': 'a'*40, 'tree': 'b'*40, 'repo': 'PRO-Robotech/kaname-iam-operator',
                   'definitions': {'test.yml:test': {'executor':'cluster-job', 'definition_digest':'c'*64}}}
            definition = M.candidate_definition(exp, script, argv, pins)
            review = root / 'review.json'; review.write_text(json.dumps({'role':'check-verifier',
                'verdict':'accept', 'blocking':[], 'definition_digest': M.digest(definition)}))
            with patch.object(M, 'registry', return_value=root / 'registry'):
                identity = M.register(exp, script, argv, pins, review)
                self.assertEqual(M.get_definition(identity), definition)
                script.write_bytes(b'printf changed\n')
                with self.assertRaises(M.Unread): M.candidate_definition(exp, script, argv, pins)
                definition['script_digest'] = '0'*64
                identity = M.digest(definition)
                M.save_new(root/'registry'/'definitions'/(identity+'.json'), {'definition':definition,
                    'review': {'role':'check-verifier','verdict':'accept','blocking':[], 'definition_digest':identity}})
                with self.assertRaises(M.Unread): M.get_definition(identity)


def negative(name, mutate):
    def experiment(self):
        state = self.state()
        mutate(state)
        with self.assertRaises(M.Unread):
            self.invoke(state)
    experiment.__name__ = 'test_hosted_negative_' + name
    setattr(ProducerExperiments, experiment.__name__, experiment)


for field, value in [('head_sha', '0' * 40), ('event', 'pull_request'),
                     ('head_branch', 'unrelated'), ('path', '.github/workflows/unrelated.yml'),
                     ('status', 'in_progress'), ('conclusion', 'cancelled')]:
    negative('run_' + field, lambda s, k=field, v=value: s['runs'][0].__setitem__(k, v))
for field, value in [('head_sha', '0' * 40), ('run_attempt', 1), ('run_id', 1),
                     ('name', 'other job'), ('status', 'in_progress'), ('conclusion', 'skipped'),
                     ('runner_group_name', 'self-hosted'), ('check_run_url', '')]:
    negative('job_' + field, lambda s, k=field, v=value: s['jobs'][0].__setitem__(k, v))
for field, value in [('status', 'in_progress'), ('conclusion', 'failure'), ('head_sha', '0' * 40)]:
    negative('check_' + field, lambda s, k=field, v=value: s['check'].__setitem__(k, v))
negative('missing_job', lambda s: s.__setitem__('jobs', []))
negative('duplicate_job', lambda s: s['jobs'].append(copy.deepcopy(s['jobs'][0])))
negative('latest_pending_beats_old_green', lambda s: s['runs'].append(
    dict(s['runs'][0], id=s['runs'][0]['id'] + 1, run_number=s['runs'][0]['run_number'] + 1, status='in_progress')))
negative('latest_attempt_beats_old_job', lambda s: s['runs'][0].__setitem__('run_attempt', 3))
negative('missing_source', lambda s: s.__setitem__('log', ProducerExperiments.native))
negative('wrong_source_tree', lambda s: s.__setitem__('log', s['log'].replace(ProducerExperiments.tree, '0' * 40)))
negative('other_attempt_source', lambda s: s.__setitem__('log', s['log'].replace('"run_attempt": 2', '"run_attempt": 1')))
negative('truncated_census', lambda s: s.__setitem__('log', s['log'].replace(ProducerExperiments.native.splitlines()[1] + '\n', '')))


if __name__ == '__main__':
    unittest.main(verbosity=2)
