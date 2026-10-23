#!/usr/bin/env python3
"""Проверка реального архивного запуска; только внешний тестовый исполнитель."""
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
PROBE = '''import importlib.util, sys
s = importlib.util.spec_from_file_location('stand', sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
try:
    print(m.registry())
except m.Unread:
    print('unread', file=sys.stderr)
    sys.exit(2)
'''


class ArchiveRegistry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.co = self.root / 'workspace'
        self.git('init', '-q', str(self.co))
        scripts = self.co / 'scripts'
        scripts.mkdir()
        shutil.copy2(HERE / 'operator-stand.py', scripts)
        self.git('-C', str(self.co), 'remote', 'add', 'origin',
                 'git@github.com:PRO-Robotech/kacho-workspace.git')
        self.git('-C', str(self.co), 'add', 'scripts')
        subprocess.run(['bash', '-c', 'source "$1"; sandbox_git_home "$2" && '
                        'sandbox_git -C "$3" commit -qm fixture', 'fixture',
                        str(HERE / 'lib/sandbox-git-home.sh'),
                        str(self.root / 'git-home'), str(self.co)], check=True)
        self.archive = self.root / 'archive'
        self.archive.mkdir()
        data = subprocess.check_output(['git', '-C', str(self.co), 'archive', 'HEAD', 'scripts'])
        with tarfile.open(fileobj=io.BytesIO(data)) as stream:
            stream.extractall(self.archive, filter='data')
        self.expected = str(self.co / 'tmp/operator-stand-registry')

    def git(self, *args):
        subprocess.run(['git', *args], check=True, capture_output=True)

    def probe(self, source, binding=None):
        env = dict(os.environ)
        env.pop('LANDING_PRECHECK_WS', None)
        if binding is not None:
            env['LANDING_PRECHECK_WS'] = str(binding)
        return subprocess.run(['python3', '-I', '-c', PROBE,
                               str(source / 'scripts/operator-stand.py')],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def accepted(self, source, binding=None):
        got = self.probe(source, binding)
        self.assertEqual(got.returncode, 0, got.stderr)
        self.assertEqual(got.stdout.strip(), self.expected)

    def refused(self, binding):
        got = self.probe(self.archive, binding)
        self.assertEqual(got.returncode, 2, got.stderr)
        self.assertEqual(got.stderr.strip(), 'unread')
        self.assertEqual(got.stdout, '')

    def test_direct(self):
        self.accepted(self.co)

    def test_archive(self):
        self.accepted(self.archive, self.co)

    def test_linked_worktree(self):
        linked = self.root / 'linked'
        self.git('-C', str(self.co), 'worktree', 'add', '--detach', str(linked), 'HEAD')
        self.accepted(linked)
        self.accepted(self.archive, linked)

    def test_missing_binding(self):
        self.refused(None)

    def test_empty_binding(self):
        self.refused('')

    def test_non_git(self):
        self.refused(self.archive)

    def test_nonexistent(self):
        self.refused(self.root / 'missing')

    def test_nested_directory(self):
        self.refused(self.co / 'scripts')

    def test_wrong_repository(self):
        self.git('-C', str(self.co), 'remote', 'set-url', 'origin',
                 'git@github.com:PRO-Robotech/registry-operator.git')
        self.refused(self.co)

    def test_missing_origin(self):
        self.git('-C', str(self.co), 'remote', 'remove', 'origin')
        self.refused(self.co)


if __name__ == '__main__':
    unittest.main(verbosity=2)
