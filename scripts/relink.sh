#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Convert broken absolute symlinks to relative or absolute symlinks." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --absolute  - Convert to absolute links.  Default: '${absolute}'." >&2
	echo "  -d --dry-run   - Do not execute commands.  Default: '${dry_run}'." >&2
	echo "  -h --help      - Show this help and exit." >&2
	echo "  -r --root-dir  - Root of file system.  Default: '${root_dir}'." >&2
	echo "  -s --start-dir - Top of directory tree to convert. Default: '${start_dir}'." >&2
	echo "  -v --verbose   - Verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="adhr:s:v"
	local long_opts="absolute,dry-run,help,root-dir:,start-dir:,verbose"

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
		-r | --root-dir)
			root_dir="${2}"
			shift 2
			;;
		-s | --start-dir)
			start_dir="${2}"
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

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source "${SCRIPTS_TOP}/tdd-lib/util.sh"

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

check_opt 'root-dir' "${root_dir}"
check_directory "${root_dir}" "" "usage"
root_dir="$(realpath ${root_dir})"

check_opt 'start-dir' "${start_dir}"
check_directory "${start_dir}" "" "usage"
start_dir="$(realpath ${start_dir})"

links=$(find "${start_dir}" -xtype l)

for link in ${links}; do
	orig_target="$(realpath -m ${link})"

	if [[ "${orig_target:0:1}" != "/" ]]; then
		echo "${script_name}: INFO: Not an absolute path: ${link} -> ${orig_target}" >&2
		continue
	fi
	#echo "${link} -> ${orig_target}" >&2

	rel_target="$(relative_path ${link} ${orig_target} ${root_dir})"
	abs_target="${root_dir}${orig_target}"

	if [[ ${verbose} || ${dry_run} ]]; then
		comb_target=${link%/*}/${rel_target}
		resolved_target="$(realpath -m ${comb_target})"

		echo "${link}" >&2
		echo "  original: ${orig_target}" >&2
		echo "  relative: ${rel_target}" >&2
		echo "  absolute: ${abs_target}" >&2
		echo "  resolved: ${resolved_target}" >&2
	fi

	if [[ ! ${dry_run} ]]; then
		if [[ ${absolute} ]]; then
			ln -sf "${abs_target}" "${link}"
		else
			ln -sf "${rel_target}" "${link}"
		fi
		ls -l "${link}" | cut -d ' ' -f 10-
	fi
done

trap "on_exit 'Success.'" EXIT
