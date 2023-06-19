#!/bin/sh

# ====CHANGE ME WHOLE====
# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=/bkp-HDD/

# See the section "Passphrase notes" for more infos.
export BORG_PASSPHRASE='xxxxxx'

# Location for LOG (including the file)
LOG="/logs/borg.log"
TEMPORAL_LOG_PATH="/tmp/"

# Name of the server (WITHOUT SPACES) DON'T CHANGE IT AFTER THE FIRST BACKUP
SERVER_NAME="SERVER_NAME"

# Paths for copy (splited by spaces)
PATHS_TO_COPY="/bkp-from/FOTOS /bkp-from/DATOS /bkp-from/appdata /bkp-from/BAUL"

# How many copies do you want to store
DAILY=7
WEEKLY=4
MONTHLY=6

# Telegram Variables
TOKEN="telegramTokenHere"
ID="chatIdHere"
DOCUMENT_NAME="telegramLogFileName" # (WITHOUT SPACES)
DESTINATION_NAME="JustANameLikeHDD" # (WITHOUT SPACES)
NUM_LINES_FILE=1000 # Number of lines of log file sent to Telegram

# Communication: All messages to telegram and log are in Spanish language, feel free to change them
# (Try not to change the $XXXX variables... you might break some things)
# Telegram allows *this* to put the text in bold
HEAD_TELEGRAM="*==${SERVER_NAME} COPIA A $DESTINATION_NAME==*"
INITIAL_TEXT_TELEGRAM="$HEAD_TELEGRAM
Iniciando copia de seguridad"
FINISH_SUCCESSFULLY_TEXT_TELEGRAM="$HEAD_TELEGRAM
La copia se ha realizado *correctamente* en $DESTINATION_NAME."
FINISH_WITH_ERROR_TEXT_TELEGRAM="$HEAD_TELEGRAM
La copia se ha realizado *con errores* en $DESTINATION_NAME."
FAILED_TEXT_TELEGRAM="$HEAD_TELEGRAM
La copia *NO* se ha realizado correctamente en $DESTINATION_NAME."
TIME_SPENT="Tiempo total: " # try to respect the last space
OCCUPIED_SPACE="Espacio ocupado: " # try to respect the last space
STARTING_WITH_DATE_MSG="Iniciando backup con fecha: " # try to respect the last space
PRUNING_MSG="Marcando revisiones para eliminar"
COMPACTING_MSG="Descartando revisiones"

# ====DO NOT TOUCH FROM HERE====
DATELOG=`date +%Y-%m-%d`

send_telegram_message() {
  local URL_MESSAGE="https://api.telegram.org/bot$TOKEN/sendMessage"
  local MESSAGE="$1"
  curl -s -X POST $URL_MESSAGE -d chat_id=$ID -d text="$MESSAGE" -d parse_mode=Markdown
}

send_telegram_document() {
  local URL_DOCUMENT="https://api.telegram.org/bot$TOKEN/sendDocument"
  curl -v -4 -F             \
  chat_id=$ID               \
  -F document=@$1           \
  $URL_DOCUMENT 2> /dev/null
}

send_telegram_message "$INITIAL_TEXT_TELEGRAM"

echo "$STARTING_WITH_DATE_MSG$DATELOG" >> $LOG

# Crono start
TIME_START=`date +%s`

# Backup the most important directories into an archive named after
# the machine this script is currently running on:

borg create                           \
    --verbose                         \
    --filter AME                      \
    --list                            \
    --stats                           \
    --show-rc                         \
    --compression lz4                 \
    --exclude-caches                  \
    --exclude 'home/*/.cache/*'       \
    --exclude 'var/tmp/*'             \
    --files-cache ctime,size          \
                                      \
    ::"${SERVER_NAME}-{now}"          \
    $PATHS_TO_COPY                    \
    2>> $LOG

backup_exit=$?

echo "$PRUNING_MSG" >> $LOG

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-*' matching is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                             \
    --list                             \
    --glob-archives "${SERVER_NAME}-*" \
    --show-rc                          \
    --keep-daily    $DAILY             \
    --keep-weekly   $WEEKLY            \
    --keep-monthly  $MONTHLY           \
    2>> $LOG

prune_exit=$?

# actually free repo disk space by compacting segments

echo "$COMPACTING_MSG" >> $LOG

borg compact 2>> $LOG

compact_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : compact_exit ))

# Crono stop
TIME_STOP=`date +%s`
RUNTIME=$(( TIME_STOP - TIME_START ))
D=$((RUNTIME/60/60/24))
H=$((RUNTIME/60/60%24))
M=$((RUNTIME/60%60))
S=$((RUNTIME%60))
TOTAL_TIME=""
if [ $D -gt 0 ]; then
  TOTAL_TIME="${D}d, "
fi
if [ $H -gt 0 ]; then
  TOTAL_TIME="${TOTAL_TIME}${H}h, "
fi
if [ $M -gt 0 ]; then
  TOTAL_TIME="${TOTAL_TIME}${M}m, "
fi
TOTAL_TIME="${TOTAL_TIME}${S}s"

# Calculating disk space used and formatting
SPACE_LEFT=$(df $BORG_REPO -h | awk '{print $3"/"$2" ("$5")"}' | sed -n '2p' | sed 's/T/TB/g; s/G/GB/g; s/M/MB/g')

TELEGRAM_FILE="$TEMPORAL_LOG_PATH$DOCUMENT_NAME-$DESTINATION_NAME-$DATELOG.log"
grep -B 1 -A $NUM_LINES_FILE "Archive name: ${SERVER_NAME}-$DATELOG" $LOG > $TELEGRAM_FILE

SPACE_ADDED=$(cat $TELEGRAM_FILE | grep "This archive" | awk '{print $7 $8}' | tail -n 1)

TIME_AND_SPACE_LEFT="$TIME_SPENT$TOTAL_TIME
$OCCUPIED_SPACE$SPACE_LEFT ($SPACE_ADDED)"

FINISH_SUCCESSFULLY_TEXT_TELEGRAM="$FINISH_SUCCESSFULLY_TEXT_TELEGRAM
$TIME_AND_SPACE_LEFT"
FINISH_WITH_ERROR_TEXT_TELEGRAM="$FINISH_WITH_ERROR_TEXT_TELEGRAM
$TIME_AND_SPACE_LEFT"
FAILED_TEXT_TELEGRAM="$FAILED_TEXT_TELEGRAM
$TIME_AND_SPACE_LEFT"

if [ ${global_exit} -eq 0 ]; then
    echo "$FINISH_SUCCESSFULLY_TEXT_TELEGRAM" >> $LOG
    send_telegram_message "$FINISH_SUCCESSFULLY_TEXT_TELEGRAM"
elif [ ${global_exit} -eq 1 ]; then
    echo "$FINISH_WITH_ERROR_TEXT_TELEGRAM" >> $LOG
    send_telegram_message "$FINISH_WITH_ERROR_TEXT_TELEGRAM"
else
    echo "$FAILED_TEXT_TELEGRAM" >> $LOG
    send_telegram_message "$FAILED_TEXT_TELEGRAM"
fi

send_telegram_document $TELEGRAM_FILE

rm $TELEGRAM_FILE

echo >> $LOG
echo "========================================================" >> $LOG
echo >> $LOG

exit ${global_exit}
