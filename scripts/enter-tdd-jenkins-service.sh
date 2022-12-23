#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace

	{
		echo "${script_name} - Enter tdd-jenkins.service container."
		echo "Usage: ${script_name} [flags]"
		echo "Option flags:"
		echo "  -c --clean   - Clean kernel rootfs files. Default: '${clean}'."
		echo "  -h --help    - Show this help and exit."
		echo "  -g --debug   - Extra verbose execution. Default: '${debug}'."
		echo "Info:"
		print_project_info
	} >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts='chg'
	local long_opts='clean,help,debug'

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-c | --clean)
			clean=1
			shift
			;;
		-h | --help)
			usage=1
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
			extra_args="${*}"
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${*}'" >&2
			exit 1
			;;
		esac
	done
}

print_project_banner() {
	echo "${script_name} (@PACKAGE_NAME@) - ${start_time}"
}

print_project_info() {
	echo "  @PACKAGE_NAME@ ${script_name}"
	echo "  Version: @PACKAGE_VERSION@"
	echo "  Project Home: @PACKAGE_URL@"
}

on_exit() {
	local result=${1}

	local sec="${SECONDS}"

	set +x
	echo "${script_name}: Done: ${result}, ${sec} sec." >&2
}

on_err() {
	local f_name=${1}
	local line_no=${2}
	local err_no=${3}

	echo "${script_name}: ERROR: function=${f_name}, line=${line_no}, result=${err_no}"
	exit "${err_no}"
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"

SECONDS=0
start_time="$(date +%Y.%m.%d-%H.%M.%S)"

real_source="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

trap "on_exit 'Failed'" EXIT
trap 'on_err ${FUNCNAME[0]:-main} ${LINENO} ${?}' ERR
trap 'on_err SIGUSR1 ? 3' SIGUSR1

set -eE
set -o pipefail
set -o nounset

clean=''
usage=''
debug=''

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

print_project_banner >&2

if [[ ${extra_args} ]]; then
	set +o xtrace
	echo "${script_name}: ERROR: Got extra args: '${extra_args}'" >&2
	usage
	exit 1
fi

kernel_rootfs=/var/jenkins_home/workspace/tdd/kernel/kernel-test/arm64-debian-buster.rootfs

if [[ ${clean} ]]; then
	exec docker exec --privileged tdd-jenkins.service sudo rm -rf ${kernel_rootfs}
fi

exec docker exec -it --privileged tdd-jenkins.service /bin/bash
