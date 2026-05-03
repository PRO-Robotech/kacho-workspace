# Kachō Specs CHANGELOG

## 2026-05-03 — Initial draft
- 5 спек-документов 00–04 утверждены
- sub-phase 0.1 acceptance готов и утверждён заказчиком
- sub-phase 0.1 implementation plan готов

## 2026-05-03 — Design change: kacho-api → kacho-proto

Заказчик переименовал proto-репо: `kacho-api` → `kacho-proto`. Семантика: единая центральная директория для всех `.proto`-определений Kachō (от всех текущих и будущих бекендов и доменов). Сервисные репо НЕ содержат `.proto`-файлов — только Go-импорт сгенерированных stubs из `github.com/PRO-Robotech/kacho-proto/gen/go/...`.

Затронуто: bootstrap.sh, sync-all.sh, go.work.example, CLAUDE.md, 6 агентов (`proto-sync`, `proto-api-reviewer`, `rpc-implementer`, `service-scaffolder`, `integration-tester`, `api-gateway-registrar`), 5 спек-документов (`00–04`), acceptance + plan для sub-phase 0.1, go.mod и proto go_package option в самом `kacho-proto`.

## (Sub-phase 0.1 — bootstrap, при завершении)
- TBD: дописать после tag kacho-workspace:0.1.0
