# CI-PY-1 — предварительные классы риска

> DRAFT, 2026-09-17. Авторская подготовка, НЕ independent initial analysis и
> НЕ design revalidation. Требуются отдельные записи роли после review.

Приёмка — docs/specs/sub-phase-CI-PY-1-python-outcomes-acceptance.md; замысел —
docs/specs/sub-phase-CI-PY-1-python-outcomes-design.md. SHA предметов записаны
в change.yaml. Ниже указаны предложенные механизмы; новых держателей ещё нет.

| Решение | Задетый класс / признак | Проверяемое условие | Механизм и будущая проба |
|---|---|---|---|
| D1 | Третий исход схлопнут в finding или успех | 0/1/2 различимы у producer/selftest; Make2 не интерпретируется без причины | Общий результат; CI-PY-01..04,09,12 |
| D1,D4 | Default/sentinel имеет второй смысл | argparse2, missing command и неизвестный код не превращаются в «нет pytest» | Валидная запись того же вызова; CI-PY-11, законный близнец |
| D2 | Ноль находок вместо нуля осмотренного | Непустой состав подтверждён; declared/executed раздельны и с единицами | Обход+AST/JUnit и итог на всех ветвях; CI-PY-05..07 |
| D2 | Повторный источник истины | Историческое48 нигде не управляет числом; перепись меняется с деревом | Вывод из фактического состава; параметризация CI-PY-07 |
| D3 | Предпосылка недостижима в общем реестре | Проверяющий работоспособен; снят pytest только у SUT | Изолированные интерпретаторы; CI-PY-04 и настоящий chain09/10 |
| D3 | Настройка теста выдаёт себя за RED | Setup failures названы отдельно; честный RED содержит исполненное несовпадение | Независимый integration-tester, тройка case/condition/outcome |
| D4 | Отметка пережила свой предмет / сосед перезаписал | Изолированная запись, current invocation, atomic write | CI-PY-11: prior-run, concurrent neighbour, corrupt/missing record |
| D4 | Общий helper имеет второй несогласованный parser | Один формат и parser, все callers читают его семантику | Production helper + реальные caller captures; ручной grep не holder |
| D4,D5 | Узкая причина стала blanket forgiveness | Real finding после GREEN prerequisite остаётся finding; совместные finding+unmet видны | CI-PY-08..11; Make recipe genuine-red sibling |
| D5 | Счётчик attempted выдан за successful | Неисполненная верхнеуровневая проверка не называется успешной | Связь имён и категорий; локальные declared/attempted/completed различимы |
| D6 | Success сборщика подменил полный job GREEN | Always-final требует всех обязательных результатов и category | CI-PY-12: allgreen/unmet/finding/no-result; parsed workflow |
| D7 | Комментарий/чужая установка принят за вызывающий | Перепись читает структуру, локальность job и реальные команды | CI-PY-13 плюс comment-only lawful twin |

Перепись до реализации: обнаружить все реальные callers; числа объявлений и
экземпляров на baseline; состав самопроверок; названные верхнеуровневые helm
проверки. Исторические 48 и 5 не заменяют эту перепись. Числа из issue —
атрибутированные наблюдения владельца, не наш новый runtime capture.

Отдельная revalidation должна сопоставить каждую строку с принятой редакцией
замысла и результатом proposed mechanism / unhandled / N/A с основанием.
Авторский файл не разрешает следующий lifecycle-переход.
