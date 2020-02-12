#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Builds a minimal Linux disk image." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -a --arch              - Target architecture. Default: '${target_arch}'." >&2
	echo "  -c --clean-rootfs      - Delete bootstrap and rootfs directories. Default: ${clean_rootfs}" >&2
	echo "  -h --help              - Show this help and exit." >&2
	echo "  -i --output-disk-image - Output a binary disk image file '${disk_img}'." >&2
	echo "  -t --rootfs-type       - Rootfs type {$(clean_ws ${known_rootfs_types})}." >&2
	echo "                           Default: '${rootfs_type}'." >&2
	echo "  -v --verbose           - Verbose execution." >&2
	echo "  --bootstrap-dir        - Bootstrap directory. Default: '${bootstrap_dir}'." >&2
	echo "  --image-dir            - Image output path. Default: '${image_dir}', ${rootfs_dir}', '${initrd}', '${disk_img}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --bootstrap          - Run bootstrap rootfs step. Default: '${step_bootstrap}'." >&2
	echo "  -2 --rootfs-setup       - Run rootfs setup step. Default: '${step_rootfs_setup}'." >&2
	echo "    --kernel-modules      - Kernel modules to install. Default: '${kernel_modules}'." >&2
	echo "    --extra-packages      - Extra distro packages. Default: '${extra_packages}'." >&2
	echo "  -3 --make-image         - Run make image step. Default: '${step_make_image}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:chit:v123"
	local long_opts="arch:,clean-rootfs,help,output-disk-image,rootfs-type:,verbose,\
bootstrap-dir:,image-dir:,\
bootstrap,rootfs-setup,kernel-modules:,extra-packages:,make-image"

	local opts
	opts=$(getopt --options "${short_opts}" --long "${long_opts}" -n "${script_name}" -- "${@}")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@${2}@"
		case "${1}" in
		-a | --arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		-c | --clean-rootfs)
			clean_rootfs=1
			shift
			;;
		-h | --help)
			usage=1
			shift
			;;
		-i | --output-disk-image)
			output_disk_image=1
			shift
			;;
		-m | --kernel-modules)
			kernel_modules="${2}"
			shift 2
			;;
		-p | --extra-packages)
			extra_packages="${2}"
			shift 2
			;;
		-t | --rootfs-type)
			rootfs_type="${2}"
			shift 2
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--bootstrap-dir)
			bootstrap_dir="${2}"
			shift 2
			;;
		--image-dir)
			image_dir="${2}"
			shift 2
			;;
		-1 | --bootstrap)
			step_bootstrap=1
			shift
			;;
		-2 | --rootfs-setup)
			step_rootfs_setup=1
			shift
			;;
		-3 | --make-image)
			step_make_image=1
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
	if [ -d ${tmp_dir} ]; then
		${sudo} rm -rf ${tmp_dir}
	fi
}

on_fail() {
	local chroot=${1}
	local mnt=${2}

	echo "${script_name}: Step ${current_step}: FAILED." >&2

	cleanup_chroot ${chroot}

	${sudo} chown -R $(id --user --real --name): ${chroot}

	if [ -d "${mnt}" ]; then
		clean_make_disk_img "${mnt}"
		rm -rf "${mnt}"
	fi

	if [ -d ${tmp_dir} ]; then
		${sudo} rm -rf ${tmp_dir}
	fi

	if [ ${need_clean_rootfs} ]; then
		${sudo} rm -rf ${chroot}
	fi

	on_exit
}

check_kernel_modules() {
	local dir=${1}

	if [ ${dir} ]; then
		if [ ! -d "${dir}" ]; then
			echo "${script_name}: ERROR: <kernel-modules> directory not found: '${dir}'" >&2
			usage
			exit 1
		fi
		if [ "$(basename $(cd ${dir}/.. && pwd))" != "modules" ]; then
			echo "${script_name}: ERROR: No kernel modules found in '${dir}'" >&2
			usage
			exit 1
		fi
	fi
}

test_step_code() {
	local step_code="${step_bootstrap}-${step_rootfs_setup}-${step_make_image}"

	case "${step_code}" in
	1--|1-1-|1-1-1|-1-|-1-1|--1)
		#echo "${script_name}: Steps OK" >&2
		;;
	--)
		step_bootstrap=1
		step_rootfs_setup=1
		step_make_image=1
		;;
	1--1)
		echo "${script_name}: ERROR: Bad flags: 'bootstrap + make_image'." >&2
		usage
		exit 1
		;;
	*)
		echo "${script_name}: ERROR: Internal bad step_code: '${step_code}'." >&2
		exit 1
		;;
	esac
}

setup_network_ifupdown() {
	local rootfs=${1}

	echo "${TARGET_HOSTNAME}" | sudo_write "${rootfs}/etc/hostname"

	sudo_append "${rootfs}/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet dhcp

#auto enP2p1s0v0
#iface enP2p1s0v0 inet dhcp

#auto enP2p1s0f1
#iface enP2p1s0f1 inet dhcp

#auto enp9s0f1
#iface enp9s0f1 inet dhcp

# gbt2s18
# DHCPREQUEST for 10.112.35.123 on enP2p1s0v0 to 255.255.255.255 port 67

EOF
}

setup_resolv_conf() {
	local rootfs=${1}

	sudo_append "${rootfs}/etc/resolv.conf" <<EOF
nameserver 4.2.2.4
nameserver 4.2.2.2
nameserver 8.8.8.8
EOF
}

setup_network_systemd() {
	local rootfs=${1}

	echo "${TARGET_HOSTNAME}" | sudo_write "${rootfs}/etc/hostname"

	sudo_append "${rootfs}/etc/systemd/network/dhcp.network" <<EOF
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
}

setup_ssh_keys() {
	local rootfs=${1}
	local key_file=${2}

	${sudo} mkdir -p -m0700 "${rootfs}/root/.ssh"

	ssh-keygen -q -f ${key_file} -N ''
	cat "${key_file}.pub" | sudo_append "${rootfs}/root/.ssh/authorized_keys"

	for key in ${HOME}/.ssh/id_*.pub; do
		[ -f "${key_file}" ] || continue
		cat "${key_file}" | sudo_append "${rootfs}/root/.ssh/authorized_keys"
		local found=1
	done
}

setup_kernel_modules() {
	local rootfs=${1}
	local src=${2}

	if [ ! ${src} ]; then
		echo "${script_name}: WARNING: No kernel modules provided." >&2
		return
	fi

	local dest="${rootfs}/lib/modules/${src##*/}"

	if [ ${verbose} ]; then
		local extra='-v'
	fi

	${sudo} mkdir -p ${dest}
	${sudo} rsync -av --delete ${extra} \
		--exclude '/build' --exclude '/source' \
		${src}/ ${dest}/
	echo "${script_name}: INFO: Kernel modules size: $(directory_size_human ${dest})"
}

setup_password() {
	local rootfs=${1}
	local pw=${2}

	pw=${pw:-"r"}
	echo "${script_name}: INFO: Login password = '${pw}'." >&2

	local i
	local hash
	for ((i = 0; ; i++)); do
		hash="$(openssl passwd -1 -salt tdd${i} ${pw})"
		if [ "${hash/\/}" == "${hash}" ]; then
			break
		fi
	done

	${sudo} sed --in-place "s/root:x:0:0/root:${hash}:0:0/" \
		${rootfs}/etc/passwd
	${sudo} sed --in-place '/^root:.*/d' \
		${rootfs}/etc/shadow
}

delete_rootfs() {
	local rootfs=${1}

	${sudo} rm -rf ${rootfs}
}

clean_make_disk_img() {
	local mnt=${1}

	${sudo} umount ${mnt} || :
}

make_disk_img() {
	local rootfs=${1}
	local img=${2}
	local mnt=${3}

	tmp_img="${tmp_dir}/tdd-disk.img"

	dd if=/dev/zero of=${tmp_img} bs=1M count=1536
	mkfs.ext4 ${tmp_img}

	mkdir -p ${mnt}

	${sudo} mount  ${tmp_img} ${mnt}
	${sudo} cp -a ${rootfs}/* ${mnt}

	${sudo} umount ${mnt} || :
	cp ${tmp_img} ${img}
	rm -f  ${tmp_img}
}

make_ramfs() {
	local fs=${1}
	local out_file=${2}

	(cd ${fs} && ${sudo} find . | ${sudo} cpio --create --format='newc' --owner=root:root | gzip) > ${out_file}
}

make_manifest() {
	local rootfs=${1}
	local out_file=${2}

	(cd ${rootfs} && ${sudo} find . -ls | sort --key=11) > ${out_file}
}

print_usage_summary() {
	local rootfs_dir=${1}
	local kernel_modules=${2}

	rootfs_size="$(directory_size_bytes ${rootfs_dir})"
	rootfs_size="$(bc <<< "${rootfs_size} / 1048576")"

	modules_size="$(directory_size_bytes ${kernel_modules})"
	modules_size="$(bc <<< "${modules_size} / 1048576")"

	base_size="$(bc <<< "${rootfs_size} - ${modules_size}")"

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name}: INFO: Base size:    ${base_size} MiB"
	echo "${script_name}: INFO: Modules size: ${modules_size} MiB"
	echo "${script_name}: INFO: Total size:   ${rootfs_size} MiB"
	eval "${old_xtrace}"
}

write_tdd_client_script() {
	local out_file=${1}
	local timeout=${2:-241}

	sudo cp -vf ${RELAY_TOP}/tdd-relay-client.sh "${out_file}"
	sudo sed --in-place "{s/@@timeout@@/${timeout}/}" "${out_file}"

	${sudo} chmod u+x "${out_file}"
}

#===============================================================================
# program start
#===============================================================================
script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}
RELAY_TOP=${RELAY_TOP:-"$( cd "${SCRIPTS_TOP}/../relay" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/chroot.sh

trap "on_exit" EXIT
set -e

sudo="sudo -S"

process_opts "${@}"

TARGET_HOSTNAME=${TARGET_HOSTNAME:-"tdd-tester"}

rootfs_type=${rootfs_type:-"debian"}
source "${SCRIPTS_TOP}/rootfs-plugin/${rootfs_type}.sh"

host_arch=$(get_arch "$(uname -m)")
target_arch=${target_arch:-"${host_arch}"}

image_dir=${image_dir:-"$(pwd)/${target_arch}-${rootfs_type}.image"}
bootstrap_dir=${bootstrap_dir:-"${image_dir%.image}.bootstrap"}

image_rootfs="${image_dir}/rootfs"
disk_img="${image_dir}/disk.img"
initrd="${image_dir}/initrd"
manifest="${image_dir}/manifest"
server_key="${image_dir}/server-key"
login_key="${image_dir}/login-key"

test_step_code

if [ ${usage} ]; then
	usage
	exit 0
fi

${sudo} true

cleanup_chroot ${image_rootfs}
cleanup_chroot ${bootstrap_dir}

tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"

if [ ${step_bootstrap} ]; then
	current_step="bootstrap"
	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2

	sudo rm -rf ${bootstrap_dir}
	mkdir -p ${bootstrap_dir}

	trap "on_fail ${bootstrap_dir} none" EXIT
	bootstrap_rootfs ${bootstrap_dir}
	${sudo} chown -R $(id --user --real --name): ${bootstrap_dir}

	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Done (${bootstrap_dir})." >&2
	echo "${script_name}: INFO: Bootstrap size: $(directory_size_human ${bootstrap_dir})"
fi

if [ ${step_rootfs_setup} ]; then
	current_step="rootfs_setup"
	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2
	echo "${script_name}: INFO: Step ${current_step}: Using ${bootstrap_dir}." >&2

	check_directory "${bootstrap_dir}"
	check_directory "${bootstrap_dir}/usr/bin"

	check_directory ${kernel_modules}
	check_kernel_modules ${kernel_modules}

	trap "on_fail ${image_rootfs} none" EXIT

	mkdir -p ${image_rootfs}
	${sudo} rsync -a --delete ${bootstrap_dir}/ ${image_rootfs}/

	setup_packages ${image_rootfs} $(get_default_packages) ${extra_packages}

	setup_initrd_boot ${image_rootfs}
	setup_login ${image_rootfs}
	setup_network ${image_rootfs}
	setup_sshd ${image_rootfs} ${server_key}
	setup_ssh_keys ${image_rootfs} ${login_key}
	setup_kernel_modules ${image_rootfs} ${kernel_modules}
	setup_relay_client ${image_rootfs}

	rootfs_cleanup ${image_rootfs}

	${sudo} chown -R $(id --user --real --name): ${image_rootfs}

	print_usage_summary ${image_rootfs} ${kernel_modules}
	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): done." >&2
fi

if [ ${step_make_image} ]; then
	current_step="make_image"
	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): start." >&2

	check_directory ${image_rootfs}

	if [ ${output_disk_image} ]; then
		tmp_mnt="${tmp_dir}/tdd-disk-mnt"
		trap "on_fail ${image_rootfs} ${tmp_mnt}" EXIT
		make_disk_img ${image_rootfs} ${disk_img} ${tmp_mnt}
		trap "on_fail ${image_rootfs} none" EXIT
		clean_make_disk_img "${tmp_mnt}"
	fi

	make_ramfs ${image_rootfs} ${initrd}
	make_manifest ${image_rootfs} ${manifest}

	if [ -d ${tmp_mnt} ]; then
		rm -rf ${tmp_mnt}
	fi

	need_clean_rootfs=${clean_rootfs}

	print_usage_summary ${image_rootfs} ${kernel_modules}
	echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): done." >&2

fi

if [ ${need_clean_rootfs} ]; then
	${sudo} rm -rf ${image_rootfs}
fi

trap on_exit EXIT

echo "${script_name}: INFO: Success: bootstrap='${bootstrap_dir}' image='${image_dir}'" >&2
