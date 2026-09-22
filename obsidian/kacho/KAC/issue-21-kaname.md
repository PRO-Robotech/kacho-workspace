---
title: "kaname#21: посадка own поднимается — три условия старта, каждое держателем"
aliases:
  - issue-21-kaname
ticket_id: 21
category: kac
status: done
type: fix
repos:
  - kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/251
issue_url: https://github.com/PRO-Robotech/kaname/issues/21
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - iam
  - deploy
verified_against: "kaname main@16b5cade (MR #266); живой стенд kind полосы #251 — чарт deploy/ с values.prod.yaml и накладкой identityProvider=own, образ из дерева, без платформы и поставщика: stand-chart.sh assert → 0, восемь слушателей, регистрация на самой полосе → 200 с сессией «1» (23 шага); стенд снесён"
---

# kaname#21: пять причин отказа `own` закрыты — и это измерено живым стартом, а не чтением стража

**Предмет.** Задача называла пять причин, по которым страж посадки отказывал `own`. Ф3 и Ф12
провязали хранилища способов входа, сессии и уровни «1»/«2»; полоса #251 добила три условия
старта, которые до неё не измерял никто, и подняла службу под `own` на kind.

## Три условия старта — и чем каждое держится

| условие | что было | держатель |
|---|---|---|
| предел памяти | `resources: {}` в `values.yaml` — страж полосы входа отказывал «предел памяти средой не назван» | боевой профиль: `limits.memory 1280Mi` ровно по арифметике стража (8 × 128 МиБ + 256 МиБ); `deploy/own_lane_memory_ceiling_test.go` зовёт `config.LoginLaneConfig.ValidateMemoryBudget` на рендере |
| секрет стенда | `make_secrets` заводил два ключа из трёх — под в `CreateContainerConfigError` | третий ключ `second-factor-encryption-key-hex`; `deploy/stand_secrets_cover_the_profile_test.go` сверяет карту секретов профиля с **исполняемой** строкой скрипта (инъекция снятого ключа — находка с переменной/ключом/объектом) |
| адрес полосы | процесс проходил всех стражей и падал на привязке полосы: адрес со схемой | `APIServerConfig.LoginLaneListenAddress()` — тот же нормализатор, что у семи других поверхностей; `cmd/kaname/loginlane_addr_test.go`: три формы записи → адрес без схемы; под `external` поверхность выключена с причиной |

## Что снято из документов

Четыре места (INSTALL.md §1, `values.prod.yaml`, `stand-chart.sh`, `configuration.mdx`)
утверждали «стартовать отказывается / живой старт не измерен» — заменены измеренным состоянием
с тремя условиями и держателями; предупреждение о трёх нерендерящихся величинах сняло
kaname#205 (пережило предмет).

## Чего измерение НЕ покрывает

- стенд **через край платформы** (kacho#2709): края на стенде нет by construction — регистрация
  измерена на самой полосе, край имитирован клиентским листом с SAN `sa/kacho-api-gateway`;
- второй лист края в скриптах стенда и числовой вердикт `run.sh --service kaname-login-lane` —
  kaname#183;
- гейт `TestEveryLaneIsEitherProfiledOrProvablyUnreachable` по-прежнему называет `own`
  «НЕ поднимается» по nil-полосе — kaname#252 (решение владельца о профиле `own`).

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — адрес полосы нормализуется как у остальных поверхностей.
- [[issue-1281-kaname]] — уровни «1»/«2» как условие `own`.

#kac #kacho-iam #iam #deploy
