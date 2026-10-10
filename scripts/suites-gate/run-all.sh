#!/usr/bin/env bash
# Прогон набора suites-gate — свойства, общие всем наборам проверок воркспейса
# (README.md рядом). Устройство прогона одно на все наборы:
# `scripts/lib/suite-runner.sh`.
# shellcheck source-path=SCRIPTDIR
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/suite-runner.sh
. "$here/../lib/suite-runner.sh"
suite_run "$here"
