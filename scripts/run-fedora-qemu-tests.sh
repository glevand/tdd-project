#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Run Fedora install test in QEMU." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch           - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --kernel-cmd     - Kernel command line options. Default: '${kernel_cmd}'." >&2
	echo "  -f --hostfwd-offset - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -o --out-file       - stdout, stderr redirection file. Default: '${out_file}'." >&2
	echo "  -s --systemd-debug  - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  --hda               - QEMU IDE hard disk image hda. Default: '${hda}'." >&2
	echo "  --initrd            - Initrd image. Default: '${initrd}'." >&2
	echo "  --kickstart         - Fedora kickstart file. Default: '${kickstart}'." >&2
	echo "  --kernel            - Kernel image. Default: '${kernel}'." >&2
	echo "  --result-file       - Result file. Default: '${result_file}'." >&2
	echo "  --ssh-key           - SSH private key file. Default: '${ssh_key}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:c:f:ho:sv"
	local long_opts="arch:,kernel-cmd:,hostfwd-offset:,help,out-file:,systemd-debug,\
verbose,hda:,initrd:,kickstart:,kernel:,result-file:,ssh-key:"

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
		-f | --hostfwd-offset)
			hostfwd_offset="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-o | --out-file)
			out_file="${2}"
			shift 2
			;;
		-s | --systemd-debug)
			systemd_debug=1
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
		--initrd)
			initrd="${2}"
			shift 2
			;;
		--kickstart)
			kickstart="${2}"
			shift 2
			;;
		--kernel)
			kernel="${2}"
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

	if [[ -d ${ks_mnt} ]]; then
		sudo umount ${ks_mnt} || :
		rm -rf ${ks_mnt} || :
		ks_mnt=''
	fi
	
	if [[ -f "${ks_img}" ]]; then
		rm -f ${ks_img}
		ks_img=''
	fi

	if [[ -d ${tmp_dir} ]]; then
		${sudo} rm -rf ${tmp_dir}
	fi

	echo "${script_name}: ${result}" >&2
}

make_kickstart_img() {
	ks_img="$(mktemp --tmpdir tdd-ks-img.XXXX)"
	ks_mnt="$(mktemp --tmpdir --directory tdd-ks-mnt.XXXX)"

	local ks_file
	ks_file="${ks_mnt}/${kickstart##*/}"

	dd if=/dev/zero of=${ks_img} bs=1M count=1
	mkfs.vfat ${ks_img}

	sudo mount -o rw,uid=$(id -u),gid=$(id -g) ${ks_img} ${ks_mnt}

	cp -v ${kickstart} ${ks_file}

	if [[ -n "${ssh_key}" ]]; then
		sed --in-place "s|@@ssh-keys@@|$(cat ${ssh_key}.pub)|" ${ks_file}
	fi

	echo '' >> ${result_file}
	echo '---------' >> ${result_file}
	echo 'kickstart' >> ${result_file}
	echo '---------' >> ${result_file}
	cat ${ks_file} >> ${result_file}
	echo '---------' >> ${result_file}

	sudo umount ${ks_mnt}
	rmdir ${ks_mnt}
	ks_mnt=''
}

start_qemu_kernel() {
	local out_file=${1}

	ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${script_name}: ssh_fwd port = ${ssh_fwd}" >&2

	${SCRIPTS_TOP}/start-qemu.sh \
		--verbose \
		--arch="${target_arch}" \
		--hostfwd-offset="${hostfwd_offset}" \
		--hda="${hda}" \
		--out-file="${out_file}" \
		--pid-file="${qemu_pid_file}" \
		--hdb="${ks_img}" \
		--initrd="${initrd}" \
		--kernel="${kernel}" \
		--kernel-cmd="${kernel_cmd}" \
		${start_extra_args} \
		</dev/null &> "${out_file}" &
}


start_qemu_hda() {
	local out_file=${1}

        ssh_fwd=$(( ${hostfwd_offset} + 22 ))

	echo "${script_name}: ssh_fwd port = ${ssh_fwd}" >&2

        ${SCRIPTS_TOP}/start-qemu.sh \
                --verbose \
                --arch="${target_arch}" \
                --hostfwd-offset="${hostfwd_offset}" \
                --hda="${hda}" \
                --out-file="${out_file}" \
                --pid-file="${qemu_pid_file}" \
                --hda-boot \
                ${start_extra_args} \
                </dev/null &> "${out_file}" &
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

process_opts "${@}"

target_arch=${target_arch:-"${host_arch}"}
hostfwd_offset=${hostfwd_offset:-"20000"}

if [[ -n "${usage}" ]]; then
	usage
	exit 0
fi

if [[ "${target_arch}" != "arm64" ]]; then
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
fi

check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

check_opt 'hda' ${hda}
check_file "${hda}"

check_opt 'kickstart' ${kickstart}
check_file "${kickstart}"

inst_repo="$(egrep '^url[[:space:]]*--url=' ${kickstart} | cut -d '=' -f 2 | sed 's/"//g')"
kernel_cmd="inst.text inst.repo=${inst_repo} inst.ks=hd:vdb:${kickstart##*/} ${kernel_cmd}"

if [[ ! ${out_file} ]]; then
	out_file="${script_name}-out.txt"
fi

if [[ ! ${result_file} ]]; then
	result_file="${script_name}-result.txt"
fi

if [[ ${ssh_key} ]]; then
	check_file ${ssh_key} " ssh-key" "usage"
fi

start_extra_args=''

if [[ ${systemd_debug} ]]; then
	start_extra_args+=' --systemd-debug'
fi

rm -f ${out_file} ${out_file}.start ${result_file}

tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"

echo '--------' >> ${result_file}
echo 'printenv' >> ${result_file}
echo '--------' >> ${result_file}
printenv        >> ${result_file}
echo '---------' >> ${result_file}

make_kickstart_img

qemu_pid_file=${tmp_dir}/qemu-pid

SECONDS=0

start_qemu_kernel ${out_file}.start

echo "${script_name}: Waiting for QEMU startup..." >&2
sleep 10s

echo '---- start-qemu start install ----' >&2
cat ${out_file}.start >&2
echo '---- start-qemu end install ----' >&2

ps aux

if [[ ! -f ${qemu_pid_file} ]]; then
	echo "${script_name}: ERROR: QEMU seems to have quit early (pid file)." >&2
	exit 1
fi

qemu_pid=$(cat ${qemu_pid_file})

if ! kill -0 ${qemu_pid} &> /dev/null; then
	echo "${script_name}: ERROR: QEMU seems to have quit early (pid)." >&2
	exit 1
fi

echo "${script_name}: Waiting for QEMU exit..." >&2
wait_pid ${qemu_pid} 5100


start_qemu_hda ${out_file}.start

echo "${script_name}: Waiting for QEMU startup..." >&2
sleep 180s

echo '---- start-qemu start boot ----' >&2
cat ${out_file}.start >&2
echo '---- start-qemu end boot ----' >&2

ps aux

if [[ ! -f ${qemu_pid_file} ]]; then
        echo "${script_name}: ERROR: QEMU seems to have quit early (pid file)." >&2
        exit 1
fi

qemu_pid=$(cat ${qemu_pid_file})

if ! kill -0 ${qemu_pid} &> /dev/null; then
        echo "${script_name}: ERROR: QEMU seems to have quit early (pid)." >&2
        exit 1
fi

user_qemu_host="root@localhost"

user_qemu_ssh_opts="-o Port=${ssh_fwd}"

ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

ssh ${ssh_no_check} -i ${ssh_key} ${user_qemu_ssh_opts} ${user_qemu_host} \
        '/sbin/poweroff &'

echo "${script_name}: Waiting for QEMU exit..." >&2
wait_pid ${qemu_pid} 180

echo "${script_name}: Boot time: $(sec_to_min ${SECONDS}) min" >&2

trap - EXIT
on_exit 'Done, success.'
