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
	local dl_root

	if [[ ${tftp_server} == "localhost" ]]; then
		cmd=''
		dl_root="$(pwd)"
	else
		cmd="ssh ${tftp_server} "
		dl_root="/var/tftproot"
	fi

	${cmd} ls -l ${dl_root}/${host}

	${cmd} dl_root=${dl_root} host=${host} files_url=${files_url} sums_url=${sums_url} 'bash -s' <<'EOF'

set -e

if [[ -f ${dl_root}/${host}/tdd-initrd \
	&& -f ${dl_root}/${host}/tdd-kernel ]]; then
	mv -f ${dl_root}/${host}/tdd-initrd ${dl_root}/${host}/tdd-initrd.old
	mv -f ${dl_root}/${host}/tdd-kernel ${dl_root}/${host}/tdd-kernel.old
fi

curl --silent --show-error --location ${f30_initrd} > ${dir}/f_initrd
curl --silent --show-error --location ${f30_kernel} > ${dir}/f_kernel

wget --no-verbose -O ${dl_root}/${host}/tdd-initrd ${dl_initrd}
wget --no-verbose -O ${dl_root}/${host}/tdd-kernel ${dl_kernel}
wget --no-verbose -O /tmp/di-sums ${sums_url}/MD5SUMS

echo "--- initrd ---"
[[ -f ${dl_root}/${host}/tdd-initrd.old ]] && md5sum ${dl_root}/${host}/tdd-initrd.old
md5sum ${dl_root}/${host}/tdd-initrd
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/initrd.gz'
echo "--- kernel ---"
[[ -f ${dl_root}/${host}/tdd-kernel.old ]] && md5sum ${dl_root}/${host}/tdd-kernel.old
md5sum ${dl_root}/${host}/tdd-kernel
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/linux'
echo "---------"

EOF
}

#===============================================================================
# program start
#===============================================================================

script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

trap "on_exit 'failed.'" EXIT
set -e

source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

config_file="${config_file:-${SCRIPTS_TOP}/upload.conf}"

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
f30)
	
	dl_url="https://download.fedoraproject.org/pub/fedora/linux/releases/${type}/Server/aarch64"
	dl_initrd="${dl_url}/os/images/pxeboot/initrd.img"
	dl_kernel="${dl_url}/os/images/pxeboot/vmlinuz"
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

echo "${script_name}: ${host} files ready on ${tftp_server}." >&2

trap "on_exit 'success.'" EXIT
exit 0

