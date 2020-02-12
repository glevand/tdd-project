#!/usr/bin/env bash

# TDD checkout client library routines.

checkout_split_reply() {
	local reply=${1}
	local -n _checkout_split_reply__cmd=${2}
	local -n _checkout_split_reply__data=${3}

	_checkout_split_reply__cmd="$(echo ${reply} | cut -d ':' -f 1)"
	_checkout_split_reply__data="$(echo ${reply} | cut -d ':' -f 2)"
}

checkout_at_server() {
	local server=${1}
	local port=${2}
	local resource=${3}
	local seconds=${4}
	local -n _checkout_at_server__token=${5}

	set +e
	local reply_msg
	reply_msg="$(echo -n "CKO:${resource}:${seconds}" | netcat ${server} ${port})"
	local reply_result=${?}
	set -e

	if [[ ${reply_result} -ne 0 ]]; then
		echo "${script_name}: checkout_at_server failed: command failed: ${reply_result}" >&2
		return ${reply_result}
	fi

	echo "${script_name}: reply_msg='${reply_msg}'" >&2

	if [[ ! ${reply_msg} ]]; then
		echo "${script_name}: checkout_at_server failed: no reply." >&2
		return -1
	fi

	local cmd
	local data
	checkout_split_reply ${reply_msg} cmd data

	if [[ ${cmd} == "ERR" ]]; then
		echo "${script_name}: checkout_at_server failed: ${reply_msg}" >&2
		return -1
	fi

	if [[ ! ${data} ]]; then
		echo "${script_name}: checkout_at_server failed: no data" >&2
		return -2
	fi

	_checkout_at_server__token="${data}"
}

checkout() {
	local resource=${1}
	local seconds=${2}
	local -n _checkout__token=${3}

	checkout_at_server ${TDD_CHECKOUT_SERVER} ${TDD_CHECKOUT_PORT} ${resource} ${seconds} _checkout__token
}

checkout_query() {
	local resource=${1}
	local -n _checkout_query__seconds=${2}

	echo "${script_name}: WARNING: checkout_query: TODO" >&2
	return 0
}

checkin_at_server() {
	local server=${1}
	local port=${2}
	local token=${3}

	set +e
	local reply_msg
	reply_msg="$(echo -n "CKI:${token}" | netcat ${server} ${port})"
	local reply_result=${?}
	set -e

	echo "${script_name}: reply_msg='${reply_msg}'" >&2

	local cmd
	local data
	checkout_split_reply ${reply_msg} cmd data

	if [[ ${cmd} == "ERR" ]]; then
		echo "${script_name}: checkin_at_server failed: ${reply_msg}" >&2
		return -1
	fi
}

checkin() {
	local token=${1}

	checkin_at_server ${TDD_CHECKOUT_SERVER} ${TDD_CHECKOUT_PORT} ${token}
}

TDD_CHECKOUT_SERVER=${TDD_CHECKOUT_SERVER:-${TDD_RELAY_SERVER:-"tdd-relay"}}
TDD_CHECKOUT_PORT=${TDD_CHECKOUT_PORT:-${TDD_RELAY_PORT:-"9600"}}
