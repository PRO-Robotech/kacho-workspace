#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Native producer captures and one-fact counterexamples; run externally."""
import importlib.util
from pathlib import Path
import sys
import unittest
sys.dont_write_bytecode = True
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('kaname_stand', HERE / 'kaname-stand.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class NativeCensus(unittest.TestCase):
    def test_real_checkout_ignores_echoed_subject(self):
        raw = (HERE / 'kaname-stand-fixtures/image-checkout-native.log').read_text()
        head = 'ad86098bda804acce99037b1f7a99acb9a03bec5'
        self.assertIn(head, gate.checkout_source(raw, head))
        for broken in (raw.replace(head, '0' * 40), raw + raw,
                       raw.replace('[command]/usr/bin/git log -1 --format=%H', 'echo HEAD_SHA'),
                       raw.replace(head, '0' * 40) + '\nHEAD_SHA: ' + head):
            with self.assertRaises(gate.common.Unread):
                gate.checkout_source(broken, head)
            self.assertIn(head, gate.checkout_source(raw, head))

    def test_newman_declared_wave_boundary_negatives(self):
        # Synthetic grammar probes; actual hosted positive is a separate acceptance step.
        header = 'RESOURCE ASSERT FAILED REQUESTS UNANSWERED RC NOTE\n'
        raw = header + 'a 2 0 1 0 0\n' + 'b 3 0 2 0 0\n' + (
            'TOTAL: 2/2 коллекций отчиталось — 3 запрос(ов), 0 без ответа, '
            '5 утверждени(й), 0 упавших, 0 немых отчёт(ов)\n')
        positive = gate.newman_tables(raw, [['a', 'b']])
        self.assertEqual(positive['passed'], 5)
        for broken in (raw.replace('b 3', 'other 3'), raw.replace('b 3', 'a 3'),
                       raw.replace('a 2 0', 'a 2 1'), raw.replace('a 2 0 1 0 0', 'a 0 0 1 0 0'),
                       raw.replace('a 2 0 1 0 0', 'a 2 0 1 1 0'),
                       raw.replace('b 3 0 2 0 0', 'b 3 0 2 0 1'),
                       raw.replace('2/2', '1/2'), raw.replace('5 утверждени', '6 утверждени'),
                       raw.replace('b 3 0 2 0 0\n', ''), raw[:raw.index('TOTAL:')], raw + raw):
            with self.assertRaises(gate.common.Unread):
                gate.newman_tables(broken, [['a', 'b']])
            self.assertEqual(gate.newman_tables(raw, [['a', 'b']]), positive)

    def test_actual_three_shards_union_and_cross_shard_duplicate(self):
        captures = [(HERE / f'kaname-stand-fixtures/integration-{i}-native.log').read_text()
                    for i in range(3)]
        # Исторический capture используется для parser twin, не как новый runtime receipt.
        selected = [p for i, raw in enumerate(captures) for p in gate.integration(raw, i, 3)['packages']]
        self.assertEqual(gate.integration_union(captures, selected)['passed'], 37)
        first = gate.integration(captures[0], 0, 3)['packages'][0]
        second = gate.integration(captures[1], 1, 3)['packages'][0]
        broken = list(captures)
        broken[1] = broken[1].replace(second, first)
        with self.assertRaises(gate.common.Unread):
            gate.integration_union(broken, selected)
        for inventory in (selected[:-1], selected + ['unexpected/package'], selected + [selected[0]]):
            with self.assertRaises(gate.common.Unread):
                gate.integration_union(captures, inventory)
        self.assertEqual(gate.integration_union(captures, selected)['passed'], 37)

    def test_real_integration_and_one_fact_twins(self):
        raw = (HERE / 'kaname-stand-fixtures/integration-shard-native.log').read_text()
        positive = gate.integration(raw, 0, 3)
        self.assertEqual(positive['passed'], 13)
        self.assertIsNone(positive['test_cases'])
        mutations = [raw.replace('исполняется в шарде 0: 13', 'исполняется в шарде 1: 13'),
                     raw.replace('ПО ШАРДАМ (3)', 'ПО ШАРДАМ (4)'),
                     raw.replace('зелёный (код go test 0)', 'красный (код go test 1)'),
                     raw.replace('659.259s', '(cached)'),
                     raw + '\nFAIL package\n']
        ok_line = next(line for line in raw.splitlines() if line.startswith('ok'))
        mutations += [raw.replace(ok_line, ''), raw + '\n' + ok_line]
        for changed in mutations:
            with self.subTest(mutation=mutations.index(changed)):
                with self.assertRaises(gate.common.Unread):
                    gate.integration(changed, 0, 3)
                self.assertEqual(gate.integration(raw, 0, 3), positive)

    def test_real_go_json_and_missing_terminal(self):
        raw = (HERE / 'kaname-stand-fixtures/go-json-native.log').read_text()
        positive = gate.go_json(raw)
        self.assertGreater(positive['passed'], 0)
        import json
        records = [json.loads(line) for line in raw.splitlines()]
        for index, record in enumerate(records):
            if record.get('Action') == 'pass':
                with self.subTest(index=index):
                    broken = '\n'.join(json.dumps(r) for i, r in enumerate(records) if i != index)
                    with self.assertRaises(gate.common.Unread):
                        gate.go_json(broken)
        with self.assertRaises(gate.common.Unread):
            gate.go_json(raw + '{"Action":"start","Package":"missing-package"}\n')
        self.assertEqual(gate.go_json(raw), positive)

    def test_group_framing_refuses_dropped_or_red_neighbors(self):
        raw = 'GROUP_BEGIN a\nnative\nGROUP_END a rc=0\nGROUP_BEGIN b\nnative\nGROUP_END b rc=0\n'
        self.assertEqual(set(gate.groups(raw)), {'a', 'b'})
        for broken in (raw.replace('b rc=0', 'b rc=1'), raw.replace('GROUP_END b rc=0', ''),
                       raw + raw, raw.replace('GROUP_END a rc=0', '')):
            with self.assertRaises(gate.common.Unread):
                gate.groups(broken)


class TrustBoundaries(unittest.TestCase):
    def setUp(self):
        import json, base64, copy
        self.copy = copy.deepcopy
        self.raw = (HERE / 'kaname-stand-fixtures/image-workflow-native.yml').read_bytes()
        self.job = json.loads((HERE / 'kaname-stand-fixtures/image-job-native.json').read_text())
        self.name = 'docker-build.yml:image'
        definition = gate.job_definition(gate.common.load_workflow(self.raw), 'image')
        self.exp = {'repo': gate.REPO, 'head': self.job['head_sha'], 'tree': 'a' * 40,
                    'ref': 'refs/heads/954', 'definitions': {self.name: {
                        'definition': definition, 'definition_digest': gate.common.digest(definition),
                        'workflow_digest': gate.common.digest(self.raw)}}}
        self.run = {'id': self.job['run_id'], 'run_number': 10, 'run_attempt': 1,
                    'head_sha': self.exp['head'], 'event': 'push', 'head_branch': '954',
                    'repository': {'full_name': gate.REPO}, 'path': '.github/workflows/docker-build.yml',
                    'status': 'completed', 'conclusion': 'success'}
        self.log = (HERE / 'kaname-stand-fixtures/image-checkout-native.log').read_text()
        self.review = {'role': 'check-verifier', 'verdict': 'accept', 'blocking': [],
                       'expected_digest': gate.common.digest(self.exp), 'job': self.name,
                       'temporary_resources': 'job-vm-only', 'transitive_source_review': True}

    def capture(self, job=None, runs=None, tree=None, raw=None, log=None):
        import base64
        from unittest.mock import patch
        job = self.job if job is None else job
        def api(repo, path, raw=False):
            if path.startswith('contents/'):
                return {'content': base64.b64encode(self.raw if content is None else content).decode()}
            if path.startswith('git/commits/'):
                return {'tree': {'sha': self.exp['tree'] if tree is None else tree}}
            if path == f"actions/jobs/{job['id']}/logs":
                self.assertTrue(raw)
                return self.log if log is None else log
            self.fail('unexpected API request: ' + path)
        content = raw
        def pages(repo, path, key):
            if key == 'workflow_runs':
                return [self.run] if runs is None else runs
            self.assertEqual(path, f"actions/runs/{self.run['id']}/attempts/1/jobs")
            return [job]
        with patch.object(gate.common, 'api', side_effect=api), patch.object(gate.common, 'pages', side_effect=pages):
            return gate.hosted_capture(self.exp, self.name, 'push')

    def test_actual_api_shape_and_one_fact_identity_failures(self):
        positive = self.capture()
        self.assertEqual(positive['job']['id'], self.job['id'])
        for key, value in [('head_sha', '0' * 40), ('run_attempt', 2), ('run_id', 1),
                           ('conclusion', 'failure'), ('conclusion', 'skipped'),
                           ('status', 'in_progress'), ('runner_group_name', 'self-hosted'),
                           ('runner_name', 'untrusted'), ('labels', ['self-hosted'])]:
            with self.subTest(field=key, value=value):
                broken = self.copy(self.job); broken[key] = value
                with self.assertRaises(gate.common.Unread): self.capture(job=broken)
                self.assertEqual(self.capture()['job']['id'], self.job['id'])
        for kwargs in ({'tree': '0' * 40}, {'raw': self.raw + b'\n# changed\n'},
                       {'log': self.log.replace(self.exp['head'], '0' * 40)}, {'runs': []}):
            with self.assertRaises(gate.common.Unread): self.capture(**kwargs)
        newer = dict(self.run, id=self.run['id'] + 1, run_number=11, conclusion='failure')
        with self.assertRaises(gate.common.Unread): self.capture(runs=[self.run, newer])
        wrong = dict(self.run, head_sha='0' * 40)
        with self.assertRaises(gate.common.Unread): self.capture(runs=[wrong])

    def test_build_steps_and_cleanup_review_fail_closed(self):
        positive = self.capture()
        def verdict(capture, review): return gate.hosted_verdict(self.exp, self.name, capture, review)
        self.assertEqual(verdict(positive, self.review)['census']['passed'], 1)
        for label in ('сборка образа', 'сверка опубликованного — доказательство инъекцией в обе стороны'):
            for action in ('remove', 'skipped', 'failure'):
                broken = self.copy(positive)
                if action == 'remove':
                    broken['job']['steps'] = [s for s in broken['job']['steps'] if s['name'] != label]
                else:
                    next(s for s in broken['job']['steps'] if s['name'] == label)['conclusion'] = action
                with self.assertRaises(gate.common.Unread): verdict(broken, self.review)
                self.assertEqual(verdict(positive, self.review)['census']['passed'], 1)
        for key, value in [('expected_digest', '0' * 64), ('temporary_resources', 'external-cluster'),
                           ('transitive_source_review', False), ('job', 'another'),
                           ('role', 'author'), ('blocking', ['unresolved']), ('verdict', 'reject')]:
            broken = dict(self.review); broken[key] = value
            with self.assertRaises(gate.common.Unread): verdict(positive, broken)
            self.assertEqual(verdict(positive, self.review)['census']['passed'], 1)

    def test_import_native_source_command_and_cleanup_are_required(self):
        exp = {'head': 'a' * 40, 'tree': 'b' * 40}
        command = 'remote-heavy: [fixture] команда начата через bash exact-reviewed-payload'
        raw = ('HEAD ' + exp['head'] + ' class=suite at=now dir=/src\n'
               'remote-heavy: [fixture] ns fixture создано: bound-api\n'
               + command + '\nSOURCE ' + exp['head'] + ' TREE ' + exp['tree'] + '\n'
               'GROUP_BEGIN unit\nactual-native\nGROUP_END unit rc=0\n'
               'remote-heavy: [fixture] команда завершилась кодом 0 за 1 с\n'
               'remote-heavy: [fixture] ns fixture снято\n')
        positive = gate.remote_log(raw, exp, command)
        self.assertEqual(positive['cleanup_kind'], 'runner-observed-namespace-delete-wait')
        for old, new in [('TREE ' + exp['tree'], 'TREE ' + '0' * 40),
                         ('SOURCE ' + exp['head'], 'SOURCE ' + '0' * 40),
                         ('HEAD ' + exp['head'], 'HEAD ' + '0' * 40),
                         ('ns fixture снято', 'cleanup API failed'),
                         ('кодом 0 за', 'кодом 1 за'),
                         (command, 'echo ' + command), ('GROUP_END unit rc=0', '')]:
            with self.subTest(fact=old):
                with self.assertRaises(gate.common.Unread):
                    gate.remote_log(raw.replace(old, new), exp, command)
                self.assertEqual(gate.remote_log(raw, exp, command), positive)

    def test_register_import_binds_review_to_current_artifacts(self):
        from unittest.mock import patch
        import tempfile
        candidate = {'artifact': 'actual-capture-digest', 'expected_digest': gate.common.digest(self.exp)}
        review = {'role': 'check-verifier', 'verdict': 'accept', 'blocking': [],
                  'candidate_digest': gate.common.digest(candidate), 'claims': [
                  'source-and-command-binding', 'native-verdict-and-cleanup',
                  'selected-package-partition', 'short-skip-applicability']}
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(gate, 'import_candidate', return_value=candidate), \
                 patch.object(gate.common, 'registry', return_value=Path(directory)), \
                 patch.object(gate.common, 'read_json', return_value=review):
                self.assertEqual(gate.register_import(self.exp, 'packet', 'review'), gate.common.digest(candidate))
            for field, value in [('candidate_digest', '0' * 64), ('claims', review['claims'][:-1]),
                                 ('role', 'author'), ('blocking', ['gap']), ('verdict', 'reject')]:
                broken = dict(review); broken[field] = value
                with patch.object(gate, 'import_candidate', return_value=candidate), \
                     patch.object(gate.common, 'read_json', return_value=broken):
                    with self.assertRaises(gate.common.Unread): gate.register_import(self.exp, 'packet', 'review')
            changed = dict(candidate, artifact='changed-bytes')
            with patch.object(gate, 'import_candidate', return_value=changed), \
                 patch.object(gate.common, 'read_json', return_value=review):
                with self.assertRaises(gate.common.Unread): gate.register_import(self.exp, 'packet', 'review')

    def test_external_stage_cannot_become_full_or_change_import(self):
        from unittest.mock import patch
        exp = {'repo': gate.REPO, 'head': 'a' * 40, 'tree': 'b' * 40, 'base': '955',
               'logical_jobs': ['unit', 'integration', *gate.HOSTED],
               'jobs': ['ci.yml:unit', 'ci.yml:integrationshard[0]', *gate.HOSTED],
               'definitions': {'ci.yml:unit': {'matrix_index': None},
                               'ci.yml:integrationshard[0]': {'matrix_index': 0}}}
        candidate = {'expected_digest': gate.common.digest(exp), 'unit': {'passed': 1},
                     'integration': {'shards': [{'passed': 1}]}}
        identity = gate.common.digest(candidate)
        admitted = {'candidate': candidate, 'review': {'candidate_digest': identity,
                    'verdict': 'accept', 'blocking': []}}
        with patch.object(gate.common, 'registry', return_value=Path('/unused')), \
             patch.object(gate.common, 'read_json', return_value=admitted):
            external = gate.staged_report(exp, identity, external_only=True)
            self.assertFalse(external['full'])
            self.assertEqual(external['stage'], 'external-ready')
            self.assertEqual(len(external['jobs']), 2)
            with self.assertRaises(gate.common.Unread): gate.staged_report(exp, identity)
            with patch.object(gate, 'hosted_capture', return_value={'fixture': True}) as captured, \
                 patch.object(gate, 'hosted_verdict', return_value={'fixture': 'accepted'}):
                full = gate.staged_report(exp, identity, {n: n for n in gate.HOSTED},
                                          {n: 'push' for n in gate.HOSTED})
                self.assertTrue(full['full'])
                self.assertEqual(set(full['jobs']), set(exp['jobs']))
                self.assertEqual(captured.call_count, 4)
            for broken in (dict(candidate, unit={'passed': 999}),
                           dict(candidate, expected_digest='0' * 64)):
                with patch.object(gate.common, 'read_json', return_value=dict(admitted, candidate=broken)):
                    with self.assertRaises(gate.common.Unread):
                        gate.staged_report(exp, identity, external_only=True)

    def test_real_cli_external_positive_and_full_refusal(self):
        # Isolated Git checkout gives the real registry() a private evidence directory.
        # This is a synthetic admitted-record fixture, never production registration.
        import json, os, shutil, subprocess, tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); scripts = root / 'scripts'; scripts.mkdir()
            for name in ('stand-report.sh', 'kaname-stand.py', 'operator-stand.py'):
                shutil.copyfile(HERE / name, scripts / name)
            subprocess.run(['git', 'init', '-q', str(root)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(root), 'remote', 'add', 'origin',
                            'https://github.com/PRO-Robotech/kacho-workspace.git'], check=True, capture_output=True)
            env = dict(os.environ); env.pop('LANDING_PRECHECK_WS', None)
            exp = {'schema': 'kaname-stand-v1', 'repo': gate.REPO, 'head': 'a' * 40,
                   'tree': 'b' * 40, 'base': '955', 'logical_jobs': ['unit', 'integration', *gate.HOSTED],
                   'jobs': ['ci.yml:unit', 'ci.yml:integrationshard[0]', *gate.HOSTED],
                   'definitions': {'ci.yml:unit': {'matrix_index': None},
                                   'ci.yml:integrationshard[0]': {'matrix_index': 0}}}
            candidate = {'expected_digest': gate.common.digest(exp), 'unit': {'passed': 1},
                         'integration': {'shards': [{'passed': 1}]}}
            identity = gate.common.digest(candidate)
            admitted = {'candidate': candidate, 'review': {'candidate_digest': identity,
                        'verdict': 'accept', 'blocking': []}}
            registry = root / 'tmp/operator-stand-registry'
            (registry / 'kaname-imports').mkdir(parents=True)
            (registry / 'kaname-imports' / (identity + '.json')).write_text(json.dumps(admitted))
            with patch.object(gate.common, 'registry', return_value=registry):
                report = gate.staged_report(exp, identity, external_only=True)
            (root / 'expect.json').write_text(json.dumps(exp))
            (root / 'report.json').write_text(json.dumps(report))
            for prefix in ([], ['check']):
                command = ['bash', str(scripts / 'stand-report.sh'), *prefix, str(root / 'report.json'),
                           '--head', exp['head'], '--expect', str(root / 'expect.json')]
                lawful = subprocess.run(command + ['--external-only'], capture_output=True, text=True, timeout=30, env=env)
                self.assertEqual(lawful.returncode, 0, lawful.stdout + lawful.stderr)
                self.assertEqual(json.loads(lawful.stdout)['verdict'], 'external-ready')
                wrong = subprocess.run(command, capture_output=True, text=True, timeout=30, env=env)
                self.assertEqual(wrong.returncode, 2)
                self.assertIn('wrong requested evidence stage', wrong.stdout)

    def test_canonical_expect_source_inventory_and_one_fact_twins(self):
        # Source snapshots from ad86098: actual mandatory inventory, no ghjob simulation.
        import json, os, subprocess, tempfile
        sources = {name: (HERE / 'kaname-stand-fixtures' / fixture).read_bytes()
                   for name, fixture in [('ci.yml', 'ci-workflow-native.yml'),
                                         ('e2e-newman.yml', 'e2e-workflow-native.yml'),
                                         ('docker-build.yml', 'image-workflow-native.yml')]}
        mutations = ('lawful', 'missing-job', 'missing-workflow', 'duplicate-shard',
                     'checkout-ref', 'self-hosted')
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); co = root / 'checkout'; co.mkdir()
                wf = co / '.github/workflows'; wf.mkdir(parents=True)
                env = dict(os.environ); env.pop('LANDING_PRECHECK_WS', None)
                def git(*args):
                    return subprocess.run(['bash', '-c',
                        '. "$1"; sandbox_git_home "$2" || exit; shift 2; sandbox_run git "$@"',
                        'fixture', str(HERE / 'lib/sandbox-git-home.sh'), str(root / 'git-home'),
                        '-C', str(co), *args], env=env,
                        check=True, capture_output=True, text=True).stdout.strip()
                git('init', '-q'); git('remote', 'add', 'origin', 'https://github.com/PRO-Robotech/kaname.git')
                for name, raw in sources.items(): (wf / name).write_bytes(raw)
                git('add', '.'); git('commit', '-qm', 'lawful source inventory')
                base = git('rev-parse', 'HEAD')
                def expect():
                    return subprocess.run(['bash', str(HERE / 'stand-report.sh'), 'expect',
                        '--checkout', str(co), '--head', git('rev-parse', 'HEAD'),
                        '--base', base, '--draft', 'false'], env=env,
                        capture_output=True, text=True, timeout=30)
                twin = expect()
                self.assertEqual(twin.returncode, 0, twin.stdout + twin.stderr)
                actual = json.loads(twin.stdout)
                self.assertEqual(len(actual['logical_jobs']), 6)
                self.assertEqual(len(actual['jobs']), 8)
                self.assertEqual(sum(x['executor'] == 'external' for x in actual['definitions'].values()), 4)
                if mutation == 'lawful': continue
                ci = gate.common.load_workflow(sources['ci.yml'])
                e2e = gate.common.load_workflow(sources['e2e-newman.yml'])
                if mutation == 'missing-workflow': (wf / 'docker-build.yml').unlink()
                elif mutation == 'missing-job':
                    del e2e['jobs']['stand-ceremony']
                    (wf / 'e2e-newman.yml').write_text(json.dumps(e2e))
                else:
                    if mutation == 'duplicate-shard':
                        ci['jobs']['integrationshard']['strategy']['matrix']['shard'].append(0)
                    elif mutation == 'checkout-ref':
                        ci['jobs']['unit']['steps'][0].setdefault('with', {})['ref'] = 'other'
                    else: ci['jobs']['unit']['runs-on'] = 'self-hosted'
                    (wf / 'ci.yml').write_text(json.dumps(ci))
                git('add', '-A'); git('commit', '-qm', mutation)
                bad = expect()
                self.assertEqual(bad.returncode, 2, bad.stdout + bad.stderr)
                self.assertTrue(bad.stdout.startswith('VOID\t'), bad.stdout)

    def test_canonical_shell_entrypoint_reaches_stage_check(self):
        # Real shell dispatcher and parser, with no network or replacement helper.
        import json, subprocess, tempfile
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            exp = {'schema': 'kaname-stand-v1', 'repo': gate.REPO, 'head': 'a' * 40, 'base': '955'}
            (d / 'expect.json').write_text(json.dumps(exp))
            (d / 'report.json').write_text(json.dumps({'full': False}))
            for prefix in ([], ['check']):
                result = subprocess.run(['bash', str(HERE / 'stand-report.sh'), *prefix,
                    str(d / 'report.json'), '--head', exp['head'], '--expect', str(d / 'expect.json')],
                    capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 2)
                self.assertIn('wrong requested evidence stage', result.stdout)
                self.assertNotIn('invalid choice', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
