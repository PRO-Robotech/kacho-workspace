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
EXTERNAL = ('ci.yml:unit', 'ci.yml:integrationshard')
# Закрытая ведомость заданий CI Kaname (ws#1365, ws#1259): каждое задание каждого workflow
# головы — ровно одной строкой, сверка в обе стороны. Строки CI_READ судит CI-читатель
# (обязательные проверки PR), staged-стенд их не воспроизводит. Задание CI без строки и
# строка без задания — отказ с координатой: новое задание входит сюда решением, а не молча.
CI_READ = frozenset((
    'ci.yml:changes', 'ci.yml:build', 'ci.yml:lint', 'ci.yml:proto', 'ci.yml:standalone',
    'ci.yml:gosec', 'ci.yml:integration', 'ci.yml:listfilter', 'ci.yml:authzartifacts',
    'ci.yml:govulncheck', 'ci.yml:catalogparity', 'ci.yml:trunkverdict', 'ci.yml:prverdict',
    'e2e-newman.yml:changes', 'e2e-newman.yml:suite', 'e2e-newman.yml:edgeselftests',
    'e2e-newman.yml:trunkverdict', 'e2e-newman.yml:prverdict',
    'docker-build.yml:changes', 'docker-build.yml:trunkverdict', 'pr-rule.yml:pr-rule'))
# Задания поставки по метке версии (ws#1404, kaname#964): `render` — полоса рендера чарта перед
# публикацией, `publish` — публикация в OCI-реестр. На событии PR их нет ни в CI, ни на стенде,
# поэтому в ожидаемое и в ci_read они не входят: вердикт запроса дают пробы `deploy/` в ci.yml.
# Строка — поимённо; что задание и правда лишь по метке, судит `release_only_trigger` по `on:`
# разобранного workflow. Строки — лишь при отслеживаемом workflow: головы линий без kaname#964
# (942, 822 @2026-10-26) его не несут; снять условие, когда `chart.yml` есть в kaname main.
RELEASE_ONLY = frozenset(('chart.yml:render', 'chart.yml:publish'))
LEDGER = frozenset(EXTERNAL + HOSTED) | CI_READ
# Юниты матрицей шардов (kaname#873, ws#1259): `unitshard` исполняет пробы долей плана,
# `unit` — свод по описям шардов с разреженной копией `.github`. Строка ведомости — только
# вместе со сводом в канонической форме производителя (`unit_shards`), иначе отказ.
UNIT_SHARD = 'ci.yml:unitshard'
UNIT_RUN = ('python3 .github/scripts/unit-shards.py --run --job-index "$JOB_INDEX" '
            '--job-total "$JOB_TOTAL" ')
UNIT_WIDTH_ENV = {'JOB_INDEX': '${{ strategy.job-index }}', 'JOB_TOTAL': '${{ strategy.job-total }}'}
MATRIX_REF = re.compile(r'\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}')
# chart-own матрицей шардов плана (kaname#848, ws#1259): ось `shard`, наборы шарда — строка
# плана `tests/newman/<план>`, сводный вердикт — задание `chart-own-verdict`. Строка ведомости
# свода — только вместе с осью `shard` в канонической форме производителя (`chart_own_shards`);
# шард плана без ноги матрицы и нога без шарда плана — отказ.
CHART_OWN_VERDICT = 'e2e-newman.yml:chart-own-verdict'
SHARD_AXIS = 'shard'
SHARD_PLAN_RUN = re.compile(
    r'\./scripts/run\.sh\s+--shard-plan\s+([A-Za-z0-9._-]+)\s+--shard\s+"\$([A-Za-z_][A-Za-z0-9_]*)"(?=\s|$)')
MATRIX_SHARD = re.compile(r'\$\{\{\s*matrix\.shard\s*\}\}')


def matrix_legs(job):
    """Ноги задания-матрицы по канону производителя: `strategy.matrix.include` либо одна ось
    `shard` (kaname#848) — нога `{shard: значение}`.

    Иные оси, их произведение, `exclude` и выражение вместо списка не разобраны — отказ.
    """
    strategy = job.get('strategy')
    if strategy is None:
        return None
    require(isinstance(strategy, dict) and set(strategy) <= {'fail-fast', 'matrix', 'max-parallel'},
            'unreviewed matrix strategy')
    matrix = strategy.get('matrix')
    require(isinstance(matrix, dict) and set(matrix) in ({'include'}, {SHARD_AXIS}), 'unreviewed matrix axes')
    if SHARD_AXIS in matrix:
        values = matrix[SHARD_AXIS]
        require(isinstance(values, list) and values and all(type(v) in (str, int) for v in values),
                'invalid matrix axis')
        require(len(values) == len(set(values)), 'duplicate matrix leg')
        return [{SHARD_AXIS: v} for v in values]
    include = matrix['include']
    require(isinstance(include, list) and include and all(
        isinstance(leg, dict) and leg and all(isinstance(k, str) and type(v) in (str, int) for k, v in leg.items())
        for leg in include), 'invalid matrix include')
    require(len({json.dumps(leg, sort_keys=True) for leg in include}) == len(include), 'duplicate matrix leg')
    return include


def expand(text, values):
    """Подстановка `${{ matrix.X }}` значением ноги; иное выражение в имени не разобрано — отказ."""
    require(isinstance(text, str) and text, 'invalid job or step name')
    def sub(m):
        require(m[1] in values, 'matrix reference outside the leg: ' + m[1])
        return str(values[m[1]])
    out = MATRIX_REF.sub(sub, text)
    require('${{' not in out, 'unsupported expression in job or step name')
    return out


def release_only_trigger(doc):
    """События `on:` workflow заданий RELEASE_ONLY, которые запускают их вне метки версии.

    Закрытая форма: `on: {push: {tags: [образец, …]}}`. Иное событие, `push` строкой или
    списком, фильтр ветки или пути рядом с `tags`, пустой `tags` или пустой образец — запуск
    вне метки. Нет `push` (в том числе `on: {}`) — тоже отказ `push`: событий ноль — не форма
    «лишь по метке», а её отсутствие; иначе пустой обход событий зеленил бы ведомость.
    """
    trigger = doc.get('on')
    if isinstance(trigger, str):
        return [trigger]
    if not isinstance(trigger, dict):
        return sorted(map(str, trigger)) if isinstance(trigger, list) else ['on']
    bad = sorted(str(event) for event in trigger if event != 'push')
    push = trigger.get('push')
    if not isinstance(push, dict):
        return bad + ['push']
    bad += sorted('push.' + str(key) for key in push if key != 'tags')
    tags = push.get('tags')
    if not (isinstance(tags, list) and tags and all(isinstance(t, str) and t for t in tags)):
        bad.append('push.tags')
    return bad


def ledger_census(co):
    """Обход ВСЕХ отслеживаемых workflow головы против закрытой ведомости, в обе стороны."""
    files = [p for p in common.git(co, 'ls-files', '--', '.github/workflows').splitlines()
             if re.fullmatch(r'\.github/workflows/[^/]+\.ya?ml', p)]
    require(files, 'no tracked workflow in the checkout')
    workflows, found = {}, set()
    for path in files:
        raw = (Path(co) / path).read_bytes()
        doc = common.load_workflow(raw)
        require(isinstance(doc, dict) and isinstance(doc.get('jobs'), dict) and doc['jobs'],
                'workflow without jobs: ' + path)
        name = path.rsplit('/', 1)[1]
        workflows[name] = (doc, common.digest(raw))
        found |= {name + ':' + key for key in doc['jobs']}
    # Шарды юнитов — строка ведомости лишь в топологии «шарды + свод»; её форму судит unit_shards.
    # Свод шардов chart-own — лишь при оси `shard`; её форму судит chart_own_shards.
    # Строки поставки — по отслеживаемому workflow; их запуск по метке судит release_only_trigger.
    release = {row for row in RELEASE_ONLY if row.split(':', 1)[0] in workflows}
    ledger = LEDGER | ({UNIT_SHARD, CHART_OWN_VERDICT} & found) | release
    outside = sorted(found - ledger)
    require(not outside, 'CI job outside the Kaname ledger: ' + ', '.join(outside))
    stale = sorted(ledger - found)
    require(not stale, 'Kaname ledger row without CI job: ' + ', '.join(stale))
    for name in sorted({row.split(':', 1)[0] for row in release}):
        events = release_only_trigger(workflows[name][0])
        rows = sorted(row for row in release if row.startswith(name + ':'))
        require(not events, 'release-only job runs outside a version tag: %s (on: %s)'
                % (', '.join(rows), ', '.join(events)))
    return workflows, {'workflows': sorted(workflows), 'jobs': len(found),
                       'staged': len(EXTERNAL) + len(HOSTED) + (UNIT_SHARD in found),
                       'ci_read': len(CI_READ) + (CHART_OWN_VERDICT in found),
                       'release_only': len(release)}


def sparse_aggregate_checkout(options):
    """Свод юнитов читает лишь `.github` своей головы: разрежена копия, источник прежний."""
    return (set(options) == {'sparse-checkout', 'sparse-checkout-cone-mode'}
            and isinstance(options['sparse-checkout'], str)
            and options['sparse-checkout'].split() == ['.github']
            and options['sparse-checkout-cone-mode'] is False)


def job_definition(doc, key, matrix=False, sparse=False):
    # Kaname сохраняет собственные changed-job conditions и shard matrix.
    # Условие не объявляется истинным по source: actual job всё равно обязана исполниться.
    job = doc['jobs'][key]
    require(isinstance(job, dict) and 'uses' not in job, 'unexpanded reusable job')
    require(job.get('runs-on') in ('ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04'),
            'unsupported job runner')
    require('strategy' not in job or key in ('integrationshard', 'unitshard')
            or (matrix and matrix_legs(job) is not None), 'unexpected matrix job')
    steps = job.get('steps')
    require(isinstance(steps, list) and steps, 'missing job steps')
    require(steps[0].get('uses', '').startswith('actions/checkout@'), 'primary checkout must be first')
    options = steps[0].get('with', {})
    require(isinstance(options, dict), 'overridden primary checkout')
    lawful_sparse = sparse and 'sparse-checkout' in options and sparse_aggregate_checkout(options)
    require(lawful_sparse or not ({'ref', 'repository', 'path', 'sparse-checkout'} & set(options)),
            'overridden primary checkout')
    return {'job': job, 'env': doc.get('env', {}), 'defaults': doc.get('defaults', {})}


def unit_shards(jobs):
    """Значения матрицы шардов юнитов по канону производителя kaname#873; None — одно задание.

    Ширину плана шард берёт у матрицы (`strategy.job-total`), долю — по `strategy.job-index`:
    иная запись ширины оставила бы пакеты без шарда, поэтому форма вызова — часть канона.
    Свод `unit` обязан ждать шарды и исполнять `--aggregate`; своих проб у него нет.
    """
    unit = jobs['unit']
    require(isinstance(unit, dict), 'unexpanded reusable job')
    if 'unitshard' not in jobs:
        require('unitshard' not in (unit.get('needs') or []), 'unit aggregate lost its producer')
        return None
    shards = jobs['unitshard']
    require(isinstance(shards, dict), 'invalid unit shard job')
    strategy = shards.get('strategy')
    require(isinstance(strategy, dict) and set(strategy) <= {'fail-fast', 'matrix', 'max-parallel'},
            'unreviewed unit shard strategy')
    matrix = strategy.get('matrix')
    require(isinstance(matrix, dict) and set(matrix) == {'shard'}, 'unreviewed unit matrix axes')
    values = matrix['shard']
    require(isinstance(values, list) and values and all(type(x) is int for x in values)
            and len(values) == len(set(values)), 'invalid unit shard matrix')
    require('unitshard' in (unit.get('needs') or []), 'unit aggregate lost its producer')
    runs = [s for s in shards.get('steps') or []
            if isinstance(s, dict) and 'unit-shards.py --run' in str(s.get('run', ''))]
    env = runs[0].get('env') if len(runs) == 1 else None
    require(isinstance(env, dict) and str(runs[0]['run']).startswith(UNIT_RUN)
            and {k: env.get(k) for k in UNIT_WIDTH_ENV} == UNIT_WIDTH_ENV,
            'unit shard width is not the matrix width')
    steps = [s for s in unit.get('steps') or [] if isinstance(s, dict)]
    require(sum('unit-shards.py --aggregate' in str(s.get('run', '')) for s in steps) == 1
            and not any(re.search(r'\bgo test\b', str(s.get('run', ''))) for s in steps),
            'unit aggregate shape differs')
    return values


def shard_plan(text, path):
    """{шард: [набор, …]} плана в порядке файла — грамматика `tests/newman/scripts/shard_plan.py`."""
    plan, seen = {}, set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        head, sep, rest = line.partition(':')
        shard, stems = head.strip(), rest.split()
        require(sep and re.fullmatch(r'[a-z0-9][a-z0-9-]*', shard) and shard not in plan and stems
                and len(stems) == len(set(stems)) and not seen.intersection(stems)
                and all(re.fullmatch(r'[A-Za-z0-9._-]+', s) for s in stems),
                f'invalid chart-own shard plan: {path}:{n}')
        seen.update(stems)
        plan[shard] = stems
    require(plan, 'chart-own shard plan without shards: ' + path)
    return plan


def joined_run(step):
    """Тело `run:` шага с продолжениями строк `\\` в одну строку."""
    return re.sub(r'\\\n\s*', ' ', str(step.get('run', ''))) if isinstance(step, dict) else ''


def chart_own_shards(co, jobs):
    """План шардов chart-own по канону производителя kaname#848; None — ноги `include` без свода.

    Нога гоняет `./scripts/run.sh --shard-plan <план> --shard "$V"` из `tests/newman`, V —
    `${{ matrix.shard }}` env задания либо шага; план отслеживаем, его шарды и ноги матрицы
    совпадают в обе стороны. Свод ждёт chart-own и судит тот же план `shard_plan.py --verdict`.
    """
    chart = jobs['chart-own']
    require(isinstance(chart, dict), 'unexpanded reusable job')
    strategy = chart.get('strategy')
    matrix = strategy.get('matrix') if isinstance(strategy, dict) else None
    if not (isinstance(matrix, dict) and SHARD_AXIS in matrix):
        require('chart-own-verdict' not in jobs, 'chart-own verdict without shard matrix')
        return None
    require('chart-own-verdict' in jobs, 'chart-own shard matrix lost its verdict')
    values = [str(leg[SHARD_AXIS]) for leg in matrix_legs(chart)]
    runs = [s for s in chart.get('steps') or [] if './scripts/run.sh ' in joined_run(s)]
    text = joined_run(runs[0]) if len(runs) == 1 else ''
    form = SHARD_PLAN_RUN.findall(text)
    env = {**(chart.get('env') or {}), **(runs[0].get('env') or {})} if len(runs) == 1 else {}
    require(len(form) == 1 and text.count('./scripts/run.sh ') == 1 and '--service' not in text
            and text.splitlines()[0].strip() == 'cd tests/newman'
            and MATRIX_SHARD.fullmatch(str(env.get(form[0][1], ''))),
            'chart-own shard runner form differs')
    path = 'tests/newman/' + form[0][0]
    require(common.git(co, 'ls-files', '--', path) == path, 'chart-own shard plan is not tracked: ' + path)
    plan = shard_plan((Path(co) / path).read_text(encoding='utf-8'), path)
    missing, extra = sorted(set(plan) - set(values)), sorted(set(values) - set(plan))
    require(not missing, 'chart-own plan shard without matrix leg: ' + ', '.join(missing))
    require(not extra, 'chart-own matrix leg without plan shard: ' + ', '.join(extra))
    verdict = jobs['chart-own-verdict']
    require(isinstance(verdict, dict), 'unexpanded reusable job')
    needs = verdict.get('needs') or []
    require('chart-own' in ([needs] if isinstance(needs, str) else needs), 'chart-own verdict lost its producer')
    steps = [joined_run(s) for s in verdict.get('steps') or []]
    judged = [r for r in steps if 'shard_plan.py' in r]
    require(len(judged) == 1 and '--verdict ' in judged[0] and re.findall(r'--plan (\S+)', judged[0]) == [path]
            and not any('./scripts/run.sh' in r for r in steps), 'chart-own verdict shape differs')
    return {'plan': path, 'shards': plan}


def expected(checkout, head, base, ref):
    """Не исполняет workflow и не подменяет отсутствующий cluster route."""
    co = Path(checkout)
    require(common.git(co, 'rev-parse', 'HEAD') == head, 'checkout differs')
    require(not common.git(co, 'status', '--porcelain', '--untracked-files=all'), 'dirty checkout')
    require(re.fullmatch(r'(?:https://github.com/|git@github.com:)PRO-Robotech/kaname(?:\.git)?',
                         common.git(co, 'remote', 'get-url', 'origin')), 'wrong repository')
    require(ref.startswith('refs/heads/') and len(ref) > 11, 'explicit source branch required')
    workflows, census = ledger_census(co)
    ci = workflows['ci.yml'][0]
    shards = ci['jobs']['integrationshard']
    matrix = shards.get('strategy', {}).get('matrix', {})
    require(set(matrix) == {'shard'}, 'unreviewed integration matrix axes')
    values = matrix['shard']
    require(isinstance(values, list) and values and all(type(x) is int for x in values)
            and len(values) == len(set(values)), 'invalid shard matrix')
    require('integrationshard' in ci['jobs']['integration'].get('needs', []),
            'integration aggregate lost its producer')
    unit_values = unit_shards(ci['jobs'])
    chart_plan = chart_own_shards(co, workflows['e2e-newman.yml'][0]['jobs'])
    definitions, unit_legs = {}, {}
    names = [('ci.yml:unit', 'ci.yml:unit', None, None)]
    if unit_values is not None:
        for i, v in enumerate(unit_values):
            unit_legs[f'{UNIT_SHARD}[shard={v}]'] = {'index': i, 'total': len(unit_values)}
        names += [(name, UNIT_SHARD, None, None) for name in unit_legs]
    names += [(f'ci.yml:integrationshard[shard={v}]', 'ci.yml:integrationshard', i, None)
              for i, v in enumerate(values)]
    for source in HOSTED:
        filename, key = source.split(':')
        legs = matrix_legs(workflows[filename][0]['jobs'][key])
        if legs is None:
            names.append((source, source, None, None))
        elif chart_plan is None or source != 'e2e-newman.yml:chart-own':
            # Ось `shard` разобрана лишь у chart-own с планом: у иного задания она не просмотрена.
            require(SHARD_AXIS not in workflows[filename][0]['jobs'][key]['strategy']['matrix'],
                    'unreviewed matrix axes')
            names +=[(f'{source}[include={i}]', source, None, {'index': i, 'total': len(legs), 'values': leg})
                      for i, leg in enumerate(legs)]
        else:
            # Нога шарда несёт план и свои наборы: отчёт судит её волну по ним.
            names += [(f'{source}[{SHARD_AXIS}={leg[SHARD_AXIS]}]', source, None,
                       {'index': i, 'total': len(legs), 'values': leg, 'plan': chart_plan['plan'],
                        'suites': chart_plan['shards'][str(leg[SHARD_AXIS])]})
                      for i, leg in enumerate(legs)]
    for name, source, index, leg in names:
        filename, key = source.split(':')
        doc, wf_digest = workflows[filename]
        hosted = source in HOSTED
        # Разреженная копия законна лишь у свода юнитов шардовой топологии.
        definition = job_definition(doc, key, matrix=hosted,
                                    sparse=unit_values is not None and source == 'ci.yml:unit')
        require('uses' not in definition['job'], 'reusable job needs an explicit reviewed expansion')
        definitions[name] = {'workflow_job': source, 'executor': 'github-hosted' if hosted else 'external',
                             'definition': definition, 'definition_digest': common.digest(definition),
                             'workflow_digest': wf_digest, 'matrix_index': index,
                             'matrix_total': len(values) if index is not None else None, 'matrix_leg': leg}
        if name in unit_legs:
            # Поле есть только у шардов юнитов: ожидаемое прежней топологии не меняет отпечатка.
            definitions[name]['unit_shard'] = unit_legs[name]
    result = {'schema': 'kaname-stand-v1', 'repo': REPO, 'head': head,
              'tree': common.git(co, 'rev-parse', 'HEAD^{tree}'), 'base': base,
              'base_sha': common.git(co, 'rev-parse', base), 'ref': ref,
              'logical_jobs': ['ci.yml:unit', 'ci.yml:integration', *HOSTED],
              'jobs': list(definitions), 'definitions': definitions, 'ledger': census,
              'unsupported_external': list(HOSTED), 'full': True}
    if unit_values is not None:
        result['unit_shards'] = len(unit_values)
    return result


def unit_shard_total(exp):
    """Шардов юнитов в ожидаемом; 0 — юниты одним заданием. Объявление сверено с определениями."""
    legs = sorted(d['unit_shard']['index'] for d in exp['definitions'].values() if 'unit_shard' in d)
    total = exp.get('unit_shards', 0)
    require(legs == list(range(total)) and all(
        d['unit_shard']['total'] == total for d in exp['definitions'].values() if 'unit_shard' in d),
        'unit shard inventory differs')
    return total


def hosted_names(exp):
    """Исполнения hosted в порядке ожидаемого: задание либо каждая нога его матрицы."""
    return [name for name in exp['jobs'] if exp['definitions'][name]['executor'] == 'github-hosted']


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


def unit_shard_union(shard_texts, aggregate_text, combined_json, total):
    """Юниты шардами (kaname#873): каждый номер матрицы — ровно один шард плана, свод — их все.

    Строки — дословный вывод `unit-shards.py --run` и `--aggregate`; счёт проб — объединённый
    поток `go test -json` свода, тем же разбором, что у одного задания.
    """
    require(type(total) is int and total > 0 and isinstance(shard_texts, list)
            and len(shard_texts) == total, 'unit shard inventory differs')
    shards = []
    for index, text in enumerate(shard_texts):
        picked = re.findall(r'^задание матрицы №(\d+) из (\d+) → шард (\S+)$', text, re.M)
        require(len(picked) == 1 and picked[0][:2] == (str(index), str(total)), 'wrong/missing unit shard')
        width = re.findall(r'^  шардов:\s+(\d+) \(', text, re.M)
        require(width == [str(total)], 'unit shard plan width differs')
        calls = re.findall(r'^  go test #(\d+) завершился с кодом (\d+) ', text, re.M)
        require(calls and [int(n) for n, _ in calls] == list(range(1, len(calls) + 1))
                and all(rc == '0' for _, rc in calls), 'failed/missing go test call in unit shard')
        require(re.findall(r'^ЗЕЛЁНЫЙ: отказов нет\.$', text, re.M) == ['ЗЕЛЁНЫЙ: отказов нет.']
                and not re.search(r'^(?:КРАСНЫЙ|НЕ ВЫПОЛНИЛОСЬ|ОТКАЗ)', text, re.M),
                'missing native unit shard verdict')
        shards.append({'unit': 'unit shard of the plan', 'shard': picked[0][2],
                       'go_test_calls': len(calls), 'matrix_index': index, 'matrix_total': total})
    require(len({s['shard'] for s in shards}) == total, 'unit shard executed twice')
    require(re.findall(r'^исход шардов: (\S+)$', aggregate_text, re.M) == ['success']
            and re.findall(r'^  копий плана: (\d+) · разошлось: (\S+)$', aggregate_text, re.M) == [(str(total), 'нет')]
            and re.findall(r'^  шардов в плане: (\d+) · отчиталось: (\d+)$', aggregate_text, re.M)
            == [(str(total), str(total))], 'unit aggregate shard census differs')
    require(re.findall(r'^ЗЕЛЁНЫЙ: .*$', aggregate_text, re.M)
            == ['ЗЕЛЁНЫЙ: все шарды плана отчитались, роздано = дерево, отказов нет.']
            and not re.search(r'^(?:КРАСНЫЙ|НЕ ВЫПОЛНИЛОСЬ|НАХОДОК СВОДА)', aggregate_text, re.M),
            'missing native unit aggregate verdict')
    return {**go_json(combined_json), 'shards': shards}


def remote_log(text, exp, argv, parse_groups=True):
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
            'cleanup_kind': 'runner-observed-namespace-delete-wait',
            'groups': groups(text) if parse_groups else {}}


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
    if packet.get('kind') == 'imported-native-preci-v1':
        preci_spec = importlib.util.spec_from_file_location('kaname_preci', Path(__file__).with_name('kaname-preci.py'))
        preci = importlib.util.module_from_spec(preci_spec)
        preci_spec.loader.exec_module(preci)
        return preci.import_candidate(exp, packet, common, remote_log, go_json, integration_union)
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
    # Шардовая топология: вывод каждого шарда — группа `unit-<номер>`, свод — `unit-aggregate`,
    # `unit` — объединённый поток свода. Шард пропал или лишний — отказ переписи групп.
    m = unit_shard_total(exp)
    sharded = {*(f'unit-{i}' for i in range(m)), 'unit-aggregate'} if m else set()
    require(set(core) == {'build', 'vet', 'vet-integration', 'unit-verdict-self', 'unit',
                          'unit-verdict', 'listfilter', 'manifest'} | sharded, 'core group inventory differs')
    n = len([d for d in exp['definitions'].values() if d['matrix_index'] is not None])
    require(set(platform) == {'platform-tests', 'platform-verdict', 'canon', 'catalog',
                              *(f'integration-{i}' for i in range(n))}, 'platform group inventory differs')
    unit = (unit_shard_union([core[f'unit-{i}'] for i in range(m)], core['unit-aggregate'], core['unit'], m)
            if m else go_json(core['unit']))
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
    claims = ['source-and-command-binding', 'native-verdict-and-cleanup',
              'selected-package-partition', 'short-skip-applicability']
    if candidate['kind'] == 'imported-native-preci-v1':
        claims.append('source-workflow-and-preci-producer-binding')
    require(review.get('claims') == claims,
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


# Observed REST names at the exact source below; this is not a general GitHub
# truncation contract. A different source or spelling requires fresh evidence.
OBSERVED_HOSTED_NAMES = {
    ('1fc23d6c126ec296eebb2b3aecceb5e8d84b12f487c4972813bcfa9ab2117261', 'stand-ceremony'): (
        'автономный стенд — волна церемонии и распорядители аккаунта (второй шард)',
        'автономный стенд — волна церемонии и распорядители ...'),
    ('1fc23d6c126ec296eebb2b3aecceb5e8d84b12f487c4972813bcfa9ab2117261', 'chart-own'): (
        'стенд посадки own (kind) — полоса входа паролем и своя церемония',
        'стенд посадки own (kind) — полоса входа паролем и своя це...'),
    # 8225e939f (kaname#941): run 40013779496, job 120620571002 — тот же укороченный вид.
    # Ноги матрицы chart-own там же (jobs 120620570854, 120620570916) пришли ПОЛНЫМ именем.
    ('be2e64e5864a22ceefe5cade1bf5baf6f5c8346f5e15e433ef1711fe811b1809', 'stand-ceremony'): (
        'автономный стенд — волна церемонии и распорядители аккаунта (второй шард)',
        'автономный стенд — волна церемонии и распорядители ...'),
}


def display_names(key, job):
    """Имена, под которыми API может показать задание: каждая нога матрицы — своё имя."""
    legs = matrix_legs(job) if isinstance(job, dict) and 'strategy' in job else None
    raw = job.get('name', key) if isinstance(job, dict) else key
    return [expand(raw, leg) for leg in legs] if legs else [expand(raw, {})]


def hosted_job_selection(workflow, workflow_digest, key, jobs, values=None):
    definitions = workflow['jobs']
    source = definitions[key]
    full_name = expand(source.get('name', key), values or {})
    accepted = {full_name}
    observed = OBSERVED_HOSTED_NAMES.get((workflow_digest, key)) if values is None else None
    if observed is not None:
        require(full_name == observed[0], 'observed source job name differs')
        accepted.add(observed[1])
    # Projection is used only to reject possible collisions, never to admit an
    # unreviewed alias. Inspect every source job, including non-required jobs
    # and the sibling legs of this job's own matrix.
    for other_key, other in definitions.items():
        if other_key == key:
            names = display_names(key, other) if values is not None else [full_name]
            require(full_name in names, 'hosted matrix leg differs')
            require(names.count(full_name) == 1, 'ambiguous source job display name')
            names = [n for n in names if n != full_name]
        else:
            names = display_names(other_key, other)
        for other_name in names:
            possible = {other_name}
            if len(other_name.encode()) > 100:
                possible.add(other_name.encode()[:97].decode('utf-8', errors='ignore') + '...')
            require(not accepted.intersection(possible), 'ambiguous source job display name')
    selected = [job for job in jobs if job.get('name') in accepted]
    require(len(selected) == 1, 'expected hosted job missing/duplicated')
    job = selected[0]
    if job['name'] != full_name:
        # Exact source-authored inventory also binds the observed alias to this
        # job. Automatic setup/post steps may be additional; named steps may not
        # disappear or acquire duplicate occurrences.
        authored = Counter(step['name'] for step in source['steps'] if 'name' in step)
        actual = Counter(step.get('name') for step in job.get('steps', []))
        require(authored and all(actual[name] == count for name, count in authored.items()),
                'observed hosted job authored steps differ')
    return job


def hosted_capture(exp, name, event):
    require(name in hosted_names(exp) and event in ('push', 'workflow_dispatch'), 'unsupported hosted subject/event')
    repo, head = exp['repo'], exp['head']
    target = exp['definitions'][name]
    filename, key = target['workflow_job'].split(':')
    leg = target.get('matrix_leg')
    content = common.api(repo, 'contents/.github/workflows/' + quote(filename) + '?' + urlencode({'ref': head}))
    raw = base64.b64decode(''.join(content['content'].split()), validate=True)
    require(common.digest(raw) == target['workflow_digest'], 'hosted workflow differs')
    workflow = common.load_workflow(raw)
    require(common.digest(job_definition(workflow, key, matrix=True)) == target['definition_digest'],
            'hosted job definition differs')
    if leg is not None:
        legs = matrix_legs(workflow['jobs'][key])
        require(legs is not None and len(legs) == leg['total'] and legs[leg['index']] == leg['values'],
                'hosted matrix leg differs')
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
    job = hosted_job_selection(workflow, target['workflow_digest'], key, jobs,
                               None if leg is None else leg['values'])
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


def suite_calls(step, values, job_env=None, leg=None):
    """Вызовы прогонщика наборов `./scripts/run.sh` шага, которые исполнит эта нога.

    Каждый вызов — одна волна (одна таблица TOTAL в журнале), с любыми ключами перед
    `--service`. Вызов внутри `if`/`elif [ "$VAR" = значение ]` берётся, когда VAR — env
    шага `${{ matrix.K }}` и значение ноги равно; `else` — когда ни одна ветвь цепочки не
    взята. Вызов в иной конструкции (`case`, иное условие, переменная не из матрицы) — отказ.
    Вызов `--shard-plan <план> --shard "$V"` (kaname#848) — наборы шарда ноги из плана,
    записанного в ожидаемое; V — `${{ matrix.shard }}` env шага либо задания.
    """
    bound = {var: m[1] for var, val in (step.get('env') or {}).items()
             for m in [re.fullmatch(r'\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}', str(val))] if m}
    lines = step.get('run', '').splitlines()
    frames, calls, i = [], [], 0
    def branch(cond):
        m = re.fullmatch(r'(?:if|elif) \[ "\$([A-Za-z_][A-Za-z0-9_]*)" = "?([A-Za-z0-9_.-]+)"? \]; then', cond)
        if m is None or m[1] not in bound:
            return None
        require(bound[m[1]] in values, 'matrix reference outside the leg: ' + bound[m[1]])
        return str(values[bound[m[1]]]) == m[2]
    while i < len(lines):
        text = lines[i].strip()
        while text.endswith('\\') and i + 1 < len(lines):
            i += 1
            text = text[:-1] + ' ' + lines[i].strip()
        i += 1
        head = text.split(' ', 1)[0]
        if head == 'if':
            taken = branch(text)
            frames.append({'kind': 'if', 'taken': taken, 'any': bool(taken)})
        elif head == 'elif':
            require(frames and frames[-1]['kind'] == 'if', 'unbalanced shell conditional')
            taken = branch(text)
            frames[-1]['taken'] = None if taken is None else (taken and not frames[-1]['any'])
            frames[-1]['any'] = frames[-1]['any'] or bool(taken)
        elif head == 'else':
            require(frames and frames[-1]['kind'] == 'if', 'unbalanced shell conditional')
            frames[-1]['taken'] = None if frames[-1]['taken'] is None else not frames[-1]['any']
        elif head == 'fi':
            require(frames and frames.pop()['kind'] == 'if', 'unbalanced shell conditional')
        elif head == 'case':
            frames.append({'kind': 'case', 'taken': None})
        elif head == 'esac':
            require(frames and frames.pop()['kind'] == 'case', 'unbalanced shell conditional')
        if './scripts/run.sh ' not in text:
            continue
        require(head == './scripts/run.sh' and text.count('./scripts/run.sh ') == 1,
                'unsupported suite runner form')
        require(all(f['taken'] is not None for f in frames), 'unsupported service selection')
        if '--shard' in text:
            form = SHARD_PLAN_RUN.findall(text)
            env = {**(job_env or {}), **(step.get('env') or {})}
            require(len(form) == 1 and text.count('--shard') == 2 and '--service' not in text
                    and isinstance(leg, dict) and leg.get('plan') == 'tests/newman/' + form[0][0]
                    and leg.get('values') == values and isinstance(leg.get('suites'), list) and leg['suites']
                    and MATRIX_SHARD.fullmatch(str(env.get(form[0][1], ''))),
                    'unsupported shard plan selection')
            if all(f['taken'] for f in frames):
                calls.append(list(leg['suites']))
            continue
        services = re.findall(r'--service ([a-z0-9-]+)(?=\s|$)', text)
        require(services and len(services) == text.count('--service '), 'unsupported service selection')
        if all(f['taken'] for f in frames):
            calls.append(services)
    require(not frames, 'unbalanced shell conditional')
    require(calls, 'suite step selects no runner call for this leg')
    return calls


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
    values = (target.get('matrix_leg') or {}).get('values', {})
    by_name = {}
    for step in job['steps']:
        by_name.setdefault(step['name'], []).append(step)
    def passed_step(label):
        label = expand(label, values)
        selected = by_name.get(label, [])
        require(len(selected) == 1 and selected[0].get('status') == 'completed'
                and selected[0].get('conclusion') == 'success', 'required hosted step missing/skipped/red: ' + label)
    if target['workflow_job'] == 'docker-build.yml:image':
        # Публикация в исходной ветке может быть неприменима. Это только build predicate.
        passed_step('сборка образа')
        passed_step('сверка опубликованного — доказательство инъекцией в обе стороны')
        census = {'unit': 'required image build job', 'passed': 1, 'publication': 'separate-delivery-gate'}
    else:
        waves = []
        for step in target['definition']['job']['steps']:
            run = step.get('run', '')
            if './scripts/run.sh ' in run:
                require(isinstance(step.get('name'), str), 'test step has no stable name')
                calls = suite_calls(step, values, target['definition']['job'].get('env'),
                                    target.get('matrix_leg'))
                passed_step(step['name'])
                waves.extend(calls)
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
    m = unit_shard_total(exp)
    require(len(candidate['unit'].get('shards', [])) == m, 'imported unit shards differ from expectation')
    for name, definition in exp['definitions'].items():
        if 'unit_shard' in definition:
            jobs[name] = {'executor': 'external', 'import_id': import_id,
                          'census': candidate['unit']['shards'][definition['unit_shard']['index']]}
        if definition['matrix_index'] is not None:
            index = definition['matrix_index']
            jobs[name] = {'executor': 'external', 'census': candidate['integration']['shards'][index],
                          'import_id': import_id}
    hosted = hosted_names(exp)
    if not external_only:
        # Отзыв об утилизации ВМ хранится в отчёте СОДЕРЖИМЫМ (ws#1365): check судит сохранённое
        # без путей машины, на которой отчёт собран; привязка — cleanup_review_digest.
        require(isinstance(reviews, dict) and set(reviews) == set(hosted)
                and all(isinstance(r, dict) for r in reviews.values())
                and isinstance(events, dict) and set(events) == set(hosted), 'incomplete hosted contract inventory')
        for name in hosted:
            captured = hosted_capture(exp, name, events[name])
            jobs[name] = hosted_verdict(exp, name, captured, reviews[name])
    require(set(jobs) == (set(exp['jobs']) - set(hosted) if external_only else set(exp['jobs'])),
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
            paths = common.read_json(args.hosted_reviews) if args.hosted_reviews else None
            reviews = ({name: common.read_json(path) for name, path in paths.items()}
                       if isinstance(paths, dict) else paths)
            result = staged_report(exp, args.import_id, reviews,
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
