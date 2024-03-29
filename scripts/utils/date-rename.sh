#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Rename directories from 'yy.mm.dd' to 'yyyy.mm.dd'"
	echo "Usage: ${script_name} [flags] top-dir" >&2
	echo "Option flags:" >&2
#	echo "  -A --opt-A   - Output directory. Default: '${opt_A}'." >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution. Default: '${verbose}'." >&2
	echo "  -g --debug   - Extra verbose execution. Default: '${debug}'." >&2
	echo "Send bug reports to: Geoff Levand <geoff@infradead.org>." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="A:hvg"
	local long_opts="opt-A:,help,verbose,debug"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-A | --opt-A)
			opt_A="${2}"
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
			keep_tmp_dir=1
			set -x
			shift
			;;
		--)
			shift
			if [[ ${1} ]]; then
				top_dir="${1}"
				shift
			fi
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
	local sec="${SECONDS}"

	echo "${script_name}: Done: ${result}, ${sec} sec." >&2
}

on_err() {
	local f_name=${1}
	local line_no=${2}
	local err_no=${3}

	echo "${script_name}: ERROR: function=${f_name}, line=${line_no}, result=${err_no}" >&2
	exit ${err_no}
}

check_top_dir() {
	local top_dir="${1}"

	if [[ ! ${top_dir} ]]; then
		echo "${script_name}: ERROR: No top-dir given." >&2
		usage
		exit 1
	fi

	if [[ ! -d ${top_dir} ]]; then
		echo "${script_name}: ERROR: Bad top-dir: '${top_dir}'" >&2
		usage
		exit 1
	fi
}
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"

real_source="$(realpath "${BASH_SOURCE}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

SECONDS=0

trap "on_exit 'Failed'" EXIT
trap 'on_err ${FUNCNAME[0]:-main} ${LINENO} ${?}' ERR
trap 'on_err SIGUSR1 ? 3' SIGUSR1

set -eE
set -o pipefail
set -o nounset

start_time="$(date +%Y.%m.%d-%H.%M.%S)"

process_opts "${@}"

opt_A="${opt_A:-todo}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

check_top_dir "${top_dir}"

for pattern in '[0-9][0-9].[0-9][0-9].[0-9][0-9]' '[0-9][0-9].[0-9][0-9].[0-9][0-9].*' '[0-9][0-9].[0-9][0-9].[0-9][0-9]-*'; do

	readarray -t path_array < <( \
		find "${top_dir}" -maxdepth 1 -type d -name "${pattern}" | sort \
		|| { echo "${script_name}: ERROR: path_array find failed, function=${FUNCNAME[0]:-main}, line=${LINENO}, result=${?}" >&2; \
		kill -SIGUSR1 $$; } )

	in_count="${#path_array[@]}"

	echo "${script_name}: INFO: Processing ${in_count} input directories." >&2

	for (( id = 1; id <= ${in_count}; id++ )); do

		path="${path_array[$(( id - 1 ))]}"
		
		dir="${path%/*}"
		
		name="${path##*/}"
		date="${name#*.}"
		year="${name%%.*}"
		new_year="20${name%%.*}"

		if [[ ${verbose} ]]; then
			echo "'${path}' -> '${dir}/${new_year}.${date}'" >&2
		fi
		
		mv -v "${path}" "${dir}/${new_year}.${date}"
	done
done

trap "on_exit 'Success'" EXIT
exit 0
