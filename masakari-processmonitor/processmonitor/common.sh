# Copyright(c) 2015 Nippon Telegraph and Telephone Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

LOGTAG=`basename $0`
HOST_NAME=`hostname`
LOGDIR="/var/log/masakari"
LOGFILE="${LOGDIR}/masakari-processmonitor.log"

# Debug log output function
# Argument
#   $1 : Message
log_debug () {
    if [ ! -e ${LOGDIR} ]; then
        mkdir -p ${LOGDIR}
    fi

    if [ "${LOG_LEVEL}" == "debug" ]; then
        log_output "$1"
    fi
}

# Info log output function
# Argument
#   $1 : Message
log_info () {
    if [ ! -e ${LOGDIR} ]; then
        mkdir -p ${LOGDIR}
    fi

    log_output "$1"
}

# This function outputs the log
# Argument
#   $1 : Message
log_output () {
    echo "`date +'%Y-%m-%d %H:%M:%S'` ${HOST_NAME} ${LOGTAG}:  $1"  >> $LOGFILE
}

# Check the value is correct type
# Argument
#   $1: Type
#   $2: Config File
#   $3: Parameter Name
#   $4: Value
# Return
#   0: The value is correct type
# Exit the program:
#   if parameter is invalid type or not set
check_config_type() {
    expected_type=$1
    conf_file=$2
    parameter_name=$3
    value=$4

    ret=0
    case $expected_type in
        int)
            expr $value + 1 > /dev/null 2>&1
            if [ $? -ge 2 ]; then ret=1; fi
            ;;
        string)
            if [ -z $value ] ; then ret=1; fi
            ;;
        *)
            ret=1
            ;;
    esac

    if [ $ret -eq 1 ] ; then
        log_info "config file parameter error. [${conf_file}:${parameter_name}]"
        exit 1
    fi

    log_info "config file parameter : ${parameter_name}=${value}"
    return 0
}

# Check the file exists or not
# Argument
#   $1: File Path
#   $2: Config File
# Return
#   0: The file is executable or is not specified
# Exit the program:
#   if the file doesn't exist or is not executable
check_executable_file () {
    # If the file path is not specified in the conf file,
    # # of argument could be 1.
    if [ $# -ne 2 ]; then
        return 0
    fi

    file_path=$1
    conf_file=$2

    if [ ! -e $file_path ]; then
        log_info "$conf_file format error: ($file_path) does't exist."
        exit 2
    fi
    if [ ! -x $file_path ]; then
        log_info "$conf_file format error: ($file_path) isn't exeutable."
        exit 2
    fi

    log_info "$file_path exists and is executable."
    return 0
}

# A function for parameter check for proc.list config file.
# proc.list must be CSV format and the format is following:
#   First column   : ID (two digits of leading zeros)
#   Second column  : A keyword for checking if the process is running or not
#   Third column   : A command for first startup the process
#   Fourth column  : A command for rebooting the process
#   Fifth column   : File path for preprocessing shell script before startup (Optional)
#   Sixth column   : File path for postprocessing shell script after startup (Optional)
#   Seventh column : File path for preprocessing shell script before rebooting (Optional)
#   Eighth column  : File path for postprocessing shell script after rebooting (Optional)
#
# Return
#   0: success to check the file format
# Exit the program:
#   if the file format is invalid

column_num=8
check_proc_file_common (){

    # Check the existence and validity of the proc.list.
    if [ ! -e $PROC_LIST ]; then
        log_info "$PROC_LIST(proc_list) is not exists."
        exit 2
    fi

    if [ ! -s $PROC_LIST ]; then
        log_info "$PROC_LIST(proc_list) is empty file."
        exit 2
    fi

    if [ ! -r "$PROC_LIST" ]; then
        log_info "$PROC_LIST(proc_list) is not readable."
        exit 2
    fi

    OLD_IFS=$IFS
    IFS=$'\n'
    proc_list=(`cat $PROC_LIST`)
    IFS=$OLD_IFS

    LINE_NO=1

    for line in "${proc_list[@]}"
    do
        num=`echo "$line" | tr -dc ',' | wc -c`
        # The number of required column are incomplete.
        check_num=`expr $column_num - 1`
        if [ $num -ne $check_num ]; then
            log_info "$PROC_LIST format error (column_num) line $LINE_NO"
            exit 2
        fi

        PROC_ID=`echo $line | cut -d"," -f 1`
        check_config_type 'int' $PROC_LIST PROC_ID $PROC_ID

        KEY_WORD=`echo $line | cut -d"," -f 2`
        check_config_type 'string' $PROC_LIST KEY_WORD $KEY_WORD

        START_CMD=`echo $line | cut -d"," -f 3`
        check_config_type 'string' $PROC_LIST START_CMD $START_CMD

        RESTART_CMD=`echo $line | cut -d"," -f 4`
        check_config_type 'string' $PROC_LIST RESTART_CMD $RESTART_CMD

        START_SP_CMDFILE_BEFORE=`echo $line | cut -d"," -f 5`
        check_executable_file $START_SP_CMDFILE_BEFORE $PROC_LIST

        START_SP_CMDFILE_AFTER=`echo $line | cut -d"," -f 6`
        check_executable_file $START_SP_CMDFILE_AFTER $PROC_LIST

        RESTART_SP_CMDFILE_BEFORE=`echo $line | cut -d"," -f 7`
        check_executable_file $RESTART_SP_CMDFILE_BEFORE $PROC_LIST

        RESTART_SP_CMDFILE_AFTER=`echo $line | cut -d"," -f 8`
        check_executable_file $RESTART_SP_CMDFILE_AFTER $PROC_LIST

        LINE_NO=`expr $LINE_NO + 1`
     done
}

