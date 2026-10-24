#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Внешний маршрут читателей (ws#1365): драйвер, сторона pod и снятый GitHub — опытом.

Песочница — клон воркспейса из файлов этой ревизии. Вход зовётся «на машине» (без
KUBERNETES_SERVICE_HOST, GITHUB_ACTIONS, KACHO_REMOTE_READER_POD); python3 машины — ловушка,
её срабатывание пишет метку. heavy-slot.sh — двойник Job: bundle закоммиченного дерева, тот же
workdir, KUBERNETES_SERVICE_HOST и настоящий PATH. gh машины — двойник площадки по виду пути
(не по выписанному перечню вызовов): его ответы снимает драйвер, совпадение ключей с вызовами
судьи и есть предмет. Эталон — тот же вход, исполненный в pod напрямую с тем же двойником gh.
Исполнять во внешнем кластере (heavy-slot.sh suite), не на машине.
"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('kaname_stand', HERE / 'kaname-stand.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
FIX = HERE / 'kaname-stand-fixtures'
COPY = ['remote-reader.sh', 'remote-reader/pod.sh', 'remote-reader/replay-gh.sh', 'stand-report.sh',
        'kaname-stand.py', 'operator-stand.py', 'pr-body.sh', 'ci-read-expected.tsv', 'lib/ws-home.sh',
        'lib/sandbox-git-home.sh', 'lib/gate_root.py', 'lib/dod_proof.jq', 'lib/gh-rate.sh',
        'hooks/attribution-rule.sh']
# Читатели демона вливания (ws#1365) и их соседи по рецепту «ЗАПУСК».
DAEMON_COPY = ['landing-precheck.sh', 'merge-readiness.sh', 'ci-read.sh', 'branch-audit.sh']
LPFIX = HERE / 'landing-precheck-fixtures'


def lp_out(result):
    """Код и вывод предпроверки; путь ведомости — каталог, где судья её читал (в pod — клон Job)."""
    import re
    return result.returncode, re.sub(r'\(/\S*/scripts/ci-read-expected\.tsv\)', '(<scripts>/ci-read-expected.tsv)',
                                     result.stdout)


SLOT = r'''#!/usr/bin/env bash
# Двойник heavy-slot.sh: Job — bundle закоммиченного дерева (HEAD и origin/*), тот же workdir.
printf '%s\n' "$*" >> "$SANDBOX_SLOT_LOG"
if [ -n "${SANDBOX_SLOT_RC:-}" ]; then echo "heavy-slot: двойник: слот занят" >&2; exit "$SANDBOX_SLOT_RC"; fi
while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift
top="$(git rev-parse --show-toplevel)"; rel="$(realpath --relative-to="$top" "$PWD")"
pod="$(mktemp -d)"
git -C "$top" bundle create "$pod/in.bundle" HEAD --remotes=origin > /dev/null 2>&1 || exit 69
git init -q "$pod/src" && git -C "$pod/src" fetch -q "$pod/in.bundle" 'refs/remotes/*:refs/remotes/*' &&
    git -C "$pod/src" fetch -q "$pod/in.bundle" HEAD &&
    git -C "$pod/src" checkout -q --detach FETCH_HEAD || exit 69
# Клон Job настоящего маршрута (remote-heavy/run.sh: init + bundle) origin не несёт; заводят его лишь
# явные случаи двойника — враждебный и законный близнец (SANDBOX_POD_ORIGIN).
[ -z "${SANDBOX_POD_ORIGIN:-}" ] || git -C "$pod/src" remote add origin "$SANDBOX_POD_ORIGIN" || exit 69
case "${SANDBOX_ORIGIN_BINDING:-}" in
    missing) rm -f "$pod/src/$rel/workspace-origin" ;;
    foreign) printf '%s\n' https://example.invalid/foreign.git > "$pod/src/$rel/workspace-origin" ;;
    credentials) printf '%s\n' https://user:password@github.com/PRO-Robotech/kacho-workspace.git > "$pod/src/$rel/workspace-origin" ;;
esac
if [ -n "${SANDBOX_EXPORT_FAIL:-}" ]; then
    mkdir -p "$pod/failbin"
    printf '#!/bin/sh\nexit 73\n' > "$pod/failbin/$SANDBOX_EXPORT_FAIL"
    chmod +x "$pod/failbin/$SANDBOX_EXPORT_FAIL"
    SANDBOX_POD_PATH="$pod/failbin:$SANDBOX_POD_PATH"
fi
# Учётные данные машины в Job не едут: метка секрета в дереве, которое получил pod, — утечка.
[ -z "${SANDBOX_SECRET:-}" ] || ! grep -rqsF -- "$SANDBOX_SECRET" "$pod/src" || echo "$*" >> "$SANDBOX_LEAK"
[ -z "${SANDBOX_MACHINE:-}" ] || mv "$SANDBOX_MACHINE" "$SANDBOX_MACHINE.hidden"
(cd "$pod/src/$rel" && env HOME="$SANDBOX_POD_HOME" PATH="$SANDBOX_POD_PATH" KUBERNETES_SERVICE_HOST=sandbox "$@") |
    case "${SANDBOX_STREAM:-}" in
        dup) awk '{print} /^remote-reader-out 1 / {print}' ;;
        drop) awk '!/^remote-reader-out 1 /' ;;
        *) cat ;;
    esac
rc=${PIPESTATUS[0]}
[ -z "${SANDBOX_MACHINE:-}" ] || mv "$SANDBOX_MACHINE.hidden" "$SANDBOX_MACHINE"
rm -rf "$pod"; exit "$rc"
'''
TRAP = '#!/usr/bin/env bash\necho "$0 $*" >> "$SANDBOX_TRAP"\nexit 97\n'
SECRET = 'SANDBOX-CREDENTIAL-7f3c'  # метка учётных данных машины: в дереве Job её быть не должно
# Промахи, которые называет pod (ws#1365): машина исполняет своим токеном лишь закрытый перечень
# чтений. REFUSED — запись, выдача токена, тело, заголовки, jq, чужой хост, обход регистром,
# слитной формой ключа, переводом строки внутри довода, псевдоним; READS — законные чтения.
R = 'repos/PRO-Robotech/kaname/issues/1/comments'
REFUSED = [
    ['api', '-X', 'POST', R], ['api', '--method=POST', R], ['api', R, '-f', 'body=x'],
    ['pr', 'merge', '1', '-R', 'PRO-Robotech/kaname', '--merge'], ['auth', 'token'],
    ['api', '--method', 'post', R], ['api', '--method', 'POST', R], ['api', '-XPOST', R],
    ['api', R, '--method', 'PATCH'], ['api', '--method', 'GET', '--method', 'POST', R],
    ['api', R, '--input', '/etc/hostname'], ['api', '-F', 'x=@/etc/passwd', R], ['api', '--field', 'a=b', R],
    ['api', '--raw-field', 'a=b', R], ['api', R, '--method', 'GET', '-f', 'x=y'],
    ['api', 'graphql', '-f', 'query=mutation{x}'], ['api', 'graphql'],
    ['API', R], ['PR', 'merge', '1'], ['co', '1'], ['repo', 'delete', 'PRO-Robotech/kaname', '--yes'],
    ['issue', 'comment', '1', '--body', 'x'], ['run', 'rerun', '1'], ['pr', 'view', '1', '--web'],
    ['api', '--jq', 'env', R], ['api', '--verbose', R], ['api', '--hostname', 'evil.example', R],
    ['api', '-H', 'X-HTTP-Method-Override: DELETE', R], ['api', 'https://evil.example/x'],
    ['api', 'repos/PRO-Robotech/kaname/../../user'], ['api', R + '\n--method\nPOST'],
]
REFUSED_RAW = ['[]', '{"argv": ["auth", "token"]}', '["api", 5]']
READS = [
    ['api', 'repos/PRO-Robotech/kaname/pulls/1'], ['api', 'rate_limit'],
    ['api', '--method', 'GET', R + '?per_page=100&page=1'],
    ['api', '--paginate', 'repos/PRO-Robotech/kaname/actions/runs?head_sha=' + 'a' * 40],
    ['pr', 'view', '1', '-R', 'PRO-Robotech/kaname', '--json', 'state,headRefOid'],
    ['pr', 'list', '-R', 'PRO-Robotech/kaname', '--json', 'number', '-L', '5'],
    ['issue', 'view', '1365', '-R', 'PRO-Robotech/kacho-workspace', '--json', 'state'],
    ['issue', 'list', '-R', 'PRO-Robotech/kacho-workspace'],
    ['run', 'view', '1', '-R', 'PRO-Robotech/kaname', '--json', 'conclusion'],
    ['run', 'list', '-R', 'PRO-Robotech/kaname', '-L', '3'],
]
# Двойник площадки по ВИДУ пути, как отвечает GitHub; неизвестный путь — 404 и строка в журнале.
GH = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SANDBOX_GH_LOG"
path="${@: -1}"; d="$SANDBOX_GH"
case "$path" in
    */contents/.github/workflows/*) cat "$d/contents.json" ;;
    */git/commits/*) cat "$d/commit.json" ;;
    */actions/workflows/*/runs\?*page=1) cat "$d/runs.json" ;;
    */actions/workflows/*/runs\?*) echo '{"total_count": 1, "workflow_runs": []}' ;;
    */actions/runs/*/attempts/*/jobs\?*page=1) cat "$d/jobs.json" ;;
    */actions/runs/*/attempts/*/jobs\?*) echo '{"total_count": 1, "jobs": []}' ;;
    */actions/jobs/*/logs) cat "$d/job.log" ;;
    repos/*/issues/*/comments\?*page=1) cat "$d/comments.json" 2> /dev/null || echo '[]' ;;
    repos/*/issues/*/comments\?*) echo '[]' ;;
    repos/PRO-Robotech/kacho-workspace/issues/5) cat "$d/issue.json" ;;
    *) echo '{"message": "Not Found", "status": "404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
'''


class Sandbox:
    def __init__(self, root):
        self.root = root
        self.ws = root / 'ws'
        self.trap, self.slot_log, self.gh_log = root / 'trap', root / 'slot.log', root / 'gh.log'
        self.leak = root / 'leak'
        for p in (self.trap, self.slot_log, self.gh_log, self.leak): p.write_text('')
        (self.ws / 'scripts' / 'remote-reader').mkdir(parents=True)
        for rel in COPY:
            dst = self.ws / 'scripts' / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HERE / rel, dst)
        shutil.copytree(HERE / 'rituals', self.ws / 'scripts' / 'rituals',
                        ignore=shutil.ignore_patterns('__pycache__'))
        self.write(self.ws / 'scripts' / 'heavy-slot.sh', SLOT)
        self.machine_bin = root / 'machine-bin'; self.machine_bin.mkdir()
        for name in ('python3', 'python'): self.write(self.machine_bin / name, TRAP)
        self.write(self.machine_bin / 'gh', GH)
        self.gh = root / 'gh'; self.gh.mkdir()
        # Файлы машины: на время Job двойник их прячет — в pod путей машины нет.
        self.files = root / 'machine'; self.files.mkdir()
        self.home = root / 'home'
        (self.ws / '.gitignore').write_text('tmp/*\n')
        self.git('init', '-q', '-b', '1365-sandbox')
        self.git('remote', 'add', 'origin', 'https://github.com/PRO-Robotech/kacho-workspace.git')
        self.commit('#1365 песочница')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    @staticmethod
    def write(path, text):
        path.write_text(text); path.chmod(0o755)

    def git(self, *args, cwd=None):
        return subprocess.run(['bash', '-c', '. "$1"; sandbox_git_home "$2" || exit; shift 2; sandbox_run git "$@"',
                               'sandbox', str(HERE / 'lib/sandbox-git-home.sh'), str(self.home),
                               '-C', str(cwd or self.ws), *args],
                              check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, message):
        self.git('add', '-A'); self.git('commit', '-qm', message)
        return self.git('rev-parse', 'HEAD')

    def env(self, machine=True, **extra):
        env = {k: v for k, v in os.environ.items()
               if k not in ('KUBERNETES_SERVICE_HOST', 'GITHUB_ACTIONS', 'KACHO_REMOTE_READER_POD', 'HEAVY_SLOT_P',
                            'KACHO_TASK', 'LANDING_PRECHECK_WS', 'RITUAL_REPO_DIR', 'RITUAL_GH',
                            'STAND_REPORT_GH', 'RITUAL_LEDGER_CLONES')}
        env.update(SANDBOX_TRAP=str(self.trap), SANDBOX_SLOT_LOG=str(self.slot_log),
                   SANDBOX_GH_LOG=str(self.gh_log), SANDBOX_GH=str(self.gh), SANDBOX_MACHINE=str(self.files),
                   SANDBOX_SECRET=SECRET, SANDBOX_LEAK=str(self.leak),
                   SANDBOX_POD_PATH=os.environ['PATH'], SANDBOX_POD_HOME=os.environ.get('HOME', '/'))
        if machine:
            # HOME машины — песочницы: коммит драйвера подписывается её корневым gitconfig.
            env.update(PATH=str(self.machine_bin) + ':' + os.environ['PATH'], HOME=str(self.home))
        else:
            env.update(KUBERNETES_SERVICE_HOST='sandbox', STAND_REPORT_GH=str(self.machine_bin / 'gh'),
                       RITUAL_GH=str(self.machine_bin / 'gh'))
        env.update(extra)
        return env

    def run(self, entry, *args, machine=True, cwd=None, **extra):
        return subprocess.run(['bash', str(self.ws / 'scripts' / entry), *args], cwd=str(cwd or self.ws),
                              env=self.env(machine, **extra), capture_output=True, text=True, timeout=600)

    def slots(self):
        return [line for line in self.slot_log.read_text().splitlines() if line]

    def mutate(self, rel, old, new):
        path = self.ws / 'scripts' / rel
        text = path.read_text()
        assert text.count(old) == 1, (rel, old)
        path.write_text(text.replace(old, new))
        self.commit('#1365 мутант')

    def residue(self):
        box = self.ws / 'tmp' / 'remote-reader'
        return sorted(p.name for p in box.iterdir()) if box.is_dir() else []


class Kaname:
    """Ожидаемое и принятый импорт kaname: unit, один шард и hosted image фикстуры ad86098."""

    def __init__(self, box, hosted=False):
        self.box = box
        raw = (FIX / 'image-workflow-native.yml').read_bytes()
        job = json.loads((FIX / 'image-job-native.json').read_text())
        definition = gate.job_definition(gate.common.load_workflow(raw), 'image')
        jobs = ['ci.yml:unit', 'ci.yml:integrationshard[shard=0]'] + (['docker-build.yml:image'] if hosted else [])
        self.exp = {'schema': 'kaname-stand-v1', 'repo': gate.REPO, 'head': job['head_sha'], 'tree': 'a' * 40,
                    'base': '955', 'ref': 'refs/heads/954', 'logical_jobs': ['ci.yml:unit', 'ci.yml:integration'],
                    'jobs': jobs, 'definitions': {
                        'ci.yml:unit': {'executor': 'external', 'matrix_index': None},
                        'ci.yml:integrationshard[shard=0]': {'executor': 'external', 'matrix_index': 0}}}
        if hosted:
            self.exp['definitions']['docker-build.yml:image'] = {
                'workflow_job': 'docker-build.yml:image', 'executor': 'github-hosted', 'matrix_index': None,
                'matrix_leg': None, 'definition': definition, 'definition_digest': gate.common.digest(definition),
                'workflow_digest': gate.common.digest(raw)}
        candidate = {'expected_digest': gate.common.digest(self.exp), 'unit': {'passed': 1},
                     'integration': {'shards': [{'passed': 1}]}}
        self.identity = gate.common.digest(candidate)
        registry = box.ws / 'tmp/operator-stand-registry/kaname-imports'
        registry.mkdir(parents=True)
        (registry / (self.identity + '.json')).write_text(json.dumps(
            {'candidate': candidate, 'review': {'candidate_digest': self.identity, 'verdict': 'accept',
                                                'blocking': []}}))
        self.expect = box.files / 'expect.json'; self.expect.write_text(json.dumps(self.exp))
        # Площадка: прогон push головы, задание image, его журнал — фикстуры ad86098.
        run = {'id': job['run_id'], 'run_number': 10, 'run_attempt': 1, 'head_sha': job['head_sha'],
               'event': 'push', 'head_branch': '954', 'repository': {'full_name': gate.REPO},
               'path': '.github/workflows/docker-build.yml', 'status': 'completed', 'conclusion': 'success'}
        g = box.gh
        (g / 'contents.json').write_text(json.dumps({'content': base64.b64encode(raw).decode()}))
        (g / 'commit.json').write_text(json.dumps({'tree': {'sha': 'a' * 40}}))
        (g / 'runs.json').write_text(json.dumps({'total_count': 1, 'workflow_runs': [run]}))
        (g / 'jobs.json').write_text(json.dumps({'total_count': 1, 'jobs': [job]}))
        shutil.copyfile(FIX / 'image-checkout-native.log', g / 'job.log')
        review = {'role': 'check-verifier', 'verdict': 'accept', 'blocking': [],
                  'expected_digest': gate.common.digest(self.exp), 'job': 'docker-build.yml:image',
                  'temporary_resources': 'job-vm-only', 'transitive_source_review': True}
        (box.files / 'review.json').write_text(json.dumps(review))
        self.reviews = box.files / 'reviews.json'
        self.reviews.write_text(json.dumps({'docker-build.yml:image': str(box.files / 'review.json')}))
        self.events = box.files / 'events.json'; self.events.write_text(json.dumps({'docker-build.yml:image': 'push'}))


class RemoteReader(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.box = Sandbox(Path(self.tmp.name))

    def tearDown(self):
        self.tmp.cleanup()

    def assertJob(self, result, slots=1):
        self.assertEqual(self.box.trap.read_text(), '', 'python3 исполнен на машине: ' + result.stderr)
        self.assertEqual(self.box.leak.read_text(), '', 'учётные данные машины уехали в Job')
        self.assertEqual(len(self.box.slots()), slots, result.stderr)
        if result.returncode == 0: self.assertEqual(self.box.residue(), [], 'журнал либо копия драйвера остались')
        self.assertFalse([p for p in self.box.residue() if not p.endswith('.log')], 'копия драйвера осталась')

    def test_kaname_external_check_runs_in_the_job(self):
        k = Kaname(self.box)
        direct = self.box.run('stand-report.sh', 'report', '--expect', str(k.expect), '--import-id', k.identity,
                              '--external-only', machine=False)
        self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
        report = self.box.files / 'report.json'; report.write_text(direct.stdout)
        machine = self.box.run('stand-report.sh', 'report', '--expect', str(k.expect), '--import-id', k.identity,
                               '--external-only')
        self.assertEqual((machine.returncode, json.loads(machine.stdout)), (0, json.loads(direct.stdout)),
                         machine.stderr)
        self.assertJob(machine)
        for prefix in (['check'], []):
            with self.subTest(prefix=prefix):
                got = self.box.run('stand-report.sh', *prefix, str(report), '--head', k.exp['head'],
                                   '--expect', str(k.expect), '--external-only')
                self.assertEqual(got.returncode, 0, got.stdout + got.stderr)
                self.assertEqual(json.loads(got.stdout)['verdict'], 'external-ready')
        wrong = self.box.run('stand-report.sh', 'check', str(report), '--head', k.exp['head'], '--expect', str(k.expect))
        self.assertEqual(wrong.returncode, 2, wrong.stdout + wrong.stderr)
        self.assertIn('wrong requested evidence stage', wrong.stdout)
        self.assertEqual(len(self.box.slots()), 4)
        self.assertEqual(self.box.trap.read_text(), '')

    def test_hosted_report_reads_github_captured_on_the_machine(self):
        k = Kaname(self.box, hosted=True)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity,
                '--hosted-reviews', str(k.reviews), '--events', str(k.events)]
        direct = self.box.run('stand-report.sh', *args, machine=False)
        self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
        self.box.gh_log.write_text('')
        machine = self.box.run('stand-report.sh', *args)
        self.assertEqual(machine.returncode, 0, machine.stdout + machine.stderr)
        self.assertEqual(json.loads(machine.stdout), json.loads(direct.stdout))
        self.assertNotIn('промахов GitHub', machine.stderr)
        self.assertJob(machine)
        # Снят ЖУРНАЛ задания — без него судья в Job промахивается, драйвер снимает промах вторым кругом.
        self.box.mutate('remote-reader.sh', 'gh_fetch api --allow-escape-sequences "repos/$repo/actions/jobs/$key/logs"',
                        ': "$key"')
        self.box.slot_log.write_text('')
        second = self.box.run('stand-report.sh', *args)
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(json.loads(second.stdout), json.loads(direct.stdout))
        self.assertIn('промахов GitHub 1 — сняты, прогон 2 из 3', second.stderr)
        self.assertJob(second, slots=2)
        self.box.mutate('remote-reader.sh', 'ROUNDS=3', 'ROUNDS=1')
        once = self.box.run('stand-report.sh', *args)
        self.assertEqual(once.returncode, 2, once.stdout + once.stderr)
        self.assertIn('producer command failed', once.stdout)

    def import_inputs(self):
        # Настоящий пакет импорта: исходные журналы и абсолютные пути машины внутри JSON.
        names = ['ci.yml:unit'] + [f'ci.yml:integrationshard[shard={i}]' for i in range(3)]
        exp = {'schema': 'kaname-stand-v1', 'repo': gate.REPO, 'head': 'a' * 40, 'tree': 'b' * 40,
               'base': '955', 'ref': 'refs/heads/954', 'jobs': names,
               'logical_jobs': ['ci.yml:unit', 'ci.yml:integration'],
               'definitions': {'ci.yml:unit': {'executor': 'external', 'matrix_index': None},
                               **{names[i + 1]: {'executor': 'external', 'matrix_index': i} for i in range(3)}}}
        expect = self.box.files / 'expect.json'; expect.write_text(json.dumps(exp))
        packet = build_packet(self.box.files, exp)
        candidate = gate.import_candidate(exp, packet)
        identity = gate.common.digest(candidate)
        review = self.box.files / 'review.json'
        review.write_text(json.dumps({'role': 'check-verifier', 'verdict': 'accept', 'blocking': [],
            'candidate_digest': identity, 'claims': ['source-and-command-binding', 'native-verdict-and-cleanup',
            'selected-package-partition', 'short-skip-applicability']}))
        record = self.box.ws / 'tmp/operator-stand-registry/kaname-imports' / (identity + '.json')
        return exp, expect, packet, review, candidate, identity, record

    def test_register_import_returns_its_registry_record(self):
        exp, expect, packet, review, candidate, identity, record = self.import_inputs()
        got = self.box.run('stand-report.sh', 'register-import', '--expect', str(expect), '--packet', str(packet),
                           '--review', str(review))
        self.assertEqual(got.returncode, 0, got.stdout + got.stderr)
        self.assertEqual(json.loads(got.stdout), {'import_id': identity})
        self.assertJob(got)
        self.assertEqual(json.loads(record.read_text())['candidate'], candidate)
        # Separate originless pods must retain the accepted identity through report and check.
        report = self.box.run('stand-report.sh', 'report', '--expect', str(expect), '--import-id', identity,
                              '--external-only')
        self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
        report_file = self.box.files / 'report.json'; report_file.write_text(report.stdout)
        checked = self.box.run('stand-report.sh', 'check', str(report_file), '--expect', str(expect),
                               '--head', exp['head'], '--pr-base', '955', '--external-only')
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
    def register(self, expect, packet, review, **env):
        return self.box.run('stand-report.sh', 'register-import', '--expect', str(expect),
                            '--packet', str(packet), '--review', str(review), **env)

    def test_register_identical_record_refuses_without_mutation(self):
        _, expect, packet, review, _, _, record = self.import_inputs()
        first = self.register(expect, packet, review)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        before = record.read_bytes()
        denied = self.register(expect, packet, review)
        self.assertEqual(denied.returncode, 2, denied.stdout + denied.stderr)
        self.assertIn('[Errno 17] File exists:', denied.stdout + denied.stderr)
        self.assertEqual(record.read_bytes(), before)

    def test_register_conflicting_record_refuses_without_mutation(self):
        _, expect, packet, review, _, _, record = self.import_inputs()
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_bytes(b'{"tampered": true}')
        denied = self.register(expect, packet, review)
        self.assertEqual(denied.returncode, 2, denied.stdout + denied.stderr)
        self.assertIn('[Errno 17] File exists:', denied.stdout + denied.stderr)
        self.assertEqual(record.read_bytes(), b'{"tampered": true}')

    def export_failure(self, tool):
        _, expect, packet, review, _, _, record = self.import_inputs()
        failed = self.register(expect, packet, review, SANDBOX_EXPORT_FAIL=tool)
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        self.assertFalse(record.exists(), tool)
        restored = self.register(expect, packet, review)
        self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)
        self.assertTrue(record.is_file())

    def test_register_tar_export_failure(self):
        self.export_failure('tar')

    def test_register_find_export_failure(self):
        self.export_failure('find')

    def test_register_cp_export_failure(self):
        self.export_failure('cp')

    def test_register_unshipped_packet_refuses(self):
        _, expect, packet, review, _, _, record = self.import_inputs()
        self.box.mutate('remote-reader.sh', '--packet|--hosted-reviews) a="$(ship "$a")"',
                        '--hosted-reviews) a="$(ship "$a")"')
        blind = self.register(expect, packet, review)
        self.assertEqual(blind.returncode, 2, blind.stdout + blind.stderr)
        self.assertFalse(record.exists())

    def archived_reader(self):
        archive = self.box.root / 'archive'
        archive.mkdir()
        # Рецепт «ЗАПУСК»: архив scripts/ из origin/main воркспейса привязки.
        payload = subprocess.check_output(['git', '-C', str(self.box.ws), 'archive', 'origin/main', 'scripts'])
        subprocess.run(['tar', '-xf', '-', '-C', str(archive)], input=payload, check=True)
        k = Kaname(self.box)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity, '--external-only']
        def run(**env):
            return subprocess.run(['bash', str(archive / 'scripts/stand-report.sh'), *args],
                                  cwd=archive, env=self.box.env(**env), capture_output=True,
                                  text=True, timeout=600)
        return archive, run

    def test_archived_reader_uses_explicit_source(self):
        archive, run = self.archived_reader()
        self.assertFalse((archive / '.git').exists())
        result = run(LANDING_PRECHECK_WS=str(self.box.ws))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertJob(result)
        self.assertEqual(self.box.trap.read_text(), '')

    def test_archived_reader_refuses_unbound_or_foreign_root(self):
        _, run = self.archived_reader()
        for env in ({}, {'LANDING_PRECHECK_WS': str(self.box.ws / 'scripts')}):
            result = run(**env)
            self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        for origin in ('https://example.invalid/foreign.git',
                       'https://user:password@github.com/PRO-Robotech/kacho-workspace.git'):
            self.box.git('remote', 'set-url', 'origin', origin)
            result = run(LANDING_PRECHECK_WS=str(self.box.ws))
            self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual(self.box.slots(), [])
        self.assertEqual(self.box.gh_log.read_text(), '')

    def test_archived_reader_binds_entire_snapshot(self):
        archive, run = self.archived_reader()
        target = archive / 'scripts/kaname-stand.py'
        original = target.read_bytes()
        for mutation in ('content', 'missing', 'extra', 'mode', 'symlink'):
            with self.subTest(mutation=mutation):
                extra = archive / 'scripts/unexpected.py'
                if mutation == 'content': target.write_bytes(original + b'\n# changed judge\n')
                elif mutation == 'missing': target.unlink()
                elif mutation == 'extra': extra.write_text('# extra\n')
                elif mutation == 'mode': target.chmod(target.stat().st_mode ^ 0o111)
                elif mutation == 'symlink':
                    target.unlink(); target.symlink_to('operator-stand.py')
                result = run(LANDING_PRECHECK_WS=str(self.box.ws))
                self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
                self.assertIn('не совпадает с origin/main', result.stderr)
                if target.is_symlink() or target.exists(): target.unlink()
                target.write_bytes(original)
                target.chmod((self.box.ws / 'scripts/kaname-stand.py').stat().st_mode)
                extra.unlink(missing_ok=True)
        self.assertEqual(self.box.slots(), [])
        self.assertEqual(self.box.gh_log.read_text(), '')
        lawful = run(LANDING_PRECHECK_WS=str(self.box.ws))
        self.assertEqual(lawful.returncode, 0, lawful.stdout + lawful.stderr)

    def test_archived_reader_refuses_dirty_source(self):
        _, run = self.archived_reader()
        target = self.box.ws / 'scripts/remote-reader.sh'
        target.write_text(target.read_text() + '\n# uncommitted\n')
        result = run(LANDING_PRECHECK_WS=str(self.box.ws))
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual(self.box.slots(), [])
        self.assertEqual(self.box.gh_log.read_text(), '')

    def test_archived_reader_ignores_enclosing_foreign_git(self):
        archive, run = self.archived_reader()
        self.box.git('init', '-q', cwd=archive)
        self.box.git('remote', 'add', 'origin', 'https://example.invalid/foreign.git', cwd=archive)
        result = run(LANDING_PRECHECK_WS=str(self.box.ws))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertJob(result)

    def test_archived_reader_refuses_mixed_committed_head(self):
        # Архив вырезан до того, как origin/main привязки ушёл вперёд: Job исполнил бы новый судья.
        _, run = self.archived_reader()
        target = self.box.ws / 'scripts/kaname-stand.py'
        target.write_text(target.read_text() + '\n# new committed judge\n')
        self.box.commit('#1365 new judge snapshot')
        self.box.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        result = run(LANDING_PRECHECK_WS=str(self.box.ws))
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertIn('не совпадает с origin/main', result.stderr)
        self.assertEqual(self.box.slots(), [])
        self.assertEqual(self.box.gh_log.read_text(), '')

    def test_workspace_origin_binding_is_closed(self):
        k = Kaname(self.box)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity, '--external-only']
        for origin in ('https://example.invalid/foreign.git',
                       'https://user:password@github.com/PRO-Robotech/kacho-workspace.git'):
            before = len(self.box.slots())
            self.box.git('remote', 'set-url', 'origin', origin)
            denied = self.box.run('stand-report.sh', *args)
            self.assertEqual(denied.returncode, 64, denied.stdout + denied.stderr)
            self.assertEqual(len(self.box.slots()), before)
        canonical = 'https://github.com/PRO-Robotech/kacho-workspace.git'
        self.box.git('remote', 'set-url', 'origin', canonical)
        invalid_root = self.box.run('stand-report.sh', *args,
                                    LANDING_PRECHECK_WS=str(self.box.ws / 'scripts'))
        self.assertEqual(invalid_root.returncode, 64, invalid_root.stderr)
        for extra in ({'SANDBOX_ORIGIN_BINDING': 'missing'}, {'SANDBOX_ORIGIN_BINDING': 'foreign'},
                      {'SANDBOX_ORIGIN_BINDING': 'credentials'},
                      {'SANDBOX_POD_ORIGIN': 'https://example.invalid/foreign.git'}):
            denied = self.box.run('stand-report.sh', *args, **extra)
            self.assertNotEqual(denied.returncode, 0, denied.stdout + denied.stderr)
        for extra in ({}, {'SANDBOX_POD_ORIGIN': canonical}, {'LANDING_PRECHECK_WS': str(self.box.ws)}):
            lawful = self.box.run('stand-report.sh', *args, **extra)
            self.assertEqual(lawful.returncode, 0, lawful.stdout + lawful.stderr)
        self.assertEqual(self.box.trap.read_text(), '')

    def test_registry_stages_run_in_a_job_clone_without_origin(self):
        # Клон Job настоящего маршрута (remote-heavy/run.sh: init + bundle) origin не несёт, а судья
        # реестра сверяет адрес origin воркспейса (находка kaname#881): pod заводит его каноническим адресом
        # rr/workspace-origin (двойник слота origin не заводит, как настоящий маршрут).
        exp = {'schema': 'kaname-stand-v1', 'repo': gate.REPO, 'head': 'a' * 40, 'tree': 'b' * 40,
               'definitions': {str(i): {'matrix_index': i} for i in range(3)}}
        expect = self.box.files / 'expect.json'; expect.write_text(json.dumps(exp))
        packet = build_packet(self.box.files, exp)
        identity = gate.common.digest(gate.import_candidate(exp, packet))
        review = self.box.files / 'review.json'
        review.write_text(json.dumps({'role': 'check-verifier', 'verdict': 'accept', 'blocking': [],
            'candidate_digest': identity, 'claims': ['source-and-command-binding', 'native-verdict-and-cleanup',
            'selected-package-partition', 'short-skip-applicability']}))
        record = self.box.ws / 'tmp/operator-stand-registry/kaname-imports' / (identity + '.json')
        args = ['register-import', '--expect', str(expect), '--packet', str(packet), '--review', str(review)]
        got = self.box.run('stand-report.sh', *args)
        self.assertEqual((got.returncode, json.loads(got.stdout or '{}')), (0, {'import_id': identity}),
                         got.stdout + got.stderr)
        self.assertTrue(record.exists())
        self.assertJob(got)
        # Мутант: pod origin не заводит — судья реестра отказывает (как на настоящем маршруте).
        record.unlink()
        self.box.mutate('remote-reader/pod.sh', 'git -C "$TOPP" remote add origin "$workspace_origin" || reader_fail',
                        ': || reader_fail')
        blind = self.box.run('stand-report.sh', *args)
        self.assertEqual(blind.returncode, 2, blind.stdout + blind.stderr)
        self.assertFalse(record.exists())

    def test_pr_body_runs_in_the_job_with_the_tracker_captured(self):
        g = self.box.gh
        (g / 'issue.json').write_text(json.dumps({'number': 5, 'state': 'open', 'title': 'задача песочницы'}))
        (self.box.ws / 'lane.txt').write_text('правка\n')
        head = self.box.commit('#5 правка песочницы')
        args = ['PRO-Robotech/kacho-workspace', 'origin/main', head]
        self.box.git('update-ref', 'refs/remotes/origin/5-lane', head)
        direct = self.box.run('pr-body.sh', *args, machine=False, RITUAL_REPO_DIR=str(self.box.ws))
        self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
        self.assertIn('#5', direct.stdout)
        machine = self.box.run('pr-body.sh', *args, RITUAL_REPO_DIR=str(self.box.ws))
        self.assertEqual((machine.returncode, machine.stdout), (0, direct.stdout), machine.stderr)
        self.assertNotIn('промахов GitHub', machine.stderr)
        self.assertJob(machine)
        self.box.git('update-ref', '-d', 'refs/remotes/origin/5-lane')
        unpublished = self.box.run('pr-body.sh', *args, RITUAL_REPO_DIR=str(self.box.ws))
        self.assertEqual(unpublished.returncode, 64, unpublished.stderr)
        self.assertIn('не на origin', unpublished.stderr)

    def test_pod_named_calls_outside_the_read_list_are_refused(self):
        # Промах называет pod — значит, его текст пишет то, что исполнилось в Job. Машина исполняет
        # своим токеном лишь закрытый перечень чтений: прочее — строка отказа, вызова gh нет.
        k = Kaname(self.box, hosted=True)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity,
                '--hosted-reviews', str(k.reviews), '--events', str(k.events)]
        direct = self.box.run('stand-report.sh', *args, machine=False)
        self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
        # Контроль: настоящий промах (журнал задания) снимается — законное чтение проходит.
        self.box.mutate('remote-reader.sh', 'gh_fetch api --allow-escape-sequences "repos/$repo/actions/jobs/$key/logs"',
                        ': "$key"')
        self.box.gh_log.write_text('')
        lawful = self.box.run('stand-report.sh', *args)
        self.assertEqual((lawful.returncode, json.loads(lawful.stdout)), (0, json.loads(direct.stdout)), lawful.stderr)
        self.assertIn('промахов GitHub 1 — сняты', lawful.stderr)
        base = set(self.box.gh_log.read_text().splitlines())
        # Pod дописывает к промахам вызовы, которых читатель не делал.
        forge = self.box.root / 'forge.jsonl'
        forge.write_text(''.join(json.dumps(a) + '\n' for a in REFUSED + READS) + ''.join(r + '\n' for r in REFUSED_RAW))
        self.box.mutate('remote-reader/pod.sh', 'cp -- "$RR/gh/misses" "$box/miss"',
                        'cat -- "$RR/gh/misses" "$SANDBOX_FORGE" > "$box/miss"')
        self.box.gh_log.write_text(''); self.box.slot_log.write_text('')
        got = self.box.run('stand-report.sh', *args, SANDBOX_FORGE=str(forge))
        self.assertEqual((got.returncode, json.loads(got.stdout)), (0, json.loads(direct.stdout)), got.stderr)
        self.assertJob(got, slots=2)
        calls = set(self.box.gh_log.read_text().splitlines())
        self.assertEqual(calls - base, {' '.join(a) for a in READS}, 'исполнено сверх законных чтений')
        refused = [line for line in got.stderr.splitlines() if 'промах вне перечня чтений GitHub не снимается' in line]
        self.assertEqual(len(refused), len(REFUSED) + len(REFUSED_RAW), got.stderr)
        # Мутант: перечень снят (всякий промах — «чтение») — запись и выдача токена исполнены.
        self.box.mutate('remote-reader.sh', 'gh_read_ok() {  # gh_read_ok', 'gh_read_ok() { return 0; }\nunused_read_ok() {  #')
        self.box.gh_log.write_text('')
        blind = self.box.run('stand-report.sh', *args, SANDBOX_FORGE=str(forge))
        self.assertIn('auth token', self.box.gh_log.read_text().splitlines(), blind.stderr)

    def test_credentials_of_the_machine_do_not_ship(self):
        secret = self.box.home / '.config' / 'gh' / 'hosts.yml'
        secret.parent.mkdir(parents=True); secret.write_text('oauth_token: ' + SECRET + '\n')
        k = Kaname(self.box, hosted=True)
        # Довод входа — сразу 64, Job не создаётся.
        top = self.box.run('stand-report.sh', 'report', '--expect', str(k.expect), '--import-id', k.identity,
                           '--hosted-reviews', str(secret), '--events', str(k.events))
        self.assertEqual(top.returncode, 64, top.stderr)
        self.assertEqual(self.box.slots(), [])
        # Путь внутри JSON-входа — не переносится, строка остаётся, Job идёт без него.
        reviews = json.loads(k.reviews.read_text()); reviews['leak'] = str(secret)
        k.reviews.write_text(json.dumps(reviews))
        inner = self.box.run('stand-report.sh', 'report', '--expect', str(k.expect), '--import-id', k.identity,
                             '--hosted-reviews', str(k.reviews), '--events', str(k.events))
        self.assertIn('хранилище учётных данных машины', inner.stderr)
        self.assertEqual(len(self.box.slots()), 1, inner.stderr)
        self.assertEqual(self.box.leak.read_text(), '', 'учётные данные машины уехали в Job')
        # Адрес origin копии expect — без userinfo.
        co, head = self.kaname_checkout()
        self.box.git('remote', 'set-url', 'origin', 'https://x-access-token:' + SECRET + '@github.com/PRO-Robotech/kaname.git', cwd=co)
        self.box.run('stand-report.sh', 'expect', '--checkout', str(co), '--head', head, '--base', 'origin/954',
                     '--draft', 'false')
        self.assertEqual(len(self.box.slots()), 2)
        self.assertEqual(self.box.leak.read_text(), '', 'userinfo адреса origin уехал в Job')
        # Мутант: адрес без очистки — метка в дереве Job (проба читает свой предмет).
        self.box.mutate('remote-reader.sh', "no_userinfo() { sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\\1#'; }",
                        'no_userinfo() { cat; }')
        self.box.run('stand-report.sh', 'expect', '--checkout', str(co), '--head', head, '--base', 'origin/954',
                     '--draft', 'false')
        self.assertNotEqual(self.box.leak.read_text(), '', 'проба утечки слепа')

    def test_stream_is_deduplicated_and_a_gap_is_refused(self):
        k = Kaname(self.box)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity, '--external-only']
        lawful = self.box.run('stand-report.sh', *args)
        self.assertEqual(lawful.returncode, 0, lawful.stderr)
        dup = self.box.run('stand-report.sh', *args, SANDBOX_STREAM='dup')
        self.assertEqual((dup.returncode, dup.stdout), (0, lawful.stdout), dup.stderr)
        drop = self.box.run('stand-report.sh', *args, SANDBOX_STREAM='drop')
        self.assertEqual((drop.returncode, drop.stdout), (70, ''), drop.stderr)
        busy = self.box.run('stand-report.sh', *args, SANDBOX_SLOT_RC='74')
        self.assertEqual((busy.returncode, busy.stdout), (74, ''), busy.stderr)
        self.assertIn('строки кода читателя нет', busy.stderr)
        self.assertEqual(self.box.trap.read_text(), '')

    def test_refusals_before_the_job(self):
        k = Kaname(self.box)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity, '--external-only']
        (self.box.ws / 'scripts' / 'kaname-stand.py').write_text('# правка вне коммита\n')
        dirty = self.box.run('stand-report.sh', *args)
        self.assertEqual(dirty.returncode, 64, dirty.stderr)
        self.box.git('checkout', '--', 'scripts/kaname-stand.py')
        folder = self.box.run('stand-report.sh', *args, '--packet', str(self.box.root))
        self.assertEqual(folder.returncode, 64, folder.stderr)
        self.box.git('checkout', '-q', '-b', 'sandbox-no-task')
        untasked = self.box.run('stand-report.sh', *args)
        self.assertEqual(untasked.returncode, 64, untasked.stderr)
        tasked = self.box.run('stand-report.sh', *args, KACHO_TASK='1365')
        self.assertEqual(tasked.returncode, 0, tasked.stderr)
        self.assertEqual(len(self.box.slots()), 1)
        self.assertEqual(self.box.trap.read_text(), '')

    def test_where_the_entry_stays_here(self):
        k = Kaname(self.box)
        args = ['report', '--expect', str(k.expect), '--import-id', k.identity, '--external-only']
        for marker in ({'KUBERNETES_SERVICE_HOST': 'x'}, {'GITHUB_ACTIONS': 'true'}, {'KACHO_REMOTE_READER_POD': '1'},
                       {'HEAVY_SLOT_P': '/slot'}):
            with self.subTest(marker=marker):
                real = {'PATH': os.environ['PATH'], 'HOME': os.environ.get('HOME', '/'), **marker}
                here = self.box.run('stand-report.sh', *args, **real)
                self.assertEqual(here.returncode, 0, here.stderr)
                body = self.box.run('pr-body.sh', 'PRO-Robotech/kacho-workspace', 'origin/main', 'HEAD',
                                    RITUAL_REPO_DIR=str(self.box.ws), **real)
                self.assertNotIn('remote-reader', body.stderr)
        self.assertEqual(self.box.slots(), [])
        # ГРАНИЦА (решение диспетчера ws#1365 их не называет): копия не kaname — вход здесь.
        boundary = self.box.run('stand-report.sh', 'expect', '--checkout', str(self.box.ws), '--head', '0' * 40)
        self.assertEqual(self.box.slots(), [])
        self.assertNotEqual(boundary.returncode, 0)

    def kaname_checkout(self):
        co = self.box.files / 'kaname'
        wf = co / '.github/workflows'; wf.mkdir(parents=True)
        for name, fixture in [('ci.yml', 'ci-workflow-native.yml'), ('e2e-newman.yml', 'e2e-workflow-matrix-native.yml'),
                              ('docker-build.yml', 'image-workflow-native.yml'),
                              ('pr-rule.yml', 'pr-rule-workflow-native.yml')]:
            shutil.copyfile(FIX / fixture, wf / name)
        self.box.git('init', '-q', '-b', '954-sandbox', cwd=co)
        self.box.git('remote', 'add', 'origin', 'https://github.com/PRO-Robotech/kaname.git', cwd=co)
        self.box.git('add', '-A', cwd=co); self.box.git('commit', '-qm', 'источник kaname', cwd=co)
        self.box.git('update-ref', 'refs/remotes/origin/954', 'HEAD', cwd=co)
        return co, self.box.git('rev-parse', 'HEAD', cwd=co)

    def test_kaname_expect_ships_the_checkout(self):
        co, head = self.kaname_checkout()
        args = ['expect', '--checkout', str(co), '--head', head, '--base', 'origin/954', '--draft', 'false']
        direct = self.box.run('stand-report.sh', *args, machine=False)
        self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
        self.assertEqual(len(json.loads(direct.stdout)['jobs']), 9)
        machine = self.box.run('stand-report.sh', *args)
        self.assertEqual((machine.returncode, json.loads(machine.stdout)), (0, json.loads(direct.stdout)), machine.stderr)
        self.assertJob(machine)
        # Правка вне коммита: expect на машине судил бы её, клон Job — нет; отказ до Job.
        (co / 'untracked.txt').write_text('x\n')
        dirty = self.box.run('stand-report.sh', *args)
        self.assertEqual(dirty.returncode, 64, dirty.stderr)
        self.assertEqual(len(self.box.slots()), 1)
        (co / 'untracked.txt').unlink()
        # Ветка копии доводом --ref: без него клон Job (отсоединённый) ref не вывел бы.
        self.box.mutate('remote-reader.sh', '|| EXTRA=(--ref "$ref")', '|| EXTRA=()')
        blind = self.box.run('stand-report.sh', *args)
        self.assertEqual(blind.returncode, 2, blind.stdout + blind.stderr)
        self.assertEqual(self.box.trap.read_text(), '')


class DaemonReaders(unittest.TestCase):
    """Читатели демона вливания (ws#1365): предпроверка целиком, формы ci-read и branch-audit — Job-ом."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.box = Sandbox(Path(self.tmp.name))
        for rel in DAEMON_COPY:
            dst = self.box.ws / 'scripts' / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HERE / rel, dst)
        self.box.commit('#1365 читатели демона')
        self.box.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    def tearDown(self):
        self.tmp.cleanup()

    def assertJob(self, result, slots=1):
        RemoteReader.assertJob(self, result, slots)

    def lp_case(self):
        """Случай kacho#3036 (landing-precheck-fixtures) и двойник площадки landing-precheck-inject.sh."""
        case = self.box.files / 'case'; case.mkdir()
        pull = json.loads((LPFIX / 'pull.json').read_text())
        commits = json.loads((LPFIX / 'commits.json').read_text())
        runs = json.loads((LPFIX / 'check-runs.json').read_text())
        pull['state'] = 'open'; pull['body'] = pull['body'].replace(' вместе с #3028', '')
        head = pull['head']['sha']
        (case / 'head').write_text(head + '\n')
        (case / 'pull.json').write_text(json.dumps(pull))
        shutil.copyfile(LPFIX / 'commits.json', case / 'commits.json')
        shutil.copyfile(LPFIX / 'check-runs.json', case / 'check-runs.json')
        for n in (2878, 2885, 2690, 2707):
            sha = next(c['sha'] for c in commits if f'#{n}' in c['commit']['message'].split('\n')[0])
            (case / f'comments-{n}.json').write_text(json.dumps([{'body': f'сдача\nDoD-proof @{sha[:12]}'}]))
        (case / 'comments-3020.json').write_text(json.dumps([{'body': f'DoD-proof @{head}'}]))
        (case / 'prview.json').write_text(json.dumps({
            'state': 'OPEN', 'baseRefName': pull['base']['ref'],
            'baseRefOid': pull['base'].get('sha') or commits[0]['parents'][0]['sha'], 'headRefName': pull['head']['ref'],
            'headRefOid': head, 'mergeStateStatus': 'CLEAN', 'body': pull['body'], 'closingIssuesReferences': [],
            'statusCheckRollup': [{'name': r['name'], 'conclusion': (r.get('conclusion') or '').upper()}
                                  for r in runs['check_runs']]}))
        (case / 'protection.json').write_text(json.dumps(
            {'required_status_checks': {'contexts': sorted({r['name'] for r in runs['check_runs']})}}))
        text = (HERE / 'landing-precheck-inject.sh').read_text().split("cat > \"$W/gh\" <<'GH'\n", 1)[1]
        double = text.split('\nGH\n', 1)[0] + '\n'
        self.box.write(self.box.machine_bin / 'gh', double)
        pod_bin = self.box.root / 'pod-bin'; pod_bin.mkdir()
        self.box.write(pod_bin / 'gh', double)
        return case, pod_bin

    def test_landing_precheck_runs_in_the_job(self):
        case, pod_bin = self.lp_case()
        args = ['PRO-Robotech/kacho', '3036']
        direct = self.box.run('landing-precheck.sh', *args, machine=False, FAKE=str(case),
                              PATH=str(pod_bin) + ':' + os.environ['PATH'])
        self.assertIn(direct.returncode, (0, 1), direct.stdout + direct.stderr)
        self.assertIn('CENSUS\tmerge-readiness: код 0', direct.stdout, direct.stdout)
        machine = self.box.run('landing-precheck.sh', *args, FAKE=str(case))
        self.assertEqual(lp_out(machine), lp_out(direct), machine.stderr)
        self.assertNotIn('промахов GitHub', machine.stderr)
        self.assertJob(machine)
        # План без check-runs предпроверки: промах снимается вторым кругом, вывод тот же.
        self.box.mutate('remote-reader.sh',
                        '    pages_q check_runs "repos/$repo/commits/$head/check-runs?per_page=100&filter=latest&page=" ""\n', '')
        self.box.slot_log.write_text('')
        second = self.box.run('landing-precheck.sh', *args, FAKE=str(case))
        self.assertEqual(lp_out(second), lp_out(direct), second.stderr)
        self.assertIn('промахов GitHub 1 — сняты, прогон 2 из 4', second.stderr)
        self.assertJob(second, slots=2)

    def test_landing_precheck_from_the_recipe_archive(self):
        case, pod_bin = self.lp_case()
        args = ['PRO-Robotech/kacho', '3036']
        direct = self.box.run('landing-precheck.sh', *args, machine=False, FAKE=str(case),
                              PATH=str(pod_bin) + ':' + os.environ['PATH'])
        # Рецепт «ЗАПУСК»: scripts/ из origin/main — каталог вне копии; LANDING_PRECHECK_WS — воркспейс.
        arch = self.box.root / 'wsg'; arch.mkdir()
        subprocess.run(f'git -C "{self.box.ws}" archive origin/main scripts | tar -x -C "{arch}"',
                       shell=True, check=True)
        got = subprocess.run(['bash', str(arch / 'scripts' / 'landing-precheck.sh'), *args], cwd='/',
                             env=self.box.env(FAKE=str(case), LANDING_PRECHECK_WS=str(self.box.ws), KACHO_TASK='1365'),
                             capture_output=True, text=True, timeout=600)
        self.assertEqual(lp_out(got), lp_out(direct), got.stderr)
        self.assertJob(got)
        # Архив разошёлся с origin/main — Job исполнил бы не вызванное: 64 до Job.
        (arch / 'scripts' / 'merge-readiness.sh').write_text('#!/usr/bin/env bash\nexit 0\n')
        drift = subprocess.run(['bash', str(arch / 'scripts' / 'landing-precheck.sh'), *args], cwd='/',
                               env=self.box.env(FAKE=str(case), LANDING_PRECHECK_WS=str(self.box.ws), KACHO_TASK='1365'),
                               capture_output=True, text=True, timeout=600)
        self.assertEqual(drift.returncode, 64, drift.stderr)
        self.assertIn('не совпадает с origin/main', drift.stderr)
        self.assertEqual(len(self.box.slots()), 1)

    def test_ci_read_job_names_run_in_the_job(self):
        wf = self.box.files / 'wf.yml'
        wf.write_text('jobs:\n  a:\n    name: сборка\n  b:\n    name: "шард ${{ matrix.n }}"\n'
                      '    strategy:\n      matrix:\n        n: [1, 2]\n')
        present = self.box.files / 'present.txt'; present.write_text('сборка\nшард 1\n')
        direct = self.box.run('ci-read.sh', '--job-names', str(wf), str(present), machine=False)
        self.assertEqual((direct.returncode, direct.stdout), (0, 'не появились 1 из 3: шард 2'), direct.stderr)
        machine = self.box.run('ci-read.sh', '--job-names', str(wf), str(present))
        self.assertEqual((machine.returncode, machine.stdout), (0, direct.stdout), machine.stderr)
        self.assertJob(machine)
        # Снимок демона (--from-state) лежит на машине — Job его не видит: 64 до Job.
        refused = subprocess.run(['bash', str(self.box.ws / 'scripts/remote-reader.sh'), 'scripts/ci-read.sh',
                                  'PRO-Robotech/kacho', '1', '--from-state'], cwd=str(self.box.ws), env=self.box.env(),
                                 capture_output=True, text=True, timeout=60)
        self.assertEqual(refused.returncode, 64, refused.stderr)
        self.assertIn('--from-state', refused.stderr)
        self.assertEqual(len(self.box.slots()), 1)

    def test_ci_read_full_form_runs_in_the_job(self):
        """Полная форма ci-read — вход полос, которым ci-read на машине не положен (ws#1383).

        Захват kacho#3296 (ci-read-fixtures): вытесненный прогон — чтение файла workflow на голове и
        разбор его имён (--job-names) в pod; двойник площадки — gh-twin.sh проб ci-read."""
        fx = self.box.files / 'ci'
        shutil.copytree(HERE / 'ci-read-fixtures' / 'kacho-3296', fx)
        self.box.write(self.box.machine_bin / 'gh', (HERE / 'ci-read-fixtures' / 'gh-twin.sh').read_text())
        args = ['PRO-Robotech/kacho', '3296']
        direct = self.box.run('ci-read.sh', *args, machine=False, CI_READ_GH=str(self.box.machine_bin / 'gh'),
                              CI_READ_FX=str(fx))
        self.assertIn(direct.returncode, (1, 3), direct.stdout + direct.stderr)
        self.assertRegex(direct.stdout, r'REASON\tRUN-DISPLACED\tproduction-posture .*не появились 3 из 3')
        machine = self.box.run('remote-reader.sh', 'scripts/ci-read.sh', *args, CI_READ_FX=str(fx))
        self.assertEqual(lp_out(machine), lp_out(direct), machine.stderr)
        self.assertNotIn('промахов GitHub', machine.stderr)
        self.assertJob(machine)
        # План без статуса коммита: промах снимается вторым кругом, вывод тот же.
        self.box.mutate('remote-reader.sh', '    gh_fetch api "repos/$repo/commits/$head/status"\n', '')
        self.box.slot_log.write_text('')
        second = self.box.run('remote-reader.sh', 'scripts/ci-read.sh', *args, CI_READ_FX=str(fx))
        self.assertEqual(lp_out(second), lp_out(direct), second.stderr)
        self.assertIn('промахов GitHub 1 — сняты, прогон 2 из 3', second.stderr)
        self.assertJob(second, slots=2)

    def audited(self):
        """Репозиторий переписи: голый origin, ствол, генератор с постоянным ответом (как vault-index)."""
        origin = self.box.root / 'origin.git'
        self.box.git('init', '-q', '--bare', '-b', 'main', str(origin), cwd=self.box.root)
        repo = self.box.root / 'audited'
        self.box.git('clone', '-q', str(origin), str(repo), cwd=self.box.root)
        self.box.git('symbolic-ref', 'HEAD', 'refs/heads/main', cwd=repo)
        (repo / 'scripts/vault-index').mkdir(parents=True)
        (repo / 'scripts/vault-index/generate.py').write_text(
            'import sys\nif "--outputs" in sys.argv:\n    print("machine/INDEX.md")\n')
        (repo / 'machine').mkdir(); (repo / 'machine/INDEX.md').write_text('собрано\n')
        self.box.git('add', '-A', cwd=repo); self.box.git('commit', '-qm', 'ствол', cwd=repo)
        self.box.git('push', '-q', 'origin', 'main', cwd=repo)
        return repo

    def test_branch_audit_generator_answer_by_job_then_memory(self):
        repo = self.audited()
        cache = self.box.root / 'cache'
        knobs = dict(XDG_CACHE_HOME=str(cache), BRANCH_AUDIT_NO_FETCH='1', BRANCH_AUDIT_NO_ACCUM='1',
                     BRANCH_AUDIT_FRESH_MIN='0')
        first = self.box.run('branch-audit.sh', str(repo), **knobs)
        self.assertIn('генераторов спрошено 1, без ключа --outputs 0; машинно собираемых путей 1', first.stdout,
                      first.stdout + first.stderr)
        self.assertIn('ответ генераторов на машине — Job внешнего кластера', first.stdout)
        self.assertJob(first)
        second = self.box.run('branch-audit.sh', str(repo), **knobs)
        self.assertIn('машинно собираемых путей 1', second.stdout, second.stdout + second.stderr)
        self.assertIn('ответ генераторов на машине — память по отпечатку текста', second.stdout)
        self.assertEqual(len(self.box.slots()), 1, 'второй прогон ходил в Job: память по отпечатку не читалась')
        # Текст генератора сменился — отпечаток иной, ответ снова Job-ом.
        (repo / 'scripts/vault-index/generate.py').write_text(
            'import sys\nif "--outputs" in sys.argv:\n    print("machine/OTHER.md")\n')
        third = self.box.run('branch-audit.sh', str(repo), **knobs)
        self.assertIn('ответ генераторов на машине — Job внешнего кластера', third.stdout, third.stdout + third.stderr)
        self.assertEqual(len(self.box.slots()), 2)
        # Маршрут не исполнился (слот занят) — «не спрошено», а не «без ключа».
        (repo / 'scripts/vault-index/generate.py').write_text('import sys\nprint("x")\n')
        busy = self.box.run('branch-audit.sh', str(repo), SANDBOX_SLOT_RC='74', **knobs)
        self.assertIn('без ключа --outputs 0', busy.stdout, busy.stdout + busy.stderr)
        self.assertIn('НЕ СПРОШЕНО 1 генераторов', busy.stdout)
        self.assertEqual(self.box.trap.read_text(), '')


def build_packet(root, exp):
    """Пакет imported-native-remote-heavy из настоящих журналов шардов — как в kaname-stand-inject."""
    import re
    captures = [(FIX / f'integration-{i}-native.log').read_text() for i in range(3)]
    selected = [p for raw in captures for p in re.findall(r'^ok\s+(\S+)\s+\d+(?:\.\d+)?s\s*$', raw, re.M)]
    core = {name: 'fixture output\n' for name in ('build', 'vet', 'vet-integration', 'unit-verdict-self',
                                                  'unit-verdict', 'listfilter', 'manifest')}
    core['unit'] = (FIX / 'go-json-native.log').read_text()
    platform = {name: 'fixture output\n' for name in ('platform-tests', 'platform-verdict', 'canon', 'catalog')}
    platform.update({f'integration-{i}': raw for i, raw in enumerate(captures)})
    artifact = root / 'fixture.txt'; artifact.write_text('synthetic fixture, not a receipt')
    packet = {'kind': 'imported-native-remote-heavy', 'head': exp['head'], 'tree': exp['tree'], 'runs': {},
              'selected_packages': selected, 'applicability_audit': str(artifact)}
    for name, census in [('core', core), ('platform', platform)]:
        ns = 'fixture-' + name
        command = f'remote-heavy: [{ns}] команда начата через fixture-only'
        raw = (f"HEAD {exp['head']} class=suite at=fixture dir=/src\n"
               f'remote-heavy: [{ns}] ns {ns} создано: fixture\n' + command + f"\nSOURCE {exp['head']} TREE {exp['tree']}\n")
        raw += ''.join(f'GROUP_BEGIN {group}\n{body.rstrip()}\nGROUP_END {group} rc=0\n' for group, body in census.items())
        raw += f'remote-heavy: [{ns}] команда завершилась кодом 0 за 1 с\nremote-heavy: [{ns}] ns {ns} снято\n'
        log = root / (name + '.log'); log.write_text(raw)
        packet['runs'][name] = dict(log=str(log), script=str(artifact), command_line=command,
                                    runner=str(artifact), auxiliary={})
    path = root / 'packet.json'; path.write_text(json.dumps(packet))
    return path


if __name__ == '__main__':
    unittest.main(verbosity=2)
