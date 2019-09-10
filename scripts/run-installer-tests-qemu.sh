#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Run Linux installer tests in QEMU." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags general:" >&2
	echo "  -h --help        - Show this help and exit." >&2
	echo "  -v --verbose     - Verbose execution." >&2

	echo "  --arch           - Target architecture. Default: '${target_arch}'." >&2
	echo "  --hda            - QEMU IDE hard disk image hda. Default: '${hda}'." >&2
	echo "  --hostfwd-offset - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  --out-file       - stdout, stderr redirection file. Default: '${out_file}'." >&2
	echo "  --result-file    - Result file. Default: '${result_file}'." >&2
	echo "  --ssh-key        - SSH private key file. Default: '${ssh_key}'." >&2
	echo "  --systemd-debug  - Run systemd with debug options. Default: '${systemd_debug}'." >&2

	echo "Option flags for installer:" >&2
	echo "  --distro         - Linux distribution type: {$(clean_ws ${known_distro_types})}. Default: '${distro}'." >&2
	echo "  --control-file   - Installer automated control file (preseed, kickstart, autoinst.xml). Default: '${control_file}'." >&2
	echo "  --kernel         - Installer kernel image. Default: '${kernel}'." >&2
	echo "  --kernel-cmd     - Installer kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  --initrd         - Installer initrd image. Default: '${initrd}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="\
help,\
verbose,\
\
arch:,\
hda:,\
hostfwd-offset:,\
out-file:,\
result-file:,\
ssh-key:,\
systemd-debug,\
\
distro:,\
control-file:,\
kernel:,\
kernel-cmd:,\
initrd:,\
"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#Secho "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;

		--arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		--hda)
			hda="${2}"
			shift 2
			;;
		--hostfwd-offset)
			hostfwd_offset="${2}"
			shift 2
			;;
		--out-file)
			out_file="${2}"
			shift 2
			;;
		--result_file)
			result_file="${2}"
			shift 2
			;;
		--ssh-key)
			ssh_key="${2}"
			shift 2
			;;
		--systemd-debug)
			systemd_debug=1
			shift
			;;

		--distro)
			distro="${2}"
			shift 2
			;;
		--control-file)
			control_file="${2}"
			shift 2
			;;
		--kernel)
			kernel="${2}"
			shift 2
			;;
		--initrd)
			initrd="${2}"
			shift 2
			;;
		--kernel-cmd)
			kernel_cmd="${2}"
			shift 2
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${script_name}: ERROR: Found extra opts: '${@}'" >&2
				usage
				exit 1
			fi
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

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo '*** on_exit ***'
	echo "*** result   = ${result}" >&2
	echo "*** qemu_pid = ${qemu_pid}" >&2
	echo "*** up time  = $(sec_to_min ${SECONDS}) min" >&2
	eval "${old_xtrace}"

	if [[ -n "${qemu_pid}" ]]; then
		sudo kill ${qemu_pid} || :
		wait ${qemu_pid}
		qemu_pid=''
	fi

	if [[ -d ${installer_extra_mnt} ]]; then
		sudo umount ${installer_extra_mnt} || :
		rm -rf ${installer_extra_mnt} || :
		unset installer_extra_mnt
	fi
	
	if [[ -f "${installer_extra_img}" ]]; then
		rm -f ${installer_extra_img}
		unset installer_extra_img
	fi

	if [[ -d ${tmp_dir} ]]; then
		${sudo} rm -rf ${tmp_dir}
	fi

	echo "${script_name}: ${result}" >&2
}

make_installer_extra_img() {
	installer_extra_img="$(mktemp --tmpdir installer_extra_img.XXXX)"
	installer_extra_mnt="$(mktemp --tmpdir --directory installer_extra_mnt.XXXX)"

	local installer_extra_file
	installer_extra_file="${installer_extra_mnt}/${control_file##*/}"

	dd if=/dev/zero of="${installer_extra_img}" bs=1M count=1
	mkfs.vfat "${installer_extra_img}"

	sudo mount -o rw,uid=$(id -u),gid=$(id -g) "${installer_extra_img}" "${installer_extra_mnt}"

	cp -v "${control_file}" "${installer_extra_file}"

	if [[ ${ssh_key} ]]; then
		sed --in-place "s|@@ssh-keys@@|$(cat ${ssh_key}.pub)|" "${installer_extra_file}"
	fi

	{
		echo ''
		echo '---------'
		echo 'control_file'
		echo '---------'
		cat ""${control_file}""
		echo '---------'
	} >> "${result_file}"

	sudo umount "${installer_extra_mnt}"
	rmdir -v "${installer_extra_mnt}"
	unset installer_extra_mnt
}

start_qemu_with_kernel() {
	local out_file=${1}

	ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${script_name}: SSH fwd port = ${ssh_fwd}" >&2

	${SCRIPTS_TOP}/start-qemu.sh \
		--verbose \
		--arch="${target_arch}" \
		--hostfwd-offset="${hostfwd_offset}" \
		--out-file="${out_file}" \
		--pid-file="${qemu_pid_file}" \
		--kernel="${kernel}" \
		--kernel-cmd="${kernel_cmd}" \
		--initrd="${initrd}" \
		--hda="${hda}" \
		--hdb="${installer_extra_img}" \
		${systemd_debug:+--systemd-debug} \
		</dev/null &>> "${out_file}" &
}

start_qemu_with_hda() {
	local out_file=${1}

        ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${script_name}: SSH fwd port = ${ssh_fwd}" >&2

        ${SCRIPTS_TOP}/start-qemu.sh \
                --verbose \
                --arch="${target_arch}" \
                --hostfwd-offset="${hostfwd_offset}" \
                --out-file="${out_file}" \
                --pid-file="${qemu_pid_file}" \
                --hda-boot \
                --hda="${hda}" \
		${systemd_debug:+--systemd-debug} \
                </dev/null &>> "${out_file}" &
}

wait_for_qemu_start () {
	local stage_name=${1}
	local stage_wait=${2}\
	local start_time=${SECONDS}

	echo "${script_name}: Waiting for ${stage_name} QEMU startup..." >&2
	sleep ${stage_wait}

	{
		echo "vvvv ${stage_name} startup vvvv"
		cat "${out_file}.start-${stage_name}"
		echo '---------------------------'
		ps aux
		echo "^^^^ ${stage_name} startup ^^^^"
	} >&2

	if [[ ! -f ${qemu_pid_file} ]]; then
		echo "${script_name}: ERROR: ${stage_name} QEMU seems to have quit early (no pid file)." >&2
		exit 1
	fi

	qemu_pid=$(cat ${qemu_pid_file})

	if ! kill -0 ${qemu_pid} &> /dev/null; then
		echo "${script_name}: ERROR: ${stage_name} QEMU seems to have quit early (no pid)." >&2
		exit 1
	fi

	local duration=$((SECONDS - start_time))
	echo "${script_name}: ${stage_name} boot time: ${duration} sec ($(sec_to_min ${duration}) min)" >&2
}

#===============================================================================
# program start
#===============================================================================
script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

trap "on_exit 'failed.'" EXIT
set -e

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/relay.sh

host_arch=$(get_arch "$(uname -m)")

known_distro_types="
	debian
	fedora
	opensuse
	sle
	ubuntu
"

process_opts "${@}"

target_arch=${target_arch:-"${host_arch}"}
hostfwd_offset=${hostfwd_offset:-"20000"}

if [[ "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ "${target_arch}" != "arm64" ]]; then
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
fi

check_opt 'distro' ${distro}

check_opt 'control_file' ${control_file}
check_file "${control_file}"

check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

check_opt 'hda' ${hda}
check_file "${hda}"

case "${distro}" in
fedora)
	inst_repo="$(egrep '^url[[:space:]]*--url=' ${control_file} | cut -d '=' -f 2 | sed 's/"//g')"
	kernel_cmd+=" inst.text inst.repo=${inst_repo} inst.ks=hd:vdb:${control_file##*/}"
	;;
opensuse)
	kernel_cmd+=" autoyast=device://vdb/${control_file##*/}"
	;;
	
debian | sle | ubuntu)
	echo "${name}: ERROR, TODO: No Support yet '${distro}'" >&2
	exit 1
	;;
*)
	echo "${name}: ERROR: Unknown distro type '${distro}'" >&2
	usage
	exit 1
	;;
esac

if [[ ! ${out_file} ]]; then
	out_file="${script_name}-out.txt"
fi

if [[ ! ${result_file} ]]; then
	result_file="${script_name}-result.txt"
fi

if [[ ${ssh_key} ]]; then
	check_file ${ssh_key} " ssh-key" "usage"
fi

rm -f ${out_file} ${out_file}.start ${result_file}

{
	echo '--------'
	echo 'printenv'
	echo '--------'
	printenv
	echo '---------'
} >> ${result_file}

tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"

make_installer_extra_img

qemu_pid_file=${tmp_dir}/qemu-pid

SECONDS=0

stage_name="installer"

start_qemu_with_kernel "${out_file}.start-${stage_name}"
wait_for_qemu_start "${stage_name}" 120

echo "${script_name}: Waiting for ${stage_name} QEMU exit..." >&2
wait_pid ${qemu_pid} 3600

stage_name="first-boot"

start_qemu_with_hda "${out_file}.start-${stage_name}"
wait_for_qemu_start "${stage_name}" 120

user_qemu_host="root@localhost"
user_qemu_ssh_opts="-o Port=${ssh_fwd}"
ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

ssh ${ssh_no_check} -i ${ssh_key} ${user_qemu_ssh_opts} ${user_qemu_host} \
        '/sbin/poweroff &'

echo "${script_name}: Waiting for ${stage_name} QEMU exit..." >&2
wait_pid ${qemu_pid} 180

echo "${script_name}: Boot time: $(sec_to_min ${SECONDS}) min" >&2

trap - EXIT
on_exit 'Done, success.'
