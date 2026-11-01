# Индекс поиска «Настроек»: из файлов разделов — заголовки карточек (card),
# строк настроек (row) и пояснения к ним (sub), в порядке на странице.
# Вывод: <файл раздела> TAB <вид> TAB <строка для I18n.tr>. Запуск — settings/Registry.qml.
FNR == 1 { comp = ""; f = FILENAME; sub(/\.qml$/, "", f) }
{
    line = $0
    if (match(line, /(^|[^A-Za-z0-9_.])(Card|SettingRow|SliderRow)[[:space:]]*\{/)) {
        c = substr(line, RSTART, RLENGTH); gsub(/[^A-Za-z]/, "", c); comp = c
    } else if (match(line, /^[[:space:]]*[A-Z][A-Za-z0-9_.]*[[:space:]]*\{/)) {
        comp = ""
    }
    if (comp == "") next
    if (match(line, /(^|[;{[:space:]])title:[^;]*I18n\.tr\("[^"]*"\)/)) {
        t = substr(line, RSTART, RLENGTH); match(t, /I18n\.tr\("[^"]*"\)/)
        print f "\t" (comp == "Card" ? "card" : "row") "\t" substr(t, RSTART + 9, RLENGTH - 11)
    }
    if (match(line, /subtitle:[^;]*I18n\.tr\("[^"]*"\)/)) {
        t = substr(line, RSTART, RLENGTH); match(t, /I18n\.tr\("[^"]*"\)/)
        print f "\tsub\t" substr(t, RSTART + 9, RLENGTH - 11)
    }
}
