#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""Bounded PRECI framing and imported native evidence.

Definitions must come from exact source workflow plus independently reviewed
producer transformations. The raw log never selects its own denominator.
"""
import json
import hashlib
import base64
import gzip
import io
import tarfile
import subprocess
import re


class EvidenceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def parse_partition(raw, source, definitions):
    """Read one complete admitted partition, preserving native stdout per step.

    source={head,tree,status:''}; definitions ordered group -> ordered step list.
    Each step definition contains step, status, runSHA and, for executed steps,
    actualCommandSHA. Transport, source upload, report bytes and cleanup are
    separate checks of the existing importer. No test is run by this parser.
    """
    require(source.get('status') == '', 'expected source is dirty')
    require(definitions, 'empty partition inventory')
    result = {}
    active = None
    phase = None
    output = []
    census = None
    total_steps = 0
    expected_groups = list(definitions)
    for line in raw.splitlines(keepends=True):
        if not line.startswith('PRECI_'):
            if active is not None and phase == 'steps':
                output.append(line)
            continue
        marker, separator, payload = line.rstrip('\r\n').partition(' ')
        require(separator, 'malformed producer marker')
        require(census is None, 'marker follows final census')
        if marker == 'PRECI_GROUP_BEGIN':
            require(active is None and payload not in result, 'overlapping/duplicate group')
            require(len(result) < len(expected_groups)
                    and payload == expected_groups[len(result)], 'group order/inventory differs')
            active, phase, output = payload, 'before', []
            result[active] = {'steps': [], 'reports': []}
            continue
        try:
            record = json.loads(payload)
        except (ValueError, TypeError) as exc:
            raise EvidenceError('invalid producer JSON') from exc
        require(isinstance(record, dict), 'producer record is not an object')
        if marker == 'PRECI_CENSUS':
            require(active is None and list(result) == expected_groups, 'incomplete partition')
            require(record.get('failed') == [] and type(record.get('steps')) is int
                    and record['steps'] == total_steps
                    and record.get('offlineTrackerIsNotLiveAPIProof') is True,
                    'failed/incomplete/ambiguous final census')
            census = record
            continue
        require(active is not None and record.get('group') == active, 'record group differs')
        if marker == 'PRECI_SOURCE_BEFORE':
            require(phase == 'before', 'duplicate/misordered before boundary')
            require(record == {'group': active, **source}, 'before source differs')
            phase = 'steps'
        elif marker == 'PRECI_STEP':
            require(phase == 'steps', 'step outside native step interval')
            seen = result[active]['steps']
            required = definitions[active]
            require(len(seen) < len(required), 'extra step')
            expected = required[len(seen)]
            require(type(record.get('step')) is int and record['step'] == expected['step'], 'missing/reordered/duplicate step')
            require(record.get('status') == expected['status']
                    and record.get('runSHA') == expected['runSHA'], 'step contract differs')
            if expected['status'] == 'conditional-error-message-not-selected':
                require(set(record) == {'group', 'step', 'status', 'runSHA'}, 'conditional record differs')
                require(not ''.join(output).strip(), 'unselected step emitted native output')
            else:
                require(expected['status'] in ('executed', 'offline-real-snapshot-semantic-check'),
                        'unknown admitted execution status')
                require(type(record.get('rc')) is int and record['rc'] == 0, 'step failed or not executed')
                require(record.get('actualCommandSHA') == expected['actualCommandSHA'],
                        'executed command differs')
                require(re.fullmatch('[0-9a-f]{64}', record.get('logSHA', '')),
                        'native log digest missing')
            seen.append({'record': record, 'native': ''.join(output)})
            output = []
            total_steps += 1
        elif marker == 'PRECI_REPORT':
            require(phase == 'steps' and len(result[active]['steps']) == len(definitions[active]),
                    'report before step inventory completion')
            require(type(record.get('rc')) is int and record['rc'] == 0 and isinstance(record.get('name'), str)
                    and re.fullmatch('[0-9a-f]{64}', record.get('sha256', '')),
                    'invalid native report record')
            require(record['name'] not in [r['name'] for r in result[active]['reports']],
                    'duplicate native report')
            result[active]['reports'].append(record)
        elif marker == 'PRECI_SOURCE_AFTER':
            require(phase == 'steps' and len(result[active]['steps']) == len(definitions[active]),
                    'after boundary before all steps')
            require(not ''.join(output).strip(), 'unassigned trailing native output')
            require(record == {'group': active, **source}, 'after source differs')
            phase = 'end'
        elif marker == 'PRECI_GROUP_END':
            require(phase == 'end' and type(record.get('rc')) is int and record['rc'] == 0, 'failed/truncated group')
            active, phase, output = None, None, []
        else:
            raise EvidenceError('unknown/error producer marker')
    require(active is None and census is not None, 'truncated partition')
    return {'groups': result, 'census': census}


# Closed producer vocabulary, not a count inferred from successful log lines.
WORKFLOW_JOBS = {
    'ci.yml': ('build', 'unit', 'lint', 'proto', 'standalone', 'gosec',
               'integrationshard', 'listfilter', 'authzartifacts', 'govulncheck', 'catalogparity'),
    'e2e-newman.yml': ('suite', 'edgeselftests'),
}


def bind_transport(argv, bootstrap, manifest, producer, digest):
    """Decode the fixed chunked make operand without evaluating shell/make code."""
    require(len(argv) >= 7 and argv[:4] == ['make', '-f', '/dev/null', '--eval'] and argv[5] == 'MAKEOVERRIDES=',
            'noncanonical PRECI argv prefix')
    count = 0
    chunks = []
    while 6 + count < len(argv) and argv[6 + count].startswith(f'P-{count}='):
        chunks.append(argv[6 + count].split('=', 1)[1])
        count += 1
    require(count > 0, 'missing transported chunks')
    encoded = ''.join(chunks)
    require(len(encoded) <= 1500000, 'transport operand exceeds bound')
    require(chunks == [encoded[i:i + 48000] for i in range(0, len(encoded), 48000)],
            'noncanonical chunk partition')
    bundle = base64.urlsafe_b64decode(encoded)
    require(base64.urlsafe_b64encode(bundle).decode() == encoded, 'noncanonical bundle encoding')
    require(digest(bundle) == manifest.get('bundleSHA') and len(bundle) == manifest.get('bundleBytes'),
            'transport bundle digest differs')
    targets = [f'part-{i}' for i in range(count)]
    rule = '.NOTPARALLEL:\n.PHONY: operand-begin operand-final ' + ' '.join(targets) + '\n'
    rule += 'operand-begin:; @test "$(CURDIR)" = /work/src && test "$${HEAVY_WORKDIR+x}" = x && : > /tmp/kaname-preci.parts\n'
    for index in range(count):
        rule += f'part-{index}:; @printf "%s\\n" "{index:03d}-$(value P-{index})" >> /tmp/kaname-preci.parts\n'
    rule += 'operand-final:; @printf %s ' + base64.b64encode(bootstrap).decode() + ' | base64 -d | bash\n'
    require(argv[4] == rule and argv[6 + count:] == ['operand-begin', *targets, 'operand-final'],
            'bootstrap/targets differ from canonical transport')
    with gzip.GzipFile(fileobj=io.BytesIO(bundle)) as zipped:
        unpacked = zipped.read(32 * 1024 * 1024 + 1)
    require(len(unpacked) <= 32 * 1024 * 1024, 'transport archive exceeds bound')
    with tarfile.open(fileobj=io.BytesIO(unpacked)) as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        require(len(names) == len(set(names)) == 4
                and set(names) == {'platform.tar.gz', 'vendor.tar.gz', 'tracker.tar.gz', 'runner.py'},
                'transport file inventory differs')
        require(all(member.isfile() for member in members), 'nonregular transport artifact')
        files = {member.name: archive.extractfile(member).read() for member in members}
    require({name: digest(data) for name, data in files.items()} == manifest.get('files'),
            'transported file digests differ')
    require(files['runner.py'] == producer, 'transported producer bytes differ')
    commands = bootstrap.decode().splitlines()
    require(commands.count('[ "$(git rev-parse HEAD)" = ' + manifest['source'] + ' ]') == 1,
            'bootstrap source binding differs')
    shard = selected_shard(manifest)
    suffix = '' if shard is None else ' --integration-shard ' + str(shard)
    require(commands.count('python3 "$assets/runner.py" --assets "$assets" --jobs ' + manifest['jobs'] + suffix) == 1,
            'bootstrap job selection differs')
    return manifest['bundleSHA']


def bind_command_line(command_line, argv):
    """Format argv as data with the same Bash %q used by remote-heavy; never eval."""
    require(all(value.isascii() and '\x00' not in value for value in argv),
            'non-ASCII/noncanonical PRECI argv')
    process = subprocess.run(
        ['bash', '--noprofile', '--norc', '-c', 'printf "%q " "$@"', 'argv-data', *argv],
        env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, capture_output=True, text=True, timeout=20,
        check=False,
    )
    require(process.returncode == 0 and not process.stderr, 'cannot format actual argv')
    prefix = re.match(r'^remote-heavy: \[[^]]+\] команда начата через \d+ с после создания Job: ',
                      command_line)
    require(prefix is not None and command_line[prefix.end():] == process.stdout,
            'captured executed argv differs from transported operand')


def selected_shard(manifest):
    if 'integrationShard' not in manifest:
        return None
    shard = manifest['integrationShard']
    require(type(shard) is int and 0 <= shard < 3
            and manifest.get('jobs') == 'integrationshard', 'invalid selected integration shard')
    return shard


def definitions_for(workflows, jobs, digest, shards, integration_shard=None):
    """Reconstruct the reviewed PRECI transformations of exact workflow run steps."""
    require(isinstance(jobs, str), 'missing manifest jobs')
    wanted = jobs.split(',')
    allowed = {job for names in WORKFLOW_JOBS.values() for job in names}
    require(len(wanted) == len(set(wanted)) and set(wanted) <= allowed, 'unknown/duplicate job selection')
    if integration_shard is not None:
        require(type(integration_shard) is int and 0 <= integration_shard < shards
                and wanted == ['integrationshard'], 'invalid selected integration shard')
    result = {}
    for filename, names in WORKFLOW_JOBS.items():
        for job in names:
            if job not in wanted:
                continue
            source = workflows[filename]['jobs'][job]
            require('uses' not in source and isinstance(source.get('steps'), list), 'unexpanded source job')
            indices = ([integration_shard] if integration_shard is not None else range(shards))
            for shard in indices if job == 'integrationshard' else [None]:
                key = filename + ':' + job + (f':{shard}' if shard is not None else '')
                steps = []
                for index, step in enumerate(source['steps']):
                    if 'run' not in step:
                        continue
                    original = step['run']
                    require(isinstance(original, str), 'non-string source command')
                    command = original
                    status = 'executed'
                    if 'steps.edge-tree.outcome' in command or 'steps.vendor-upstream.outcome' in command:
                        status = 'conditional-error-message-not-selected'
                    else:
                        for old, new in {
                            '${{ github.repository }}': 'PRO-Robotech/kaname',
                            '${{ steps.platform-tree.outputs.root }}': '/work/src/upstream-kacho',
                            '$GITHUB_WORKSPACE/upstream-kacho': '/work/src/upstream-kacho',
                        }.items():
                            command = command.replace(old, new)
                        require('${{' not in command, 'unresolved workflow expression')
                        if command.strip() == 'python3 .github/scripts/review-event-silence.py':
                            command += ' --tracker-fixture /tmp/kaname-preci-assets/tracker-snapshot'
                            status = 'offline-real-snapshot-semantic-check'
                        if 'python3 .github/scripts/newman-suite-debt.py ||' in command:
                            status = 'offline-real-snapshot-semantic-check'
                    record = {'step': index, 'status': status, 'runSHA': digest(original.encode())}
                    if status != 'conditional-error-message-not-selected':
                        record['actualCommandSHA'] = digest(command.encode())
                    steps.append(record)
                require(steps, 'source job has no run steps')
                result[key] = steps
    require(result, 'empty source-derived group inventory')
    return result


def verify_native(group, digest):
    """Check stdout hashes; unit JSON is appended separately by the producer."""
    unit_json = None
    for step in group['steps']:
        record, native = step['record'], step['native']
        if record['status'] == 'conditional-error-message-not-selected':
            continue
        if digest(native.encode()) == record['logSHA']:
            continue
        # A unit run appends test.json after command stdout. A split is accepted
        # only when the prefix has the producer's exact logSHA and the suffix is
        # an actual complete JSON stream subsequently checked by go_json().
        lines = native.splitlines(keepends=True)
        matches = []
        prefix = hashlib.sha256()
        for index, line in enumerate(lines):
            if not line.startswith('{'):
                prefix.update(line.encode())
                continue
            try:
                event = json.loads(line)
            except ValueError:
                prefix.update(line.encode())
                continue
            if not isinstance(event, dict) or 'Action' not in event or 'Package' not in event:
                prefix.update(line.encode())
                continue
            if prefix.hexdigest() == record['logSHA']:
                matches.append(''.join(lines[index:]))
                break
            prefix.update(line.encode())
        require(record['group'] == 'ci.yml:unit' and unit_json is None and len(matches) == 1,
                'native output digest differs')
        unit_json = matches[0]
    reports = {record['name']: record['sha256'] for record in group['reports']}
    key = group['steps'][0]['record']['group']
    required = {'ci.yml:unit': {'test.json'},
                'ci.yml:gosec': {'gosec.sarif', 'gosec-summary.txt'}}.get(key, set())
    require(set(reports) == required, 'required native report inventory differs')
    if key == 'ci.yml:unit':
        require(unit_json is not None and digest(unit_json.encode()) == reports['test.json'],
                'native unit report digest differs')
    return unit_json


def import_candidate(exp, packet, common, remote_log, go_json, integration_union):
    """Source-bound PRECI import, distinct from the historical core/platform kind."""
    from pathlib import Path
    require(packet.get('head') == exp['head'] and packet.get('tree') == exp['tree'], 'import source differs')
    require(set(packet.get('workflows', {})) == set(WORKFLOW_JOBS), 'workflow source inventory differs')
    workflows, workflow_digests = {}, {}
    for filename, path in packet['workflows'].items():
        raw = Path(path).read_bytes()
        bound = {d['workflow_digest'] for d in exp['definitions'].values()
                 if d['workflow_job'].split(':')[0] == filename}
        require(bound == {common.digest(raw)}, 'workflow source bytes differ')
        workflows[filename] = common.load_workflow(raw)
        workflow_digests[filename] = common.digest(raw)
    n = len([d for d in exp['definitions'].values() if d['matrix_index'] is not None])
    require(n == 3, 'PRECI producer supports exactly three integration shards')
    runs = packet.get('runs')
    require(isinstance(runs, dict) and runs, 'missing imported runs')
    groups, artifacts, cleanup, producers = {}, {}, {}, set()
    for name, run in runs.items():
        require(isinstance(name, str) and name and isinstance(run, dict), 'invalid partition name')
        require(set(run) == {'log', 'runner', 'manifest', 'argv', 'bootstrap', 'command_line', 'auxiliary'},
                'unreviewed partition artifact shape')
        artifacts[name] = {key: common.digest(Path(run[key]).read_bytes())
                           for key in ('log', 'runner', 'manifest', 'argv', 'bootstrap')}
        require(isinstance(run['auxiliary'], dict), 'auxiliary artifacts missing')
        artifacts[name]['auxiliary'] = {key: common.digest(Path(path).read_bytes())
                                        for key, path in run['auxiliary'].items()}
        manifest = common.read_json(run['manifest'])
        require(manifest.get('source') == exp['head'], 'manifest source differs')
        require(manifest.get('files', {}).get('runner.py') == artifacts[name]['runner'],
                'transported producer differs')
        producers.add(artifacts[name]['runner'])
        argv = common.read_json(run['argv'])
        require(isinstance(argv, list) and argv and all(isinstance(v, str) for v in argv),
                'actual argv artifact invalid')
        require(manifest.get('argvBytes') == sum(len(v.encode()) + 1 for v in argv), 'argv size differs')
        bind_transport(argv, Path(run['bootstrap']).read_bytes(), manifest,
                       Path(run['runner']).read_bytes(), common.digest)
        bind_command_line(run['command_line'], argv)
        raw = Path(run['log']).read_text()
        transport = remote_log(raw, exp, run['command_line'], parse_groups=False)
        artifacts[name]['command_line'] = run['command_line']
        definitions = definitions_for(workflows, manifest.get('jobs'), common.digest, n, selected_shard(manifest))
        parsed = parse_partition(raw, {'head': exp['head'], 'tree': exp['tree'], 'status': ''}, definitions)
        require(not set(parsed['groups']) & set(groups), 'group repeated across imported runs')
        for key, group in parsed['groups'].items():
            group['unit_json'] = verify_native(group, common.digest)
            groups[key] = group
        cleanup[name] = {'namespace': transport['namespace'], 'kind': transport['cleanup_kind']}
    # Every producer version is independently bound and reviewed. An unchanged
    # successful integration run need not be repeated because unit-report
    # relocation required a corrected producer in a different partition.
    required = {'ci.yml:unit', *(f'ci.yml:integrationshard:{i}' for i in range(n))}
    require(required <= set(groups), 'required external group missing')
    unit = go_json(groups['ci.yml:unit']['unit_json'])
    integration = integration_union([
        ''.join(step['native'] for step in groups[f'ci.yml:integrationshard:{i}']['steps'])
        for i in range(n)
    ], packet['selected_packages'])
    audit = Path(packet['applicability_audit']).read_bytes()
    require(audit, 'short skip applicability evidence missing')
    census = {key: {'steps': [step['record'] for step in group['steps']], 'reports': group['reports']}
              for key, group in groups.items()}
    return {'kind': packet['kind'], 'repo': exp['repo'], 'head': exp['head'], 'tree': exp['tree'],
            'expected_digest': common.digest(exp), 'artifacts': artifacts,
            'workflow_digests': workflow_digests, 'producer_digests': sorted(producers),
            'group_census': census, 'applicability_audit_digest': common.digest(audit),
            'selected_packages': packet['selected_packages'], 'unit': unit,
            'integration': integration, 'cleanup': cleanup}
