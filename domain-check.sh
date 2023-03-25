#!/bin/bash
#==============================================================================
# Your Access-SSID here:
SSID=.secret.

BCURL=/usr/bin/curl
BJQ=/usr/bin/jq
BGREP=/usr/bin/grep
BDIG=/usr/bin/dig

#==============================================================================
# METHODS
#==============================================================================

VERSION="Haeniken WebNotif checker build 17.05.2022"
verbose=false

# Функция проверки значения переменной
function empty {
        local var="$1"
        # Возвращает true, если:
        # 1.    Имеет значение null ("" пустая строка или значение null текст)
        # 2.    Не установлена
        # 3.    Объявлена, но без значения
        # 4.    Пустой массив
        if test -z "$var"
        then
                [[ $( echo "1" ) ]]
        return
        # Возвращает true, если 0 (0 для integer или "0" для строки)
        elif [ "$var" == 0 2> /dev/null ]
        then
                [[ $( echo "1" ) ]]
        return
        # возвращает true, если null (текст)
        elif [ "$var" == null 2> /dev/null ]
        then
                [[ $( echo "1" ) ]]
        return
        # Возвращает true, если 0.0 (0 для float)
        elif [ "$var" == 0.0 2> /dev/null ]
        then
                [[ $( echo "1" ) ]]
        return
        fi
                [[ $( echo "" ) ]]
}

# Версия
function show_version {
        echo -e "$VERSION\n"
        }
show_version

# История изменений
function show_changelog {
        echo -e "История изменений:\n"
        echo -e "14.05.2022\nДобавлен парсинг id конфигураций домена (id).\nНаписаны модули помощи, версии, истории изменений.\nРеализованы проверки на наличие аргумента.\n"
        echo -e "15.05.2022\nРеализовал проверку на статус домена (включён/нет), наличие listen/backend ip.\nДобавлен автоперевод доменных имён в punycone.\nДобавил парсинг доменного имени из любой ссылки.\nУлучшены проверки аргументов.\nДобавлен парсинг backend ip из конфигураций домена.\n"
        echo -e "16.05.2022\nДобавлен режим вербозности.\nРеализована regexp проверка на совпадение распарсенного домена с json результом.\nДобавлено формирование ссылок на Graylog и услугу в биллинге.\nВ случае отсутствия backend ip, появилась проверка на время создания доменных конфигураций и дополнительный алерт, если она создана менее 24 часов назад.\nДобавлена проверка на доступность cc.\nДобавил алерт про отсутствие пакета idn.\n"
        echo -e "17.05.2022\nРеализована проверка на balance/enable backend ip, а так же их идемпотентность для scheme 80 и 443.\nРеализована проверка на протокол (фронт) при формировании ссылки для check-host.\nДобавил в вывод информацию для отладки (listen и backend ip, порты и протоколы).\nДобавил формирование готового curl запроса к backend."
        echo -e "\e[1;33m\nTODO\e[0m"
        echo -e "\e[1;33m\n* Парсить и игнорировать WaF backend.\n* Добавить readmode для Access-SSID.\n* Реализовать проверку поддержки SNI для SSL и проверку наличия шаблона в rules.\n* Проверка А-записей на совпадение с listen, проверка А-записей от whois опционально.\n* Добавить простукивание порта backend.\e[\0m"
        }

# Помощь
function show_help {
echo -e "\e[1;33mЧто умеет:\e[0m"
echo -e "* Проверяет активность услуги (статус)."
echo -e "* Проверяет наличие listen ip."
echo -e "* Чекает А-запись через local dns, проверяет эту А-запись на соответствие с listen ip. Если есть разница, формирует готовую ссылку на check-host для проверки А-записей."
echo -e "* Парсит ip бэкэнд серверов (только в статусе balance с типом enable)."
echo -e "* Проверяет, совпадают ли ip backend в 80 и 443 схемах (только balance+enable), если нет, выдаёт алерт"
echo -e "* Если бэкэнд отсутствует, осуществляет проверку на давность заведения конфигураций, дополнительно информирует, если конфигурация заведена менее 24 назад."
echo -e "* Стучится циклом в нужные айпи и порты бэкэнд серверов с помощью netcat (аналог телнета), таймаут 15 сек."
echo -e "* Формирует готовый curl запрос к бэкэнду (сейчас остаётся скопировать и вставить из вывода, пока есть некоторые проблемы, которые не могу автоматизировать)."
echo -e "* Формирует ссылки на биллинг (услуга), грейлог (как зафильтрованый так и нет), чекхост (заполненный с протоколом и доменом)."
echo -e "* Собирает табличку с основной информации о домене."
echo -e "\n\e[1;33mПо мелочи:\e[0m"
echo -e "* Парсит доменное имя из любых ссылок."
echo -e "* Перевод доменных имён в punycode (если утилита idn на хосте отсутствует, меняется алгоритм некоторых циклов и выдаётся алерт). На лбшках idn есть."
echo -e "* Проверяет соотвествие ввода домена к полученному имени домена в json (уведомляет при несовпадении и предлагает автоматически исправить, т.к. поиск в кц работает не по строгому соответствию, берётся первый попавший)."
echo -e "* Если отсутствует стрим (нужен для формирования ссылки грейлога), автоматически будет использовать стрим l7filter при формировании ссылки."
echo -e "\n\e[1;33mСлабые места:\e[0m"
echo -e "* Я принял за данность то, что 80 и 443 scheme всегда идут первой и второй строкой в массиве данных соответственно. Я не нашёл, где это было бы иначе, но в теории, если удалить конфигурацию для 80 и создать её заново (не удаляя 443), то id могут поменяться, и это поломает скрипт. Проверку писать долго."
echo -e "* Если  в 80 и 443 схемах разное количество backend ip (balance+enable), будет выведен алерт, а значение бэков будет браться из 443 схемы (это тоже взаимосвязано с предыдущим пунктом, схема в теории может быть не 443)"
echo -e "* Я принял за данность то, что если хотя бы один из backend ip (balance+enable) использует 443 порт, то они все используют 443 порт (ну, иначе в принципе и быть не может, но проверка бы не помешала)"
echo -e "\n\e[1;33mПока не умеет:\e[0m"
echo -e "* IPTV и любые кастомные порты"
echo -e "* Делать трассировку при таймауте в порткноке (спать хочу, за пару минут можно доделать)."
echo -e "* Проверять, находится ли домен под атакой в данный момент (немного не разобрался с json)."
echo -e "* Различать WaF и обычные ip и алертить в случае WaF (спать хочу, цикл надо обдумать, долго)."
echo -e "* Проверять www А-запись (возникают вопросы с поддоменами, пока не придумал элегантное решение)."
echo -e "* Сама делать curl запрос (это может быть длительная операция)."
echo -e "* Пока нет проверки на SNI (как по факту, так и в конфигурации домена)."
echo -e "* Нужна проверка на шаблон cloudflare, вдруг домен работает через нас и через клару одновременно (считаю это иногда критичным, например при использовании лф)."
echo -e "* Не умеет изменять ACCESS-SSID (пока воткнут мой, инструкция по получению этого SSID в confluence.\n\n"

        echo -e "Usage: domain-check [DOMAIN ..]                domain check"
        echo -e "   or: domain-check [DOMAIN ..] -v, --verbose  verbosity domain check"
        echo -e "   or: domain-check [OPTIONS]"
        echo -e ""
        echo -e "Options includes:"
        echo -e "   --version   prints out version information"
        echo -e "   -e, --edit-ssid     requires new access-ssid        \e[1;31m(not allowed yet)\e[0m"
        echo -e "   -h, --help          displays this message"
        echo -e ""
        echo -e "   The command requires a domain name for work"
        exit
        }

### All unexpected errors ###
function unexpected_error {
        echo -e "\e[1;31mError!\e[0m Unexpected error"
        }

### Die on demand with message ###
die(){
echo "$@"
exit 999
}

# Проверяем пути к программам, иначе завершение
verify_bins(){
[ ! -x $BCURL ] && die "File $BCURL does not exists. Make sure correct path is set in $0."
[ ! -x $BJQ ] && die "File $BJQ does not exists. Make sure correct path is set in $0."
[ ! -x $BGREP ] && die "File $BGREP does not exists. Make sure correct path is set in $0."
[ ! -x $BDIG ] && die "File $BDIG does not exists. Make sure correct path is set in $0."
}

function show_version {
        echo -e "$VERSION\n"
        }

# TODO
function edit_ssid {
        read -sp "Please enter your Access-SSID: " ssid && echo
        echo -e "Access-SSID is replaced. Please, start script again."
        exit
        }

# цикл проверки аргумента
while [ "$1" != "" ];
do
        case $1 in
        -v | --verbose )
                verbose=true
                ;;
        --version )
                show_changelog
                exit
                ;;
        -e | --edit-ssid )
                edit_ssid
                ;;
        -h | --help )
                show_help
                ;;
        -* | --* )
                echo -e "\e[1;31mWrong option \"$1\"!\e[0m\n"
                show_help
                ;;
        * )
                # проверка на поддержку хостом idn
                IDN=$(command -v idn;)
                if empty "$IDN"
                then
                        echo -e "\e[1;33mWarning!\e[0m Punicode will not converting because \e[1;33midn\e[0m package missing on this host.\nYou can install this package: \e[1;34msudo apt install -y idn\e[0m\n"
                        DOMAIN=$(sed -e 's|^[^/]*//||' -e 's|/.*$||' <<< $1)
                else
                        DOMAIN=$(sed -e 's|^[^/]*//||' -e 's|/.*$||' <<< $1 | idn)
                fi
                echo -ne "Fetching domain configuration \e[1;33m$DOMAIN\e[0m from CC...   "
                ;;
        esac
        shift
done

#sed -i 's/-H \'Access-SSID: .secret.' \\/-H \'Access-SSID: $ssid/' domain-check.sh
#sed -i.bak "s/SSID:/!d" domain-check.sh

#проверка наличия аргумента (домена)
if [ -n "$DOMAIN" ]
then
        :
else
        echo -e "\e[1;33mWarning!\e[0m Need domain as argument: ./check.sh \e[1;33mexample.com\e[0m\n"
        show_help
        exit
fi

#==============================================================================
# MAIN
#==============================================================================

# извлечение основной конфигурации домена из кц по доменному имени
RESULT=$($BCURL -s 'http://.secret.' \
-H 'Accept: application/json, text/plain, */*' \
-H 'Accept-Language: en,en-US;q=0.9' \
-H "Access-SSID: $SSID" \
-H 'Connection: keep-alive' \
-H 'Content-Type: application/json;charset=UTF-8' \
-H '.secret.' \
-H '.secret.' \
--data '{"offset":0,"limit":20,"search":"\"'$DOMAIN'","searchField":"name"}' \
--compressed \
--insecure \;)

if [[ $RESULT = "{}" || $RESULT =~ "\"totalCount\":0," ]]
then
        echo -e "\e[1;31mError!\e[0m Domain not found in CC!"
        $verbose && echo "var \$$RESULT\n$RESULT" || :
        exit
elif empty "${RESULT}"
then
        # проверка на резолв cc (отсутствие VPN или какие-либо иные проблемы. Можно добавить отладку dig +trace в случае unexpected_error
        DIGCC=$($BDIG a .secret. +short;)
                if empty "${DIGCC}"
                then
                        echo -e "\e[1;31mError!\e[0m You are not in StormWall network!\nCheck your VPN or that the script is running on l7filter."
                else
                        unexpected_error
                fi
        exit
# 401 отдаётся при протухшем/неверном Access-SSID
elif [[ $RESULT =~ "401 Authorization Required" ]]
then
        echo -e "\e[1;31mError!\e[0m Wrong or missing access SSID!\e"
        edit_ssid
else
        echo -e "\e[1;32mSuccess!\e[0m"
fi

# алерт вербозности
$verbose && echo -e "\n\e[1;31mVerbose mode active!\n\e[0m" || :

# парсим тело запроса  в json формат
JSONRESULT=$($BJQ -r '.[]' <<< $RESULT;)
$verbose && echo -e "var \$RESULT\n$RESULT" || :
$verbose && echo -e "\nvar \$JSONRESULT\n$JSONRESULT" || :

# проверка на строгое соответствие домена
NAME=$($BJQ -r '.result.items | .. | .name? | select (.)' <<< $RESULT | tr -d '\"[]' | head -n 1;)
if [ "$NAME" != "$DOMAIN" ]
then
        echo -e "\e[1;33m\nWarning! The domain name argument does not match with the configuration!\e[0m"
        $verbose && echo -e "\nvar \$DOMAIN\n$DOMAIN\nvar \$NAME\n$NAME" || echo -e "\ninput: $DOMAIN\njson: $NAME"
        echo
        read -p "You will check $NAME. Are you sure to continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
                exit 1
        fi
else
        $verbose && echo -e "\nvar \$DOMAIN\n$DOMAIN\nvar \$NAME\n$NAME" || :
fi


# получение id конфигураций доменов, внимание, здесь в переменную вносится массив
IDRESULT=($($BJQ -r '.result.items | .. | .id? | select (.)' <<< $RESULT | tr -d '\"#';))
$verbose && echo -e "\nvar \$IDRESULT\n${IDRESULT[*]}" || :


# примем за данность то, что 80 и 443 scheme всегда идут первой и второй строкой в массиве соответственно - немного слабое место
# получаем 80 scheme из массива
RESULT2=$($BCURL -s -XPOST '.secret.' \
-H 'Accept: application/json, text/plain, */*' \
-H 'Accept-Language: en,en-US;q=0.9' \
-H "Access-SSID: $SSID" \
-H 'Connection: keep-alive' \
-H 'Content-Type: application/json;charset=UTF-8' \
-H '.secret.' \
-H '.secret.' \
-d '{"id":'${IDRESULT[0]}'}' \
--compressed \
--insecure \;)

# получаем 443 scheme из массива
RESULT3=$($BCURL -s -XPOST '.secret.' \
-H 'Accept: application/json, text/plain, */*' \
-H 'Accept-Language: en,en-US;q=0.9' \
-H "Access-SSID: $SSID" \
-H 'Connection: keep-alive' \
-H 'Content-Type: application/json;charset=UTF-8' \
-H '.secret.' \
-H '.secret.' \
-d '{"id":'${IDRESULT[1]}'}' \
--compressed \
--insecure \;)


# парсим тело 80 scheme в json формат
JSONRESULT2=$($BJQ -r '.[]' <<< $RESULT2;)
$verbose && echo -e "\nvar \$JSONRESULT2\n$JSONRESULT2" || :
# парсим тело 443 scheme в json формат
JSONRESULT3=$($BJQ -r '.[]' <<< $RESULT3;)
$verbose && echo -e "\nvar \$JSONRESULT3\n$JSONRESULT3" || :


# проверка на статус домена (0 - домен выключен в кц, услуга неактивна). Если всё ок - продолжаем выполнение с выводом предупреждения
STATUSRESULT=$($BJQ -r '.result.items | .. | .status? | select (.)' <<< $RESULT | tr -d ',';)
# тут надо допилить проверку массива функцией empty as best practices
if [[ $STATUSRESULT =~ 0 ]]
then
        echo -e "\n\e[1;33mWarning! Domain status is disabled for one or more ports.\e[0m\nVisit to http://.secret. and billing, and check status!"
else
        :
fi
$verbose && echo -e "\nvar \$STATUSRESULT\n$STATUSRESULT" || :

# проверка на наличие listen (здесь массив)
FRONTENDIPSRESULT=($($BJQ -r '.result.items | .. | .frontend_ips? | select (.)' <<< $RESULT | tr -d ',"[]' | sort -u;))
if empty "$FRONTENDIPSRESULT"
then
        echo -e "\e[1;31m\nError! Domain have not listen ip.\e[0m\nVisit to http://.secret."
else
        :
fi
$verbose && echo -e "\nvar \$FRONTENDIPSRESULT\n$FRONTENDIPSRESULT" || :


# проверка на наличие backend
BACKENDIPSRESULT=$($BJQ -r '.result.items | .. | .backend_ips? | select (.)' <<< $RESULT | tr -d ',\"[]' | sort -u;)
if [[ -z "$BACKENDIPSRESULT" ]]
then
        # получаем время создания конфигурации 80 scheme, вычисляем разницу - потестировать на проде, может быть проблема с временным поясом
        RESULTCREATED=$($BJQ -r '.result.created' <<< $RESULT2;)
        TIMEDIFF=$(( $(date +%s) - (RESULTCREATED) ))
        echo -e "\e[1;31m\nError! Domain have not backend ip.\e[0m Domain configuration was created \e[1;33m$(($TIMEDIFF / 3600))h $((($TIMEDIFF / 60) % 60))m\e[0m ago."
        # проверка на 24 часа с момента создания конфигурации
                if (( (RESULTCREATED + 1440*60) > $(date +%s) ))
                then
                        echo -e "\e[1;32mPossible new domain - created less than 24 hours ago\e[0m"
                fi
else
        RESULTCREATED=$($BJQ -r '.result.created' <<< $RESULT2;)
        TIMEDIFF=$(( $(date +%s) - (RESULTCREATED) ))
        $verbose && echo -e "\nvar \$TIMEDIFF\n$TIMEDIFF" || :
        $verbose && echo -e "\nvar \$TIMEDIFF human readable\n$(($TIMEDIFF / 3600))h $((($TIMEDIFF / 60) % 60))m" || :
fi
$verbose && echo -e "\nvar \$BACKENDIPSRESULT\n$BACKENDIPSRESULT" || :

# проверка на наличие ssl в 443 scheme (frontend) - возможно, имеет смысл реализовать по no_ssl=1 из domains.get
SSL_FRONTEND=$($BJQ -r '.result.ssl_key' <<< $RESULT3 | tr -d '"';)
$verbose && echo -e "\nvar \$SSL_FRONTEND\n$SSL_FRONTEND" || :
if empty "${SSL_FRONTEND}"
then
        SSL_FRONTEND=http
else
        SSL_FRONTEND=https
fi
$verbose && echo -e "\nvar \$SSL_FRONTEND was changed to \e[1;33m$SSL_FRONTEND\e[0m" || :

# формирование ссылки на check-host, учитывая протокол
echo -e "\e[1;34m\nCheck-host https response:\e[0m https://check-host.net/check-http?host=$SSL_FRONTEND%3A//$NAME"

# формирование ссылки на Graylog (получение стрима)
GRAYLOGSTREAM=$($BJQ -r '.result.graylog_stream' <<< $RESULT2 | tr -d '"';)

# проверка на заполнение стрима, и выбор l7filter в случае отсутствия стрима в конфигурации
if empty "${GRAYLOGSTREAM}"
then
        GRAYLOGSTREAM=5eb3eaf8bb3f0840b000cf83
        $verbose && echo -e "\nvar \$GRAYLOGSTREAM was empty and changed to default l7filter stream: $GRAYLOGSTREAM" || :
else
        :
fi
echo -e "\e[1;34m\nGraylog link 5m unfiltered:\e[0m http://graylog.storm-pro.net/streams/$GRAYLOGSTREAM/search?q=DM%3A$NAME%2A"
#echo -e "\e[1;34m\nGraylog link 10m filtered:\e[0m http://graylog.storm-pro.net/streams/$GRAYLOGSTREAM/search?q=DM%3A$NAME%2A+AND+NOT+BS%3AJS-BLOCK%2A+AND+NOT+BS%3AHEADERS-BLOCK%2A+AND+NOT+BS%3ACAPTCHA+AND+NOT+BS%3AGEO-BLOCK%2A+AND+NOT+LOCS-BLOCK%2A&from=600"
#$verbose && echo -e "\nvar \$GRAYLOGSTREAM\n$GRAYLOGSTREAM" || :

# формирование ссылки на услугу
SERVICE_ID=$($BJQ -r '.result.service_id' <<< $RESULT2;)
echo -e "\e[1;34m\nBilling link:\e[0m https://stormwall.pro/my/4g5jla3lh92y3eg57/clientsservices.php?id=$SERVICE_ID"
$verbose && echo -e "\nvar \$SERVICE_ID\n$SERVICE_ID" || :

# получение balance enabled ip, с сортировкой т.к. в конфигурации порядок может быть иной (внимание, здесь массив)
ENABLE_BALANCE_IP80=($($BJQ -r '.result.backend_ips[] | select(.type == "balance" and .status == "enabled") | .ip' <<< $RESULT2 | tr -d '"' | sort -u;))
ENABLE_BALANCE_IP443=($($BJQ -r '.result.backend_ips[] | select(.type == "balance" and .status == "enabled") | .ip' <<< $RESULT3 | tr -d '"' | sort -u;))
$verbose && echo -e "\nvar \$ENABLE_BALANCE_IP80\n${ENABLE_BALANCE_IP80[*]}" || :
$verbose && echo -e "\nvar \$ENABLE_BALANCE_IP443\n${ENABLE_BALANCE_IP443[*]}" || :

# проверка на совпадение balance enabled backend ip в 80 и 443 схемах
if [[ "${ENABLE_BALANCE_IP80[*]}" != "${ENABLE_BALANCE_IP443[*]}" ]]
then
        echo -e "\e[1;33m\nWarning! 80 and 443 schemes for domain have differend active backend ip. Need manual check!\e[0m\nVisit to http://.secret.\n80 scheme enable and balance backend ip:\n${ENABLE_BALANCE_IP80[*]}\n443 scheme enable and balance backend ip:\n${ENABLE_BALANCE_IP443[*]}"
else
        :
fi

# проверка на наличие ssl в 443 scheme (backend) - тут слабое место, я принимаю за данность то, что для нескольких бэков указаны идентичные порты
PORT_BACKEND=$($BJQ -r '.result.backend_ips[] | select(.type == "balance" and .status == "enabled") | .port' <<< $RESULT3 | tr -d '"' | head -n 1;)
if [[ $PORT_BACKEND == "80" ]]
then
        SSL_BACKEND=http
elif [[ $PORT_BACKEND == "443" ]]
then
        SSL_BACKEND=https
else
unexpected_error
fi
$verbose && echo -e "\nvar \$PORT_BACKEND\n$PORT_BACKEND" || :
$verbose && echo -e "\nvar \$SSL_BACKEND\n$SSL_BACKEND" || :

# проверка на совпадение А-записи и listen, так же учитываем наличие idn
if empty "$IDN"
then
        echo -e "\n\e[1;33mWarning! You can get null A-record!\e[0m The domain name is not being converted now to punycode, it needs to be done manually!\n[1;33mInput mode switched, now there is no filtering!\e[0m\nVisit to https://www.punycoder.com"
#else
#       :
#fi
        DIG=($($BDIG a $DOMAIN +time=5 +tries=1 +short | sort -u))
        $verbose && $BDIG a $DOMAIN || :
        $verbose && $BDIG a $DOMAIN +trace || :
        if [[ "${$BDIG[*]}" != "${FRONTENDIPSRESULT[*]}" ]]
        then
                echo -e "\n\e[1;33mWarning! Difference A-record!\e[0m\n\e[1;34m\nCheck-host A-records:\e[0m https://check-host.net/check-dns?host=$NAME"
        else
                :
        fi
else
        DIG=($($BDIG a $NAME +time=5 +tries=1 +short | sort -u))
        $verbose && $BDIG a $NAME || :
        $verbose && $BDIG a $NAME +trace || :
        if [[ "${DIG[*]}" != "${FRONTENDIPSRESULT[*]}" ]]
        then
                echo -e "\n\e[1;33mWarning! Difference A-record!\e[0m\n\e[1;34m\nCheck-host A-records:\e[0m https://check-host.net/check-dns?host=$NAME"
        else
                :
        fi
        $verbose && echo -e "\nvar \$DIG\n${DIG[*]}" || :
        $verbose && echo -e "\nvar \$DIG\n$DIG" || :
fi

# формируем вывод основной информации
echo -e "\n===================\nDomain info:"
echo -e "$NAME"
echo -e "* this domain uses $SSL_BACKEND"
echo -e "* his backend host uses port $PORT_BACKEND"
echo -e "* his listen ip: ${FRONTENDIPSRESULT[*]}"
echo -e "* his a-records: ${DIG[*]}"
echo -e "\nCurl to backends:"

# формируем готовый curl запрос (source backend ip - 443 scheme)
for ip in "${ENABLE_BALANCE_IP443[@]}"
do
        $verbose && echo -e "\nvar \$ip\n$ip\n" || :
        echo -e "\e[1;34m\`\`\`\ntime curl -LI -ikH \"Host: $NAME\" $SSL_BACKEND://$ip:$PORT_BACKEND\n\`\`\`\e[0m"
#time curl -LI -ikH "Host: $NAME" $SSL_BACKEND://$ip:$PORT_BACKEND
#sleep 1
done
#echo -e "Hint: if you will have \"Empty reply from server\", try changing the header in curl to \e[1;34m\"Host $NAME\"\e[0m\n"
echo -e "==================="

# стучимся в порт backend (source backend ip - 443 scheme)
for ip in "${ENABLE_BALANCE_IP443[@]}"
do
        $verbose && echo -e "\nvar \$ip\n$ip\n" || :
        echo -ne "\nKnocking to $ip:$PORT_BACKEND... "
        NC=$(nc -zvw 15 $ip $PORT_BACKEND 2>&1 | $BGREP Connect;)
        echo $NC
done
