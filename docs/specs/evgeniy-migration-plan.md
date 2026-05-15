# Migration Plan — применение skill `evgeniy` к kacho-vpc / kacho-compute / kacho-resource-manager

> Skill: `kacho-workspace/.claude/skills/evgeniy/SKILL.md`. План повторяет §12 из skill, расширен YT-эпиками и приоритизацией.

## Origin

Ревью @EvgenyGRI / @pointpu, PR PRO-Robotech/kacho-vpc#52 commit `9d865df` 2026-05-14. 48 архитектурных правил extracted и оформлены в `evgeniy` skill.

PR #52 в CONFLICTING state (112 commits behind main), сам не подлежит straight merge. **Ребейз нереалистичен** — за неделю vpc эволюционировал в 100+ файлах. План ниже — нормативный «переход к этой архитектуре» отдельной серией PR'ов.

## Краткий ITEMIZED план (11 фаз)

| Фаза | Описание | Объём | Зависит от |
|---|---|---|---|
| 1 | Domain newtypes + Validate (D.2-D.10) | 8 resource × ~3 файла = 24 PR'а | — |
| 2 | Domain builders + constants (D.7-D.9) | 8 resource × 1 PR | 1 |
| 3 | UseCases вместо Services (B.1-B.4) | 8 resource × 1 PR | 2 |
| 4 | DTO table-driven (C.1-C.6) | 1 PR core + 8 per-resource | 1 |
| 5 | CQRS Repository (G.1-G.7) | 1 PR per-service | 3, 4 |
| 6 | YAML config + viper (J.1-J.7) | 1 PR per-service | — |
| 7 | cmd/migrator отдельный (K.1-K.3) | 1 PR per-service | 6 |
| 8 | ExecAbstract параллельные servers (K.4-K.5) | 1 PR per-service | 6, 7 |
| 9 | gRPC client-builder (K.6) | 1 PR per-service | — |
| 10 | operations.Run preserve context (I.3) | 1 PR в corelib + per-service | — (corelib) |
| 11 | ER-diagrams + docs (E.6) | 1 PR per-service | 5 |

**Оценка**: ~33 рабочих дня, 6-7 недель fulltime на kacho-vpc (template). Дальше compute / rm берут общие паттерны и идут быстрее (по ~3-4 недели каждый).

## Приоритизация

**Wave 1 — quick wins, низкий риск:**
- Фаза 6 (config refactor) — не ломает контракт API.
- Фаза 7 (cmd/migrator) — не ломает контракт.
- Фаза 9 (client-builder) — drop-in replacement.
- Фаза 11 (ER-docs) — pure docs.

**Wave 2 — domain rewrite, средний риск:**
- Фаза 1 (newtypes + Validate).
- Фаза 2 (builders + constants).
- Фаза 4 (DTO).

**Wave 3 — service-level rewrite, высокий риск (полный refactor):**
- Фаза 3 (UseCases).
- Фаза 5 (CQRS Repository).

**Wave 4 — cross-service:**
- Фаза 10 (corelib operations.Run) — затрагивает все сервисы одновременно.
- Фаза 8 (ExecAbstract) — после Wave 1.

## Рекомендация: запустить Wave 1 параллельно как 4 epic'а

- KAC-N6 (config refactor — kacho-vpc).
- KAC-N7 (cmd/migrator split — kacho-vpc).
- KAC-N9 (gRPC client-builder — kacho-vpc).
- KAC-N11 (ER-diagrams — все 3 сервиса).

Каждый эпик — 1-2 дня работы, low-risk. После их merge'а — Wave 2.

## Что НЕ покрыто этим планом

- KAC-87 G1/G2/G3 миграции (текущая работа) — это **другой** epic (DB safety, не architecture). Идёт независимо.
- KAC-15 Geography → compute — уже сделано.
- KAC-36 cleanup post-kube-ovn — уже сделано.
- KAC-39 / KAC-50 / KAC-71 — текущие фичи, идут независимо от этого rewrite.

## Открытые вопросы

1. **id TEXT vs UUID** (NOTES.txt). Текущее решение TEXT с 3-char-prefix зафиксировано в `kacho-vpc/CLAUDE.md` §3 — оперативная маршрутизация api-gateway. **Не меняем**.
2. **operations.Run контекст**: затрагивает все сервисы; должен быть в corelib (Wave 4).
3. **Pkg/-структура для shared SDK**: насколько публичный domain нужен (внешние интеграции)? Если нет — можно оставить `internal/domain/` и не плодить `pkg/`. Спросить тимлида.
4. **viper vs koanf**: предпочтение @EvgenyGRI — viper. Если есть аргументы за koanf (smaller, less magic) — обсудить.
5. **H-BF/corlib зависимость**: добавление новой external-либ → размер дерева зависимостей. Прикинуть DAG.

## Что делать с PR #52

**Не мёрджить** (CONFLICTING, 112 behind main). 

Варианты:
- **Закрыть** с комментарием «Идеи извлечены в skill evgeniy + docs/specs/evgeniy-migration-plan.md. Спасибо!» — рекомендуемое.
- Оставить open как «архивная ссылка» — но это шум в PR-listing.

После закрытия — ветка `review` остаётся в репо как историческая точка. Удалять её не нужно.
