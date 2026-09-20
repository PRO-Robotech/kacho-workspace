# Историческая операционная диагностика b5fa

Автор /root/e2e_audit, 2026-09-17. Это не независимый holder RED и не approval.
45 фактических процессов завершены, 90 stream hashes проверены в original
handoff.json. Product/holder bytes не менялись.

В канон перенесены 75 точных файлов: исходные DRAFT subjects и metadata плюс
66 небольших текстовых потоков actual vet/public-test. Все тела сохранены
побайтово; markdown с историческими командами хранится как .txt.

24 полных go-list потока со стандартной библиотекой не копируются сюда. Их
точные hashes/census и структурные ошибки находятся в load-diagnosis.json и
handoff.json; оригинальные файлы доступны по исходным путям AUD/issue-2672-design.
copy-bindings.json перечисляет именно доставленные файлы, не весь внешний corpus.
Исполняемый бинарник и диагностические fixture-source файлы в package не включены.
