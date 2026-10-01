# Поверхность до посадки — #2917 E2 anonmail: метрики, правила тревоги, выключатель

- ревизия: `56080205e21d1cf8f4b49477a6b15f0a8a0a67f8` (ветка `2917-e2-anonmail-lane`), дельта `f2b0b18fa66..56080205e21`
- режим: поверхность до посадки, узкая дельта; планка — высокая/средняя
- вердикт: ✅ принято на `56080205e21`

## Объём осмотренного

`git diff --stat f2b0b18fa66..56080205e21` — 25 файлов (+1074/−159). Прочитаны целиком по диффу:
`gateway/internal/observability/metrics/anon_mail.go`, `gateway/deploy/templates/prometheusrule.yaml`,
`gateway/deploy/values.yaml`, пять слоёв `deploy/helm/umbrella/values.{a8f60d,dev,fe3455,own-stand,prorobotech}.yaml`,
`gateway/internal/middleware/anonmail/{store,store_pg,store_memory,gate,ladder,doc}.go`,
`gateway/docs/content/install/observability.mdx`. Тестовые файлы — по grep на метки/журнал.

## Вопросы задания

1. **Метки метрик.** Два новых дескриптора (`…_bucket_hold_seconds_total`, `…_clock_offset_seconds`)
   объявлены `prometheus.NewDesc(name, help, nil, nil)` — ни переменных, ни постоянных меток; значения —
   агрегаты процесса (сумма удержаний, последнее смещение). Ключи запроса, адреса, подсети в серию
   не попадают. Предикат: `git diff f2b0b18fa66..HEAD | grep -nE '^\+.*(NewDesc|NewCounterVec|NewGaugeVec|ConstLabels)'`
   → только два `NewDesc` без меток. Новых вызовов журнала в дельте нет (тот же grep по `slog.`/`log.*` — пусто).
2. **Правила тревоги.** Четыре правила; `labels` — только `severity`, `annotations.summary` — постоянный
   текст без шаблонных подстановок (`{{ $labels }}`/`$value` нет). Выражения агрегируют `sum`/`max` без
   `by(...)` — метки источника в уведомление не протекают (их и нет у серий).
3. **Выключатель.** Перенесён из `api-gateway.alertRules` в `global.kacho.alertRules`; перепись старого
   адреса на базе — 5 слоёв зонтика + корень values чарта, на голове все 5 слоёв переведены, в корне
   ручки нет (`git grep -n alertRules f2b0b18fa66` vs `HEAD`). Рендер fail-closed: отсутствие блока или
   `enabled` даёт `fail` без `disabledBecause`. Тихо недействующего второго адреса не осталось.
   Выключатель касается только наблюдаемости и ни одного защитного контроля не снимает.

## Находки

Высокой и средней тяжести — 0. Раунд сухой.

## Проверки

`go test -count=1 ./internal/observability/metrics/ ./deploy/` (в `gateway/`) @56080205e21 — 2 пакета ok.
