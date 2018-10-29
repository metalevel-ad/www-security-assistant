#!/bin/bash

# Name:    www-security-assistant.bash
# Summary: This is the main script of the the project of the same name.
#          It is designed to help you with malicious IP addresses handling.
#          The IPs should be provided by external programs such as ModSecurity or ModEvasive for Apache2, etc.
# Home:    https://github.com/pa4080/www-security-assistant
# Author:  Spas Z. Spasov <spas.z.spasov@gmail.com> (C) 2018
#
# This program is free software; you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; See the GNU General Public License for more details.
#
# Positional parameters
# $1 = $IP             - The IP address object of the thread
# $2 = $AGENT          - Agent or Mode
# $3 = $NOTES          - Log notes of the thread
# $4 = $MODSEC_RULE_ID - ModSecurity's disruptive Rule ID, cause of the thread
#
# Automatic Mode: Available Agents, call syntax
# 	wwwsas <IP> < ModSecurity ["$NOTES"] | FloodDetector ["$NOTES"] | ModEvasive | Guardian | a2Analyst >
#
# Manual Mode: Pseudo Agents, call syntax
#	wwwsas <IP> < --DROP ["$NOTES"] | --CLEAR ["$NOTES"] | --ACCEPT ["$NOTES"] | --ACCEPT-CHAIN ["$NOTES"] >


# ---------------------------------
# Input data and requirements check
# ---------------------------------

# The script should be run as root
[[ "$EUID" -ne 0 ]] && { echo "Please run as root (use sudo)."; exit 0; }

# Check the dependencies
[[ -x /usr/bin/at ]] || { echo "Please, install 'at'"; exit 0; }
[[ -x /usr/bin/tee ]] || { echo "Please, install 'tee'"; exit 0; }
[[ -x /usr/bin/awk ]] || { echo "Please, install 'awk'"; exit 0; }
[[ -x /usr/bin/who ]] || { echo "Please, install 'who'"; exit 0; }
[[ -x /usr/bin/mail ]] || { echo "Please, install 'mail' command"; exit 0; }
[[ -x /sbin/iptables ]] || { echo "Please, install 'iptables'"; exit 0; }

# Check the input data
[[ -z ${1+x} ]] || [[ -z ${2+x} ]] && (echo "$USAGE"; echo; exit 0)


# -------------------------
# Environment setup section
# -------------------------

# The directory where the script is located - see the 'default' note in the beginning.
WORK_DIR="/etc/www-security-assistant"
CONF_FILE="${WORK_DIR}/www-security-assistant.conf"

# Asign the input data to certain variables
IP="${1}"
AGENT="${2}"
NOTES="${3}"
MODSEC_RULE_ID="${4}"

# Get the $USER that execute the script
RUN_USER="$(who -m | awk '{print $1}')"
if [[ -z ${RUN_USER} ]]; then RUN_USER="${SUDO_USER:-${USER}}"; fi
if [[ -z ${RUN_USER} ]]; then RUN_USER="$USER"; fi
if [[ -z ${RUN_USER} ]]; then RUN_USER="root"; fi

# Load/source the configuration file
if [[ -f $CONF_FILE ]]
then
    source "${CONF_FILE}"
else
    echo "Please use \"${CONF_FILE}.example\" and create your own \"${CONF_FILE}\""
    exit 0
fi

# Clear the Error log
>"$WWW_SAS_ERROR_LOG"

# Output a header for the log file
printf "\n\n*****\nSECURITY LOG from %s on %s : %s : %s : %s\n\n" "$TIME" "$DATE" "${WWW_SAS_FULL}.bash" "$AGENT" "$IP"


# --------------
# Action section
# --------------

# If the $IP is a member of the $WWW_SAS_WHITE_LIST (grep -q "$IP" "$WWW_SAS_WHITE_LIST" - doesn't work)
if [[ ! -z $(grep -o "$IP" "$WWW_SAS_WHITE_LIST") ]] && [[ " ${AGENTS[@]} " == *" ${AGENT} "* ]]
then
    # Output a message and exit
    printf 'The IP address %s is a member of our Whitelist!\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='TYPE_1'

elif [[ ! -z $(grep -o "$IP" "$WWW_SAS_WHITE_LIST") ]] && [[ ! " ${AGENTS[@]} " == *" ${AGENT} "* ]]
then
    # Output a message and exit
    printf 'The IP address %s is a member of out withelist!\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='DO_NOT_SEND'

# Remove $IP from the DROP (BAN) List, syntax: www-security-assistant.bash <IP> --CLEAR 'log notes'"
elif [[ $AGENT == "--CLEAR" ]]
then
    /sbin/iptables -L "$WWW_SAS_IPTBL_CHAIN" -n --line-numbers; echo
    sed -i "/$IP/d" "$WWW_SAS_HISTORY"
    sed -i "/$IP/d" "$WWW_SAS_BAN_LIST"
    echo "Attemt to remove the rule from the $WWW_SAS_IPTBL_CHAIN chain:"
    /sbin/iptables -C "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP && /sbin/iptables -D "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP && echo "The rule has been removed from the chain $WWW_SAS_IPTBL_CHAIN!"
    eval "$WWW_SAS_IPTABLES_SAVE"; echo
    /sbin/iptables -L "$WWW_SAS_IPTBL_CHAIN" -n --line-numbers; echo
    # Output and Log a message and exit
    printf 'On %-10s at %-8s | This IP/CIDR was removed from the Banlist by @%s: %-18s \t| Notes: %s\n' "$DATE" "$TIME" "$RUN_USER" "$IP" "$NOTES" | tee -a "$WWW_SAS_BAN_CLEAR_LIST"
    exit 0

# If there is a DROP rule for the $IP, and if the IP is a member of the $WWW_SAS_BAN_LIST, output a message and exit
elif [[ ! -z ${@+x} ]] && grep -q "^DROP.*$IP" <(/sbin/iptables -L -n -w)
then
    if [[ ! -z $(grep -o "$IP" "$WWW_SAS_BAN_LIST") ]] && grep -q "^DROP.*$IP" <(/sbin/iptables -L -n -w)
    then
	printf 'The IP address %s is already added to the Banlist, also there is a Iptables rule!\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='DO_NOT_SEND'
    elif grep -q "^DROP.*$IP" <(/sbin/iptables -L -n -w)
    then
        printf 'Iptables DROP rule for %s already exists. The agent should wait for a while.\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='DO_NOT_SEND'
    else
        printf 'Something is wrong! The processing of %s does not went correctly!\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='TYPE_1'
    fi

# Add $IP to the DROP (BAN) List, syntax: www-security-assistant.bash <IP> --DROP 'log notes'"
elif [[ $AGENT == "--DROP" ]]
then
    /sbin/iptables -A "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP
    /sbin/iptables -L "$WWW_SAS_IPTBL_CHAIN" -w -n --line-numbers
    eval "$WWW_SAS_IPTABLES_SAVE"
    # Output and Log a message and exit
    printf 'On %-10s at %-8s | This IP/CIDR was added to the Banlist by @%s: %-18s \t| Notes: %s\n' "$DATE" "$TIME" "$RUN_USER" "$IP" "$NOTES" | tee -a "$WWW_SAS_BAN_LIST"

    if [[ ! -z $AbuseIPDB_APIKEY ]]
    then
        printf "To report the IP address to AbuseIPDB use this command:\n\n\t%s %s 'push-ip-data-html' '21,15' 'Comment'\n\n" "$WWW_SAS_ABUSEIPDB" "$IP"
        printf "Where '21,15' are categories from https://www.abuseipdb.com/categories\n"
        printf "Use the following command to see the full list:\n\n\t%s - 'categories'\n\n" "$WWW_SAS_ABUSEIPDB"
    fi

    exit 0

# Add $IP to the ACCEPT (WHITE) List, syntax: www-security-assistant.bash <IP> --ACCEPT 'log notes'"
elif [[ $AGENT == "--ACCEPT" ]]
then
    # Output and Log a message and exit
    printf 'On %-10s at %-8s | This IP/CIDR was added to the ACCEPT (WHITE) List by @%s: %-18s \t| Notes: %s\n' "$DATE" "$TIME" "$RUN_USER" "$IP" "$NOTES" | tee -a "$WWW_SAS_WHITE_LIST"
    printf 'A rule has benn added to our Whitelist - %s \nFor ModSecurity and ModEvasi you should do it on yourself.\n' "$WWW_SAS_WHITE_LIST"
    exit 0

# Add $IP to the ACCEPT (WHITE) List and add Iptables rule, syntax: www-security-assistant.bash <IP> --ACCEPT-CHAIN 'log notes'"
elif [[ "$AGENT" == "--ACCEPT-CHAIN" ]]
then
    /sbin/iptables -A "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j ACCEPT
    /sbin/iptables -L "$WWW_SAS_IPTBL_CHAIN" -w -n --line-numbers
    eval "$WWW_SAS_IPTABLES_SAVE"
    # Output and Log a message and exit
    NOTE='Iptables rule has been created!'
    printf 'On %-10s at %-8s | This IP/CIDR was added to the ACCEPT (WHITE) List by @%s: %-18s \t| Notes: %s %s\n' "$DATE" "$TIME" "$RUN_USER" "$IP" "$NOTES" "$NOTE" | tee -a "$WWW_SAS_WHITE_LIST"
    printf 'A rule has benn added to our Whitelist - %s \nAlso Iptables rule has been added.\nFor ModSecurity and ModEvasi you should do it on yourself.\n' "$WWW_SAS_WHITE_LIST"
    exit 0

# If the $AGENT belogs to the list of $AGENTS
elif [[ " ${AGENTS[@]} " == *" ${AGENT} "* ]]
then
    # Check for errors
    if [[ ! -z $(grep -o "$IP" "$WWW_SAS_BAN_LIST") ]]
    then
	printf 'The IP address %s belongs to our Banlist, but there is not Iptables rule!\n\n' "$IP" | tee -a "$WWW_SAS_ERROR_LOG" && MAIL_FLAG='TYPE_2'
    fi

    # Get the number of the previous transgressions from this $IP and increment +1 to get the current number;
    # Note '$(grep -c $IP $WWW_SAS_HISTORY)' sometimes works sometime doesn`t work '!!!'
    IP_SINS=$(awk '{print $8}' "$WWW_SAS_HISTORY" | grep "$IP" | wc -l)
    IP_SINS=$((IP_SINS+1))

    if [[ ! -z $AbuseIPDB_APIKEY ]] && [[ $AbuseIPDB_ANALYSE_IP_AND_BAN == 'YES' ]] && [[ "$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'analyse-ip')" == 'Bad Guy' ]]
    then
        # Add $IP to the Black List add Iptales rule. Please note that
        # The $NOTES are not logged here, this will be done within the following section: Log the current thread
        /sbin/iptables -A "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP

        eval "$WWW_SAS_IPTABLES_SAVE"

        if [[ -z $(grep -o "$IP" "$WWW_SAS_BAN_LIST") ]]
        then
            printf 'On %-10s at %-8s | This IP was added to the Banist by @%s: %-18s\t Due to an analyse, providedd by @%s\n' "$DATE" "$TIME" "$AGENT" "$IP" "$WWW_SAS_ABUSEIPDB_FULL" | tee -a "$WWW_SAS_BAN_LIST"
        fi

        ACTION_SPECIFFIC_MESSAGE="$(printf 'Due to an analyse, provided by @%s, they <i>was added to the Banlist</i> on %s at %s!' "$WWW_SAS_ABUSEIPDB_FULL" "$DATE" "$TIME")"
        AbuseIPDB_REPORT='YES'
    elif [[ ! "$IP_SINS" -ge "$LIMIT" ]]
    then
        # Add the following firewall rule (block IP); alt.: `iptables -I INPUT -p tcp --dport 80 -s %s -j DROP`
        /sbin/iptables -I "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP
        # Unblock offending IP after $BAN_TIME through the `at` command
        echo "/sbin/iptables -D $WWW_SAS_IPTBL_CHAIN -w -s \"$IP\" -j DROP && $WWW_SAS_IPTABLES_SAVE" | at now + "$BAN_TIME"

        ACTION_SPECIFFIC_MESSAGE="$(printf 'The system has blocked the IP by the firewall for %s as from %s on %s.' "$BAN_TIME" "$TIME" "$DATE")"
    else
        # Add $IP to the Black List add Iptales rule. Please note that
        # The $NOTES are not logged here, this will be done within the following section: Log the current thread
        /sbin/iptables -A "$WWW_SAS_IPTBL_CHAIN" -w -s "$IP" -j DROP

        eval "$WWW_SAS_IPTABLES_SAVE"

        if [[ -z $(grep -o "$IP" "$WWW_SAS_BAN_LIST") ]]
        then
            printf 'On %-10s at %-8s | This IP was added to the Banist by @%s: %-18s\n' "$DATE" "$TIME" "$AGENT" "$IP" | tee -a "$WWW_SAS_BAN_LIST"
        fi

        ACTION_SPECIFFIC_MESSAGE="$(printf 'They reached our limit of tolerance and <i>was added to the Banlist</i> on %s at %s!' "$DATE" "$TIME")"

        if [[ ! -z $AbuseIPDB_APIKEY ]]
        then
            AbuseIPDB_REPORT='YES'
        fi
    fi

    # Remove ModEvasive lock file
    if [[ $AGENT == 'ModEvasive' ]]; then printf 'rm -f %s' "$MOD_EVASIVE_LOG_DIR/dos-$IP" | at now + "$BAN_TIME"; fi

# For all other cases
else
    echo "Something went wrong!"; echo; echo "$USAGE"; echo;
    exit 0
fi

# Log the current thread into the $WWW_SAS_HISTORY file
printf 'On %-10s at %-8s | %-12s : %-18s | Notes: %s\n' "$DATE" "$TIME" "$AGENT" "$IP" "$NOTES_LOCAL" | tee -a "$WWW_SAS_HISTORY"


# ---------------------
# AbuseIPDB Integration
# ---------------------

# Compose reference links for the $IP. Note here is applied the integration with www.abuseipdb.com. If you want to use this feature, you should provide correct value for $AbuseIPDB_APIKEY.

if [[ ! -z $AbuseIPDB_APIKEY ]]
then

    if   [[ " ${AbuseIPDB_AGGRESSIVE_MODE_RULES[@]} " == *" ${MODSEC_RULE_ID} "* ]] && [[ $AGENT == "$AGENT_MODSEC" ]]
    then
        AbuseIPDB_REPORT="$(echo -n "Aggressive mode (RuleId $MODSEC_RULE_ID): "; eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'push-ip-data-html' "'21'" "'Detected by $AGENT_MODSEC'")"
    elif [[ $AbuseIPDB_REPORT == 'YES' ]] && [[ $AGENT == "$AGENT_MODSEC" ]]
    then
        AbuseIPDB_REPORT="$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" "'push-ip-data-html'" "'21,15'" "'Detected by $AGENT_MODSEC'")"
    elif [[ $AbuseIPDB_REPORT == 'YES' ]] && [[ $AGENT == "$AGENT_FLOODT" ]]
    then
        AbuseIPDB_REPORT="$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'push-ip-data-html' "'4,6'" "'Detected by $AGENT_FLOODT'")"
    elif [[ $AbuseIPDB_REPORT == 'YES' ]] && [[ $AGENT == "$AGENT_MODEVS" ]]
    then
        AbuseIPDB_REPORT="$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'push-ip-data-html' "'4'" "'Detected by $AGENT_MODEVS'")"
    elif [[ $AbuseIPDB_REPORT == 'YES' ]] && [[ $AGENT == "$AGENT_GUARDI" ]]
    then
        AbuseIPDB_REPORT="$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'push-ip-data-html' "'4'" "'Detected by $AGENT_GUARDI'")"
    elif [[ $AbuseIPDB_REPORT == 'YES' ]] && [[ $AGENT == "$AGENT_A2ANLS" ]]
    then
        AbuseIPDB_REPORT="$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'push-ip-data-html' "'4'" "'Detected by $AGENT_A2ANLS'")"
    else
        AbuseIPDB_REPORT="The IP address $IP is not reported to AbuseIPDB."
    fi

else
    echo 'The integration with AbuseIPDB is not enabled. The API Key is not provided.'
fi


# -----------------------------------
# Email construction and send section
# -----------------------------------

# By the $MAIL_FLAG we manage the email processing
# 'DO_NOT_SEND' - will interrupt the execution of the script at this point - so an email will not be sent
# 'TYPE_1'      - will interrupt the email compose at the middle - so only short whitelisting instructions will be added
# 'TYPE_2'      - will output the error message in the middle of the email body - so full whitelisting instructions will be added
if [[ $MAIL_FLAG == 'DO_NOT_SEND' ]]; then exit 0; fi

# If the destination email is not set, we do not need to process the rest part
if [[ -z "$EMAIL_TO" ]] && [[ -z "$EMAIL_TO_PLAIN" ]]; then exit 0; fi

# Prepare the notes that comes from modsecurity-assistant.bash and flood-detector.bash
# The custom divider is used to dicourage some bugs when the note comes from ModSecurity
NOTES_LOCAL="$(echo "$NOTES" | sed "s/$MY_DIVIDER/; /g")"
NOTES_EMAIL="$(echo "$NOTES" | sed "s/$MY_DIVIDER/\n/g")"

# E-MAIL construction section
{

printf '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">\n<html>\n<head>\n<title>Security Assistant on %s</title>\n' "${HOSTNAME^^}"
printf '<style>\n'
cat "$WWW_SAS_MAIL_STYLE_CSS"
printf '</style>\n'
printf '\n</head>\n<body style="font-family: monospace; max-width: 720px;">\n'
printf '\n<h3 style="color: #000000;"><a href="%s" style="text-decoration: none;color: #000000;">%s</a> %s</h3>\n' "${HOSTNAME^^}" "${HOSTNAME^^}" "$AGENT"

if [[ $AGENT == "$AGENT_MODSEC" ]]
then

    IP_REFERENCE="<a href=\"$IP\">$IP</a> | <a href=\"www.abuseipdb.com/check/$IP\">AbuseIPDB</a> | <a href=\"geoipinfo.org/?ip=$IP\">GeoIPInfo</a>"
    printf '\n<p style="margin-bottom: 5px;">New transgression has been detected. <br>Source: %s</p>\n' "$IP_REFERENCE"
    # Add <a href=..> to `Our server`
    NOTES_EMAIL="$(echo "$NOTES_EMAIL" | sed -r 's/^(Our Server: )(.*)$/\1<a href="\2">\2<\/a>/')"

    # Extract the value of the UNIQUE_ID used several tiles below
    UNIQUE_ID="$(echo "$NOTES_EMAIL" | sed -r -n 's/^Unique ID: (.*)$/\1/p')"

    printf "\n<pre class=\"info\">\n%b\n</pre>\n" "${NOTES_EMAIL}"

    if [[ $REPORT_MODE_MODSEC = 'verbose' ]]
    then
        printf "\n<pre class=\"info small\">\n%b\n</pre>\n" "$(eval "$WWW_SAS_MOD_SECURITY_WLRG_EXEC" 'active-rules' 'unique-id' "$UNIQUE_ID")" # | sed -r 's/^\/([0-9]+.*)$/\1/'
    fi

elif [[ $AGENT == "$AGENT_FLOODT" ]]
then

    printf '\n<p style="margin-bottom: 5px;">New flood attack has been detected. <br>Source: %s</p>\n' "$IP_REFERENCE"
    printf "\n<pre class=\"info\">\n%b\n</pre>\n" "${NOTES_EMAIL}"

else # The other agents are DDoS detectors at all

    printf '\n<p>Massive connections has been detected. <br>Source: %s</p>\n' "$IP_REFERENCE"

fi

if [[ $REPORT_MODE_ABIPDB = 'verbose' ]] && [[ ! -z $AbuseIPDB_APIKEY ]]
then
    printf "\n<pre class=\"info small\">\n%b\n</pre>\n" "$(eval "$WWW_SAS_ABUSEIPDB_EXEC" "$IP" 'pull-ip-data-html')" 
fi

if [[ $MAIL_FLAG == 'TYPE_1' ]]
then

    printf '\n<p><strong>%s</strong></p>' "$(cat "$WWW_SAS_ERROR_LOG")"

    if [[ $AGENT == "$AGENT_MODSEC" ]]
    then

        printf "\n<p class=\"green\">To whitelist similar actions within ModSecurity execute:</p>"
        printf "\n<pre class=\"green\">\nsudo %s '999999' 'unique-id' '%s'\n</pre>\n" "$WWW_SAS_MOD_SECURITY_WLRG" "$UNIQUE_ID"

    fi

else

    if [[ $MAIL_FLAG == 'TYPE_2' ]]
    then

        printf '\n<p><strong>%s</strong></p>' "$(cat "$WWW_SAS_ERROR_LOG")"
    fi

    printf '\n<p style="color: #000000 !important;">\nThe current number of the transgressions commited by <strong>%s</strong> is <strong>%s</strong> / %s. ' "$IP" "$IP_SINS" "$LIMIT"
    printf '\n%s %s\n</p>\n' "$ACTION_SPECIFFIC_MESSAGE" "$AbuseIPDB_REPORT"

    if [[ $IP_SINS -gt $LIMIT ]]
    then

        printf '\n<p><strong>Please check why the curent transgressions from %s are greater than the limit!</strong></p>\n' "$IP"

    fi

    printf "\n<p class=\"red\">To allow access of this IP address from the command line, use one of the following commands:</p>"
    printf "\n<pre class=\"red\">\nsudo iptables -D $WWW_SAS_IPTBL_CHAIN -s %s -j DROP\nsudo %s %s --CLEAR 'notes'\n</pre>\n" "$IP" "$WWW_SAS" "$IP"
    printf "\n<p class=\"grey\">To add this IP address to our Whitelist execute:</p>"
    printf "\n<pre class=\"grey\">\nsudo %s %s --ACCEPT 'notes'\nsudo %s %s --ACCEPT-CHAIN 'notes'</pre>\n" "$WWW_SAS" "$IP" "$WWW_SAS" "$IP"

    if [[ $AGENT == "$AGENT_MODSEC" ]]
    then

        printf "\n<p class=\"green\">To whitelist similar actions within ModSecurity execute:</p>"
        printf "\n<pre class=\"green\">\nsudo %s '999999' 'unique-id' '%s'\n</pre>\n" "$WWW_SAS_MOD_SECURITY_WLRG" "$UNIQUE_ID"
        printf "\n<p class=\"blue\">To perform the booth (1) whitelist similar actions and (2) allow access to this IP address execute:</p>"
        printf "\n<pre class=\"blue\">\nsudo %s %s --CLEAR 'notes' && \\ \nsudo %s '999999' 'unique-id' '%s'\n</pre>\n" "$WWW_SAS" "$IP" "$WWW_SAS_MOD_SECURITY_WLRG" "$UNIQUE_ID"

    fi

fi

printf '\n</body>\n</html>'

} > "$EMAIL_BODY"


# Email send section
if [[ ! -z "$EMAIL_TO" ]]
then
    mail -r "$EMAIL_FROM" -s "Attack Detected on ${HOSTNAME^^}" "$EMAIL_TO" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" < "$EMAIL_BODY"
    # Add clarification to the copy of the last sent email
    printf '\n***\n This email has been sent to %s at %s\n\n' "$EMAIL_TO" "$TIME" >> "$EMAIL_BODY"
fi

if [[ ! -z "$EMAIL_TO_PLAIN" ]]
then
    sed '/<style>/,/<\/style>/d' "$EMAIL_BODY" | sed 's/<[^>]*>//g' | sed '/^$/N;/^\n$/D' > "$EMAIL_BODY_PLAIN"
    mail -r "$EMAIL_FROM" -s "Attack Detected on ${HOSTNAME^^}" "$EMAIL_TO_PLAIN" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" < "$EMAIL_BODY_PLAIN"
    # Add clarification to the copy of the last sent email
    printf '\n***\n This email has been sent to %s at %s\n\n' "$EMAIL_TO_PLAIN" "$TIME" >> "$EMAIL_BODY_PLAIN"
fi

exit 0