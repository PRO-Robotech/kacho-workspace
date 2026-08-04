---
title: proto-root
category: package
repo: kacho-proto
path: proto
layer: proto
status: stable
tags:
  - proto
  - buf
  - common
---

# proto/ — единственный дом контрактов

**Каталог**: `proto/` в монорепо `PRO-Robotech/kacho`.
**Прежде** (полирепо): отдельный репозиторий `kacho-proto`; тег `kacho-proto`
означает теперь **домен контрактов**, а не репозиторий.

**Новый `.proto` — ВСЕГДА сюда.** Сервисные каталоги файлов контрактов не содержат
вовсе, только Go-импорт сгенерённого. Один `buf lint` и один `buf breaking` на всё
дерево (`polyrepo.md`).

## Что лежит наверху

- `buf.yaml`, `buf.gen.yaml` — конфигурация сборки контрактов;
- `google/api/`, `google/rpc/` — привезённые контракты Google: аннотации HTTP для
  транскодирования REST и `status`/`error_details`, на которые опирается
  [[corelib-errors]];
- `kacho/cloud/validation.proto` — собственные опции валидации полей;
- `kacho/cloud/<домен>/` — по домену на каталог.

> [!note] Каталога общих типов `common` в дереве НЕТ
> Прежняя редакция называла его «пустым placeholder'ом». Пустого места нет — есть
> **отсутствие**: общие типы живут либо в `kacho/cloud/reference/`
> ([[proto-reference]]), либо в `package_options.proto` своего домена. Заводить
> «общий» каталог заново — решение, а не восстановление.

## Домены (по дереву, `96b2879a`)

`access` · `api` · `apigateway` · `compute` · `geo` · `iam` · `loadbalancer` ·
`operation` · `reference` · `registry` · `storage` · `vpc`.

Записки в этой категории есть не на все: **нет** записок про `iam`, `storage`,
`registry` и `apigateway` — при том что `iam/v1` крупнейший по числу файлов домен
дерева. Это пробел покрытия, а не признак отсутствия предмета.

## Сборка

Стабы генерируются **в тот же модуль**: `option go_package =
"github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/<домен>;<домен>v1"`, результат
лежит в `pkg/api/…` и **руками не правится**. Прежняя редакция называла отдельный
репозиторий, каталог `gen/go/…` и цель сборки в нём — при одном модуле пиннить и
регенерировать «в соседний репозиторий» нечего.

## См. также

[[proto-vpc]] [[proto-operation]] [[proto-reference]] [[kacho-monorepo]]

#proto #buf #common
