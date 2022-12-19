#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace

	local p=''

	if [[ ${password} ]]; then
		p='*******'
	fi

	{
		echo "${script_name} - Adds a TDD jenkins user to the system."
		echo "Usage: ${script_name} [flags]"
		echo "Option flags:"
		echo "  -c --check    - Only run checks then exit."
		echo "  -d --delete   - Delete user '${user}' from system."
		echo "  -e --home     - home. Default: '${home}'."
		echo "  -g --gid      - GID. Default: '${gid}'."
		echo "  -n --np-sudo  - Setup NOPASSWD sudo. Default: '${np_sudo}'."
		echo "  -p --group    - Group. Default: '${group}'."
		echo "  -r --user     - User. Default: '${user}'."
		echo "  -s --sudo     - Setup sudo. Default: '${sudo}'."
		echo "  -u --uid      - UID. Default: '${uid}'."
		echo "  -w --password - Account password. Default: '${p}'."
		echo "  -h --help     - Show this help and exit."
		echo "  -v --verbose  - Verbose execution. Default: '${verbose}'."
		echo "  -x --debug    - Extra verbose execution. Default: '${debug}'."
		echo "Environment:"
		echo "  JENKINS_USER - Default: '${JENKINS_USER}'"
		echo "Info:"
		print_project_info
	} >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts='cde:g:np:r:su:w:lhvx'
	local long_opts='check,delete,home:,gid:,np-sudo,group:,user:,sudo,uid:,password:,help,verbose,debug'

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-c | --check)
			check=1
			shift
			;;
		-d | --delete)
			delete=1
			shift
			;;
		-e | --home)
			home="${2}"
			shift 2
			;;
		-g | --gid)
			gid="${2}"
			shift 2
			;;
		-n | --np-sudo)
			np_sudo=1
			shift
			;;
		-p | --group)
			group="${2}"
			shift 2
			;;
		-r | --user)
			user="${2}"
			shift 2
			;;
		-s | --sudo)
			sudo=1
			shift
			;;
		-u | --uid)
			uid="${2}"
			shift 2
			;;
		-w | --password)
			password="${2}"
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
		-x | --debug)
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

run_checks() {
	local result=''
	local check_msg

	if [[ ${check} ]]; then
		check_msg='INFO'
	else
		check_msg='ERROR'
	fi

	if getent passwd "${user}" &> /dev/null; then
		echo "${script_name}: ${check_msg}: user '${user}' exists." >&2
		echo "${script_name}: ${check_msg}: => $(id "${user}")" >&2
		result=1
	else
		echo "${script_name}: INFO: user '${user}' does not exist." >&2
	fi

	if getent group "${uid}" &> /dev/null; then
		echo "${script_name}: ${check_msg}: uid ${uid} exists." >&2
		result=1
	else
		echo "${script_name}: INFO: uid ${uid} does not exist." >&2
	fi

	if [[ -d ${home} ]]; then
		echo "${script_name}: ${check_msg}: home '${home}' exists." >&2
		result=1
	else
		echo "${script_name}: INFO: home '${home}' does not exist." >&2
	fi

	if getent group "${group}" &> /dev/null; then
		echo "${script_name}: ${check_msg}: group '${group}' exists." >&2
		result=1
	else
		echo "${script_name}: INFO: group '${group}' does not exist." >&2
	fi

	if getent group "${gid}" &> /dev/null; then
		echo "${script_name}: ${check_msg}: gid ${gid} exists." >&2
		result=1
	else
		echo "${script_name}: INFO: gid ${gid} does not exist." >&2
	fi

	if [[ -f "/etc/sudoers.d/${user}" ]]; then
		echo "${script_name}: ${check_msg}: sudoers '/etc/sudoers.d/${user}' exists." >&2
		result=1
	else
		echo "${script_name}: INFO: sudoers '/etc/sudoers.d/${user}' does not exist." >&2
	fi

	if [[ ${result} ]]; then
		return 1
	fi

	echo "${script_name}: INFO: Checks OK." >&2

	return 0
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

# shellcheck source=scripts/tdd-lib/util.sh
source "${SCRIPT_TOP}/tdd-lib/util.sh"

check=''
delete=''
home=''
gid=''
np_sudo=''
group=''
user=''
sudo=''
uid=''
password=''
usage=''
verbose=''
debug=''

process_opts "${@}"

JENKINS_USER="${JENKINS_USER:-}"
user="${user:-${JENKINS_USER}}"
user="${user:-tdd-jenkins}"
uid="${uid:-5522}"

home=${home:-"/home/${user}"}
group=${group:-"${user}"}
gid=${gid:-"${uid}"}

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

if [[ ${delete} ]]; then
	set -x

	userdel "${user}"
	rm -rf "${home}"
	rm -f "/etc/sudoers.d/${user}"s

	trap $'on_exit "Success"' EXIT
	exit 0
fi

echo "${script_name}: NOTE: A seperate TDD jenkins user is no longer needed." >&2
trap - EXIT
exit 0

if ! run_checks; then
	exit 1
fi

if [[ ${check} ]]; then
	trap $'on_exit "Success"' EXIT
	exit 0
fi

sudo true

sudo groupadd --gid="${gid}" "${group}"

sudo useradd --create-home --home-dir="${home}" \
	--uid="${uid}" --gid="${gid}" --groups='docker'  \
	--shell='/bin/bash' "${user}"

if [[ ${sudo} || ${np_sudo} ]]; then
	sudo usermod --append --groups='sudo' "${user}"
fi

if [[ ${np_sudo} ]]; then
	echo "%${user} ALL=(ALL) NOPASSWD:ALL" | sudo_write "/etc/sudoers.d/${user}"
fi

old_xtrace="$(shopt -po xtrace || :)"
set +o xtrace
if [[ ${password} ]]; then
	echo "${user}:${password}" | sudo chpasswd
fi
eval "${old_xtrace}"

trap $'on_exit "Success"' EXIT
exit 0

