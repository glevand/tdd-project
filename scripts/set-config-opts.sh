#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Sets kernel config options from <spec-file>." >&2
	echo "Usage: ${script_name} [flags] <spec-file> <kernel-config>" >&2
	echo "Option flags:" >&2
	echo "  -h --help          - Show this help and exit." >&2
	echo "  -v --verbose       - Verbose execution." >&2
	echo "  --platform-args    - Platform args. Default: '${platform_args}'." >&2
	echo "Args:" >&2
	echo "  <spec-file>     - Build target {${target_list}}." >&2
	echo "                 Default: '${target}'." >&2
	echo "  <kernel-config> - Kernel source directory." >&2
	echo "                 Default: '${kernel_src}'." >&2
	echo "Spec File Info:" >&2
	echo "  The spec file contains one kernel option per line.  Lines beginning with '#' (regex '^#') are comments." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose,platform-args:"

	local opts
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
		--platform-args)
			platform_args="${2}"
			shift 2
			;;
		--)
			spec_file="${2}"
			kernel_config="${3}"
			if ! shift 3; then
				echo "${script_name}: ERROR: Missing args:" >&2
				echo "${script_name}:        <spec-file>='${spec_file}'" >&2
				echo "${script_name}:        <kernel-config>='${kernel_config}'" >&2
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

	echo "${script_name}: ${result}" >&2
}

#===============================================================================
# program start
#===============================================================================
script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

trap "on_exit 'Done, failed.'" EXIT
set -e

process_opts "${@}"

check_file "${spec_file}" "" "usage"
check_file "${kernel_config}" "" "usage"

if [[ ${usage} ]]; then
	usage
	exit 0
fi

cp -f "${kernel_config}" "${kernel_config}".orig

while read -r update; do
	if [[ -z "${update}" || "${update:0:1}" == '#' ]]; then
		#echo "skip @${update}@"
		continue
	fi

	tok="${update%%=*}"

	if old=$(egrep ".*${tok}[^_].*" ${kernel_config}); then
		sed  --in-place "{s@.*${tok}[^_].*@${update}@g}" ${kernel_config}
		new=$(egrep ".*${tok}[^_].*" ${kernel_config})
		echo "${script_name}: Update: '${old}' -> '${new}'"
	else
		echo "${update}" >> "${kernel_config}"
		echo "${script_name}: Append: '${update}'"
	fi

done < "${spec_file}"

if [[ ${platform_args} ]]; then
	sed  --in-place "{s@platform_args@${platform_args}@g}" ${kernel_config}
fi

diff -u "${kernel_config}".orig "${kernel_config}" || : >&2

echo "" >&2

trap - EXIT

on_exit 'Done, success.'

