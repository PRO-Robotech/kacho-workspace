---
title: "kaname cmd/kaname"
aliases:
  - kaname composition root
  - kaname-cmd
category: packages
path: cmd/kaname
repo: kacho-iam
layer: cmd
status: stable
related_tickets:
  - "[[KAC/issue-337-kaname]]"
  - "[[KAC/issue-338-kaname]]"
tags:
  - packages
  - kacho-iam
  - cmd
  - composition-root
  - config
verified_against: "перепись непробных файлов каталога на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21) — 47 файлов; построчно прочитан только участок `buildSAKeysHandler` в `wiring.go`"
---

# kaname `cmd/kaname`

Композиционный корень продукта: единственное место, где посадка известна целиком и где
решения о ней и принимаются. Сборка разнесена по файлам предмета (`wiring.go`, `serve.go`,
`posture.go`, `laneposture.go`, `revocationauthority.go`, `retention.go` и далее) — вариант
использования свойств посадки не выводит.

## Ручки посадки независимы, и одно их сочетание не работает

Вид поставщика личности и перевод контура выдачи ключей служебных учёток — **разные**
ручки. Три сочетания из четырёх работают; четвёртое — собственная посадка при непереведённом
контуре — отказывает на всяком входе, и накладка чарта сегодня даёт именно его. Предмет —
[[KAC/issue-337-kaname]].

Сегодня это **предупреждение оператору при старте**, а не отказ: отказ был бы верен по
существу и стоил бы подъёма собственной посадки целиком. Молчание на этом месте и есть то,
из-за чего дефект доживал до пути запроса.

## Решение о посадке принимается здесь — и потому здесь же его граница

Двое потребителей административной дороги получают клиента доводом, и решение за них
принимает эта сборка — **один раз на обоих**, а не каждым. Предмет —
[[KAC/issue-338-kaname]].

## See also

[[packages/kaname-internal-check]] · [[packages/kaname-repo-pg]] · [[packages/apigw-cmd]]

#packages #kacho-iam #cmd #composition-root #config
