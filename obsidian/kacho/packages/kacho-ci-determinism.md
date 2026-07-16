---
title: CI — детерминизм: пины версий и честные exit-коды
category: packages
repo: kacho
layer: ci
status: stable
tags: [packages, architecture, migrations, go]
---

# CI: local == CI по построению

> [!danger] Сверяйся с CI ЕГО метрикой, а не похожей своей
> gosec-гейт считает по SARIF `level == "error"`. Это **не** `severity == HIGH` из
> JSON-вывода: G304 в `pkg/internal/tlsutil` приходит **MEDIUM** в JSON, но
> **level=error** в SARIF. Локальная проверка «severity==HIGH» показывала 0, пока CI
> честно краснел, — находка выглядела невоспроизводимой. Комментарий в гейте при этом
> утверждал «severity error (HIGH)» (унаследовано из polyrepo) и уводил в сторону.
> Правильная локальная команда:
> ```
> gosec -exclude-dir=pkg/api -fmt sarif -out g.sarif ./... && \
>   jq '[.runs[].results[]|select(.level=="error")]|length' g.sarif
> ```
> Директива подавления у gosec — **`// #nosec G115 -- причина`**. `//nolint:gosec` —
> это golangci-lint, gosec его игнорирует (проверено: 11 находок не сдвинулись).

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

## Автообновление: dependabot + сторож за пинами

`dependabot.yml` в polyrepo был **у 2 репо из 12** (compute, vpc) и покрывал gomod +
github-actions. В монорепе — 4 экосистемы: **gomod** (единый модуль = весь Go-граф),
**github-actions** (сюда попадают СКАНЕРЫ trivy/codeql — интервал weekly, не monthly),
**docker** (базовые образы), **npm** (консоль: workspace + все standalone-пакеты).

> [!warning] Dependabot НЕ видит версию внутри шага
> Он обновляет `uses:`, go.mod, package.json, Dockerfile-FROM — но не
> `with: {version: v3.17.0}`, не `go install …@v2.12.2` и не URL в `curl`. А пиним мы
> именно так. Такой пин протухает **молча**.

Закрыто `pinned-tools-freshness` (еженедельно) + `.github/scripts/check-pinned-tools.sh`
(гоняется локально). Сверяет пины с апстримом, держит ОДИН переиспользуемый issue.
Ничего не обновляет сам. Осознанные **HOLD** (helm — до kacho#3) в отчёт не попадают,
иначе issue шумит вечно.

Гочи скрипта: разделитель `sed` — **`#`** (`/` ломается на URL'ах, `|` — на alternation
в ERE); многострочный markdown в inline-`run:` ломает YAML → вынесен в скрипт.

Связано: [[kacho-ci-runners]], [[kacho-monorepo]].

#packages #architecture #migrations #go
