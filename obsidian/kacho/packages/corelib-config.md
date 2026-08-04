---
title: corelib-config
category: package
repo: kacho-corelib
path: pkg/config
layer: config
status: stable
tags:
  - packages
  - kacho-corelib
  - config
---

# pkg/config — загрузка конфигурации из окружения

**Каталог**: `pkg/config/` · импорт `github.com/PRO-Robotech/kacho/pkg/config`
**Прежде** (полирепо): `kacho-corelib/config`.
**Импортирует**: `github.com/kelseyhightower/envconfig` (единственная зависимость).
**Импортируют** (`go list` на `96b2879a`, non-test): по одному конфиг-пакету у vpc ·
iam · geo · compute · storage · registry · gateway. Ровно два файла, две функции —
это весь пакет.

## Экспортируемое API (снято с дерева)

```go
func Load(c any) error                        // envconfig.Process("", c)
func LoadPrefixed(prefix string, c any) error // envconfig.Process(prefix, c)
```

## Зачем нужен `LoadPrefixed` — это не удобство, а per-edge независимость

`Load` ждёт **полные** имена переменных в тегах. `LoadPrefixed` выводит имя из
иерархии полей: `prefix` + имя вложенного поля + …

Следствие, ради которого функция и заведена: горизонтальная value-структура
фундамента (`grpcsrv.TLSServer`, `grpcclient.TLSClient`) встраивается в конфиг
сервиса под **разными** полями — и два экземпляра одной и той же структуры получают
**независимые**, префиксованные по ребру переменные. Именование ребра принадлежит
сервису (через имя поля), а не структуре фундамента (через зашитый тег). Без этого
пришлось бы либо вшивать абсолютный тег в общий тип — и получить один глобальный
TLS на все рёбра, — либо дублировать структуру на каждое ребро.

## Конвенция

- Префикс не вшит в `Load`: сервис сам владеет пространством имён
  (`KACHO_<DOMAIN>_<NAME>`, core §naming).
- Правило скила `evgeniy`: env-теги допустимы **только** в верхнеуровневом конфиге;
  доменная логика читает уже разобранную структуру.
- Конфиг-структуры TLS описаны у своих владельцев — [[corelib-grpcsrv]]
  (`TLSServer`) и [[corelib-grpcclient]] (`TLSClient`); здесь они не пересказываются,
  чтобы предмет не разъехался по двум местам.

> [!note] Про `enable=false`
> Нулевое значение флага включения TLS означает незашифрованное ребро. Это
> **фикстурный** режим, а не эксплуатационный: любой развёрнутый стенд, включая
> локальный, работает в production-посадке (core §Non-negotiables, п. 16), и
> production boot-guard обязан отказать в старте на insecure-конфигурации.

## См. также

[[vpc-apps-kacho-config]] [[apigw-config]] [[corelib-grpcsrv]] [[corelib-grpcclient]]

#packages #kacho-corelib #config
