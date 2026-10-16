#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""ghjob — шаги ОДНОГО задания GitHub Actions на этой машине, в форме конвейера.

ЗАЧЕМ. Предпрогон перед CI (решение владельца 2026-10-16, ws#1110: «сначала
делается перепись, потом фиксится, потом прогоняется тесты на внешнем кластере,
потом в master ci») повторяет задания продукта шагами, как ранер: порядок,
`if:` с always()/failure()/success(), `timeout-minutes`, `continue-on-error`,
GITHUB_OUTPUT, GITHUB_ENV, GITHUB_PATH; на первом красном шаге не стоит — шаги
`if: always()` идут. До ws#1110 исполнитель жил копиями в tmp/ трёх полос
(537, w9, 820) и правился каждой заново: три случая — механизм, а не копия.

СРЕДА PYTHON. Ранер конвейера исполняет шаги системным python3 образа с его
apt-пакетами (yaml, cryptography), шаги ставят свои `pip install`. Предпрогон
идёт в своём venv (системный python машины не трогается) над системным python:
venv видит его пакеты (`--system-site-packages`, как образ — свои) и СРАЗУ
получает пакеты, которые ставят `pip install` шагов ЭТОГО задания, — выведенные
из текста шагов, а не выписанные. Причина — ws#1110: шаг 17 задания `stand`
kaname (`if: always()`) читал yaml, а шаг, ставящий pyyaml, был пропущен после
красного подъёма; посев того же задания звал cryptography, которую ни один шаг
не ставит (её несёт образ). В голом venv — «No module named …», и предпрогон
судил среду, а не дерево.
Пакет с подстановкой оболочки (`$X`) не выводится — строка «ghjob: pip …» это
называет. Отказ установки — код 4, «не выполнилось».

ФОРМА
  ghjob.py <workflow.yml> <задание> <копия> <каталог вывода> [--env K=V]…
      --env — поверх env задания (имена стенда, чтобы не столкнуться с соседом).
  ghjob.py --pip <workflow.yml> <задание>
      печатает выведенные пакеты venv — по строке; подставленные — строкой «?».

ИСХОДЫ: 0 — все исполненные шаги успешны; 1 — есть упавший шаг; 3 — шагов не
исполнено; 4 — среда не подготовлена (venv, пакеты задания) — не выполнилось;
64 — вызов неверен. Перепись — строкой «итог: шагов N, исполнено N, упало N,
пропущено N».

Действия эмулируются: checkout с `repository` — частичный клон, прочий checkout
и setup-go — копия уже на ревизии, go из PATH; upload-artifact — копия в
<вывод>/artifacts; остальные `uses:` — код 2 шага «не эмулируется». Токен
площадки (`gh auth token`) в текст шагов НЕ подставляется: `${{ github.token }}`
становится `${GITHUB_TOKEN}`, значение — в окружении шага.

ОКРУЖЕНИЕ — уровнями ранера: env workflow, поверх него env задания, поверх — шага
(`--env` — поверх задания). До ws#1115 env workflow терялся: шаг пина shellcheck
воркспейса тянул релиз `v${SHELLCHECK_VERSION}` с пустой версией — curl 404.

Доказательство — scripts/ghjob/inject.sh.
"""
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

import yaml

PIP_RE = re.compile(r'(?:^|[\s;&|(])(?:python3?(?:\.\d+)?\s+-m\s+)?pip3?\s+install\b([^\n;&|)]*)')
# Флаги pip, берущие значение отдельным словом (значение — не пакет).
PIP_VALUED = {'-c', '--constraint', '-i', '--index-url', '--extra-index-url', '-t', '--target',
              '--prefix', '--root', '-f', '--find-links', '--platform', '--python-version',
              '--implementation', '--abi', '--src', '--upgrade-strategy', '--progress-bar',
              '--log', '--proxy', '--retries', '--timeout', '--exists-action', '--trusted-host',
              '--cert', '--client-cert', '--cache-dir', '--report', '-e', '--editable'}


def pip_packages(job):
    """Пакеты `pip install` шагов задания: (пакеты, -r файлы, невыводимые)."""
    pkgs, reqs, unknown = [], [], []
    for st in job.get('steps') or []:
        run = st.get('run') if isinstance(st, dict) else None
        if not isinstance(run, str):
            continue
        text = re.sub(r'\\\n', ' ', run)
        for m in PIP_RE.finditer(text):
            try:
                words = shlex.split(m.group(1), comments=True)
            except ValueError:
                unknown.append(m.group(1).strip())
                continue
            i = 0
            while i < len(words):
                w = words[i]
                if w in ('-r', '--requirement'):
                    if i + 1 < len(words):
                        reqs.append(words[i + 1])
                    i += 2
                    continue
                if w.startswith('--requirement='):
                    reqs.append(w.split('=', 1)[1])
                elif w in PIP_VALUED:
                    i += 1
                elif w.startswith('-'):
                    pass
                elif '$' in w or '`' in w:
                    unknown.append(w)
                elif w not in pkgs:
                    pkgs.append(w)
                i += 1
    return pkgs, reqs, unknown


def die(code, msg):
    print(f'ghjob: {msg}', file=sys.stderr, flush=True)
    sys.exit(code)


def load_wf(wf, job):
    """Документ workflow и его задание <job>; отказ — 64."""
    try:
        d = yaml.safe_load(open(wf))
    except (OSError, yaml.YAMLError) as e:
        die(64, f'workflow {wf} не прочитан: {str(e).splitlines()[0]}')
    jobs = d.get('jobs') if isinstance(d, dict) else None
    if not isinstance(jobs, dict) or not isinstance(jobs.get(job), dict):
        die(64, f'задания «{job}» в {wf} нет')
    return d, jobs[job]


def load_job(wf, job):
    return load_wf(wf, job)[1]


def env_of(node):
    """env узла (документ workflow, задание) — строками, как их видит шаг."""
    e = node.get('env')
    return {k: str(v) for k, v in (e if isinstance(e, dict) else {}).items()}


# Пакеты системного python видны venv — как образу ранера его apt-пакеты.
SYS_SITE = '--system-site-packages'


def prepare_venv(venv, job, wt):
    """venv предпрогона с пакетами системы и задания; отказ — код 4."""
    cfg = os.path.join(venv, 'pyvenv.cfg')
    want = SYS_SITE == '--system-site-packages'
    try:
        fresh = (f'include-system-site-packages = {"true" if want else "false"}' in open(cfg).read()
                 and os.path.exists(os.path.join(venv, 'bin', 'python')))
    except OSError:
        fresh = False
    if not fresh:
        shutil.rmtree(venv, ignore_errors=True)
        # Основа venv — ТОТ ЖЕ системный python, что исполняет ghjob: его пакеты и
        # видны. uv — первым (ensurepip у системного python бывает снят пакетом
        # дистрибутива), иначе модуль venv.
        uv = shutil.which('uv')
        site = [SYS_SITE] if want else []
        cmd = ([uv, 'venv', '--seed', '-q', '--python', sys.executable, *site, venv] if uv
               else [sys.executable, '-m', 'venv', *site, venv])
        if subprocess.run(cmd).returncode != 0:
            die(4, f'venv {venv} не создан ({" ".join(cmd[:2])}) — не выполнилось')
    pkgs, reqs, unknown = pip_packages(job)
    for u in unknown:
        print(f'ghjob: pip-пакет «{u}» с подстановкой оболочки — не выведен, venv его не несёт', file=sys.stderr)
    if not pkgs and not reqs:
        print('ghjob: venv — pip-пакетов у задания нет', file=sys.stderr, flush=True)
        return
    args = list(pkgs)
    for r in reqs:
        args += ['-r', os.path.join(wt, r)]
    print(f'ghjob: venv — пакеты задания: {" ".join(pkgs + ["-r " + r for r in reqs])}', file=sys.stderr, flush=True)
    rc = subprocess.run([os.path.join(venv, 'bin', 'python'), '-m', 'pip', 'install', '--quiet', *args]).returncode
    if rc != 0:
        die(4, f'пакеты задания в venv не поставлены (pip код {rc}) — не выполнилось')


def main(argv):
    if len(argv) >= 1 and argv[0] == '--pip':
        if len(argv) != 3:
            die(64, 'форма: ghjob.py --pip <workflow.yml> <задание>')
        pkgs, reqs, unknown = pip_packages(load_job(argv[1], argv[2]))
        for p in pkgs:
            print(p)
        for r in reqs:
            print(f'-r {r}')
        for _ in unknown:
            print('?')
        return 0
    pos, extra = [], {}
    i = 0
    while i < len(argv):
        if argv[i] == '--env' and i + 1 < len(argv) and '=' in argv[i + 1]:
            k, v = argv[i + 1].split('=', 1)
            extra[k] = v
            i += 2
            continue
        pos.append(argv[i])
        i += 1
    if len(pos) != 4:
        die(64, 'форма: ghjob.py <workflow.yml> <задание> <копия> <каталог вывода> [--env K=V]…')
    wf, jobname, wt, out = pos
    wt = os.path.abspath(wt)
    out = os.path.abspath(out)
    WF, J = load_wf(wf, jobname)
    os.makedirs(out, exist_ok=True)
    run_tmp = os.path.join(out, 'runner-temp')
    bindir = os.path.join(out, 'bin')
    npm_prefix = os.path.join(out, 'npm')
    for d in (run_tmp, bindir, npm_prefix):
        os.makedirs(d, exist_ok=True)
    venv = os.path.join(out, 'venv')
    prepare_venv(venv, J, wt)

    def git(*a):
        return subprocess.run(['git', '-C', wt, *a], capture_output=True, text=True).stdout.strip()

    sha = git('rev-parse', 'HEAD')
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        die(64, f'копия {wt} не git-копия')
    m = re.search(r'github\.com[:/](.+?)(?:\.git)?$', git('remote', 'get-url', 'origin'))
    repo = m.group(1) if m else ''
    ref = git('rev-parse', '--abbrev-ref', 'HEAD')
    env = dict(os.environ)
    env.update({
        'CI': 'true', 'GITHUB_ACTIONS': 'true', 'GITHUB_WORKSPACE': wt, 'RUNNER_TEMP': run_tmp,
        'GITHUB_SHA': sha, 'GITHUB_REF': f'refs/heads/{ref}', 'GITHUB_REF_NAME': ref,
        'GITHUB_EVENT_NAME': 'push', 'GITHUB_REPOSITORY': repo, 'GITHUB_JOB': jobname,
        'GOBIN': bindir, 'NPM_CONFIG_PREFIX': npm_prefix,
    })
    # Уровни ранера: env workflow, поверх — задания (шага — у шага ниже).
    env.update(env_of(WF))
    env.update(env_of(J))
    env.update(extra)
    try:
        gh_token = subprocess.check_output(['gh', 'auth', 'token'], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        gh_token = ''
    extra_path = []  # GITHUB_PATH — впереди системного, позади своих каталогов
    outputs, outcomes, results = {}, {}, []
    state = {'job_ok': True}

    def path_of():
        return ':'.join([os.path.join(venv, 'bin'), os.path.join(npm_prefix, 'bin'), bindir] + extra_path + [os.environ['PATH']])

    def expr(s, in_script):
        def sub(mm):
            e = mm.group(1).strip()
            if e == 'github.token':
                return '${GITHUB_TOKEN}' if in_script else gh_token
            if e == 'github.workspace':
                return wt
            if e == 'runner.temp':
                return run_tmp
            if e in ('github.sha', 'github.repository', 'github.ref', 'github.ref_name', 'github.job'):
                return env['GITHUB_' + e.split('.', 1)[1].upper()]
            mo = re.fullmatch(r'steps\.([\w-]+)\.outputs\.([\w-]+)', e)
            if mo:
                return outputs.get(mo.group(1), {}).get(mo.group(2), '')
            mo = re.fullmatch(r'steps\.([\w-]+)\.(?:outcome|conclusion)', e)
            if mo:
                return outcomes.get(mo.group(1), 'skipped')
            mo = re.fullmatch(r'env\.(\w+)', e)
            if mo:
                return env.get(mo.group(1), '')
            die(64, f'выражение не разобрано: {e}')
        return re.sub(r'\$\{\{(.*?)\}\}', sub, s)

    def cond(c):
        c = c.strip()
        if c.startswith('${{'):
            c = c[3:-2]
        py = re.sub(r"steps\.([\w-]+)\.(?:outcome|conclusion)", lambda mm: repr(outcomes.get(mm.group(1), 'skipped')), c)
        py = py.replace('always()', 'True').replace('cancelled()', 'False')
        py = py.replace('success()', repr(state['job_ok'])).replace('failure()', repr(not state['job_ok']))
        py = re.sub(r'\btrue\b', 'True', re.sub(r'\bfalse\b', 'False', py))
        py = py.replace('&&', ' and ').replace('||', ' or ')
        py = re.sub(r'!(?!=)', ' not ', py).replace("'", '"')
        return bool(eval(py))  # noqa: S307 — условие своего workflow, не чужой ввод

    def kv(path):
        o, lines, k = {}, open(path).read().split('\n'), 0
        while k < len(lines):
            ln = lines[k]
            k += 1
            mm = re.match(r'^([^=<]+)<<(.+)$', ln)
            if mm:
                buf = []
                while k < len(lines) and lines[k] != mm.group(2):
                    buf.append(lines[k])
                    k += 1
                k += 1
                o[mm.group(1)] = '\n'.join(buf)
            elif '=' in ln:
                a, b = ln.split('=', 1)
                o[a] = b
        return o

    def has_status_fn(c):
        return c is not None and any(f in str(c) for f in ('always()', 'failure()', 'cancelled()', 'success()'))

    for i, s in enumerate(J.get('steps') or []):
        name = s.get('name') or s.get('uses') or (s.get('run') or '').splitlines()[0]
        sid = s.get('id') or f'_{i}'
        c = s.get('if')
        run_it = cond(str(c)) if has_status_fn(c) else (state['job_ok'] and (c is None or cond(str(c))))
        rec = {'i': i, 'name': name, 'id': sid}
        if not run_it:
            outcomes[sid] = 'skipped'
            rec['outcome'] = 'skipped'
            results.append(rec)
            continue
        t0 = time.time()
        uses = s.get('uses', '')
        rc = 0
        log = os.path.join(out, f'step-{i:02d}.log')
        with open(log, 'w') as lf:
            if uses.startswith('actions/checkout') and 'repository' in (s.get('with') or {}):
                w = {k: expr(str(v), False) for k, v in s['with'].items()}
                dst = os.path.join(wt, w.get('path', '.'))
                shutil.rmtree(dst, ignore_errors=True)
                sparse = w.get('sparse-checkout', '').split()
                cmd = (f"git clone -q --filter=blob:none --no-checkout https://github.com/{shlex.quote(w['repository'])} {shlex.quote(dst)}"
                       + (f" && git -C {shlex.quote(dst)} sparse-checkout set {' '.join(map(shlex.quote, sparse))}" if sparse else '')
                       + f" && git -C {shlex.quote(dst)} checkout -q {shlex.quote(w.get('ref', 'HEAD'))}")
                rc = subprocess.run(['bash', '-c', cmd], stdout=lf, stderr=subprocess.STDOUT, env=env).returncode
            elif uses.startswith('actions/checkout') or uses.startswith('actions/setup-go'):
                lf.write(f'эмуляция: {uses} — копия {wt} уже на ревизии, go из PATH\n')
            elif uses.startswith('actions/upload-artifact'):
                w = s.get('with') or {}
                src = os.path.join(wt, expr(str(w.get('path', '')), False))
                dst = os.path.join(out, 'artifacts', str(w.get('name', 'artifact')))
                if os.path.exists(src) and (os.path.isfile(src) or os.listdir(src)):
                    if os.path.isdir(src):
                        shutil.copytree(src, dst, dirs_exist_ok=True)
                    else:
                        os.makedirs(os.path.dirname(dst), exist_ok=True)
                        shutil.copy(src, dst)
                    lf.write(f'артефакт {w.get("name")} → {dst}\n')
                else:
                    lf.write(f'артефакт {w.get("name")}: файлов нет ({src})\n')
                    rc = 1 if w.get('if-no-files-found') == 'error' else 0
            elif 'run' in s:
                script = expr(s['run'], True)
                sf = os.path.join(out, f'step-{i:02d}.sh')
                open(sf, 'w').write(script)
                gho, ghe, ghp = (os.path.join(out, f'step-{i:02d}.{x}') for x in ('output', 'env', 'path'))
                for f in (gho, ghe, ghp):
                    open(f, 'w').close()
                senv = dict(env)
                senv.update({k: expr(str(v), False) for k, v in (s.get('env') or {}).items()})
                senv.update({'GITHUB_OUTPUT': gho, 'GITHUB_ENV': ghe, 'GITHUB_PATH': ghp, 'GITHUB_TOKEN': gh_token,
                             'GITHUB_STEP_SUMMARY': os.path.join(out, 'summary.md'), 'PATH': path_of()})
                tmo = s.get('timeout-minutes')
                p = subprocess.Popen(['bash', '--noprofile', '--norc', '-eo', 'pipefail', sf],
                                     cwd=os.path.join(wt, s.get('working-directory', '.')),
                                     stdout=lf, stderr=subprocess.STDOUT, env=senv, start_new_session=True)
                try:
                    rc = p.wait(timeout=tmo * 60 if tmo else None)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGTERM)
                    time.sleep(5)
                    try:
                        os.killpg(p.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    p.wait()
                    rc = 124
                    lf.write(f'\nghjob: шаг оборван по timeout-minutes={tmo}\n')
                outputs[sid] = kv(gho)
                env.update(kv(ghe))
                for line in open(ghp):
                    if line.strip():
                        extra_path.insert(0, line.strip())
            else:
                lf.write(f'ghjob: шаг вида {uses} не эмулируется\n')
                rc = 2
        outcome = 'success' if rc == 0 else 'failure'
        outcomes[sid] = outcome
        if outcome != 'success' and not s.get('continue-on-error'):
            state['job_ok'] = False
        rec.update({'outcome': outcome, 'rc': rc, 'secs': round(time.time() - t0), 'log': log})
        results.append(rec)
        print(f'[{jobname}] {i:02d} {outcome:8} rc={rc} {round(time.time() - t0)}s {name}', flush=True)

    json.dump({'job': jobname, 'job_ok': state['job_ok'], 'steps': results},
              open(os.path.join(out, 'result.json'), 'w'), ensure_ascii=False, indent=1)
    ran = [r for r in results if r['outcome'] != 'skipped']
    print(f'[{jobname}] итог: шагов {len(results)}, исполнено {len(ran)}, '
          f'упало {sum(1 for r in ran if r["outcome"] == "failure")}, пропущено {len(results) - len(ran)}; '
          f'job_ok={state["job_ok"]}', flush=True)
    return 3 if not ran else (0 if state['job_ok'] else 1)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
