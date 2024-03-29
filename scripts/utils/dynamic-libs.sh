#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - List dynamic library dependencies." >&2
	echo "Usage: ${script_name} [flags] file|directory" >&2
	echo "Option flags:" >&2
	echo "  -h --help        - Show this help and exit." >&2
	echo "  -v --verbose     - Verbose execution." >&2
	echo "  -g --debug       - Extra verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvg"
	local long_opts="help,verbose,debug"

	usage=''
	verbose=''
	debug=''

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
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
			src_path="${1:-}"
			if [[ ${src_path} ]]; then
				shift
			fi
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

	echo "${script_name}: ERROR: function=${f_name}, line=${line_no}, result=${err_no}" >&2
	exit ${err_no}
}

print_paths() {
	local name="${1}"
	local paths="${2}"

	paths="${paths%:}"

	echo "${name}"

	readarray -d ':' -t p_array <<< "${paths}"

	local i
	for (( i = 0; i < ${#p_array[@]}; i++ )); do
		p_array[i]="${p_array[i]//[$'\n']}"
		echo " $(( i + 1 )): [${p_array[i]}]"
	done
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"
base_name="${script_name##*/%}"
base_name="${base_name%.sh}"

SECONDS=0
start_time="$(date +%Y.%m.%d-%H.%M.%S)"

real_source="$(realpath "${BASH_SOURCE}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

tmp_dir=''

trap "on_exit 'Failed'" EXIT
trap 'on_err ${FUNCNAME[0]:-main} ${LINENO} ${?}' ERR
trap 'on_err SIGUSR1 ? 3' SIGUSR1

set -eE
set -o pipefail
set -o nounset

source "${SCRIPT_TOP}/../tdd-lib/util.sh"

process_opts "${@}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${extra_args} ]]; then
	set +o xtrace
	echo "${script_name}: ERROR: Got extra args: '${extra_args}'" >&2
	usage
	exit 1
fi

readelf="${readelf:-readelf}"
file="${file:-file}"

if ! check_progs "${readelf}" "${file}"; then
	exit 1
fi

check_exists "${src_path}" 'Input path'

src_path="$(realpath "${src_path}")"

declare -a files_array

if [[ -d "${src_path}" ]]; then
	readarray -t files_array < <( find "${src_path}" -type f | sort \
		|| { echo "${script_name}: ERROR: files_array_array find failed, function=${FUNCNAME[0]:-main}, line=${LINENO}, result=${?}" >&2; \
		kill -SIGUSR1 $$; } )
elif [[ -f "${src_path}" ]]; then
	files_array=("${src_path}")
else
	echo "${script_name}: ERROR: Source path not found: '${src_path}'" >&2
	usage
	exit 1
fi

lib_regex='^[^(]+\(NEEDED\) *(Shared library: .+)$'

rpath_regex='^[^(]+\(RPATH\) *(Library rpath: .+)$'

runpath_regex='^[^(]+\(RUNPATH\) *(Library runpath: )\[(.+)\]$'

{
	echo 'Dynamic Library Dependencies'
	echo "Generated by ${script_name} (TDD Project) - ${start_time}"
	echo 'https://github.com/glevand/tdd-project'
	echo ''
	echo "Source path = '${src_path}'"
	echo ''
	echo '--------------------------------------------------'

	for f in "${files_array[@]}"; do
		# f="${f//[$'\t\r\n ']}"
		if data="$("${readelf}" -d "${f}" 2>/dev/null)"; then
			echo "File = '${f}'"
			echo ''
			"${file}" --brief "${f}"
			echo ''
			while read -r line; do
				#echo "line = '${line}'"
				if [[ "${line}" =~ ${lib_regex} ]]; then
					#echo "match = '${BASH_REMATCH[0]}'"
					echo "${BASH_REMATCH[1]}"
				elif [[ "${line}" =~ ${rpath_regex} ]]; then
					#echo "match = '${BASH_REMATCH[0]}'"
					echo ""
					print_paths "${BASH_REMATCH[1]}"
				elif [[ "${line}" =~ ${runpath_regex} ]]; then
					#echo "match = '${BASH_REMATCH[0]}'"
					echo ""
					print_paths "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
				fi
			done< <(echo "${data}")
			echo ''
			echo '--------------------------------------------------'
		fi
	done
} >&1

trap "on_exit 'Success'" EXIT
exit 0
