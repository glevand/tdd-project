#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Runs a tdd container.  If no command is provided, runs an interactive container." >&2
	echo "Usage: ${script_name} [flags] -- [command] [args]" >&2
	echo "Option flags:" >&2
	echo "  -a --docker-args    - Args for docker run. Default: '${docker_args}'" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -n --container-name - Container name. Default: '${container_name}'." >&2
	echo "  -t --tag            - Print Docker tag to stdout and exit." >&2
	echo "  -r --as-root        - Run as root user." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "Args:" >&2
	echo "  command             - Default: '${user_cmd}'" >&2
	echo "Environment:" >&2
	echo "  DOCKER_TAG          - Default: '${DOCKER_TAG}'" >&2
	echo "  TDD_CHECKOUT_SERVER - Default: '${TDD_CHECKOUT_SERVER}'" >&2
	echo "  TDD_CHECKOUT_PORT   - Default: '${TDD_CHECKOUT_PORT}'" >&2
	echo "  TDD_RELAY_SERVER    - Default: '${TDD_RELAY_SERVER}'" >&2
	echo "  TDD_RELAY_PORT      - Default: '${TDD_RELAY_PORT}'" >&2
	echo "  TDD_TFTP_SERVER     - Default: '${TDD_TFTP_SERVER}'" >&2
	echo "  TDD_TFTP_USER       - Default: '${TDD_TFTP_USER}'" >&2
	echo "  TDD_TFTP_ROOT       - Default: '${TDD_TFTP_ROOT}'" >&2
	echo "Examples:" >&2
	echo "  ${script_name} -v" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:hn:trv"
	local long_opts="docker-args:,help,container-name:,tag,as-root,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	if [ $? != 0 ]; then
		echo "${script_name}: ERROR: Internal getopt" >&2
		exit 1
	fi

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-a | --docker-args)
			docker_args="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-n | --container-name)
			container_name="${2}"
			shift 2
			;;
		-t | --tag)
			tag=1
			shift
			;;
		-r | --as-root)
			as_root=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--)
			shift
			user_cmd="${@}"
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

add_server() {
	local server=${1}
	local addr

	if ! is_ip_addr ${server}; then
		find_addr addr "/etc/hosts" ${server}
		docker_extra_args+=" --add-host ${server}:${addr}"
	fi
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
script_name="${0##*/}"

if [ ${TDD_BUILDER} ]; then
	echo "${script_name}: ERROR: Already in tdd-builder." >&2
	exit 1
fi

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}
source ${SCRIPTS_TOP}/lib/util.sh

trap "on_exit 'Done, failed.'" EXIT
set -e

DOCKER_TOP=${DOCKER_TOP:-"$( cd "${SCRIPTS_TOP}/../docker" && pwd )"}
DOCKER_TAG=${DOCKER_TAG:-"$("${DOCKER_TOP}/builder/build-builder.sh" --tag)"}

process_opts "${@}"

docker_extra_args=""
container_name=${container_name:-"tdd-builder"}
user_cmd=${user_cmd:-"/bin/bash"}

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${tag} ]]; then
	echo "${DOCKER_TAG}"
	exit 0
fi

if [[ ! ${TDD_CHECKOUT_SERVER} ]]; then
	echo "${script_name}: ERROR: TDD_CHECKOUT_SERVER not defined." >&2
	usage
	exit 1
fi
if [[ ! ${TDD_RELAY_SERVER} ]]; then
	echo "${script_name}: ERROR: TDD_RELAY_SERVER not defined." >&2
	usage
	exit 1
fi
if [[ ! ${TDD_TFTP_SERVER} ]]; then
	echo "${script_name}: ERROR: TDD_TFTP_SERVER not defined." >&2
	usage
	exit 1
fi

if [[ ! ${SSH_AUTH_SOCK} ]]; then
	echo "${script_name}: ERROR: SSH_AUTH_SOCK not defined." >&2
fi

if ! echo "${docker_args}" | grep -q ' -w '; then
	docker_extra_args+=" -v $(pwd):/work -w /work"
fi

if [[ ! ${as_root} ]]; then
	docker_extra_args+=" \
	-u $(id --user --real):$(id --group --real) \
	-v ${HOME}/.ssh:${HOME}/.ssh:ro \
	-v /etc/group:/etc/group:ro \
	-v /etc/passwd:/etc/passwd:ro \
	-v /etc/shadow:/etc/shadow:ro \
	-v /dev:/dev"
fi

add_server ${TDD_CHECKOUT_SERVER}
add_server ${TDD_RELAY_SERVER}
add_server ${TDD_TFTP_SERVER}

echo "${script_name}: ${TDD_TARGET_BMC_LIST} = '${TDD_TARGET_BMC_LIST}'." >&2

for s in ${TDD_TARGET_BMC_LIST}; do
	add_server ${s}
done

if egrep '127.0.0.53' /etc/resolv.conf; then
	docker_extra_args+=" --dns 127.0.0.53"
fi

eval "docker run \
	--rm \
	-it \
	--device /dev/kvm \
	--privileged \
	--network host \
	--name ${container_name} \
	--hostname ${container_name} \
	--add-host ${container_name}:127.0.0.1 \
	-v ${SSH_AUTH_SOCK}:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	--group-add $(stat --format=%g /var/run/docker.sock) \
	--group-add $(stat --format=%g /dev/kvm) \
	--group-add sudo \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-e TDD_CHECKOUT_SERVER \
	-e TDD_CHECKOUT_PORT \
	-e TDD_RELAY_SERVER \
	-e TDD_RELAY_PORT \
	-e TDD_TFTP_SERVER \
	-e TDD_TFTP_USER \
	-e TDD_TFTP_ROOT \
	${docker_extra_args} \
	${docker_args} \
	${DOCKER_TAG} \
	${user_cmd}"

trap - EXIT
on_exit 'Done, success.'
