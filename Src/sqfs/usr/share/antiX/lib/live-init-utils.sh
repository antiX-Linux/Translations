# File: live-init-utils.sh
#
# Utility routines for live init.d scripts.
#
# Meant to run under /bin/dash or busybox ash.
# Handles: color output, logging, xlat translation, loading lang file, and
#          protecting files from being written to more than once.


INIT_LANG_DIR=/usr/share/antiX/init-lang
INIT_XLAT_DIR=/usr/share/antiX/init-xlat

DISABLED_RC_DIR=/etc/live/disabled-rc.d

PROTECT_DIR=/etc/live/protect
PERSIST_PROTECT_FILE=$PROTECT_DIR/persist
REMASTER_PROTECT_FILE=$PROTECT_DIR/remaster

X_INIT_LOG_FILE=/var/log/live/live-init.log
INIT_LOG_FILE=/dev/null

export TEXTDOMAIN=$(basename $0)
export TEXTDOMAINDIR=/usr/share/locale

#COLOR_LOW=true

VERBOSE=5

[ "$CMDLINE" ] || CMDLINE="$(cat /proc/cmdline)"
for param in $CMDLINE; do
    case "$param" in
    #    verbose=*|verb=*|v=*) VERBOSE=${param#*=}      ;;
                noco|nocolor) COLOR_OFF=true           ;;
               loco|lowcolor) COLOR_LOW=true           ;;
              hico|highcolor) unset COLOR_LOW          ;;
                       nolog) NO_LOG=true              ;;
                      lang=*) LIB_CMD_LANG=${param#*=} ;;
    esac
done

if ! [ "$COLOR_OFF" ]; then
    NO_COLOR="[0m"
    RED="[1;31m"
    GREEN="[1;32m"
    YELLOW="[1;33m"
    BLUE="[1;34m"
    MAGENTA="[1;35m"
    CYAN="[1;36m"
    WHITE="[1;37m"
    AMBER="[0;33m"
fi

if [ "$COLOR_OFF" ]; then
    START_PARAM='"'
    END_PARAM='"'
elif [ "$COLOR_LOW" ]; then
    ANTIX_COLOR="$WHITE"
    LIVE_COLOR="$AMBER"
    START_PARAM="$WHITE"
    END_PARAM="$LIVE_COLOR"
    SCRIPT_COLOR="$GREEN"
    SCRIPT_PARAM_COLOR="$WHITE"
    ERROR_PARAM_COLOR="$RED"
else
    ANTIX_COLOR="$GREEN"
    LIVE_COLOR="$CYAN"
    START_PARAM="$YELLOW"
    END_PARAM="$LIVE_COLOR"
    SCRIPT_COLOR="$GREEN"
    SCRIPT_PARAM_COLOR="$CYAN"
    ERROR_PARAM_COLOR="$RED"
fi

# alias pf=printf  (**sigh**)
pf() {
    printf "$@"
}

pquote() {
    echo "$START_PARAM$@$END_PARAM"
}

paren() {
    echo "($SCRIPT_COLOR$@$LIVE_COLOR)"
}

start_init_logging() {
    [ "$NO_LOG" ] && return
    INIT_LOG_FILE=$X_INIT_LOG_FILE
    mkdir -p $(dirname $INIT_LOG_FILE)
    echo               >> $INIT_LOG_FILE
    echo "$(date)  $0" >> $INIT_LOG_FILE
}

echo_live() {
    local fmt="$1" && shift
    printf "$LIVE_COLOR  $fmt$NO_COLOR\n" "$@"
}

error() {
    local fmt="$1" && shift
    load_translation live-init-utils.sh

    # This is not optimally fast but it allows "Error" to get transated
    # via the normal mechanism.
    err=$(pf "$_Error_")
    printf "  ${ERROR_PARAM_COLOR}$err:$LIVE_COLOR $fmt$NO_COLOR\n" "$@"
}

echo_script() {
    echo "$SCRIPT_COLOR$(basename $2)$NO_COLOR: $SCRIPT_PARAM_COLOR$1$NO_COLOR"
}


time_it() {
    "$@"
}

load_translation() {
    local file=${1:-$(basename $0)}.xlat
    local lang full

    if [ "$LIB_CMD_LANG" ]; then
        lang=${LIB_CMD_LANG%_*}
        full=$INIT_XLAT_DIR/$lang/$file
        [ -r $full ] && . $full && return 0
    fi

    full=$INIT_XLAT_DIR/en/$file
    [ -r $full ] && . $full && return 0
    echo "${RED}ERROR:$NO_COLOR Could not find xlat file for $(basename $0)!" 1>&2
}

get_init_lang() {
    local lang=$1

    load_translation live-init-utils.sh

    local lang_file=$INIT_LANG_DIR/$lang.lang
    if ! [ -r "$lang_file" ]; then
        [ "$2" ] && init_lang_error $1
        return 1
    fi

    echo_live "$_Setting_language_via_X_" $(pquote lang=$lang)
    . $lang_file
    return 0
}

init_lang_error() {
    local lang=$1

    load_translation live-init-utils

    error "$_Unknown_language_code_X_" $(pquote $lang)
    local vlangs
    for vlang in $(ls $INIT_LANG_DIR | sed 's/\.sh//g'); do
        vlangs="$vlangs $vlang"
    done
    echo_live "$_Valid_languages_codes_X_" "$NO_COLOR$vlangs";
}

#------------------------------------------------------------------------------
# Function: first_write unique-flag
#
# Decide if a config file should be updated or protected/preserved.  If The
# unique flag (usually the absolute path of the config file) is not in either
# of the protect files then we return true, signaling that the file should be
# initialized.
#
# The idea is that some config files should only be intialized once if
# persistence is enabled.  If a boot parameter is specifically given then we
# will update the file anyway.
#
# DOES NOT COMMUTE!  Should be after all ANDs and before all ORs.
#------------------------------------------------------------------------------

first_write() {
    local flag="$1"
    shift

    #touch $PERSIST_PROTECT_FILE
    if ! grep -q "^$flag$" $PERSIST_PROTECT_FILE 2> /dev/null; then
        echo "$flag" >> $PERSIST_PROTECT_FILE

        #touch $REMASTER_PROTECT_FILE
        grep -q "^$flag$" $REMASTER_PROTECT_FILE 2> /dev/null || return 0
    fi

    return 1
}

