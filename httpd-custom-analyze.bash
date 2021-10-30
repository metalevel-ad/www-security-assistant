#!/bin/bash

# Name:    httpd-custom-analyze.bash
# Summary: Eexample port between Apache's logging mechanism and WWW Security Assistant.
#          It is designed to analyze Apache's web server requests
#	   through the piped logging mechanism (especially of modsec_guardian.log).
# Home:    https://github.com/metalevel-ad/www-security-assistant
# Author:  Spas Z. Spasov <spas.z.spasov@gmail.com> (C) 2018
#
# This program is free software; you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; See the GNU General Public License for more details.


# -------------------------
# Environment setup section
# -------------------------

# The directory where the script is located - see the 'default' note in the beginning.
WORK_DIR="/etc/www-security-assistant"
CONF_FILE="${WORK_DIR}/www-security-assistant.conf"

# Load/source the configuration file
if [[ -f "$CONF_FILE" ]]
then
    source "$CONF_FILE"
else
    echo "Please use \"${CONF_FILE}.example\" and create your own \"${CONF_FILE}\""
    exit 0
fi

APACHE_MOD_SECURITY_LOG="${MOD_SECURITY_LOG_DIR}/modsec_guardian.a2Analyst.log"                 # Create also regular Apache Log

CACHE_DIR="${WWW_SAS_TMP}/httpd-custom-analyze-cache"
[[ ! -d "${CACHE_DIR}" ]] && mkdir -p "${CACHE_DIR}"


# --------------
# Script begin
# --------------

sCACHE="${CACHE_DIR}/short.cache"                                                               # SHORT term CACHE file name
lCACHE="${CACHE_DIR}/long.cache"                                                                # LONG term CACHE file name
hCACHE="${CACHE_DIR}/history.cache"                                                             # HISTORY CACHE file name
VISITORS="${WORK_DIR}/httpd-custom-analyze.visitors.history"                                    # Log each unique visitor's IP address

sAGE="1"                                                                                        # Max age of the SHORT term CACHE file - minutes
lAGE="5"                                                                                        # Max age of the LONG term CACHE file - minutes
hAGE="30"                                                                                       # Max age of the HISTORY CACHE file - minutes

sMaxCOUNT="360"                                                                                 # Max number of IP coincidences in the SHORT CACHE
lMaxCOUNT="720"                                                                                 # Max number of IP coincidences in the LONG CACHE
hMaxCOUNT="3078"                                                                                # Max number of IP coincidences in the HISTORY CACHE

PATTERN='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'                                        # Rough IPv4 match pattern

while read -r LOGLINE; do                                                                       # While there is input data; do the script

        echo -e "${LOGLINE}" >> "${APACHE_MOD_SECURITY_LOG}"                                    # Write regular log file
        #(exec echo -e "${LOGLINE}" |/etc/www-security-assistant/httpd-guardian.pl)             # Feed HTTPD-Guardian with log data
        AUDIT="$(echo -e "${LOGLINE}" | grep -wEo "$PATTERN" | sed '/^\s*$/d' | sort | uniq)"   # Get unique IPs from the current $LOGLINE feed

        for IP in $AUDIT; do                                                                    # For every $IP from the current log entry

                touch "$VISITORS"                                                               # Create list of unique IPs visited the server
                if [ "$(grep "$IP" "$VISITORS")" == "" ]; then
                        echo "${IP}" >> "${VISITORS}"
                fi


                if [ "$(grep "$IP" "$WWW_SAS_WHITE_LIST")" == "" ]; then

                        if [ -f "$hCACHE" ]; then find "$hCACHE" -mmin "+${hAGE}" -delete; fi   # Delete HISTORY CACHE file if it is older than $hAGE: -mtime +1 :one day; for seconds see: https://stackoverflow.com/a/24909473/6543935
                        if [ ! -f "$hCACHE" ]; then touch "$hCACHE"; fi                         # Create HISTORY CACHE file if it doesn't exist

                        OrDATE="$(stat -c %Y "$hCACHE")"                                        # Get the origin date of the file
                        echo "${IP}" >> "${hCACHE}"                                             # Feed HISTORY CACHE file
                        touch -d "@$OrDATE" "${hCACHE}"                                         # Set the origin date back

                        if [ -f "$sCACHE" ]; then find "$sCACHE" -mmin "+${sAGE}" -delete; fi   # Delete SHORT CACHE file if it is older than $sAGE
                        if [ ! -f "$sCACHE" ]; then touch "$sCACHE"; fi                         # Create SHORT CACHE file if it doesn't exist

                        OrDATE="$(stat -c %Y "$sCACHE")"                                        # Get the origin date of the file
                        echo "${IP}" >> "${sCACHE}"                                             # Feed SHORT CACHE
                        touch -d "@$OrDATE" "${sCACHE}"                                         # Set the origin date back

                        if [ -f "$lCACHE" ]; then find "$lCACHE" -mmin "+${lAGE}" -delete; fi   # Delete LONG CACHE file if it is older than $lAGE
                        if [ ! -f "$lCACHE" ]; then touch "$lCACHE"; fi                         # Create LONG CACHE file if it doesn't exist

                        OrDATE="$(stat -c %Y "$lCACHE")"                                        # Get the origin date of the file
                        echo "${IP}" >>  "${lCACHE}"                                            # Feed LONG CACHE
                        touch -d "@$OrDATE" "${lCACHE}"                                         # Set the origin date back

                        sCOUNT="$(grep -c "$IP" "${sCACHE}")"                                   # Current number of IP coincidences in the SHORT CACHE
                        lCOUNT="$(grep -c "$IP" "${lCACHE}")"                                   # Current number of IP coincidences in the LONG CACHE
                        hCOUNT="$(grep -c "$IP" "${hCACHE}")"                                   # Current number of IP coincidences in the HISTORY CACHE

                        # If, for certain $IP, there are more than $sMaxCOUNT connections per last 1 minute ($sAGE) or $lMaxCOUNT connections per last 5 minutes ($lAGE)
                        # or $hMaxCOUNT connections per last half hour ($hAGE); then
                        if [ "$sCOUNT" -ge "$sMaxCOUNT" ] || [ "$lCOUNT" -ge "$lMaxCOUNT" ] || [ "$hCOUNT" -ge "$hMaxCOUNT" ]; then

                                # If there is not Iptables DROP Rule for this IP then produce one
                                if ! grep -woq "^DROP.*$IP" <(/sbin/iptables -L "$WWW_SAS_IPTBL_CHAIN" -n -w)
                                then
                                        ## ACTION RULES: call external script - Call WWW Security Assistant Script
                                        ( exec sudo "$WWW_SAS_EXEC" "$IP" "$AGENT_A2ANLS" 'AutoMode' >> "$WWW_SAS_EXEC_LOG" 2>&1 )

                                fi
                        fi
                fi
        done
done

# References:
# Get file date: http://www.linuxquestions.org/questions/programming-9/get-file-modification-date-time-in-bash-script-163731/
# Set file date: https://www.mkssoftware.com/docs/man1/touch.1.asp
# 'stat' time stamp to 'touch': https://unix.stackexchange.com/questions/36763/using-stat-to-provide-timestamp-for-touch
# https://superuser.com/questions/202818/what-regular-expression-can-i-use-to-match-an-ip-address
