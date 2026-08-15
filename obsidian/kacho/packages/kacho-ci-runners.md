---
title: CI монорепы — ранеры и раскладка job'ов
category: packages
repo: kacho
layer: ci
status: stable
tags: [packages, architecture, dependencies, go]
---

# CI монорепы: где что исполняется

Два хоста, выбор — по **замерам**, не по предпочтению. Раскладка сложилась
2026-07-16 (см. [[kacho-monorepo]]).

## Хосты (измерено, а не из доков)

| | beget-runner | ubuntu-latest |
|---|---|---|
| Ядра | **12** | 4 |
| Память | **15 ГБ** (14 своб.) | 15 ГБ |
| Диск | **29 ГБ (~11 своб.)** ⚠️ | 89 ГБ |
| Параллелизм | **1 job** (ранер один → очередь) | job = своя VM |
| Кэш слоёв | **переживает прогоны** | холодный каждый раз |

Память ранера поднята до 15 ГБ **2026-07-16** (было 3.8 ГБ — стенд newman тогда не
влезал, см. ниже). Теперь узкое место — **диск**: 29 ГБ, свободно ~11 (остальное
занимает кэш buildkit от `docker-build`).

`beget-runner` подключён **на уровне организации** и шарится в репо. Из репо он
**не виден**: `gh api repos/.../actions/runners` отдаёт пустой список, а
`orgs/PRO-Robotech/actions/runners` — 403 без `admin:org`. Пустой repo-список ≠
«ранеров нет».

> [!warning] `runs-on: beget-runner` не сработает никогда
> `beget-runner` — **имя** ранера. Метки у него дефолтные: `self-hosted`, `Linux`,
> `X64`. Целиться надо в **метку** (`runs-on: self-hosted`); по имени job не матчится
> и висит в очереди молча — без единой ошибки, до таймаута.

На ранере нет `go`/`kubectl`/`helm`/`node` — только docker (демон живой), git, jq,
make. Тулчейны ставятся `actions/setup-*` (кэшируются в tool-cache ранера).

## Раскладка

- **`docker-build` → beget-runner.** Выигрыш — 12 ядер + локальный кэш: холодная
  сборка 76-95с, горячая **30с**; весь прогон 8 образов — **2:27**. Мультиарх почти
  бесплатен: Dockerfile'ы несут `FROM --platform=$BUILDPLATFORM` + `GOOS/GOARCH`,
  т.е. Go **кросс-компилируется** нативно, QEMU эмулирует лишь финальный alpine-слой.
- **`e2e-newman` → beget-runner** (после апгрейда памяти). Стенд требует 4.2 ГБ
  memory.requests — на 3.8 ГБ не влезал даже урезанный (3.08 ГБ + kind ~0.7 ГБ).
- **`ci` → ubuntu-latest.** Ранер ОДИН: держать на нём ещё и 12 job'ов `ci` (включая
  матрицу integration на 7 сервисов с testcontainers) — значит выстроить их в очередь
  за e2e (~20 мин). Быстрый сигнал важнее.

> [!warning] Стенд в CI обязан подниматься с НУЛЯ
> На ubuntu-latest VM одноразовая — чистить нечего. На self-hosted машина живёт, и
> kind-кластер переживает job'ы. Переиспользованный стенд — НЕ экономия, а источник
> **ложных падений**: доказано 2026-07-16 — в кластере, пережившем много прогонов,
> накопились мусорные AccessBinding'и, и кейсы, ждущие чистое состояние, краснели
> «сами по себе». `kind delete` — ДО и ПОСЛЕ (`if: always()`): прошлый job мог упасть
> жёстко и не дойти до уборки, а брошенный кластер съедает диск, где свободно 11 ГБ,
> и роняет следующую СБОРКУ на `no space left`.

**sudo не гарантирован.** На ubuntu-latest беспарольный sudo есть всегда — на
self-hosted нет. Тулчейны (kind) ставим в `~/bin` + `GITHUB_PATH`. Ровно тот класс
различий, на котором «работало на hosted» ломается при переезде.

**ui-unit host jest-ESM link-hang — КОРЕНЬ: `@ant-design/icons` Proxy-мок (kacho#7).**
Точный root-cause сведён 6 CI-DIAG-итерациями 2026-07-16, опровергнув **8 гипотез**:
async-leak (виснет с `--forceExit`), host-vs-docker (`container: node:22` тоже виснет),
GitHub-VM-vs-real (**self-hosted beget ТОЖЕ виснет 18 мин** — «GitHub-VM-специфично» ОПРОВЕРГНУТО),
node-patch (22.23.1 локально ok), install-layout/dual-react, ulimit/threadpool-старвейшн
(raised → всё равно висит), CPU-scheduling (taskset 1-CPU ok).

**Механизм (изолирован DIAG6):** `setup.ts` мокал `@ant-design/icons` через
`jest.unstable_mockModule`, возвращая **Proxy**. Proxy НЕ даёт СТАТИЧЕСКИХ named-экспортов,
поэтому под `--experimental-vm-modules` ESM-линкер `import { ApartmentOutlined } from
'@ant-design/icons'` (HostRail, 20 иконок) **висит ВЕЧНО**, ожидая binding — доказано:
изолированный `import { XOutlined }` виснет на LINK ДАЖЕ без рендера; lucide-иконки (real) — ok.
Виснут ровно 3 shell-теста (App/HostShell/HostRail) — все рендерят HostRail, единственный
импортёр `@ant-design/icons`. libuv висящего процесса: только findBy-таймер (render не доходит).

> [!danger] Локально jest МОЛЧА no-op'ит shell-import тесты (false-green, прятал баг)
> На локальной машине jest под `--experimental-vm-modules` на shell-import тесте выдаёт **0 байт
> вывода + exit 0 даже с failing-assert** (тот же link-провал → тихий выход). Поэтому «локально
> проходит за 2с» было ИЛЛЮЗИЕЙ — jest их не исполнял. Тривиальный тест (без импортов) исполняется
> нормально. Это отдельная опасность: `npm test` локально даёт ложный green на shell-тестах.

**Фикс (kacho#7):** `moduleNameMapper ^@ant-design/icons$` → `src/test/antd-icons-stub.tsx`
(20 реальных статических named-экспортов `<span>`) → линкер резолвит. Убран сломанный
`unstable_mockModule` из `setup.ts`. Заодно снимает исходную ESM/CJS-гонку antd↔icons.
**Проверено на CI: 3 бывших-виснущих файла ✓, host 13 suites/31 tests зелёный.**
`runs-on: ubuntu-latest` (дефолтный ранер — корень не в окружении). Guard на 3 shell-теста
ловит регресс класса. Ранняя гипотеза «фикс = self-hosted» — ОПРОВЕРГНУТА (self-hosted тоже висел).

## Гочи одного ранера (не повторять)

**Матрица на одном ранере — вредна.** Она окупается только при параллельных job'ах.
Замер: сумма сборок 5.4 мин, прогон — **14 мин**; ~8 мин съели 7 передач job'ов
(GitHub отдаёт ранеру следующий job с задержкой ~минуту). Схлопнуто в один job с
циклом. Шаги job'а суммарно ~25с, checkout — **1с** (на self-hosted workspace
переживает прогоны).

**`concurrency: cancel-in-progress` обязателен.** Ранер один: два пуша подряд ставят
16 job'ов в очередь, и она растёт быстрее, чем разбирается.

**Уборка диска обязательна.** Кэш buildkit копится вечно при 29 ГБ диска (свободно
~11) → `no space left on device` в момент, не связанный с коммитом-виновником.
`buildx prune --keep-storage=6GB` + `if: always()` (красный прогон тоже обязан убрать
за собой).

Детерминизм (пины версий, `; \`-цепочки) — [[kacho-ci-determinism]].

## Стенд newman (e2e-newman)

dev-профиль поднимает **5** локальных `:dev`-образов (iam, vpc, compute, nlb,
api-gateway); `geo` тянется готовым образом с DockerHub, storage/registry в dev
выключены → newman гоняется по iam/vpc/compute/nlb. Стенд поднимает `make dev-up` (он
сам создаёт kind-кластер нашим kind-config) — CI идёт тем же путём, что и
разработчик. Замер: `dev-up complete in 303s`, 26 подов Running.

Связано: [[kacho-monorepo]], [[fe3455-production-deploy]], [[../rpc/iam-access-binding-service]].

#packages #architecture #dependencies #go
