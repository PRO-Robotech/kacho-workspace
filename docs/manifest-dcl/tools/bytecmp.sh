#!/usr/bin/env bash
# Побайтовая сверка порождённой модели с блоками живой. Не «совпадает по
# смыслу» — идентична: модель есть контракт, и лишняя строка в ней это
# лишнее право.
set -u
Y="${1:-../vpc.manifest.yaml}"
python3 yaml2fga.py "$Y" > /tmp/gen.fga 2>/dev/null || { echo "✗ генерация упала"; exit 2; }
[ -s /tmp/gen.fga ] || { echo "✗ произведено НОЛЬ байт — сверять нечего"; exit 2; }
if cmp -s live-vpc-blocks.fga /tmp/gen.fga; then
  echo "✓ идентично: $(wc -c < /tmp/gen.fga) байт, md5 $(md5sum < /tmp/gen.fga | cut -c1-12)"
  exit 0
fi
echo "✗ расходится:"; diff -u live-vpc-blocks.fga /tmp/gen.fga | grep -E '^[-+][^-+]' | head -6
exit 1
