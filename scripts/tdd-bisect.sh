#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Runs TDD via git bisect." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	echo "  -g --good         - git bisect good revision. Default: '${good_rev}'." >&2
	echo "  -b --bad          - git bisect bad revision. Default: '${bad_rev}'." >&2
	echo "  -a --all-steps    - Run all steps." >&2
	echo "  -t --test-only    - Only run --run-tests step." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvgbat"
	local long_opts="help,verbose,good:,bad:,all-steps,test-only"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
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
		-g | --good)
			good_rev="${2}"
			shift 2
			;;
		-b | --bad)
			bad_rev="${2}"
			shift 2
			;;
		-a | --all-steps)
			all_steps=1
			shift
			;;
		-t | --test-only)
			test_only=1
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${@}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	echo "${script_name}: Done: ${result}" >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -x

script_name="${0##*/}"

trap "on_exit 'failed.'" EXIT

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

sudo="sudo -S"

if [[ ${all_steps} ]]; then
	steps="-12345"
elif [[ ${test_only} ]]; then
	steps="-5"
else
	steps="-135"
fi

${sudo} true

echo "${script_name}: TODO" >&2

trap "on_exit 'Success.'" EXIT
exit 0
