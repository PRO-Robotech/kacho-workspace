Уточнение единицы счёта перед замораживанием независимой carrier/capacity матрицы. Принятый subject `1604e73f8b496a5be946da4a732e7c57f4d6e6118f2b95ef7dd3d572a243b96c`, acceptance/design и все пределы остаются прежними.

Одно раскрытие Buffer/base64/base64url/URL производит одно типизированное представление. Разбор содержащегося в bytes JSON object/array входит в это же раскрытие: глубина 1. Если результат — JSON string со следующей JSON-обёрткой, её отдельное раскрытие даёт глубину 2. Nodes учитывает исходное разобранное представление и каждый дополнительный типизированный результат; технические bytes/string parser temporaries не считаются повторно.

Точные контрольные примеры для `{"ok":true}`: обычный JSON object — 2 nodes / depth 0; исходная JSON string с этим объектом — 3 / 1; Buffer с 11 байтами этого JSON — 16 / 1; явный base64 envelope с объектом — 5 / 1; тот же envelope с дополнительной JSON-string обёрткой — 6 / 2. Ключи проверяются как carriers, но не считаются nodes. Равенство пределу разрешено, следующий шаг сверх предела запрещён.

В lawful set текущей матрицы значения отсутствующего секрета — только null и пустая строка. Нового разрешённого словаря `[REDACTED]` или `{{access_token}}` не вводится.

Машиночитаемый review subject `newman-decoding-typed-result-clarification.json`, SHA256 `0f5c81dd85a2ada556e3d599db160e85befe28903c74646795cce89c0e49a50a`. Это routine уточнение accounting перед RED; оно не разрешает source scanner, не меняет global phase и не утверждает GREEN.
