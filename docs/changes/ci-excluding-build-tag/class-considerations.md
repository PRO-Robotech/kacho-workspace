# CI-EBT-1 — DRAFT авторской экспозиции

Это подготовка к independent initial/revalidation, не verdict этих ролей.
Exact hashes приёмки, замысла и интерфейса находятся в change.yaml.

| Класс | Наблюдаемая граница | Держатель/контроль |
|---|---|---|
| Пустой предмет принят за успех | Ноль прочитанного отдельно от нуля исключений | CI-EBT-03/04 |
| Форма вместо существа | Связка уходит целиком либо теряется символ | CI-EBT-01/02 |
| Предусловие растворилось | baseline compiler и workspace failures видны | CI-EBT-06/07 |
| Loader принят за compiler | Полный JSON-stream, Error при rc0 не успех | CI-EBT-08; proposed DC-02 |
| Процесс не стартовал | Реальный exec error отдельно от finding | CI-EBT-09 |
| Частичная свёртка скрыла одну сторону | И findings, и неполнота сохранены | CI-EBT-10 |
| Рабочий диск заменил индекс | Пропавший tracked file не исчезает из обхода | CI-EBT-11 |
| Platform/header semantics изменились | Прежние исключения остаются видимыми | CI-EBT-04/05 и existing4 |
| Helper без публичного caller | Тот же public test binary на каждой фикстуре | Все CI-EBT-01–11 |
| Output classifier принял неизвестное | Positive real compiler; unknown отказ | CI-EBT-02; proposed DC-01 |
| Новый внешний вызов не имеет отмены | Конечный deadline и завершённый child | proposed DC-03, prerequisite не доказан |
| Новый JSON даёт ложную полноту | Точный status/census и одна final record | Все CI-EBT-01–11 |

Строки DC не закрыты наличием плана. До full design approval независимый reviewer
проверяет конструктивность, полноту и точный допустимый переход. Неприменимость
DB/proto reviews выводится из фактического diff отдельно; авторское перечисление
одного Go-файла не даёт N/A будущим изменениям, которых ещё нет.
