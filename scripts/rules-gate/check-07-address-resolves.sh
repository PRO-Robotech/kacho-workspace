#!/usr/bin/env bash
# check-07 — АДРЕС НОРМЫ РЕЗОЛВИТСЯ, id УНИКАЛЕН.
# Предмет: перенос текста между файлами рвёт ссылку молча. Область ШИРЕ, чем у
# `skills-gate/check-01`: агенты, правила, `CLAUDE.md` и гейты продукта.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 scripts/rules-gate/address-refs.py
