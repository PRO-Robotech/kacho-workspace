# Архив: testing-newman.md

Снято 2026-09-20. Норма живёт в `.claude/rules/testing-newman.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.
Также остался нормой (искл. а — повелительная форма) `robust-ryw-not-masking`, хотя опись
отнесла абзац, из которого он взят (`n-header`), к классу D: «...newman обязан быть robust
к read-your-writes окну, но НИКОГДА не маскировать реальный дефект» — прямой императив
(«обязан», «никогда не»). Остаток того же абзаца — навигация, ниже в этом архиве.

## n-header (класс D — не норма; императивный хвост абзаца ушёл нормой `robust-ryw-not-masking`)

«Часть правила `.claude/rules/testing.md`. Инварианты, общие всем suite'ам — RYW-retry,
authz-first толерантность негативов, per-service fixture isolation, идемпотентность
прогона, — живут там же, §«e2e-инварианты», и здесь не повторяются.» Навигация и пересказ
eventual-consistency из `api-conventions.md` — предмета нормы не несут.

## poll-cost-and-symptom (класс D — замер и симптом, не норма)

«Цена измерена. Без него петля на 30 итераций покрывает ~0.15s, а не секунды: op завершался
за 3.6s, а кейс сдавался мгновенно (инцидент IAM-USR-INV-CRUD-OK; sweep нашёл 51 такую петлю
в 26 case-файлах iam/registry/nlb).» «Симптом класса: «поллер сдался, хотя async-хвост был
здоров» — выглядит как materialization-лаг сервиса, а на деле проба вообще не ждала.»
Норма (без замера и симптома) — в корпусе как `poll-busywait-before-setnextrequest`.

## parallel-run-and-pointwise-debug (класс C — процесс, гейта нет)

«Параллельный прогон суит и точечный debug. newman-parallel.sh fan-out iam/vpc/compute/nlb
после единого seed → wall-time = max(суита), убирает serial-timeout (суиты независимы при
изоляции). Debug — точечно: newman run collections/<битая>.json + --folder <case>; Go-фикс →
make reload-svc SVC=x (patch без dev-up) → re-run той коллекции.»

## n-meta (класс D — пересказ раздела, не норма)

«Мета: массовая параллелизация большого e2e (65+ коллекций) — инженерная задача пирога
throughput+isolation+idempotency, а не «добавить retry». Retry-обёртки — для истинного
read-your-own-writes EC-окна; не лечат collision/phantom/idempotency (там — fixture-изоляция/
энтропия/preclean-retry). Прод-фиксы (форвард/lock/delete-stale) — TDD+db-review; тест-фиксы
не маскируют.»

## edge-is-newman — поток подписки (класс D — замер; исключение снято 2026-09-23)

Прежняя редакция отдавала тело потока playwright: «ответ-поток newman не дочитывает». Замер
опроверг довод. newman 6.2.2 (конвейер — `newman@6`) против локального SSE (chunked, кадры
`opened` и `event`, служебный кадр раз в 1 с): поток, закрытый сервером через 3 с, — 200,
тело с обоими кадрами, 3 утверждения из 3; незакрывающийся поток — newman не вернулся за 60 с
и при `--timeout-request 8000`. Край kacho закрывает поток сам и чисто: `StreamBudget`
(`KACHO_API_GATEWAY_SUBSCRIPTION_STREAM_BUDGET`, умолчание 90s; чарт
`gateway/deploy/values.yaml` — `streamBudget: 90s`), ветвь `ctx.Done()` в `pump`
(`gateway/internal/subscriptionstream/handler.go`) @kacho 1d42a6728bf; `--timeout-request`
прогонщики kacho не ставят. Итог: тело потока newman читает до закрытия по сроку, консоль
поверх потока — playwright.
