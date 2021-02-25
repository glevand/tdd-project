#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Convert ld scripts to relative or absolute paths." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --absolute  - Convert to absolute paths.  Default: '${absolute}'." >&2
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
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
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

	if [[ -d ${tmp_dir} ]]; then
		rm -rf "${tmp_dir:?}"
	fi

	set +x
	echo "${script_name}: Done: ${result}" >&2
}


#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
script_name="${0##*/}"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

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

tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"

# FIXME: Need to fixup /etc/ld.so.conf?

files=$(find "${start_dir}" -name '*.so')

for file in ${files}; do
	if [[ "$(file -b ${file})" != "ASCII text" ]]; then
		continue
	fi

	echo "${script_name}: ${file}" >&2

	while read -r line_in; do
		if [[ "${line_in:0:5}" != "GROUP" ]]; then
			echo "${line_in}" >> ${tmp_dir}/1
		else
			line_out=""
			for w in ${line_in}; do
				if [[ ${w} != *"/lib/"* ]]; then
					line_out+="${w} "
				else
					if [[ ${absolute} ]]; then
						line_out+="${root_dir}${w} "
					else
						line_out+="$(relative_path ${file} ${w} ${root_dir}) "
					fi
				fi
			done
			echo "${script_name}:  in:  ${line_in}" >&2
			echo "${script_name}:  out: ${line_out}" >&2
			echo "${line_out}" >> ${tmp_dir}/1
		fi
	done < "${file}"

	#cat ${tmp_dir}/1
	cp -f ${tmp_dir}/1 ${file}
done

trap "on_exit 'Success.'" EXIT
