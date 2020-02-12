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
	echo "${script_name} - Write systemd debug args to a kernel image." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -i --in-file      - Kernel image. Default: '${in_file}'." >&2
	echo "  -o --out-file     - Output file. Default: '${out_file}'." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	eval "${old_xtrace}"
}

short_opts="hi:o:v"
long_opts="help,in-file:,out-file:,verbose"

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
	-i | --in-file)
		in_file="${2}"
		shift 2
		;;
	-o | --out-file)
		out_file="${2}"
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

out_file=${out_file:-"${in_file}.out"}

if [[ ${usage} ]]; then
	usage
	exit 0
fi

if [[ ! ${in_file} ]]; then
	echo "${script_name}: ERROR: Must provide --in-file option." >&2
	usage
	exit 1
fi

check_file "${in_file}"

on_exit() {
	local result=${1}

	echo "${script_name}: ${result}" >&2
}

trap "on_exit 'Done, failed.'" EXIT

LANG=C
LC_ALL=C


# systemctl show --no-pager
# log_level: debug info notice warning err crit alert emerg
# log_target: console journal kmsg journal-or-kmsg
#
# 'systemd.log_level=info '            => 'systemd.log_level=debug'
# 'systemd.log_target=journal-or-kmsg' => 'systemd.log_target=console'
# systemd.journald.forward_to_console=1


# systemd args must match the CONFIG_CMDLINE entry in the kernel config fixup.spec file.

args=(
	'systemd.log_level=info :systemd.log_level=debug'
#	'systemd.log_target=journal-or-kmsg:systemd.log_target=console        '
)

tmp_file=${out_file}.tmp
rm -f ${out_file} ${tmp_file}
cp -vf ${in_file} ${tmp_file}

for pair in "${args[@]}"; do
	echo "pair:      @${pair}@" >&2
	
	unset old_txt new_txt

	old_txt=${pair%:*}
	new_txt=${pair#*:}

	echo "  old_txt:  @${old_txt}@" >&2
	echo "  new_txt: @${new_txt}@" >&2

	set +e
	old=$(eval "egrep --text --only-matching --max-count=1 '${old_txt}' ${tmp_file}")
	result=${?}

	if [[ ${result} -ne 0 ]]; then
		echo "${script_name}: ERROR: Kernel command line arg not found: '${old_txt}'." >&2
		echo "Kernel strings:" >&2
		egrep --text 'systemd.' ${in_file} >&2
		egrep --text  --max-count=1 'chosen.*bootargs' ${in_file} >&2
		exit 1
	fi
	set -e

	sed --in-place "{s/${old_txt}/${new_txt}/g}" ${tmp_file}

	if [[ ${verbose} ]]; then
		eval "egrep --text '${new_txt}' ${tmp_file}" >&2
	fi
done

cp -vf ${tmp_file} ${out_file}
rm -f ${tmp_file}

trap - EXIT

echo "${script_name}: INFO: Output kernel: '${out_file}'" >&2

on_exit 'Done, success.'
