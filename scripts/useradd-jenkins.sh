#!/usr/bin/env bash

set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace

	if [[ -z ${password} ]]; then
		local p
	else
		local p='*******'
	fi
	
	echo "${script_name} - Adds a TDD jenkins user to system." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --check    - Only run checks then exit." >&2
	echo "  -d --delete   - Delete user '${user}' from system." >&2
	echo "  -e --home     - home. Default: '${home}'." >&2
	echo "  -g --gid      - GID. Default: '${gid}'." >&2
	echo "  -h --help     - Show this help and exit." >&2
	echo "  -n --np-sudo  - Setup NOPASSWD sudo. Default: '${np_sudo}'." >&2
	echo "  -p --group    - Group. Default: '${group}'." >&2
	echo "  -r --user     - User. Default: '${user}'." >&2
	echo "  -s --sudo     - Setup sudo. Default: '${sudo}'." >&2
	echo "  -u --uid      - UID. Default: '${uid}'." >&2
	echo "  -w --password - Account password. Default: '${p}'." >&2
	echo "Environment:" >&2
	echo "  JENKINS_USER - Default: '${JENKINS_USER}'" >&2
	eval "${old_xtrace}"
}

short_opts="cde:g:hnp:r:su:w:"
long_opts="check,delete,home:,gid:,help,np-sudo,group:,user:,sudo,uid:,password:"
opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

if [ $? != 0 ]; then
	echo "${script_name}: ERROR: Internal getopt" >&2
	exit 1
fi

eval set -- "${opts}"

while true ; do
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
	-h | --help)
		usage=1
		shift
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

user=${user:-"${JENKINS_USER}"}
user=${user:-'tdd-jenkins'}
uid=${uid:-"5522"}

home=${home:-"/home/${user}"}
group=${group:-"${user}"}
gid=${gid:-"${uid}"}

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

run_checks() {
	local result
	local check_msg

	if [[ ${check} ]]; then
		check_msg='INFO'
	else
		check_msg='ERROR'
	fi

	if getent passwd ${user} &> /dev/null; then
		echo "${script_name}: ${check_msg}: user '${user}' exists." >&2
		echo "${script_name}: ${check_msg}: => $(id ${user})" >&2
		result=1
	else
		echo "${script_name}: INFO: user '${user}' does not exist." >&2
	fi

	if getent group ${uid} &> /dev/null; then
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

	if getent group ${group} &> /dev/null; then
		echo "${script_name}: ${check_msg}: group '${group}' exists." >&2
		result=1
	else
		echo "${script_name}: INFO: group '${group}' does not exist." >&2
	fi

	if getent group ${gid} &> /dev/null; then
		echo "${script_name}: ${check_msg}: gid ${gid} exists." >&2
		result=1
	else
		echo "${script_name}: INFO: gid ${gid} does not exist." >&2
	fi

	if [[ -f /etc/sudoers.d/${user} ]]; then
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

if [[ ${delete} ]]; then
	set -x
	
	userdel ${user}
	rm -rf ${home}
	rm -f /etc/sudoers.d/${user}

	exit 0
fi

result=$(run_checks)

if [[ ${result} ]]; then
	exit 1
fi

if [[ ${check} ]]; then
	exit 0
fi

set -x

groupadd --gid=${gid} ${group}
useradd --create-home --home-dir=${home} \
	--uid=${uid} --gid=${gid} --groups='docker'  \
	--shell=/bin/bash ${user}

if [[ ${sudo} || ${np_sudo} ]]; then
	usermod --append --groups='sudo' ${user}
fi

if [[ ${np_sudo} ]]; then
	echo "%${user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${user}
fi

if [[ ${no_lecture} ]]; then # TODO
	echo 'Defaults lecture = never' > /etc/sudoers.d/lecture
fi

old_xtrace="$(shopt -po xtrace || :)"
set +o xtrace
if [[ -n ${password} ]]; then
	echo "${user}:${password}" | chpasswd
fi
eval "${old_xtrace}"

echo "${script_name}: INFO: Done OK." >&2
