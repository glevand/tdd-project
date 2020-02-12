#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Upload Debian netboot installer to tftp server." >&2
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
	buster
	daily
	sid
"

type=${type:-"buster"}

case "${type}" in
buster)
	release="current"
	files_url="http://ftp.nl.debian.org/debian/dists/buster/main/installer-arm64/${release}/images/netboot/debian-installer/arm64"
	sums_url="http://ftp.nl.debian.org/debian/dists/buster/main/installer-arm64/${release}/images/"
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

ssh ${tftp_server} ls -l /var/tftproot/${host}

ssh ${tftp_server} host=${host} files_url=${files_url} sums_url=${sums_url} 'bash -s' <<'EOF'

set -e

if [[ -f /var/tftproot/${host}/tdd-initrd \
	&& -f /var/tftproot/${host}/tdd-kernel ]]; then
	mv -f /var/tftproot/${host}/tdd-initrd /var/tftproot/${host}/tdd-initrd.old
	mv -f /var/tftproot/${host}/tdd-kernel /var/tftproot/${host}/tdd-kernel.old
fi

wget --no-verbose -O /var/tftproot/${host}/tdd-initrd ${files_url}/initrd.gz
wget --no-verbose -O /var/tftproot/${host}/tdd-kernel ${files_url}/linux
wget --no-verbose -O /tmp/di-sums ${sums_url}/MD5SUMS

echo "--- initrd ---"
[[ -f /var/tftproot/${host}/tdd-initrd.old ]] && md5sum /var/tftproot/${host}/tdd-initrd.old
md5sum /var/tftproot/${host}/tdd-initrd
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/initrd.gz'
echo "--- kernel ---"
[[ -f /var/tftproot/${host}/tdd-kernel.old ]] && md5sum /var/tftproot/${host}/tdd-kernel.old
md5sum /var/tftproot/${host}/tdd-kernel
cat /tmp/di-sums | egrep 'netboot/debian-installer/arm64/linux'
echo "---------"

EOF

echo "${script_name}: ${host} files ready on ${tftp_server}." >&2

trap "on_exit 'success.'" EXIT
exit 0

