# CI-NP-1 — задачи принятого потока

Предмет и порядок задаёт APPROVED acceptance/design из change.yaml. Таблица —
конкретные следующие задачи, а не заявление выполненных проверок.

| Task | Владелец и дом | Сценарии | Вход и выход |
|---|---|---|---|
| NP-T1 | integration-tester, corelib area-ci-newman-tests | CI-NP-01,02,03,04,06 | Согласованный interface.md, годные настоящие fixtures/readers/SDK → Python/Node holders и различающий RED; product source не меняется |
| NP-T2 | worker, corelib area-ci-newman-corelib | CI-NP-01,02,03,04,06 | Независимый RED и root transition → общий projector/scanner/publisher, один pinned SDK; tests автора не правятся |
| NP-T3 | root release + consumer worker/tester, Kaname/Kachō | CI-NP-03,04,05 | Выпущенный corelib payload → оба pins, clean runtime materialization, снятая private копия Kaname, parsed workflow holders обеих полярностей |
| NP-T4 | independent integration-tester, оба consumer runtime | CI-NP-07 | Действительная новая поставка → own identity и все declared shards полностью positive, опубликованные bytes повторно скачаны и проверены |
| NP-T5 | scanner worker + independent verifier, private retention | CI-NP-08,10 | Свежая полная paginated metadata и доступные ZIP → каждый объект имеет scoped доказанный исход, ошибки явно остаются непроверенными |
| NP-T6 | root actions + independent landing-reviewer | CI-NP-09 | Только content-verified и отдельно accepted exact-set → повтор identity/digest, точечное действие, exact404; при отсутствии findings удаление не выдумывается |
| NP-T7 | convergence/landing-reviewers + root | CI-NP-10 | Новая prelanding перепись/scan и все необходимые runtime/reviews → main по repos и closure по delivered content |

NP-T1 разрешён после effective событий и routine interface agreement. NP-T2
закрыт до предъявленного RED и отдельного root transition. NP-T3–T7 имеют
собственные зависимости и не зеленеют от corelib synthetic holders.


17 сентября внешний переход 5713435493 открыл только Python projection часть
NP-T2 после независимого scoped RED на e27d244. Точный scope, executable и
отложенные части приведены в добавленном разделе route.md и landing record.
Остальной NP-T1 продолжается независимо; ни один поздний runtime/retention
результат не выводится из локального projection holder.
