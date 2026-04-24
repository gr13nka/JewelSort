-- Russian locale. Russian uses three plural forms (one/few/many)
-- driven by the last digit; see src/i18n.lua's PLURAL_RULES.ru.
return {
    back            = "< Назад",
    got_it          = "Понятно",
    complete        = "Готово",
    solved          = "Решено!",
    already_mastered = "Уже освоено",
    resetting       = "Сброс прогресса...",
    select_book     = "Выберите книгу",
    sealed          = "ЗАКРЫТО",
    unsolved        = "НЕ РЕШЕНО",
    no_preview      = "? ? ?",

    tutorial_title  = "Масштаб и панорама",
    tutorial_wheel  = "Колёсико  —  масштаб",
    tutorial_drag   = "Фон  —  перетащить",

    jewel_delta = {
        one  = "+%d камень",
        few  = "+%d камня",
        many = "+%d камней",
    },
    locked_needs = {
        one  = "Закрыто — нужен %d камень",
        few  = "Закрыто — нужно %d камня",
        many = "Закрыто — нужно %d камней",
    },
}
