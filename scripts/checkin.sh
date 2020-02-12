#!/usr/bin/env bash

set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/checkout.sh

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Checkin TDD resource." >&2
	echo "Usage: ${script_name} [flags] <token>" >&2
	echo "Option flags:" >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "Args:" >&2
	echo "  <token>      - Checkout reservation token" >&2
	eval "${old_xtrace}"
}

short_opts="hv"
long_opts="help,verbose"

opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

if [ $? != 0 ]; then
	echo "${script_name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
	case "${1}" in
	-h | --help)
		usage=1
		shift
		;;
	-v | --verbose)
		set -x
		verbose=1
		shift
		;;
	--)
		shift
		token=${1}
		if ! shift 1; then
			set +o xtrace
			echo "${script_name}: ERROR: Missing args:" >&2
			echo "${script_name}:   <token>='${token}'" >&2
			usage
			exit 1
		fi
		if [[ -n "${1}" ]]; then
			set +o xtrace
			echo "${script_name}: ERROR: Got extra args: '${@}'" >&2
			usage
			exit 1
		fi
		break
		;;
	*)
		set +o xtrace
		echo "${script_name}: ERROR: Internal opts: '${@}'" >&2
		exit 1
		;;
	esac
done

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

on_err() {
	set +x
	set +e

	echo "${script_name}: token: ${token}"
	echo "${script_name}: Done, failed." >&2
}

trap on_err EXIT

checkin "${token}"

trap - EXIT
echo "${script_name}: Done, success." >&2
