#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Run Linux kernel in QEMU." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch              - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --kernel-cmd        - Kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  -e --ether-mac         - QEMU Ethernet MAC. Default: '${ether_mac}'." >&2
	echo "  -f --hostfwd-offset    - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  -h --help              - Show this help and exit." >&2
	echo "  -i --initrd            - Initrd image. Default: '${initrd}'." >&2
	echo "  -k --kernel            - Kernel image. Default: '${kernel}'." >&2
# TODO	echo "  -m --modules           - Kernel modules directory.  To mount over existing modules directory. Default: '${modules}'." >&2
	echo "  -o --out-file          - stdout, stderr redirection file. Default: '${out_file}'." >&2
# TODO	echo "  -r --disk-image        - Raw disk image.  Alternative to --initrd. Default: '${disk_image}'." >&2
	echo "  -s --systemd-debug     - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -t --qemu-tap          - Use QEMU tap networking. Default: '${qemu_tap}'." >&2
	echo "  -v --verbose           - Verbose execution." >&2
	echo "  --hda                  - QEMU IDE hard disk image hda. Default: '${hda}'." >&2
	echo "  --hdb                  - QEMU IDE hard disk image hdb. Default: '${hdb}'." >&2
	echo "  --hdc                  - QEMU IDE hard disk image hdc. Default: '${hdc}'." >&2
	echo "  --pid-file             - QEMU IDE hard disk image hdb. Default: '${pid_file}'." >&2
	echo "  --p9-share             - Plan9 share directory. Default: '${p9_share}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:c:e:f:hi:k:m:o:r:stv"
	local long_opts="arch:,kernel-cmd:,ether-mac:,hostfwd-offset:,help,initrd:,\
kernel:,modules:,out-file:,disk-image:,systemd-debug,qemu-tap,verbose,\
hda:,hdb:,hdc:,pid-file:,p9-share:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	if [ $? != 0 ]; then
		echo "${script_name}: ERROR: Internal getopt" >&2
		exit 1
	fi

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-a | --arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		-c | --kernel-cmd)
			kernel_cmd="${2}"
			shift 2
			;;
		-e | --ether-mac)
			ether_mac="${2}"
			shift 2
			;;
		-f | --hostfwd-offset)
			hostfwd_offset="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-i | --initrd)
			initrd="${2}"
			shift 2
			;;
		-k | --kernel)
			kernel="${2}"
			shift 2
			;;
		-m | --modules)
			modules="${2}"
			shift 2
			;;
		-o | --out-file)
			out_file="${2}"
			shift 2
			;;
		-r | --disk-image)
			disk_image="${2}"
			shift 2
			;;
		-s | --systemd-debug)
			systemd_debug=1
			shift
			;;
		-t | --qemu-tap)
			qemu_tap=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--hda)
			hda="${2}"
			shift 2
			;;
		--hdb)
			hdb="${2}"
			shift 2
			;;
		--hdc)
			hdc="${2}"
			shift 2
			;;
		--pid-file)
			pid_file="${2}"
			shift 2
			;;
		--p9-share)
			p9_share="${2}"
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
}

setup_efi() {
	local efi_code_src
	local efi_vars_src
	local efi_full_src

	case "${target_arch}" in
	amd64)
		efi_code_src="/usr/share/OVMF/OVMF_CODE.fd"
		efi_vars_src="/usr/share/OVMF/OVMF_VARS.fd"
		efi_full_src="/usr/share/ovmf/OVMF.fd"
		;;
	arm64)
		efi_code_src="/usr/share/AAVMF/AAVMF_CODE.fd"
		efi_vars_src="/usr/share/AAVMF/AAVMF_VARS.fd"
		efi_full_src="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
		;;
	esac

	efi_code="${efi_code_src}"
	efi_vars="${target_arch}-EFI_VARS.fd"

	check_file ${efi_code_src}
	check_file ${efi_vars_src}

	copy_file ${efi_vars_src} ${efi_vars}
}

on_exit() {
	local result=${1}

	echo "${script_name}: Done: ${result}" >&2
	exit ${result}
}

#===============================================================================
# program start
#===============================================================================
script_name="${0##*/}"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}
source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

TARGET_HOSTNAME=${TARGET_HOSTNAME:-"tdd-tester"}

MODULES_ID=${MODULES_ID:-"kernel_modules"}
P9_SHARE_ID=${SHARE_ID:-"p9_share"}

host_arch=$(get_arch "$(uname -m)")
target_arch=${target_arch:-"${host_arch}"}
hostfwd_offset=${hostfwd_offset:-"20000"}
ether_mac=${ether_mac:-"01:02:03:00:00:01"}

if [[ ${systemd_debug} ]]; then
	# FIXME: need to run set-systemd-debug.sh???
	kernel_cmd+=" systemd.log_level=debug systemd.log_target=console systemd.journald.forward_to_console=1"
fi

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

case ${target_arch} in
arm64|ppc*)
	;;
*)
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
	;;
esac

if [[ ! ${kernel} ]]; then
	echo "${script_name}: ERROR: Must provide --kernel option." >&2
	usage
	exit 1
fi

check_file "${kernel}"

if [[ ! ${initrd} && ! ${disk_image} ]]; then
	echo "${script_name}: ERROR: Must provide --initrd or --disk-image option." >&2
	usage
	exit 1
fi

if [[ ${initrd} ]]; then
	check_file "${initrd}"
fi

if [[ ${disk_image} ]]; then
	check_file "${disk_image}"
	disk_image_root="/dev/vda"
fi

if [[ ${modules} ]]; then
	check_directory "${modules}"
fi


qemu_args="-kernel ${kernel}"
qemu_append_args="${kernel_cmd}"

case "${host_arch}--${target_arch}" in
amd64--amd64)
	have_efi=1
	qemu_exe="qemu-system-x86_64"
	qemu_args+=" -machine accel=kvm -cpu host -m 2048 -smp 2"
	;;
arm64--amd64)
	have_efi=1
	qemu_exe="qemu-system-x86_64"
	qemu_args+=" -machine pc-q35-2.8 -cpu kvm64 -m 2048 -smp 2"
	;;
amd64--arm64)
	have_efi=1
	qemu_exe="qemu-system-aarch64"
	#qemu_mem=${qemu_mem:-5120} # 5G
	qemu_mem=${qemu_mem:-6144} # 6G
	#qemu_mem=${qemu_mem:-16384} # 16G
	qemu_args+=" -machine virt,gic-version=3 -cpu cortex-a57 -m ${qemu_mem} -smp 2"
	;;
arm64--arm64)
	have_efi=1
	qemu_exe="qemu-system-aarch64"
	qemu_args+=" -machine virt,gic-version=3,accel=kvm -cpu host -m 4096 -smp 2"
	;;
amd64--ppc*)
	unset have_efi
	qemu_exe="qemu-system-ppc64"
	#qemu_args+=" -machine cap-htm=off -m 2048"
	#qemu_args+=" -machine pseries,cap-htm=off -m 2048"
	qemu_args+=" -machine pseries,cap-htm=off -m 2048 -append 'root=/dev/ram0 console=hvc0'"
	;;
*)
	echo "${script_name}: ERROR: Unsupported host--target combo: '${host_arch}--${target_arch}'." >&2
	exit 1
	;;
esac

nic_model=${nic_model:-"virtio-net-pci"}

if [[ ${qemu_tap} ]]; then
	qemu_args+=" \
	-netdev tap,id=tap0,ifname=qemu0,br=br0 \
	-device ${nic_model},netdev=tap0,mac=${ether_mac} \
	"
else
	ssh_fwd=$(( ${hostfwd_offset} + 22 ))
	echo "${script_name}: SSH fwd = ${ssh_fwd}" >&2

	# FIXME: When is -nic unsupported?
	if [[ ${use_virtio_net} ]]; then
		#virtio_net_type="virtio-net-device"
		virtio_net_type="virtio-net-pci"
		qemu_args+=" -netdev user,id=eth0,hostfwd=tcp::${ssh_fwd}-:22,hostname=${TARGET_HOSTNAME}"
		qemu_args+=" -device ${virtio_net_type},netdev=eth0"
	else
		qemu_args+=" -nic user,model=${nic_model},hostfwd=tcp::${ssh_fwd}-:22,hostname=${TARGET_HOSTNAME}"
	fi
fi

if [[ ${initrd} ]]; then
	qemu_args+=" -initrd ${initrd}"
fi

if [[ ${hda} ]]; then
	qemu_args+=" -hda ${hda}"
fi

if [[ ${hdb} ]]; then
	qemu_args+=" -hdb ${hdb}"
fi

if [[ ${hdc} ]]; then
	qemu_args+=" -hdc ${hdc}"
fi

if [[ ${p9_share} ]]; then
	check_directory "${p9_share}"
	qemu_args+=" \
		-virtfs local,id=${P9_SHARE_ID},path=${p9_share},security_model=none,mount_tag=${P9_SHARE_ID}"
	echo "${script_name}: INFO: 'mount -t 9p -o trans=virtio ${P9_SHARE_ID} <mount-point> -oversion=9p2000.L'" >&2
fi

if [[ ${modules} ]]; then
	qemu_args+=" \
		-virtfs local,id=${MODULES_ID},path=${modules},security_model=none,mount_tag=${MODULES_ID}"
fi

if [[ ${disk_image} ]]; then # TODO
	qemu_args+=" \
		-drive if=none,id=blk,file=${disk_image}   \
		-device virtio-blk-device,drive=blk \
	"
	qemu_append_args+=" root=${disk_image_root} rw"
fi

if [[ ${out_file} ]]; then
	qemu_args+=" \
		-display none \
		-chardev file,id=char0,path=${out_file} \
		-serial chardev:char0 \
	"
else
	qemu_args+=" -nographic"
fi

if [[ ${pid_file} ]]; then
	qemu_args+=" -pidfile ${pid_file}"
fi

if [[ ${have_efi} ]]; then
	setup_efi
	qemu_args+=" -drive if=pflash,file=${efi_code},format=raw,readonly"
	qemu_args+=" -drive if=pflash,file=${efi_vars},format=raw"
fi

ls -l /dev/kvm || :
cat /etc/group || :
id

cmd="${qemu_exe} \
	-name tdd-vm \
	-object rng-random,filename=/dev/urandom,id=rng0 \
	-device virtio-rng-pci,rng=rng0 \
	${qemu_args} \
	-append '${qemu_append_args}' \
"

eval exec "${cmd}"
