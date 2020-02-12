#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Query TDD resource." >&2
	echo "Usage: ${script_name} [flags] <resource>" >&2
	echo "Option flags:" >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "Args:" >&2
	echo "  <resource>   - Resource to query. Default: '${resource}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

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
			resource=${1}
			if ! shift 1; then
				set +o xtrace
				echo "${script_name}: ERROR: Missing args:" >&2
				echo "${script_name}:   <resource>='${resource}'" >&2
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
}

on_err() {
	set +x
	set +e

	echo "${script_name}: resource: ${resource}"
	echo "${script_name}: Done, failed." >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
script_name="${0##*/}"

trap on_err EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/checkout.sh

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi


seconds="XXX"
checkout_query "${resource}" seconds

trap - EXIT
echo "${token}"
