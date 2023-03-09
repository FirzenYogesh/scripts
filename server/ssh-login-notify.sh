#!/usr/bin/env bash

# add this like to /etc/pam.d/sshd
# session optional pam_exec.so seteuid /path/to/ssh-login-notify.sh
# check if UsePAM=yes in sshd_config

APP_ROOT="$(dirname "$(readlink -fm "$0")")"

source "${APP_ROOT}/.ssh-login-notify.env"


if [[ "${PAM_TYPE}" != "close_session" ]]; then
    host="`hostname`"
    subject="SSH Login: ${PAM_USER} from ${PAM_RHOST} on ${host}"
    # Message to send, e.g. the current environment variables.
    envs=(`echo "$(env)" | tr '\n' ' '`)
    message=""
    for i in "${envs[@]}"; do
	message+="${i}<br>"
    done
    html="<h3>${subject}</h3><code>${message}</code>"
    text="${subject}"

    # Hookshot webhook
    if [[ ! -z "${SSH_NOTIFY_HOOKSHOT_URL}" ]]; then
        curl -L -X POST "${SSH_NOTIFY_HOOKSHOT_URL}" \
        -H 'Content-Type: application/json' \
        --data-raw '{
            "text": "'"${text}"'",
            "html": "'"${html}"'"
        }'
    fi
fi
