#!/usr/bin/env bash

set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/relay.sh

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Write a tdd-relay triple to a kernel image." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -k --kernel       - Kernel image. Default: '${kernel}'." >&2
	echo "  -o --out-file     - Output file. Default: '${out_file}'." >&2
	echo "  -t --relay-triple - tdd-relay triple.  File name or 'server:port:token'. Default: '${relay_triple}'." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	eval "${old_xtrace}"
}

short_opts="hk:o:t:v"
long_opts="help,kernel:,out-file:,relay-triple:,verbose"

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
	-k | --kernel)
		kernel="${2}"
		shift 2
		;;
	-o | --out-file)
		out_file="${2}"
		shift 2
		;;
	-t | --relay-triple)
		relay_triple="${2}"
		shift 2
		;;
	-v | --verbose)
		set -x
		verbose=1
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

if [[ -f "${relay_triple}" ]]; then
	relay_triple=$(cat ${relay_triple})
	echo "${script_name}: INFO: Relay triple: '${relay_triple}'" >&2
fi

if [[ ! ${relay_triple} ]]; then
	echo "${script_name}: ERROR: Must provide --relay_triple option." >&2
	usage
	exit 1
fi

relay_triple=$(relay_resolve_triple ${relay_triple})

token=$(relay_triple_to_token ${relay_triple})
out_file="${out_file:-${kernel}.${token}}"

if [[ ${usage} ]]; then
	usage
	exit 0
fi

if [[ ! ${kernel} ]]; then
	echo "${script_name}: ERROR: Must provide --kernel option." >&2
	usage
	exit 1
fi

check_file "${kernel}"

on_exit() {
	local result=${1}

	echo "${script_name}: ${result}" >&2
}

trap "on_exit 'Done, failed.'" EXIT

LANG=C
LC_ALL=C

# kernel_param must match the CONFIG_CMDLINE entry in the kernel config fixup.spec file.
kernel_param='tdd_relay_triple=x*z'
set +e
old=$(eval "egrep --text --only-matching --max-count=1 '${kernel_param}' ${kernel}")
result=${?}

if [[ ${result} -ne 0 ]]; then
	echo "${script_name}: ERROR: Kernel tdd_relay_triple command line param '${kernel_param}' not found." >&2
	echo "Kernel strings:" >&2
	egrep --text 'tdd_relay_triple' ${kernel} >&2
	egrep --text  --max-count=1 'chosen.*bootargs' ${kernel} >&2
	exit 1
fi
set -e

old_len=${#old}

new="tdd_relay_triple=${relay_triple}"
new_len=${#new}

empty="                                                          "

pad=$(printf '%0.*s' $(( ${old_len} - ${new_len} )) "${empty}")
pad_len=${#pad}

cat ${kernel} | sed "{s/${old}/${new}${pad}/g}" > ${out_file}

if [[ ${verbose} ]]; then
	egrep --text 'tdd_relay_triple' ${out_file} >&2
fi

trap - EXIT

echo "${script_name}: INFO: Test kernel: '${out_file}'" >&2

on_exit 'Done, success.'
