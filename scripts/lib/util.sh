#!/usr/bin/env bash

clean_ws() {
	local in="$*"

	shopt -s extglob
	in="${in//+( )/ }" in="${in# }" in="${in% }"
	echo -n "$in"
}

substring_has() {
	local string=${1}
	local substring=${2}

	[ -z "${string##*${substring}*}" ];
}

substring_begins() {
	local string=${1}
	local substring=${2}

	[ -z "${string##${substring}*}" ];
}

substring_ends() {
	local string=${1}
	local substring=${2}

	[ -z "${string##*${substring}}" ];
}

sec_to_min() {
	local sec=${1}
	local min=$((sec / 60))
	local frac_10=$(((sec - min * 60) * 10 / 60))
	local frac_100=$(((sec - min * 60) * 100 / 60))

	if ((frac_10 != 0)); then
		unset frac_10
	fi

	echo "${min}.${frac_10}${frac_100}"
}

test_sec_to_min() {
	local start=${1:-1}
	local end=${2:-100}
	local enc=${3:-1}

	for ((sec = start; sec <= end; sec += enc)); do
		echo "${sec} sec = $(sec_to_min ${sec}) ($(echo "scale=2; ${sec}/60" | bc -l | sed 's/^\./0./')) min" >&2
	done
}

directory_size_bytes() {
	local dir=${1}

	local size
	size="$(du -sb "${dir}")"
	echo "${size%%[[:space:]]*}"
}

directory_size_human() {
	local dir=${1}

	local size
	size="$(du -sh "${dir}")"
	echo "${size%%[[:space:]]*}"
}

check_directory() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -d "${src}" ]]; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Directory not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${script_name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_opt() {
	option=${1}
	shift
	value="${*}"

	if [[ ! ${value} ]]; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Must provide --${option} option." >&2
		usage
		exit 1
	fi
}

check_not_opt() {
	option1=${1}
	option2=${2}
	shift 2
	value2="${*}"

	if [[ ${value2} ]]; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Can't use --${option2} with --${option1}." >&2
		usage
		exit 1
	fi
}

check_progs() {
	local progs="${*}"
	local p;
	local result;

	result=0
	for p in ${progs}; do
		if ! test -x "$(command -v "${p}")"; then
			echo "${script_name}: ERROR: Please install '${p}'." >&2
			result=1
		fi
	done

	return ${result}
}

check_pairs () {
	local -n _check_pairs__pairs=${1}
	local key
	local val
	local result

	result=0
	for key in "${!_check_pairs__pairs[@]}"; do
		val="${_check_pairs__pairs[${key}]}"
		[[ ${verbose} ]] && echo "${script_name}: check: '${val}' => '${key}'." >&2

		if [[ ! -e "${val}" ]]; then
			echo "${script_name}: ERROR: '${val}' not found, please install '${key}'." >&2
			((result += 1))
		fi
	done
	return ${result}
}

check_progs_and_pairs () {
	local progs="${1}"
	local -n _check_progs_and_pairs__pairs=${2}
	local result

	result=0
	if ! check_progs "${progs}"; then
		((result += 1))
	fi

	if ! check_pairs _check_progs_and_pairs__pairs; then
		((result += 1))
	fi
	return ${result}
}

find_common_parent() {
	local dir1
	dir1="$(realpath -m "${1}")"
	local dir2
	dir2="$(realpath -m "${2}")"
	local A1
	local A2
	local sub

	IFS="/" read -ra A1 <<< "${dir1}"
	IFS="/" read -ra A2 <<< "${dir2}"

	#echo "array len = ${#A1[@]}" >&2

	for ((i = 0; i < ${#A1[@]}; i++)); do
		echo "${i}: @${A1[i]}@ @${A2[i]}@" >&2
		if [[ "${A1[i]}" != "${A2[i]}" ]]; then
			break;
		fi
		sub+="${A1[i]}/"
	done

	#echo "sub = @${sub}@" >&2
	echo "${sub}"
}

relative_path_2() {
	local base="${1}"
	local target="${2}"
	local root="${3}"

	base="${base##${root}}"
	base="${base%%/}"
	base=${base%/*}
	target="${target%%/}"

	local back=""
	while :; do
		set +x
		echo "target: ${target}" >&2
		echo "base:   ${base}" >&2
		echo "back:   ${back}" >&2
		set -x
		if [[ "${base}" == "/" || ! ${base} ]]; then
			break
		fi
		back+="../"
		if [[ "${target}" == ${base}/* ]]; then
			break
		fi
		base=${base%/*}
	done

	echo "${back}${target##${base}/}"
}

relative_path() {
	local base="${1}"
	local target="${2}"
	local root="${3}"

	base="${base##${root}}"
	base="${base%%/}"
	base=${base%/*}
	target="${target%%/}"

	local back=""
	while :; do
		#echo "target: ${target}" >&2
		#echo "base:   ${base}" >&2
		#echo "back:   ${back}" >&2
		if [[ "${base}" == "/" || "${target}" == ${base}/* ]]; then
			break
		fi
		back+="../"
		base=${base%/*}
	done

	echo "${back}${target##${base}/}"
}

copy_file() {
	local src="${1}"
	local dest="${2}"

	check_file "${src}"
	cp -f "${src}" "${dest}"
}

cpu_count() {
	local result

	if result="$(getconf _NPROCESSORS_ONLN)"; then
		echo "${result}"
	else
		echo "1"
	fi
}

get_user_home() {
	local user=${1}
	local result;

	if ! result="$(getent passwd "${user}")"; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): No home for user '${user}'" >&2
		exit 1
	fi
	echo "${result}" | cut -d ':' -f 6
}

known_arches="arm64 amd64 ppc32 ppc64 ppc64le"

get_arch() {
	local a=${1}

	case "${a}" in
	arm64|aarch64)			echo "arm64" ;;
	amd64|x86_64)			echo "amd64" ;;
	ppc|powerpc|ppc32|powerpc32)	echo "ppc32" ;;
	ppc64|powerpc64)		echo "ppc64" ;;
	ppc64le|powerpc64le)		echo "ppc64le" ;;
	*)
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

get_triple() {
	local a=${1}

	case "${a}" in
	amd64)		echo "x86_64-linux-gnu" ;;
	arm64)		echo "aarch64-linux-gnu" ;;
	ppc32)		echo "powerpc-linux-gnu" ;;
	ppc64)		echo "powerpc64-linux-gnu" ;;
	ppc64le)	echo "powerpc64le-linux-gnu" ;;
	*)
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

kernel_arch() {
	local a=${1}

	case "${a}" in
	amd64)		echo "x86_64" ;;
	arm64*)		echo "arm64" ;;
	ppc*)		echo "powerpc" ;;
	*)
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

sudo_write() {
	sudo tee "${1}" >/dev/null
}

sudo_append() {
	sudo tee -a "${1}" >/dev/null
}

is_ip_addr() {
	local host=${1}
	local regex_ip="[[:digit:]]{1,3}\.([[:digit:]]{1,3}/.){3}"

	if [[ "${host}" =~ ${regex_ip} ]]; then
		echo "found name: '${host}'"
		return 1
	fi
	echo "found ip: '${host}'"
	return 0
}

find_addr() {
	local -n _find_addr__addr=${1}
	local hosts_file=${2}
	local host=${3}

	_find_addr__addr=""

	if is_ip_addr "${host}"; then
		_find_addr__addr="${host}"
		return
	fi

	if [[ ! -x "$(command -v dig)" ]]; then
		echo "${script_name}: WARNING: Please install dig (dnsutils)." >&2
	else
		_find_addr__addr="$(dig "${host}" +short)"
	fi

	if [[ ! ${_find_addr__addr} ]]; then
		_find_addr__addr="$(grep -E -m 1 "${host}[[:space:]]*$" "${hosts_file}" \
			| grep -E -o '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' || :)"

		if [[ ! ${_find_addr__addr} ]]; then
			echo "${script_name}: ERROR (${FUNCNAME[0]}): '${host}' DNS entry not found." >&2
			exit 1
		fi
	fi
}

my_addr() {
	ip route get 8.8.8.8 | grep -E -o 'src [0-9.]*' | cut -f 2 -d ' '
}

wait_pid() {
	local pid="${1}"
	local timeout_sec=${2}
	timeout_sec=${timeout_sec:-300}

	echo "${script_name}: INFO: Waiting ${timeout_sec}s for pid ${pid}." >&2

	local count=1
	while kill -0 "${pid}" &> /dev/null; do
		((count = count + 5))
		if [[ count -gt ${timeout_sec} ]]; then
			echo "${script_name}: ERROR (${FUNCNAME[0]}): wait_pid failed for pid ${pid}." >&2
			exit 2
		fi
		sleep 5s
	done
}

git_get_repo_name() {
	local repo=${1}

	if [[ "${repo: -1}" == "/" ]]; then
		repo=${repo:0:-1}
	fi

	local repo_name="${repo##*/}"

	if [[ "${repo_name:0:1}" == "." ]]; then
		repo_name="${repo%/.*}"
		repo_name="${repo_name##*/}"
		echo "${repo_name}"
		return
	fi

	repo_name="${repo_name%.*}"

	if [[ -z "${repo_name}" ]]; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad repo: '${repo}'" >&2
		exit 1
	fi

	echo "${repo_name}"
}

git_set_remote() {
	local dir=${1}
	local repo=${2}
	local remote

	remote="$(git -C "${dir}" remote -v | grep -E --max-count=1 'origin' | cut -f2 | cut -d ' ' -f1)"

	if ! remote="$(git -C "${dir}" remote -v | grep -E --max-count=1 'origin' | cut -f2 | cut -d ' ' -f1)"; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad git repo ${dir}." >&2
		exit 1
	fi

	if [[ "${remote}" != "${repo}" ]]; then
		echo "${script_name}: INFO: Switching git remote '${remote}' => '${repo}'." >&2
		git -C "${dir}" remote set-url origin "${repo}"
		git -C "${dir}" remote -v
	fi
}

git_checkout_force() {
	local dir=${1}
	local repo=${2}
	local branch=${3:-'master'}

	if [[ ! -d "${dir}" ]]; then
		mkdir -p "${dir}/.."
		git clone "${repo}" "${dir}"
	fi

	git_set_remote "${dir}" "${repo}"

	git -C "${dir}" checkout -- .
	git -C "${dir}" remote update -p
	git -C "${dir}" reset --hard origin/"${branch}"
	git -C "${dir}" checkout --force "${branch}"
	git -C "${dir}" pull "${repo}" "${branch}"
	git -C "${dir}" status
}

git_checkout_safe() {
	local dir=${1}
	local repo=${2}
	local branch=${3:-'master'}

	if [[ -e "${dir}" ]]; then
		if [[ ! -e "${dir}/.git/config" ]]; then
			mv "${dir}" "${dir}.backup-$(date +%Y.%m.%d-%H.%M.%S)"
		elif ! git -C "${dir}" status --porcelain; then
			echo "${script_name}: INFO: Local changes: ${dir}." >&2
			cp -a --link "${dir}" "${dir}.backup-$(date +%Y.%m.%d-%H.%M.%S)"
		fi
	fi

	git_checkout_force "${dir}" "${repo}" "${branch}"
}

run_shellcheck() {
	local file=${1}

	shellcheck=${shellcheck:-"shellcheck"}

	if ! test -x "$(command -v "${shellcheck}")"; then
		echo "${script_name}: ERROR: Please install '${shellcheck}'." >&2
		exit 1
	fi

	${shellcheck} "${file}"
}

get_container_id() {
	local cpuset
	cpuset="$(cat /proc/1/cpuset)"
	local regex="^/docker/([[:xdigit:]]*)$"
	local container_id

	if [[ "${cpuset}" =~ ${regex} ]]; then
		container_id="${BASH_REMATCH[1]}"
		echo "${script_name}: INFO: Container ID '${container_id}'." >&2
	else
		echo "${script_name}: WARNING: Container ID not found." >&2
	fi

	echo "${container_id}"
}

ansi_reset='\e[0m'
ansi_red='\e[1;31m'
ansi_green='\e[0;32m'
ansi_blue='\e[0;34m'
ansi_teal='\e[0;36m'

if [[ ${PS4} == '+ ' ]]; then
	if [[ ${JENKINS_URL} ]]; then
		export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '
	else
		export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
	fi
fi

script_name="${script_name:-${0##*/}}"
