#!/usr/bin/env bash
# Прогон набора skills-gate — утверждения скилов о себе и о дереве сверены с
# деревом (README.md рядом). Вердикт стоит в КОДЕ ВЫХОДА, а не в печати.
#
# Устройство прогона — одно на все наборы: `scripts/lib/suite-runner.sh` (три
# исхода и их коды, пустой обход — находка, объём осмотренного обязателен,
# рабочий каталог проверки — пустой чужой репозиторий). Своей копии цикла у
# набора нет: свойство, заведённое в одной копии, до ws#762 не доезжало до
# соседних.
# shellcheck source-path=SCRIPTDIR
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/suite-runner.sh
. "$here/../lib/suite-runner.sh"
suite_run "$here"
