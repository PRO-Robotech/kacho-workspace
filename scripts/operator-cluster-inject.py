#!/usr/bin/env python3
"""External-only reader probes; captured API shape, synthetic successful fixture.

Usage: python3 operator-cluster-probes.py /path/scripts/operator-stand.py shape.json
These fixtures are NOT operator validation evidence. Each negative restores an
accepted positive twin and changes one fact. Real capture()/complete() run.
"""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('stand', sys.argv.pop(1))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)
SHAPE = json.loads(Path(sys.argv.pop(1)).read_text())

class ClusterProbes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.mock = patch.object(M, 'registry', return_value=self.root)
        self.mock.start()
        self.addCleanup(self.mock.stop)
        self.addCleanup(self.tmp.cleanup)
        self.head, self.tree = 'a' * 40, 'b' * 40
        self.name = 'ci.yml:test'
        self.definition = {'repo': 'PRO-Robotech/registry-operator', 'head': self.head,
            'tree': self.tree, 'jobs': {self.name: 'c' * 64},
            'argv': ['bash', '/work/check.sh'], 'command_digest': M.digest(['bash', '/work/check.sh']),
            'runner_digest': M.digest((Path(M.__file__).parent / 'remote-heavy/run.sh').read_bytes())}
        self.identity = M.digest(self.definition)
        M.save_new(self.root / 'definitions' / (self.identity + '.json'),
            {'definition': self.definition, 'review': {'definition_digest': self.identity,
             'verdict': 'accept', 'blocking': [], 'role': 'check-verifier'}})
        self.exp = {'repo': self.definition['repo'], 'head': self.head, 'tree': self.tree,
            'definitions': {self.name: {'definition_digest': 'c' * 64, 'parser': 'go-v1'}}}
        raw = copy.deepcopy(SHAPE)
        self.uid = raw['job']['metadata']['uid']
        self.nsuid = raw['namespace']['metadata']['uid']
        for s in [raw['pod']['spec'], raw['job']['spec']['template']['spec']]:
            for c in s['containers']:
                if c['name'] == 'run': c['command'] = ['bash', '-c', 'PREP', 'run'] + self.definition['argv']
        # Explicit fixture completion, never represented as actual product run.
        raw['pod']['status']['containerStatuses'] = [{'name': 'run',
            'imageID': 'docker-pullable://fixture@sha256:' + 'd' * 64,
            'state': {'terminated': {'exitCode': 0}}}]
        for k, v in raw.items(): (self.root / (k + '.json')).write_text(json.dumps(v))
        self.log = (f'REMOTE_SOURCE_V1 before {self.head} {self.tree} clean\n'
            'OPERATOR_GROUP_V1 {"job":"ci.yml:test","phase":"begin"}\n'
            '=== RUN   TestFixture\n--- PASS: TestFixture (0.00s)\n'
            'OPERATOR_GROUP_V1 {"job":"ci.yml:test","phase":"end","rc":0}\n'
            f'REMOTE_SOURCE_V1 after {self.head} {self.tree} clean\n')
        (self.root / 'log').write_text(self.log)
        M.capture(self.identity, self.root / 'job.json', self.root / 'pod.json',
                  self.root / 'namespace.json', self.root / 'log')
        M.complete(self.uid, self.nsuid)
        self.path = self.root / 'receipts' / (self.uid + '.json')
        self.receipt = json.loads(self.path.read_text())

    def invoke(self, receipt):
        self.path.write_text(json.dumps(receipt))
        return M.cluster(self.exp, self.name, self.identity, self.uid)

    def test_positive_capture_complete(self):
        self.assertEqual(self.invoke(self.receipt)['cases'], 1)

    def test_one_fact_negatives(self):
        mutations = {
            'job_uid': lambda r: r['job']['metadata'].update(uid='0' * 36),
            'owner_uid': lambda r: r['pod']['metadata'].update(ownerReferences=[]),
            'argv': lambda r: next(c for c in r['pod']['spec']['containers'] if c['name']=='run')['command'].append('extra'),
            'runner': lambda r: r.update(runner_digest='0' * 64),
            'pod_userns': lambda r: r['pod']['spec'].update(hostUsers=True),
            'job_userns': lambda r: r['job']['spec']['template']['spec'].update(hostUsers=True),
            'cleanup_absent': lambda r: r.update(cleanup=None),
            'cleanup_uid': lambda r: r['cleanup'].update(namespace_uid='wrong'),
            'exit': lambda r: r['pod']['status']['containerStatuses'][0]['state']['terminated'].update(exitCode=1),
            'image_id': lambda r: r['pod']['status']['containerStatuses'][0].update(imageID='fixture:tag'),
            'log_digest': lambda r: r.update(log_digest='0' * 64),
        }
        logs = {
            'empty_log': '',
            'empty_case_census': self.log.replace('=== RUN   TestFixture\n--- PASS: TestFixture (0.00s)\n', ''),
            'empty_group_census': self.log.splitlines()[0] + '\n' + self.log.splitlines()[-1] + '\n',
            'after_before_groups': self.log.splitlines()[0] + '\n' + self.log.splitlines()[-1] + '\n' + '\n'.join(self.log.splitlines()[1:-1]) + '\n',
            'groups_before_before': '\n'.join(self.log.splitlines()[1:-1]) + '\n' + self.log.splitlines()[0] + '\n' + self.log.splitlines()[-1] + '\n',
            'source': self.log.replace(self.head, 'e' * 40),
            'dirty': self.log.replace(' clean', ' dirty'),
            'truncated': self.log.split('OPERATOR_GROUP_V1 {"job":"ci.yml:test","phase":"end"')[0],
            'duplicate_group': self.log + self.log.splitlines()[1] + '\n',
            'required_skip': self.log.replace('--- PASS:', '--- SKIP:'),
            'incomplete_case': self.log.replace('--- PASS: TestFixture (0.00s)\n', ''),
            'failed_group': self.log.replace('"rc":0', '"rc":1'),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                self.assertEqual(self.invoke(self.receipt)['cases'], 1)
                broken = copy.deepcopy(self.receipt)
                mutate(broken)
                with self.assertRaises(M.Unread): self.invoke(broken)
                print("CLUSTER_PROBE_V1 " + json.dumps({"name": name, "negative": "rejected", "positive_twin": "accepted"}), flush=True)
        for name, log in logs.items():
            with self.subTest(name=name):
                self.assertEqual(self.invoke(self.receipt)['cases'], 1)
                broken = copy.deepcopy(self.receipt)
                broken.update(log=log, log_digest=M.digest(log.encode()))
                with self.assertRaises(M.Unread): self.invoke(broken)
                print("CLUSTER_PROBE_V1 " + json.dumps({"name": name, "negative": "rejected", "positive_twin": "accepted"}), flush=True)

if __name__ == '__main__':
    unittest.main(verbosity=2)
