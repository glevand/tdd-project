#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Upload Fedora netboot installer to tftp server." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --config-file - Config file. Default: '${config_file}'." >&2
	echo "  -h --help        - Show this help and exit." >&2
	echo "  -o --host        - Target host. Default: '${host}'." >&2
	echo "  -r --release     - Debian release. Default: '${release}'." >&2
	echo "  -s --tftp-server - TFTP server. Default: '${tftp_server}'." >&2
	echo "  -t --type        - Release type {$(clean_ws ${types})}." >&2
	echo "                     Default: '${type}'." >&2
	echo "  -v --verbose     - Verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="c:hors:t:v"
	local long_opts="config-file:,help,host:,release:,tftp-server:,type:,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-o | --host)
			host="${2}"
			shift 2
			;;
		-r | --release)
			release="${2}"
			shift 2
			;;
		-s | --tftp-server)
			tftp_server="${2}"
			shift 2
			;;
		-t | --type)
			type="${2}"
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

	echo "${script_name}: Done: ${result}" >&2
}


download_fedora_files() {
	local cmd
	local dir
        local ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"


	if [[ ${tftp_server} == "localhost" ]]; then
		cmd=''
		dir="$(pwd)"
		cp ${JENKINS_TOP}/jobs/distro/fedora/${type}-qemu.ks ./f_kickstart
	else
		cmd="ssh ${tftp_server} ${ssh_no_check} "
		dir="/var/tftproot/${host}"
		sudo scp ${ssh_no_check} ${JENKINS_TOP}/jobs/distro/fedora/${type}-qemu.ks ${tftp_server}:${dir}/f_kickstart
	fi

	set +e

        ${cmd} env dir=${dir} f_initrd=${f_initrd} f_kernel=${f_kernel}  bash -s <<'EOF'

set -ex

if [[ -f ${dir}/f_initrd \
	&& -f ${dir}/f_kernel ]]; then
	mv -f ${dir}/f_initrd ${dir}/f_initrd.old
	mv -f ${dir}/f_kernel ${dir}/f_kernel.old
fi

curl --silent --show-error --location ${f_initrd} > ${dir}/f_initrd
curl --silent --show-error --location ${f_kernel} > ${dir}/f_kernel

sum1=$(md5sum "${dir}/f_initrd" "${dir}/f_kernel" | cut -f 1 -d ' ')
sum2=$(md5sum "${dir}/f_initrd.old" "${dir}/f_kernel.old" | cut -f 1 -d ' ')

set +e

if [[ "${sum1}" != "${sum2}" ]]; then
        exit 0
else
        exit 1
fi

EOF

return ${?}

}

#===============================================================================
# program start
#===============================================================================

script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}
JENKINS_TOP=${DOCKER_TOP:-"$( cd "${SCRIPTS_TOP}/../jenkins" && pwd )"}


trap "on_exit 'failed.'" EXIT
set -e

source "${SCRIPTS_TOP}/tdd-lib/util.sh"

process_opts "${@}"

config_file="${config_file:-${SCRIPTS_TOP}/upload.conf-sample}"

check_file ${config_file} " --config-file" "usage"
source ${config_file}

if [[ ! ${tftp_server} ]]; then
	echo "${script_name}: ERROR: No tftp_server entry: '${config_file}'" >&2
	usage
	exit 1
fi

if [[ ! ${host} ]]; then
	echo "${script_name}: ERROR: No host entry: '${config_file}'" >&2
	usage
	exit 1
fi

types="
	f28
	f30
	daily?
	rawhide?
"

type=${type:-"f30"}

case "${type}" in
f30 | f28 )
	
	f_url="https://download.fedoraproject.org/pub/fedora/linux/releases/${type#f}/Server/aarch64"
	f_initrd="${f_url}/os/images/pxeboot/initrd.img"
	f_kernel="${f_url}/os/images/pxeboot/vmlinuz"
	;;
daily)
	release="daily"
	files_url="https://d-i.debian.org/daily-images/arm64/${release}/netboot/debian-installer/arm64"
	sums_url="https://d-i.debian.org/daily-images/arm64/${release}"
	;;
sid)
	echo "${script_name}: ERROR: No sid support yet." >&2
	exit 1
	;;
*)
	echo "${script_name}: ERROR: Unknown type '${type}'" >&2
	usage
	exit 1
	;;
esac

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

download_fedora_files

result=${?}

set -e

echo "${script_name}: ${host} files ready on ${tftp_server}." >&2

trap "on_exit 'success.'" EXIT

if [[ ${result} -ne 0 ]]; then
	echo "No new files" >&2
	exit 1
else
	echo "need test" >&2
	exit 0
fi
