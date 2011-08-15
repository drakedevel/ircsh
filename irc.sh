#!/bin/bash
# -*- indent-tabs-mode: nil -*-
shopt -s extglob

declare gToServer
declare gFromServer

if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "Usage: $0 <config.sh>" >&2
    exit 1
fi

# This just fires off a netcat and sets appropriate globals with the file
# descriptors for the coprocess. If the bash you use supports /dev/tcp, you
# could replace this with a bidirectional redirection to
# /dev/tcp/${pServer:?}/${pPort:?}.
function connect() {
    coproc nc "${pServer:?}" "${pPort:?}"
    gToServer="${COPROC[1]}"
    gFromServer="${COPROC[0]}"
}

# This sends a command to the server. The final argument is permitted to
# have whitespace, and will be prefixed with a : appropriately in-protocol.
function sendToServer() {
    local line="$1"
    shift
    while [[ $# -gt 1 ]]; do
        line+=" $1"
        shift
    done
    line+=" :$1\r\n"
    echo -en "$line" >&$gToServer
} 2>/dev/null

# Takes a raw line as read from the server and breaks it apart into the pieces
# of the prefix, the command, and its arguments. The second argument is the
# callback to call with the bits of the message as arguments.
function decode() {
    local line="$1"
    local callback="$2"

    local nick
    local user
    local host
    local -a body
    local -i bodyidx=0

    local char
    local innick
    local inuser
    local inhost
    local inspace=true
    local inlast

    if [[ "${line::1}" == ':' ]]; then
        innick=true
        line="${line:1}"
    fi

    while [[ ${#line} -ne 0 ]]; do
        char="${line::1}"
        line="${line:1}"
        [[ "$char" == $'\r' ]] && break
        if [[ $innick ]]; then
            if [[ "$char" == '!' ]]; then
                innick=
                inuser=true
            elif [[ "$char" == '@' ]]; then
                innick=
                inhost=true
            elif [[ "$char" == ' ' ]]; then
                innick=
            else
                nick+="$char"
            fi
        elif [[ $inuser ]]; then
            if [[ "$char" == '@' ]]; then
                inuser=
                inhost=true
            elif [[ "$char" == ' ' ]]; then
                inuser=
            else
                user+="$char"
            fi
        elif [[ $inhost ]]; then
            if [[ "$char" == ' ' ]]; then
                inhost=
            else
                host+="$char"
            fi
        elif [[ $inspace ]]; then
            if [[ "$char" == ':' ]]; then
                inspace=
                inlast=true
            elif [[ "$char" != ' ' ]]; then
                inspace=
                body[bodyidx]+="$char"
            fi
        elif [[ $inlast ]]; then
            body[bodyidx]+="$char"
        else
            if [[ "$char" == ' ' ]]; then
                inspace=true
                bodyidx+=1
            else
                body[bodyidx]+="$char"
            fi
        fi
    done
    [[ $innick || $inuser || $inhost ]] && return 1

    $callback "$nick" "$user" "$host" "${body[@]}"
}

# Read a line from the server, decode it, and call the given callback with the
# bits of the incoming message.
function readFromServer() {
    local callback="$1"

    local lineraw
    read -u $gFromServer lineraw || return $?
    decode "$lineraw" "$1"
} 2>/dev/null

# A default on-connect script that should be sufficient for most bot needs,
# it requests an identify-msg capability to allow easy NickServ authentication
# and sends along the configured user, nickname, and realname.
function onConnect() {
    [[ -n "$pPassword" ]] && sendToServer PASS "$pPassword"
    sendToServer CAP LS
    sendToServer CAP REQ identify-msg
    sendToServer USER "${pUser:?}" 0 "*" "${pRealname:?}"
    sendToServer NICK "${pNick:?}"
    sendToServer CAP END
}

# Called after connected and registered to join channels or do whatever other
# initialization one may wish to do.
function onStartup() {
    return 0
}

# Called whenever a message comes in. By default, figures out what command
# or status code came in and calls the appropriate onCOMMAND callback if
# present, or onUnknown otherwise.
function onMessage() {
    [[ $# -lt 4 ]] && return
    local command="$4"
    [[ "$command" != "${command##!(+([A-Z0-9]))}" ]] && return

    local callback="on$command"
    local callbackType="$(type -t "$callback")"
    if [[ "$callbackType" != "function" ]]; then
        onUnknown "$@"
    else
        "$callback" "$@"
    fi
}

# Called whenever onMessage encounters an unknown/unhandled message. By
# default, just prints out some useful spew to the terminal.
function onUnknown() {
    local nick="$1"
    shift 3

    if [[ $nick ]]; then
        echo -n "$nick>"
    else
        echo -n "SERVER>"
    fi
    while [[ $# -ne 0 ]]; do
        echo -n " $1"
        shift
    done
    echo
}

# Called by onMessage when the server sends a PING, immediately responds with
# a PONG to avoid getting timed out.
function onPING() {
    [[ $# -ne 5 ]] && return
    local message="$5"
    sendToServer PONG "$message"
}

# Load up the user configuration
. "$1"

# Connect to the server and start up the bot!
connect
onConnect
onStartup
while [[ $? -eq 0 ]]; do
    readFromServer onMessage
done
