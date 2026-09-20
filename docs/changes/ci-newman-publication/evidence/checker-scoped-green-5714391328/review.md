# CI-NP-1 — root scoped GREEN, полный ZIP envelope

Reviewer /root; source author /root/e2e_audit; holder author /root/ci_verdict_audit.
Acceptance2c30dc5fb1ba6fb985b8e63918c5c4bd58a115d06bf31e35006acf737531e400;
designd60f34f6a2458e011f46cbe460310ed0e5071ee0635ae0fb188a70c387bc9181.
Authorization event #1810 comment5714248971.
Source4d37cfb6ef62d31c09cd65daadf09bdef671d3a5, immutable holder08d5d91cd431a34159af5d7d556764c4ecc52372.

Полный source diff: 2 файла, 93 добавленных строки. Root прочитал весь новый
zip_envelope.py и вызов publication.py вместе с его guards. Предельные archive,
entry и expanded/document размеры проверяются до inflater. Envelope требует
точный EOCD/central span/count и полный непересекающийся набор local spans,
согласие local/central полей и обычные файлы. Расширения, которых собственный
writer не производит, не разрешаются. CRC/content/catalogue/projection binding
проверяются прежним reader после envelope. Не добавлены scan stub или upload.

Root извлёк точный Git archive в свой внешний TMPDIR и запустил неизменённые
18 canonical tests: 18 PASS, FAIL/ERROR/SKIP0. Все24 отрицательных ZIP теперь
отказаны;24 lawful project/file-check/stdin-check сохранены. Все278 subprocess
outputs проверены по SHA256. Source+holder файлы перед/после совпадают.
Ранее8 из24 variants ошибочно разрешались; остальные16 отказов сохранены.
Прежние10 projection tests, including реальные readers, не ослаблены.

Независимый дополнительный root эксперимент проверил concern нового inflater:
обычный readable ZIP с прежними extracted members и непрочитанным tail в
compressed span разрешался старым checker (rc0) и отказан новым (rc3), оба
lawful twins rc0, все stderr пусты. Это локальный scoped опыт, не добавленный
canonical holder и не утверждение о полном scanner/transport корпусе.

VERDICT SCOPED_GREEN_APPROVED для projection + полного final ZIP envelope.
Обязательства scanner/capacity/SDK/consumers/runtime/retention/convergence и
main delivery не выполнены этим результатом. #1810 остаётся открытым.
