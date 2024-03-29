#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Convert sysroot to relative or absolute paths." >&2
	echo "Usage: ${script_name} [flags] <sysroot>" >&2
	echo "Option flags:" >&2
	echo "  -a --absolute  - Convert to absolute paths.  Default: '${absolute}'." >&2
	echo "  -d --dry-run   - Do not execute commands.  Default: '${dry_run}'." >&2
	echo "  -h --help      - Show this help and exit." >&2
	echo "  -v --verbose   - Verbose execution." >&2
	echo "Args:" >&2
	echo "  <sysroot> - Sysroot directory. Default: '${sysroot}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="adhv"
	local long_opts="absolute,dry-run,help,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-a | --absolute)
			absolute=1
			shift
			;;
		-d | --dry-run)
			dry_run=1
			shift
			;;
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
			sysroot=${2}
			if ! shift 2; then
				echo "${script_name}: ERROR: Missing arg: <sysroot>='${sysroot}'" >&2
				usage
				exit 1
			fi
			if [[ -n "${1}" ]]; then
				echo "${script_name}: ERROR: Got extra args: '${@}'" >&2
				usage
				exit 1
			fi
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

	set +x
	echo "${script_name}: Done: ${result}" >&2
}


#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

set -e

script_name="${0##*/}"
trap "on_exit 'failed.'" EXIT

real_source="$(realpath "${BASH_SOURCE}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

source "${SCRIPT_TOP}/tdd-lib/util.sh"

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

check_opt 'sysroot' "${sysroot}"
check_directory "${sysroot}" '' 'usage'

# FIXME: Need to fixup /etc/ld.so.conf?

${SCRIPT_TOP}/relink.sh \
	--root-dir=${sysroot} \
	${absolute:+--absolute} \
	${dry_run:+--dry-run} \
	${verbose:+--verbose} \
	--start-dir=${sysroot}
${SCRIPT_TOP}/prepare-ld-scripts.sh \
	--root-dir=${sysroot} \
	${absolute:+--absolute} \
	${dry_run:+--dry-run} \
	${verbose:+--verbose} \
	--start-dir=${sysroot}

trap "on_exit 'Success.'" EXIT
