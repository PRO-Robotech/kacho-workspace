import hashlib
import io
import json
import os
import pathlib
import subprocess
import tarfile
import tempfile
import time

ws = pathlib.Path('/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace')
repo = ws / 'tmp/area-ci-truth'
audit = ws / 'tmp/area-ci-audit/docs-truth-author'
env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
env.update(GOWORK='off', TMPDIR='/home/dk/kacho-tmp/area-ci-tools')
expected = sorted([
    'api/corelib/subscription/subscription.pb.go',
    'api/corelib/subscription/subscription_service.pb.go',
    'api/corelib/subscription/subscription_service.pb.gw.go',
    'api/corelib/subscription/subscription_service_grpc.pb.go',
])
records = {}
for label, rev in [('baseline', 'b5fa093341f1fdbe96adfc6a9555482690968253'),
                   ('candidate', '88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0')]:
    stage = pathlib.Path(tempfile.mkdtemp(prefix='ci-dt-author-' + label + '-', dir=env['TMPDIR']))
    archive = subprocess.check_output(['git', '-C', str(repo), 'archive', rev, 'proto', 'go.mod', 'go.sum'], env=env)
    with tarfile.open(fileobj=io.BytesIO(archive)) as f:
        f.extractall(stage, filter='data')
    template = stage / 'proto/buf.gen.yaml'
    prefix, sep, _ = template.read_bytes().partition(b'\ninputs:')
    assert sep
    template.write_bytes(prefix + b'\ninputs:\n  - directory: .\n    paths:\n      - corelib/subscription\n')
    assert template.read_bytes().partition(b'\ninputs:')[0] == prefix
    record = {'source_sha': rev, 'stage': str(stage), 'GOWORK': 'off', 'TMPDIR': env['TMPDIR'],
              'git_environment_sanitized': True, 'archive_sha256': hashlib.sha256(archive).hexdigest(),
              'plugin_prefix_sha256': hashlib.sha256(prefix).hexdigest(),
              'buf_version': subprocess.check_output(['buf', '--version'], env=env, text=True).strip(),
              'go_version': subprocess.check_output(['go', 'version'], cwd=stage, env=env, text=True).strip(),
              'commands': []}
    for operation, args in [('generate', ['buf', 'generate']),
                            ('descriptor', ['buf', 'build', '--path', 'corelib/subscription',
                                            '--as-file-descriptor-set', '--exclude-source-info',
                                            '-o', str(stage / 'semantic-descriptor.binpb')])]:
        started = time.time()
        result = subprocess.run(args, cwd=stage / 'proto', env=env, capture_output=True)
        (audit / ('author-' + label + '-' + operation + '.stdout')).write_bytes(result.stdout)
        (audit / ('author-' + label + '-' + operation + '.stderr')).write_bytes(result.stderr)
        record['commands'].append({'command': args, 'cwd': str(stage / 'proto'), 'rc': result.returncode,
                                   'elapsed_seconds': time.time() - started,
                                   'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                                   'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()})
        result.check_returncode()
    outputs = sorted(p for p in (stage / 'pkg/api').rglob('*') if p.is_file())
    record['outputs'] = {str(p.relative_to(stage / 'pkg')): hashlib.sha256(p.read_bytes()).hexdigest() for p in outputs}
    assert sorted(record['outputs']) == expected
    record['semantic_descriptor_sha256'] = hashlib.sha256((stage / 'semantic-descriptor.binpb').read_bytes()).hexdigest()
    records[label] = record
    (audit / ('author-' + label + '-generation.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(label, str(stage), 'outputs', len(outputs), flush=True)

baseline = pathlib.Path(records['baseline']['stage'])
candidate = pathlib.Path(records['candidate']['stage'])
module = pathlib.Path('/home/dk/go/pkg/mod/github.com/!p!r!o-!robotech/corelib@v1.8.0')
for rel in expected:
    assert (baseline / 'pkg' / rel).read_bytes() == (module / rel).read_bytes(), rel
differs = [p for p in expected if (baseline / 'pkg' / p).read_bytes() != (candidate / 'pkg' / p).read_bytes()]
assert differs == ['api/corelib/subscription/subscription.pb.go'], differs
assert (baseline / 'semantic-descriptor.binpb').read_bytes() == (candidate / 'semantic-descriptor.binpb').read_bytes()
records['comparison'] = {'baseline_matches_module': 'v1.8.0', 'changed_files': differs,
                         'semantic_descriptor_equal': True,
                         'generation_script_sha256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()}
(audit / 'author-generation-comparison.json').write_text(json.dumps(records, indent=2) + '\n')
print(json.dumps(records['comparison'], indent=2))
