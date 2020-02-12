#!/usr/bin/env bash

# TDD relay client library routines.

relay_double_to_server() {
	echo ${1} | cut -d ':' -f 1
}

relay_double_to_port() {
	echo ${1} | cut -d ':' -f 2
}

relay_test_triple() {
	[[ ${1} =~ .:[[:digit:]]{3,5}:. ]]
}

relay_verify_triple() {
	local triple=${1}

	if ! relay_test_triple ${triple}; then
		echo "${script_name}: ERROR: Bad triple: '${triple}'" >&2
		exit 1
	fi
}

relay_random_token() {
	echo "$(cat /proc/sys/kernel/random/uuid)"
}

relay_make_random_triple() {
	local server=${1}
	local port=${2}

	server=${server:-${TDD_RELAY_SERVER}}
	port=${port:-${TDD_RELAY_PORT}}

	echo "${server}:${port}:$(relay_random_token)"
}

relay_triple_to_server() {
	local triple=${1}

	relay_verify_triple ${triple}
	echo ${triple} | cut -d ':' -f 1
}

relay_triple_to_port() {
	local triple=${1}

	relay_verify_triple ${triple}
	echo ${triple} | cut -d ':' -f 2
}

relay_triple_to_token() {
	local triple=${1}

	relay_verify_triple ${triple}
	echo ${triple} | cut -d ':' -f 3
}

relay_split_triple() {
	local triple=${1}
	local -n _relay_split_triple__server=${2}
	local -n _relay_split_triple__port=${3}
	local -n _relay_split_triple__token=${4}

	relay_verify_triple ${triple}

	_relay_split_triple__server="$(echo ${triple} | cut -d ':' -f 1)"
	_relay_split_triple__port="$(echo ${triple} | cut -d ':' -f 2)"
	_relay_split_triple__token="$(echo ${triple} | cut -d ':' -f 3)"
}

relay_resolve_triple() {
	local triple=${1}
	local server port token addr

	relay_split_triple ${triple} server port token

	find_addr addr "/etc/hosts" ${server}

	echo "${addr}:${port}:${token}"
}

relay_init_triple() {
	local server=${1}
	local port addr token triple

	if [[ ${server} ]]; then
		port=$(relay_double_to_port ${server})
		server=$(relay_double_to_server ${server})
	else
		port=${TDD_RELAY_PORT}
		server=${TDD_RELAY_SERVER}
	fi

	find_addr addr "/etc/hosts" ${server}
	token=$(relay_random_token)
	triple="${addr}:${port}:${token}"

	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "relay_triple:  ${triple}" >&2
	echo " relay_server: ${server}" >&2
	echo " relay_addr:   ${addr}" >&2
	echo " relay_port:   ${port}" >&2
	echo " relay_token:  ${token}" >&2
	eval "${old_xtrace}"

	echo "${triple}"
}

relay_split_reply() {
	local reply=${1}
	local -n _relay_split_reply__cmd=${2}
	local -n _relay_split_reply__data=${3}

	_relay_split_reply__cmd="$(echo ${reply} | cut -d ':' -f 1)"
	_relay_split_reply__data="$(echo ${reply} | cut -d ':' -f 2)"
}

relay_get() {
	local timeout=${1}
	local triple=${2}
	local -n _relay_get__remote_addr=${3}

	local server
	local port
	local token
	relay_split_triple ${triple} server port token

	echo "${script_name}: relay client: Waiting ${timeout}s for msg at ${server}:${port}..." >&2

	SECONDS=0
	local reply_msg
	local reply_result

	#timeout="3s" # For debug.
	set +e
	reply_msg="$(echo -n "GET:${token}" | netcat -w${timeout} ${server} ${port})"
	reply_result=${?}
	set -e

	local boot_time="$(sec_to_min ${SECONDS})"

	echo "${script_name}: reply_result='${reply_result}'" >&2
	echo "${script_name}: reply_msg='${reply_msg}'" >&2

	if [[ ${reply_result} -eq 1 ]]; then
		echo "${script_name}: relay GET ${server} failed (${reply_result}): Host unreachable? Server down?" >&2
		ping -c 1 -n ${server}
		return 1
	fi

	if [[ ${reply_result} -eq 124 || ! ${reply_msg} ]]; then
		echo "${script_name}: relay GET ${server} failed (${reply_result}): Timed out ${timeout}." >&2
		return 1
	fi

	if [[ ${reply_result} -ne 0 ]]; then
		echo "${script_name}: relay GET ${server} failed (${reply_result})." >&2
		return ${reply_result}
	fi

	echo "${script_name}: reply_msg='${reply_msg}'" >&2
	local cmd
	relay_split_reply ${reply_msg} cmd _relay_get__remote_addr

	if [[ "${cmd}" != 'OK-' ]]; then
		echo "${script_name}: relay_get failed: ${reply_msg}" >&2
		_relay_get__remote_addr="server-error"
		return 1
	fi

	echo "${script_name}: Received msg from '${_relay_get__remote_addr}" >&2
	echo "${script_name}: ${_relay_get__remote_addr} boot time = ${boot_time} min" >&2
}

TDD_RELAY_SERVER=${TDD_RELAY_SERVER:-"tdd-relay"}
TDD_RELAY_PORT=${TDD_RELAY_PORT:-"9600"}
