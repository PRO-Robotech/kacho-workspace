---
title: "#1483 — Край разрешает типы Any, упакованные владельцами"
category: kac
status: done
ticket_id: "issue-1483"
type: fix
repos: [kacho]
prs: []
issue_url: https://github.com/PRO-Robotech/kacho/issues/1483
closed: "2026-09-11T12:41:10Z"
verified_against: "Предмет и область свидетельства: продукт d941344bd972b2e994263a9e964afa1491aff293, 2026-09-11; нормативная база workspace 364c7411b3f1a5f66a16b5388850ac3297cb4c4e"
tags: [kac, fix]
---

# #1483 — Край разрешает типы Any, упакованные владельцами

## Что и зачем

Гейт связывает типы, упаковываемые владельцами ресурсов, с реестром процесса края. Перепись и парные инъекции удерживают полноту этой связи при изменении дерева.

Задача: [PRO-Robotech/kacho#1483](https://github.com/PRO-Robotech/kacho/issues/1483). Релиз: `release:gates`. Тип: исправление проверки.

Затронутые пути продукта: `internal/repohygiene/`, `gateway/`.

## Состояние и свидетельство

На 2026-09-11 независимая проверка на [d941344bd972](https://github.com/PRO-Robotech/kacho/commit/d941344bd972b2e994263a9e964afa1491aff293) подтвердила предикат задачи.
Задача закрыта в GitHub 2026-09-11T12:41:10Z с причиной `completed`; состояние и причина повторно подтверждены API после действия. [Закрывающий комментарий](https://github.com/PRO-Robotech/kacho/issues/1483#issuecomment-5634577619). Статус записки — `done`.

Оба требуемых гейта прошли; область: 34 исполняемых пакета, 12 владельцев, 32 proto-пакета края; 1833 файла владельцев, 134 места упаковки. Выполнены парные инъекции полноты и распознавания форм.

Команды повторения из корня продукта указанной ревизии:

```bash
go test -v -count=1 ./internal/repohygiene -run 'Test(EdgeResolvesEveryProtoPackageItsOwnersCanProduce|ForeignTypesPackedInTheTreeAreDeclaredByTheEdge|CompletenessGate|Recognizer|UnwrittenArgument|DeclarationIsRead|MigrationMonotonic|NewMigrationOutranksEveryAppliedOne)'
```

Область свидетельства: 13 верхнеуровневых тестов в объединённом прогоне, 34 записи PASS с подтестами, 0 FAIL, 0 SKIP. Статическая разрешимость и её инъекции; не runtime E2E.

Исправление уже доставлено в `main`: [95ea80b686ef](https://github.com/PRO-Robotech/kacho/commit/95ea80b686ef76cd764085c8915d859ab16898c9). Отдельный PR этой документальной сверкой не установлен; поле `prs` пусто.

Публичный прогон проверяемой ревизии: [CI 34539784562](https://github.com/PRO-Robotech/kacho/actions/runs/34539784562).

## DoD

- [x] Предикат повторно проверен на указанной ревизии; область и ограничения названы.
- [x] Ссылка на доставленный коммит исправления сверена независимым ревью.
- [x] Закрывающий комментарий опубликован; состояние GitHub перечитано после закрытия.
- [x] Статус записки изменён на `done` после закрытия с причиной `completed`.

## Затронутые сущности vault

- [[packages/proto-root]] — связанный контекст проверки; содержимое соседней записки этой сверкой не пересматривалось.
- [[packages/kacho-ci-determinism]] — связанный контекст проверки; содержимое соседней записки этой сверкой не пересматривалось.

## Связанные задачи

Связанные задачи в этой полосе не установлены.

#kac #fix
