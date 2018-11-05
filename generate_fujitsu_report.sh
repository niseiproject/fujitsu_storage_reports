#!/bin/bash

######## VARIABLES
ODX600PRO='pro-odx600'
EDX600PRO='pro-edx600'
ODX440PRO='pro-odx440'
EDX440PRO='pro-edx440'
ODX440PRE='pre-odx440'
EDX440PRE='pre-edx440'

# Fill the variables with valid IPs from your environment
ODX600PRO_IP='CABINET IP1'
EDX600PRO_IP='CABINET IP2'
ODX440PRO_IP='CABINET IP3'
EDX440PRO_IP='CABINET IP4'
ODX440PRE_IP='CABINET IP5'
EDX440PRE_IP='CABINET IP6'

DX_HOSTS_CSV="$HOME/$1_hosts.csv"
DX_VOLUMES_CSV="$HOME/$1_volumes.csv"
DX_RAIDGRP_CSV="$HOME/$1_raidgrp.csv"
DX_MASKING_CSV="$HOME/$1_masking.csv"

HOST_HEADER='Hostname;Initiators'
MASKING_HEADER='Hostname;SCSI id;Volume id;Volume name;Status;Size (MB);Shared'
RAID_HEADER='RG id;RG name;RAID level;Assigned CM;Status;Total capacity (MB);Free capacity (MB)'
VOLUME_HEADER='Volume ID;Volume name;Status;Type;RG id;RG name;Size(MB);UUID'

ID_PUB="$HOME/.ssh/id_dsa_fujitsu"
USER='x101513'

LOG='/home/ipa/admx101513/scripts/log'

#Num  Colour    #define         R G B

#0    black     COLOR_BLACK     0,0,0
#1    red       COLOR_RED       1,0,0
#2    green     COLOR_GREEN     0,1,0
#3    yellow    COLOR_YELLOW    1,1,0
#4    blue      COLOR_BLUE      0,0,1
#5    magenta   COLOR_MAGENTA   1,0,1
#6    cyan      COLOR_CYAN      0,1,1
#7    white     COLOR_WHITE     1,1,1

WHITE=7
GREEN=2
RED=1
CYAN=6
MAGENTA=5


######## FUNCTIONS
get_usage_example (){

    echo
    echo "Example usage:"
    echo "$0 ( pro-odx600 | pro-edx600 | pro-odx440 | pro-edx440 | pre-odx440 | pre-edx440 )"
    return 0
}

check_parameters (){

    case $1 in

        'pro-odx600'|'pro-edx600'|'pro-odx440'|'pro-edx440'|'pre-odx440'|'pre-edx440')
                    return 1
                    ;;
        *)
            get_usage_example
            ;;

    esac

    return 0
}

get_array (){
	
	# Adjust this case statement with the identifiers filled above.
    case $1 in

        'pro-odx600')
                    echo $ODX600PRO_IP
                    return 1
                    ;;
        'pro-edx600')
                    echo $EDX600PRO_IP
                    return 1
                    ;;
        'pro-odx440')
                    echo $ODX440PRO_IP
                    return 1
                    ;;
        'pro-edx440')
                    echo $EDX440PRO_IP
                    return 1
                    ;;
        'pre-odx440')
                    echo $ODX440PRE_IP
                    return 1
                    ;;
        'pre-edx440')
                    echo $EDX440PRE_IP
                    return 1
                    ;;

        *)
                    echo ''
                    ;;

    esac

    return 0
}


initialize_csv_files (){

    
    if test -s $DX_HOSTS_CSV
    then
        > $DX_HOSTS_CSV

    else
        touch $DX_HOSTS_CSV
    fi

    if test -s $DX_VOLUMES_CSV
    then
        > $DX_VOLUMES_CSV

    else
        touch $DX_VOLUMES_CSV
    fi

    if test -s $DX_RAIDGRP_CSV
    then
        > $DX_RAIDGRP_CSV

    else
        touch $DX_RAIDGRP_CSV
    fi

    if test -s $DX_MASKING_CSV
    then
        > $DX_MASKING_CSV

    else
        touch $DX_MASKING_CSV
    fi

    return 0
}


get_hosts (){

        ip=$1
        hosts_file=$2

        hg_file=`mktemp hg.XXXX`
        hg_list=`mktemp hg2.XXXX`

        echo show host-groups -all | ssh -i $ID_PUB -T $USER@$ip > $hosts_file 2> /dev/null
        dos2unix -q -o $hosts_file
        for hg_number in `cat $hosts_file | grep -i -E "[a-zA-F0-9]{16}" | awk '{print $1}'`
        do
            echo "show host-groups -host-number $hg_number" | ssh -i $ID_PUB -T $USER@$ip > $hg_file 2> /dev/null
            dos2unix -q -o $hg_file
            wwn=`cat $hg_file | grep -i -E "[a-zA-F0-9]{16}" | awk '{print $3}'`
            host=`cat $hg_file | grep -i "FC/FCoE" | awk '{print $2}'`
            echo "`get_hostname $host` $wwn" >> $hg_list
        done
        
        > $hosts_file

        echo $HOST_HEADER > $hosts_file

        for host in `cat $hg_list | awk '{print $1}' | uniq`
        do
            initiators=`grep -i $host $hg_list | awk '{print $2}' | xargs | sed s/" "/,/g`
            line="$host;$initiators"
            echo $line >> $hosts_file
        done    
        rm -f $hg_file
        rm -f $hg_list
        return 0
}   


get_hostname (){

    chain=$1
    echo $chain | awk -F'_' '{print $2}'

    return 0
}


get_affinity_groups (){

    ip=$1
    masking_f=$2
    ag_file=`mktemp ag.XXXX`
    ag_list=`mktemp ag2.XXXX`
    
    echo $MASKING_HEADER > $masking_f

    echo "show affinity-groups" | ssh -i $ID_PUB -T $USER@$ip > $ag_file 2> /dev/null
    dos2unix -q -o $ag_file

    for afgr in `cat $ag_file | grep -i -E "[Aa][Gg]_" | awk '{print $2}'`
    do

        echo "show affinity-groups -ag-name $afgr" | ssh -i $ID_PUB -T $USER@$ip 2> /dev/null | grep -i -E "^[ ]{1,}[0-9]{1,} " > $ag_list
        
        myhost=`get_hostname $afgr`
        while read vol
        do
            line="$myhost;`echo $vol | sed s/" "/';'/g`"
            echo $line >> $masking_f
        done < $ag_list
        
    done

    rm -f $ag_file
    rm -f $ag_list
    return 0
}


get_raid_groups (){

    ip=$1
    raid_f=$2

    echo $RAID_HEADER > $raid_f

    echo "show raid-groups" | ssh -i $ID_PUB -T $USER@$ip 2> /dev/null | grep -i -E "^[ ]{1,}[0-9]{1,} " | sed 's/[ ]\{1,\}/;/g' | sed 's/^;//g' >> $raid_f
}


get_volumes (){

    ip=$1
    volumes_f=$2

    echo $VOLUME_HEADER > $volumes_f

    echo "show volumes -mode detail" | ssh -i $ID_PUB -T $USER@$ip 2> /dev/null | grep -i -E "^[ ]{1,}[0-9]{1,} " | sed 's/[ ]\{1,\}/;/g' | sed 's/^;//g' \
| awk -F ';' '{print $1";"$2";"$3";"$4";"$8";"$9";"$12";"$17}' >> $volumes_f
}


log_init (){

    mylog=$1

    tput setaf [1-7]
    if ! `test -w $mylog`
    then
        > $mylog
    fi
    return 0
}


log_input (){

    color=$1
    eol=$2
    mylog=$3
    message=$4


    if `test $eol = 'yes'`
    then
        echo $message >> $mylog
        echo "$(tput setaf $color) $message"
        return 1
    else if `test $eol = 'no'`
    then
        echo -n $message >> $mylog
        echo -n "$(tput setaf $color) $message"
        return 1
    fi
    fi
    return 0
}


######## MAIN

#MAIN

    if ! check_parameters $1
    then

        log_init $LOG
      
        initialize_csv_files
        array_ip=`get_array $1`
        
        log_input $MAGENTA 'yes' $LOG "========== Collecting Fujitsu Eternus report from $1 =========="

        log_input $WHITE 'no' $mylog 'Retrieving hosts information................'
        get_hosts $array_ip $DX_HOSTS_CSV
        log_input $GREEN 'yes' $mylog 'DONE'

        log_input $WHITE 'no' $mylog 'Retrieving affinity groups information......'
        get_affinity_groups $array_ip $DX_MASKING_CSV
        log_input $GREEN 'yes' $mylog 'DONE'

        log_input $WHITE 'no' $mylog 'Retrieving raid groups information..........'
        get_raid_groups $array_ip $DX_RAIDGRP_CSV
        log_input $GREEN 'yes' $mylog 'DONE'

        log_input $WHITE 'no' $mylog 'Retrieving volumes information..............'
        get_volumes $array_ip $DX_VOLUMES_CSV
        log_input $GREEN 'yes' $mylog 'DONE'

    fi
