#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Collects various system info." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -o --out-file - Output file. Default: '${out_file}'." >&2
	echo "  -n --no-sudo  - Skip tests run with sudo." >&2
#	echo "  -a --action   - todo. Default: '${action}'." >&2
	echo "  -h --help     - Show this help and exit." >&2
	echo "  -v --verbose  - Verbose execution." >&2
	echo "  -g --debug    - Extra verbose execution." >&2
	echo "Send bug reports to: Geoff Levand <geoff@infradead.org>." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="ona:hvg"
	local long_opts="out-file:,no-sudo,action:,help,verbose,debug"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-o | --out-file)
			out_file="${2}"
			shift 2
			;;
		-n | --no-sudo)
			no_sudo=1
			shift
			;;
		-a | --action)
			action="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			verbose=1
			shift
			;;
		-g | --debug)
			verbose=1
			debug=1
			set -x
			shift
			;;
		--)
			shift
			if [[ ${*} ]]; then
				set +o xtrace
				echo "${script_name}: ERROR: Got extra args: '${*}'" >&2
				usage
				exit 1
			fi
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${*}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	if [[ -d "${tmp_dir}" ]]; then
		eval "${sudo}" rm -rf "${tmp_dir:?}"
	fi
	
	set +x
	echo "${script_name}: Done : ${result}." >&2
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"
base_name="${script_name##*/%}"
base_name="${base_name%.sh}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}

start_time="$(date +%Y.%m.%d-%H.%M.%S)"
SECONDS=0

trap "on_exit 'failed.'" EXIT
set -o pipefail
set -e

source "${SCRIPTS_TOP}/../tdd-lib/util.sh"

process_opts "${@}"

out_file="${out_file:-/tmp/${script_name%.*}--$(hostname)-${start_time}.tar.gz}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${no_sudo} ]]; then
	unset sudo
else
	sudo="sudo -S"
	echo "${script_name}: INFO: Current flags require sudo privileges." >&2
	eval "${sudo}" true 
fi


tmp_dir="$(mktemp --tmpdir --directory "${script_name}".XXXX)"

stage_name="${out_file##*/}"
stage_name="${stage_name%.tar.gz}"
stage_dir="${tmp_dir}/${stage_name}"

eval "${sudo}" rm -f "${out_file}"

mkdir -p "${stage_dir}"

host="$(hostname)"

echo '' >&1
echo "Generated by ${script_name} (TDD Project) - ${start_time}" >&1
echo "https://github.com/glevand/tdd-project" >&1
echo "Host '${host//[$'\t\r\n ']}'" >&1
echo '' >&1

echo "${host//[$'\t\r\n ']}" > "${stage_dir}/host-info"
echo "${start_time}" >> "${stage_dir}/host-info"

ip a > "${stage_dir}/ip"
ip r >> "${stage_dir}/ip"

eval "${sudo}" journalctl -b --no-pager > "${stage_dir}/journalctl"
eval "${sudo}" systemctl --no-pager > "${stage_dir}/systemctl"
eval "${sudo}" systemctl status --no-pager > "${stage_dir}/systemctl-status"
eval "${sudo}" ps aux > "${stage_dir}/ps"

mkdir -p "${out_file%/*}"

tar -czf "${out_file}" -C "${tmp_dir}" "${stage_name}"

if [[ ${verbose} ]]; then
	mkdir "${tmp_dir}/test"
	tar -C "${tmp_dir}/test" -xvf "${out_file}"

	echo '=================' >&2
	ls -lh "${tmp_dir}/test/${stage_name}" >&2
	echo '=================' >&2
	tar -tf "${out_file}" >&2
	echo '=================' >&2
	find "${tmp_dir}/test/${stage_name}" -type f \
		-exec echo '----------------' \; -print -exec cat {} \;
fi

echo "${script_name}: Results in '${out_file}'." >&2

trap "on_exit 'Success'" EXIT
exit 0
