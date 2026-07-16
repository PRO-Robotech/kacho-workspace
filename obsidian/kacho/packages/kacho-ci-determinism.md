---
title: CI — детерминизм: пины версий и честные exit-коды
category: packages
repo: kacho
layer: ci
status: stable
tags: [packages, architecture, migrations, go]
---

# CI: local == CI по построению

Два класса дефектов, при которых **гейт зелёный, а проверено не то**. Оба вскрыты
2026-07-16 первым прогоном `e2e-newman` на чистом кластере ([[kacho-ci-runners]]).

## Пины версий: local == CI по построению

Разъезд версий даёт гейт, который зеленеет, проверяя НЕ то, что в проде.

> [!danger] `azure/setup-helm@v4` без `version` притащил **Helm 4**
> Локально и на проде — **v3.17**, CI молча ставил **v4.2.3** (action ставит latest).
> Helm 4 по умолчанию делает **server-side apply** (Helm 3 — client-side 3-way merge),
> где владение полями энфорсится → `UPGRADE FAILED: conflict with "kubectl-patch"`.
> Гейт `helm lint · template` при этом был ЗЕЛЁНЫЙ — он валидировал чарты чужой
> версией. Запинен `v3.17.0`. Сама несовместимость чартов с Helm 4 — долг, kacho#3.

Так же запинены: buf `1.69.0`, golangci-lint `v2.12.2`, protoc-плагины через
`tools/tools.go` (CI ставит их БЕЗ `@latest`). `govulncheck` ОСТАЁТСЯ на `@latest`
осознанно — ему нужна свежая база CVE.

## `; \`-цепочка в Makefile лжёт про успех

`dev-up` — одна `; \`-цепочка: упавшая команда **не прерывает цель**. Наблюдалось
2026-07-16 — `helm phase 2` упал с `UPGRADE FAILED`, цель дошла до конца, напечатала
`dev-up complete` и отдала **exit 0**. Стенд был собран наполовину (mTLS не применён,
fga-bootstrap без SA), CI считал его поднятым и шёл гонять newman — краснота вылезала
позже и в другом месте. Тот же класс, что near-miss 2026-07-15 (упавший
`use-context` не прервал цепочку → стенд поехал на ПРОД). Лечится `set -e` в начале
рецепта (команды, которым падать разрешено, несут `|| true`).

Связано: [[kacho-ci-runners]], [[kacho-monorepo]].

#packages #architecture #migrations #go
