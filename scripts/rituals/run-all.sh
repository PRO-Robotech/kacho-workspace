#!/usr/bin/env bash
# Прогон набора rituals — самопробы ритуалов потока (тело PR, закрытие волны, событие
# одобрения, trail хранилища) на подставном репозитории и подставном трекере
# (ws#930; README.md рядом). Вердикт стоит в КОДЕ ВЫХОДА, а не в печати.
#
# Устройство прогона — одно на все наборы: `scripts/lib/suite-runner.sh` (три
# исхода и их коды, пустой обход — находка, объём осмотренного обязателен,
# рабочий каталог проверки — пустой чужой репозиторий).
# shellcheck source-path=SCRIPTDIR
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/suite-runner.sh
. "$here/../lib/suite-runner.sh"
suite_run "$here"
