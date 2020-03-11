#!/bin/bash
# Enviando estatísticas do servidor Asterisk para o servidor Zabbix

# Matriz de pares de strings Comando Asterisk - uma string de um programa awk para processar strings
# resposta da equipe
aComAwk=(
 'core show uptime seconds' '/System uptime:/ { print "uptime", int($3) }'
 'core show threads' '/threads listed/ { print "threads", int($1) }'
 'voicemail show users' '/voicemail users configured/ { print "voicemail.users", int($1) } BEGIN { m = 0 } /^default/ { m += int($NF) } END { print "voicemail.messages", m }'
 'sip show channels' '/active SIP/ { print "sip.channels.active", int($1) }'
 'iax2 show channels' '/active IAX/ { print "iax2.channels.active", int($1) }'
 'sip show peers' '/sip peers/ { print "sip.peers", int($1); print "sip.peers.online", int($5) + int($10) }'
 'iax2 show peers' '/iax2 peers/ { print "iax2.peers", int($1) }'
 'core show channels' '/active channels/ { print "channels.active", int($1) } /active calls/ { print "calls.active", int($1) } /calls processed/ { print "calls.processed", int($1) }'
 'xmpp show connections' '/Number of clients:/ { print "xmpp.connections", int($NF) }'
 'sip show subscriptions' '/active SIP subscriptions/ { print "sip.subscriptions", int($1) }'
 'sip show registry' '/SIP registrations/ { print "sip.registrations", int($1) } BEGIN { r = 0 } /Registered/ { r += 1 } END { print "sip.registered", int(r) }'
 'iax2 show registry' '/IAX2 registrations/ { print "iax2.registrations", int($1) } BEGIN { r = 0 } /Registered/ { r += 1 } END { print "iax2.registered", int(r) }'
)

# Formação de uma linha de comando do Asterisk a partir das linhas de comando da matriz
CommandStr=$(
 for(( i = 0; i < ${#aComAwk[@]}; i += 2 )); do
  echo -n "Action: command\r\nCommand: ${aComAwk[i]}\r\n\r\n"
 done
)

# Executando comandos do Asterisk através da interface AMI
ResStr = $ (/ bin / echo -e "Ação: Login \ r \ nUsername: Monitoring_user \ r \ nSecret: Monitoring_password \ r \ nEventos: desativados \ r \ n \ r \ n $ {CommandStr} Ação: Logoff \ r \ n \ r \ n "| / usr / bin / nc 127.0.0.1 5038 2> / dev / null)
# Estatísticas não disponíveis - retornando o status do serviço - 'não funciona'
[$? ! = 0] && echo 0 && exit 1

# Índice de linha awk na matriz
iAwk = 1
# Separador de campos na linha de entrada - para processamento linha por linha
IFS = $ '\ n'
# Linha de saída
OutStr=$(
 # Processamento linha a linha de uma sequência de resultados de execução de comando
 for rs in $ResStr; do
  # A sequência do início da substring do resultado do comando
  if [ "$rs" = "Response: Follows"$'\r' ]; then
   # Salvando a posição do início da substring de resultado na linha de resultado
   begin=$pos
  # Строка конца подстроки результата выполнения команды
  elif [ "$rs" = '--END COMMAND--'$'\r' ]; then
   # Выполнение awk-программы над подстрокой результата выполнения команды
   (cat <<EOF
${ResStr:$begin:$pos-$begin}
EOF
   ) | awk "${aComAwk[iAwk]}"
   # Переключение индекса строки awk-программы в массиве на следующую
   let "iAwk+=2"
  fi
  # Позиция начала следующей строки в строке результатов
  let "pos+=${#rs}+1"
 # Вставка в начало каждой строки
 done | awk '{ print "- asterisk."$0 }'
)

# Идентификатор процесса Asterisk из PID-файла
pid=$(/bin/cat /var/run/asterisk/asterisk.pid 2>/dev/null)
# PID-файл отсутствует - возврат статуса сервиса - 'не работает'
[ -z "$pid" ] && echo 0 && exit 1
# Строка вывода использования CPU и памяти процессом Asterisk
OutStr1=$((/bin/ps --no-headers --pid $pid --ppid $pid -o pcpu,rssize || echo 0 0) | awk '{ c+=$1; m+=$2 } END { print "- asterisk.pcpu", c; print "- asterisk.memory", m*1024 }')

# Отправка строки вывода серверу Zabbix. Параметры zabbix_sender:
#  --config		файл конфигурации агента;
#  --host		имя узла сети на сервере Zabbix;
#  --input-file		файл данных('-' - стандартный ввод)
(cat<<EOF
$OutStr
$OutStr1
EOF
) | /usr/bin/zabbix_sender --config /etc/zabbix/zabbix_agentd.conf --host=`hostname` --input-file - >/dev/null 2>&1
# Возврат статуса сервиса - 'работает'
echo 1
exit 0
