#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace

	local target_list
	target_list="$(clean_ws "${targets}")"
	local op_list
	op_list="$(clean_ws "${ops}")"

	echo "${script_name} - Builds linux kernel." >&2
	echo "Usage: ${script_name} [flags] <target> <kernel_src> <op>" >&2
	echo "Option flags:" >&2
	echo "  -h --help             - Show this help and exit." >&2
	echo "  -v --verbose          - Verbose execution." >&2
	echo "  -b --build-dir        - Build directory. Default: '${build_dir}'." >&2
	echo "  -i --install-dir      - Target install directory. Default: '${install_dir}'." >&2
	echo "  -l --local-version    - Default: '${local_version}'." >&2
	echo "  -p --toolchain-prefix - Default: '${toolchain_prefix}'." >&2
	echo "Args:" >&2
	echo "  <target> - Build target.  Default: '${target}'." >&2
	echo "  Known targets: ${target_list}" >&2
	echo "  <kernel-src> - Kernel source directory.  Default : '${kernel_src}'." >&2
	echo "  <op> - Build operation.  Default: '${op}'." >&2
	echo "  Known targets: ${op_list}" >&2
	echo "Info:" >&2
	echo "  ${cpus} CPUs available." >&2

	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvb:i:l:p:"
	local long_opts="help,verbose,\
build-dir:,install-dir:,local-version:,toolchain-prefix:"

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
			verbose=1
			set -x
			shift
			;;
		-b | --build-dir)
			build_dir="${2}"
			shift 2
			;;
		-l | --local-version)
			local_version="${2}"
			shift 2
			;;
		-t | --install-dir)
			install_dir="${2}"
			shift 2
			;;
		-p | --toolchain-prefix)
			toolchain_prefix="${2}"
			shift 2
			;;
		--)
			target=${2}
			kernel_src=${3}
			op=${4}
			if [[ ${check} ]]; then
				break
			fi
			if ! shift 4; then
				echo "${script_name}: ERROR: Missing args:" >&2
				echo "${script_name}:        <target>='${target}'" >&2
				echo "${script_name}:        <kernel_src>='${kernel_src}'" >&2
				echo "${script_name}:        <op>='${op}'" >&2
				echo "" >&2
				usage
				exit 1
			fi
			if [[ -n "${1}" ]]; then
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

	set +x
	echo "${script_name}: Done: ${result}" >&2
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}

start_time="$(date)"
SECONDS=0

trap "on_exit 'failed.'" EXIT
set -o pipefail
set -e

source "${SCRIPTS_TOP}/../lib/util.sh"

progs="efivar efibootmgr"

if ! check_progs ${progs}; then
	exit 1
fi

readarray -t list < <(efivar --list | sort)
sleep 0.1

host="$(hostname)"
echo -n "${script_name}: [${host//[$'\t\r\n ']}] "
date

start=1
echo "==============================================================================" >&1

for i in "${list[@]}"; do
	if [[ ${start} ]]; then
		unset start
	else
		echo "------------------------------------------------------------------------------" >&1
	fi
	efivar --print --name="${i}"
	sleep 0.1
done

echo "==============================================================================" >&1
efibootmgr -v
echo "==============================================================================" >&1

trap "on_exit 'Success.'" EXIT
exit 0

