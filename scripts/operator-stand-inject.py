#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""One-fact negative experiments over captured operator producers.

Run through heavy-slot in the external cluster. This file does not authorize a
product run; API fixtures intentionally avoid network and exercise the reader.
"""
import base64
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
        cls.co = Path(cls.temp.name)
        subprocess.run(['git', 'init', '-q', str(cls.co)], check=True)
        (cls.co / 'source.txt').write_text('actual producer fixture\n')
        subprocess.run(['git', '-C', str(cls.co), 'add', 'source.txt'], check=True)
        subprocess.run(['git', '-C', str(cls.co), '-c', 'user.name=Fixture', '-c',
                        'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        cls.head = M.git(str(cls.co), 'rev-parse', 'HEAD')
        cls.tree = M.git(str(cls.co), 'rev-parse', 'HEAD^{tree}')
        cls.job = json.loads((FIX / 'iam-job.json').read_text())
        cls.run = json.loads((FIX / 'iam-run.json').read_text())
        cls.check_run = json.loads((FIX / 'iam-check.json').read_text())
        cls.env = dict(os.environ, GITHUB_SHA=cls.head, GITHUB_RUN_ID=str(cls.run['id']),
                       GITHUB_RUN_ATTEMPT=str(cls.run['run_attempt']), GITHUB_JOB='integration')
        cls.before = cls.produce('before')
        cls.after = cls.produce('after')
        cls.native = (FIX / 'iam-go.log').read_text()
        cls.workflow = (FIX / 'iam-integration.yml').read_bytes()
        definition = M.definition(M.load_workflow(cls.workflow), 'integration')
        cls.exp = {'repo': 'PRO-Robotech/kaname-iam-operator', 'head': cls.head, 'tree': cls.tree,
                   'ref': 'refs/heads/' + cls.run['head_branch'], 'definitions': {
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
        run, job, check = map(copy.deepcopy, (self.run, self.job, self.check_run))
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

    def test_api_error_negative(self):
        with patch.object(M, 'api', side_effect=M.Unread('HTTP403')):
            with self.assertRaises(M.Unread):
                M.hosted(self.exp, 'integration.yml:integration')


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
