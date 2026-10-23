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

    def test_import_rejects_extra_shard_against_source_inventory(self):
        # Настоящие native captures внутри явно synthetic transport fixture.
        import json, re, tempfile
        exp = {'repo': gate.REPO, 'head': 'a' * 40, 'tree': 'b' * 40,
               'definitions': {str(i): {'matrix_index': i} for i in range(3)}}
        captures = [(HERE / f'kaname-stand-fixtures/integration-{i}-native.log').read_text()
                    for i in range(3)]
        selected = [p for raw in captures
                    for p in re.findall(r'^ok\s+(\S+)\s+\d+(?:\.\d+)?s\s*$', raw, re.M)]
        core = {name: 'fixture output\n' for name in
                ('build', 'vet', 'vet-integration', 'unit-verdict-self', 'unit-verdict',
                 'listfilter', 'manifest')}
        core['unit'] = (HERE / 'kaname-stand-fixtures/go-json-native.log').read_text()
        platform = {name: 'fixture output\n' for name in
                    ('platform-tests', 'platform-verdict', 'canon', 'catalog')}
        platform.update({f'integration-{i}': raw for i, raw in enumerate(captures)})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'fixture.txt'; artifact.write_text('synthetic fixture, not a receipt')
            packet = {'kind': 'imported-native-remote-heavy', 'head': exp['head'],
                      'tree': exp['tree'], 'runs': {}, 'selected_packages': selected,
                      'applicability_audit': str(artifact)}
            for name, census in [('core', core), ('platform', platform)]:
                ns = 'fixture-' + name
                command = f'remote-heavy: [{ns}] команда начата через fixture-only'
                raw = (f"HEAD {exp['head']} class=suite at=fixture dir=/src\n"
                       f'remote-heavy: [{ns}] ns {ns} создано: fixture\n'
                       + command + f"\nSOURCE {exp['head']} TREE {exp['tree']}\n")
                raw += ''.join(f'GROUP_BEGIN {group}\n{body.rstrip()}\nGROUP_END {group} rc=0\n'
                               for group, body in census.items())
                raw += (f'remote-heavy: [{ns}] команда завершилась кодом 0 за 1 с\n'
                        f'remote-heavy: [{ns}] ns {ns} снято\n')
                log = root / (name + '.log'); log.write_text(raw)
                packet['runs'][name] = dict(log=str(log), script=str(artifact),
                    command_line=command, runner=str(artifact), auxiliary={})
            packet_path = root / 'packet.json'; packet_path.write_text(json.dumps(packet))
            positive = gate.import_candidate(exp, packet_path)
            self.assertEqual(positive['integration']['passed'], 37)
            log = root / 'platform.log'; original = log.read_text()
            extra = 'GROUP_BEGIN integration-3\nextra complete shard\nGROUP_END integration-3 rc=0\n'
            log.write_text(original.replace('remote-heavy: [fixture-platform] команда завершилась',
                                            extra + 'remote-heavy: [fixture-platform] команда завершилась'))
            with self.assertRaisesRegex(gate.common.Unread, 'platform group inventory differs'):
                gate.import_candidate(exp, packet_path)
            log.write_text(original)
            self.assertEqual(gate.import_candidate(exp, packet_path), positive)

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
                        values = ci['jobs']['integrationshard']['strategy']['matrix']['shard']
                        values.append(values[0])
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


class PreciCensus(unittest.TestCase):
    def setUp(self):
        import json
        self.json = json
        spec = importlib.util.spec_from_file_location('preci_probe', HERE / 'kaname-preci.py')
        self.preci = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.preci)
        self.source = {'head': 'a' * 40, 'tree': 'b' * 40, 'status': ''}
        self.key = 'ci.yml:unit'
        native = (HERE / 'kaname-stand-fixtures/go-json-native.log').read_text()
        self.native = native
        summary = 'actual command summary\n'
        command = 'go test ./... -race -short -json > test.json'
        self.definition = {self.key: [{'step': 1, 'status': 'executed',
            'runSHA': gate.common.digest(command.encode()),
            'actualCommandSHA': gate.common.digest(command.encode())}]}
        record = {'group': self.key, **self.definition[self.key][0], 'rc': 0,
                  'logSHA': gate.common.digest(summary.encode())}
        line = lambda marker, value: marker + ' ' + json.dumps(value) + '\n'
        self.raw = ('PRECI_GROUP_BEGIN ' + self.key + '\n' +
            line('PRECI_SOURCE_BEFORE', {'group': self.key, **self.source}) +
            summary + native + line('PRECI_STEP', record) +
            line('PRECI_REPORT', {'group': self.key, 'name': 'test.json',
                 'sha256': gate.common.digest(native.encode()), 'rc': 0}) +
            line('PRECI_SOURCE_AFTER', {'group': self.key, **self.source}) +
            line('PRECI_GROUP_END', {'group': self.key, 'rc': 0}) +
            line('PRECI_CENSUS', {'failed': [], 'steps': 1, 'offlineTrackerIsNotLiveAPIProof': True}))

    def parse(self, raw=None):
        return self.preci.parse_partition(self.raw if raw is None else raw, self.source, self.definition)

    def mutate(self, marker, key, value):
        result = []
        for line in self.raw.splitlines(keepends=True):
            if line.startswith(marker + ' '):
                record = self.json.loads(line.split(' ', 1)[1]); record[key] = value
                line = marker + ' ' + self.json.dumps(record) + '\n'
            result.append(line)
        return ''.join(result)

    def test_preci_ordered_boundaries_and_typed_outcomes(self):
        positive = self.parse()
        changes = [
            ('PRECI_SOURCE_BEFORE', 'head', 'c' * 40),
            ('PRECI_SOURCE_AFTER', 'status', ' M go.mod'),
            ('PRECI_STEP', 'group', 'ci.yml:other'),
            ('PRECI_STEP', 'step', True), ('PRECI_STEP', 'step', '1'),
            ('PRECI_STEP', 'rc', False), ('PRECI_STEP', 'rc', '0'), ('PRECI_STEP', 'rc', 125),
            ('PRECI_STEP', 'status', 'not-executed-harness-error'),
            ('PRECI_STEP', 'runSHA', '0' * 64), ('PRECI_STEP', 'actualCommandSHA', '0' * 64),
            ('PRECI_REPORT', 'rc', False), ('PRECI_GROUP_END', 'rc', False),
            ('PRECI_GROUP_END', 'rc', 1), ('PRECI_CENSUS', 'steps', True),
            ('PRECI_CENSUS', 'steps', '1'), ('PRECI_CENSUS', 'failed', [self.key]),
        ]
        for marker, key, value in changes:
            with self.subTest(marker=marker, key=key, value=value):
                with self.assertRaises(self.preci.EvidenceError): self.parse(self.mutate(marker, key, value))
                self.assertEqual(self.parse(), positive)
        for marker in ('PRECI_SOURCE_BEFORE', 'PRECI_STEP', 'PRECI_SOURCE_AFTER', 'PRECI_GROUP_END', 'PRECI_CENSUS'):
            broken = ''.join(line for line in self.raw.splitlines(keepends=True) if not line.startswith(marker + ' '))
            with self.assertRaises(self.preci.EvidenceError): self.parse(broken)
        with self.assertRaises(self.preci.EvidenceError): self.parse(self.raw + self.raw)
        self.assertEqual(self.parse(), positive)

    def test_preci_unit_file_digest_is_not_stdout_digest(self):
        parsed = self.parse()['groups'][self.key]
        self.assertEqual(self.preci.verify_native(parsed, gate.common.digest), self.native)
        self.assertGreater(gate.go_json(self.native)['passed'], 0)
        for marker, field, value in [('PRECI_REPORT', 'sha256', '0' * 64),
                                     ('PRECI_REPORT', 'name', 'other.json'),
                                     ('PRECI_STEP', 'logSHA', '0' * 64)]:
            broken = self.parse(self.mutate(marker, field, value))['groups'][self.key]
            with self.assertRaises(self.preci.EvidenceError): self.preci.verify_native(broken, gate.common.digest)
        without = ''.join(line for line in self.raw.splitlines(keepends=True) if not line.startswith('PRECI_REPORT '))
        with self.assertRaises(self.preci.EvidenceError):
            self.preci.verify_native(self.parse(without)['groups'][self.key], gate.common.digest)
        self.assertEqual(self.preci.verify_native(self.parse()['groups'][self.key], gate.common.digest), self.native)

    def test_preci_source_steps_and_partition_selection(self):
        workflows = {name: gate.common.load_workflow((HERE / ('kaname-stand-fixtures/' +
            ('ci-workflow-native.yml' if name == 'ci.yml' else 'e2e-workflow-native.yml'))).read_bytes())
            for name in self.preci.WORKFLOW_JOBS}
        definitions = self.preci.definitions_for(workflows, 'unit,integrationshard', gate.common.digest, 3)
        self.assertEqual(set(definitions), {'ci.yml:unit', *(f'ci.yml:integrationshard:{i}' for i in range(3))})
        for selection in ('unit,unit', 'missing', '', 'unit,integrationshard,missing'):
            with self.assertRaises(self.preci.EvidenceError):
                self.preci.definitions_for(workflows, selection, gate.common.digest, 3)
        self.assertEqual(self.preci.definitions_for(workflows, 'unit,integrationshard', gate.common.digest, 3), definitions)


    def make_transport(self, directory, jobs, producer=None):
        import base64, gzip, io, tarfile
        if producer is None:
            producer = b'# Explicit synthetic producer fixture; not execution evidence.\n'
        files = {'runner.py': producer, 'platform.tar.gz': b'platform',
                 'vendor.tar.gz': b'vendor', 'tracker.tar.gz': b'tracker'}
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w') as archive:
            for name, data in sorted(files.items()):
                item = tarfile.TarInfo(name); item.size = len(data)
                archive.addfile(item, io.BytesIO(data))
        bundle = gzip.compress(stream.getvalue(), mtime=0)
        encoded = base64.urlsafe_b64encode(bundle).decode()
        chunks = [encoded[i:i + 48000] for i in range(0, len(encoded), 48000)]
        bootstrap = ('# Synthetic bootstrap fixture.\n[ "$(git rev-parse HEAD)" = ' + self.source['head'] + ' ]\npython3 "$assets/runner.py" --assets "$assets" --jobs ' + jobs + '\n').encode()
        targets = [f'part-{i}' for i in range(len(chunks))]
        rule = '.NOTPARALLEL:\n.PHONY: operand-begin operand-final ' + ' '.join(targets) + '\n'
        rule += 'operand-begin:; @test "$(CURDIR)" = /work/src && test "$${HEAVY_WORKDIR+x}" = x && : > /tmp/kaname-preci.parts\n'
        for i in range(len(chunks)):
            rule += f'part-{i}:; @printf "%s\\n" "{i:03d}-$(value P-{i})" >> /tmp/kaname-preci.parts\n'
        rule += 'operand-final:; @printf %s ' + base64.b64encode(bootstrap).decode() + ' | base64 -d | bash\n'
        argv = ['make', '-f', '/dev/null', '--eval', rule, 'MAKEOVERRIDES=']
        argv += [f'P-{i}={chunk}' for i, chunk in enumerate(chunks)]
        argv += ['operand-begin', *targets, 'operand-final']
        manifest = {'source': self.source['head'], 'jobs': jobs,
                    'bundleSHA': gate.common.digest(bundle), 'bundleBytes': len(bundle),
                    'argvBytes': sum(len(v.encode()) + 1 for v in argv),
                    'files': {name: gate.common.digest(data) for name, data in files.items()}}
        for name, data in [('runner.py', producer), ('bootstrap.sh', bootstrap),
                           ('argv.json', self.json.dumps(argv).encode()),
                           ('manifest.json', self.json.dumps(manifest).encode())]:
            (directory / name).write_bytes(data)
        return argv, bootstrap, manifest, producer

    def test_preci_canonical_transport_negative_twins(self):
        import tempfile, copy
        with tempfile.TemporaryDirectory() as temporary:
            argv, bootstrap, manifest, producer = self.make_transport(Path(temporary), 'unit')
            positive = self.preci.bind_transport(argv, bootstrap, manifest, producer, gate.common.digest)
            wrong = copy.deepcopy(manifest); wrong['files']['runner.py'] = '0' * 64
            wrong_bundle = copy.deepcopy(manifest); wrong_bundle['bundleSHA'] = '0' * 64
            cases = [(argv + ['extra-target'], bootstrap, manifest, producer),
                     (argv, bootstrap + b'extra', manifest, producer),
                     (argv, bootstrap, manifest, producer + b'extra'),
                     (argv, bootstrap, wrong, producer), (argv, bootstrap, wrong_bundle, producer),
                     (argv[:4], bootstrap, manifest, producer)]
            for args in cases:
                with self.assertRaises(self.preci.EvidenceError): self.preci.bind_transport(*args, gate.common.digest)
                self.assertEqual(self.preci.bind_transport(argv, bootstrap, manifest, producer, gate.common.digest), positive)

    def test_preci_whole_import_workflow_native_and_failed_transport(self):
        import tempfile, copy
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            workflow_paths = {name: HERE / ('kaname-stand-fixtures/' +
                ('ci-workflow-native.yml' if name == 'ci.yml' else 'e2e-workflow-native.yml'))
                for name in self.preci.WORKFLOW_JOBS}
            workflows = {name: gate.common.load_workflow(path.read_bytes()) for name, path in workflow_paths.items()}
            jobs = 'unit,integrationshard'
            definitions = self.preci.definitions_for(workflows, jobs, gate.common.digest, 3)
            argv, _, _, _ = self.make_transport(directory, jobs)
            selected = []
            captures = []
            for i in range(3):
                capture = (HERE / f'kaname-stand-fixtures/integration-{i}-native.log').read_text()
                selected += gate.integration(capture, i, 3)['packages']; captures.append(capture)
            ns = 'fixture-ns'
            import subprocess
            quoted = subprocess.check_output(['bash', '--noprofile', '--norc', '-c', 'printf "%q " "$@"', 'argv-data', *argv], env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, text=True)
            command_line = f'remote-heavy: [{ns}] команда начата через 1 с после создания Job: ' + quoted
            raw = (f'HEAD {self.source["head"]} class=fixture at=fixture dir=/work/src\n'
                   f'SOURCE {self.source["head"]} TREE {self.source["tree"]}\n'
                   f'remote-heavy: [{ns}] ns {ns} создано:\n' + command_line + '\n')
            line = lambda marker, value: marker + ' ' + self.json.dumps(value) + '\n'
            count = 0
            for key, steps in definitions.items():
                raw += 'PRECI_GROUP_BEGIN ' + key + '\n'
                raw += line('PRECI_SOURCE_BEFORE', {'group': key, **self.source})
                for position, definition in enumerate(steps):
                    record = {'group': key, **definition}
                    native = ''
                    if definition['status'] != 'conditional-error-message-not-selected':
                        record['rc'] = 0
                        if position == len(steps) - 1 and key != 'ci.yml:unit':
                            native = captures[int(key.rsplit(':', 1)[1])]
                        record['logSHA'] = gate.common.digest(native.encode())
                        if position == len(steps) - 1 and key == 'ci.yml:unit':
                            native += self.native
                    raw += native + line('PRECI_STEP', record); count += 1
                if key == 'ci.yml:unit':
                    raw += line('PRECI_REPORT', {'group': key, 'name': 'test.json',
                        'sha256': gate.common.digest(self.native.encode()), 'rc': 0})
                raw += line('PRECI_SOURCE_AFTER', {'group': key, **self.source})
                raw += line('PRECI_GROUP_END', {'group': key, 'rc': 0})
            raw += line('PRECI_CENSUS', {'failed': [], 'steps': count, 'offlineTrackerIsNotLiveAPIProof': True})
            raw += f'remote-heavy: [{ns}] команда завершилась кодом 0 за 1 с\n'
            raw += f'remote-heavy: [{ns}] ns {ns} снято\n'
            (directory / 'raw.log').write_text(raw)
            (directory / 'audit.txt').write_text('Synthetic import fixture, native short skip counts remain visible.\n')
            exp = {'repo': gate.REPO, **self.source, 'definitions': {}}
            for i in range(3):
                exp['definitions'][f'integration{i}'] = {'matrix_index': i,
                    'workflow_job': 'ci.yml:integrationshard', 'workflow_digest': gate.common.digest(workflow_paths['ci.yml'].read_bytes())}
            exp['definitions']['hosted'] = {'matrix_index': None, 'workflow_job': 'e2e-newman.yml:stand',
                'workflow_digest': gate.common.digest(workflow_paths['e2e-newman.yml'].read_bytes())}
            packet = {'kind': 'imported-native-preci-v1', 'head': self.source['head'], 'tree': self.source['tree'],
                      'workflows': {k: str(v) for k, v in workflow_paths.items()}, 'selected_packages': selected,
                      'applicability_audit': str(directory / 'audit.txt'), 'runs': {'synthetic': {
                          'log': str(directory / 'raw.log'), 'runner': str(directory / 'runner.py'),
                          'manifest': str(directory / 'manifest.json'), 'argv': str(directory / 'argv.json'),
                          'bootstrap': str(directory / 'bootstrap.sh'), 'command_line': command_line, 'auxiliary': {}}}}
            def imported(value):
                return self.preci.import_candidate(exp, value, gate.common, gate.remote_log, gate.go_json, gate.integration_union)
            positive = imported(packet)
            self.assertEqual(positive['integration']['passed'], 37)
            # All local transport artifacts agree with each other, but they
            # must still equal the actual argv captured in the unchanged log.
            self.make_transport(directory, jobs, b'# Different self-consistent producer.\n')
            with self.assertRaisesRegex(self.preci.EvidenceError, 'captured executed argv differs'):
                imported(packet)
            self.make_transport(directory, jobs)
            self.assertEqual(imported(packet), positive)
            for broken in (raw.replace('кодом 0 за', 'кодом 1 за'), raw.replace(f'ns {ns} снято', 'cleanup missing'),
                           raw.replace('"failed": []', '"failed": ["ci.yml:unit"]')):
                (directory / 'raw.log').write_text(broken)
                with self.assertRaises((self.preci.EvidenceError, gate.common.Unread)): imported(packet)
                (directory / 'raw.log').write_text(raw)
                self.assertEqual(imported(packet), positive)
            wrong = copy.deepcopy(packet); wrong['selected_packages'] = selected[:-1]
            with self.assertRaises(gate.common.Unread): imported(wrong)
            wrong = copy.deepcopy(packet); wrong['runs']['duplicate'] = copy.deepcopy(wrong['runs']['synthetic'])
            with self.assertRaises(self.preci.EvidenceError): imported(wrong)
            self.assertEqual(imported(packet), positive)


if __name__ == '__main__':
    unittest.main(verbosity=2)
