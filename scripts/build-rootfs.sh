#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	{
		echo "${script_name} - Builds a small Linux disk image."
		echo "Usage: ${script_name} [flags]"
		echo "Option flags:"
		echo "  -a --arch           - Target architecture {${known_arches}}. Default: '${target_arch}'."
		echo "  -t --rootfs-type    - Rootfs type {${known_rootfs_types}}. Default: '${rootfs_type}'."
		echo "  -m --minimal        - Build minimal image. Install no extra packages. Default: '${minimal_install}'."
		echo "  -c --clean-rootfs   - Remove bootstrap and rootfs working directories. Default: '${clean_rootfs}'"
		echo "  -i --disk-image     - Generate a binary disk image file: '${output_disk_image}'."
		echo "  --bootstrap-dir     - Bootstrap directory. Default: '${bootstrap_dir}'."
		echo "  --output-dir        - Output directory:   '${output_dir}'."
		echo "                         Root FS:           '${rootfs_dir}'."
		echo "                         Initrd:            '${initrd}'."
		echo "                         Binary Disk Image: '${disk_img}'."
		echo "  -h --help           - Show this help and exit."
		echo "  -v --verbose        - Verbose execution. Default: '${verbose}'."
		echo "  -g --debug          - Extra verbose execution. Default: '${debug}'."
# 		echo "  -d --dry-run        - Dry run, don't run commands. Default: '${dry_run}'."
		echo "Option steps:"
		echo "  -1 --bootstrap      - Run bootstrap rootfs step. Default: '${step_bootstrap}'."
		echo "  -2 --rootfs-setup   - Run rootfs setup step. Default: '${step_rootfs_setup}'."
		echo "     --kernel-modules - Kernel modules to install. Default: '${kernel_modules}'."
		echo "     --extra-packages - Extra packages to install. Default: '${extra_packages}'."
		echo "     --hostname       - Target hostname. Default: '${target_hostname}'."
		echo "  -3 --make-image     - Run make image step. Default: '${step_make_image}'."
	} >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:t:mcikp:123hvgd"
	local long_opts="\
arch:,\
rootfs-type:,\
minimal,\
clean-rootfs,\
disk-image,\
bootstrap-dir:,\
output-dir:,\
help,verbose,debug,dry-run,\
bootstrap,\
rootfs-setup,kernel-modules:,extra-packages:,hostname:,\
make-image"

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
		-t | --rootfs-type)
			rootfs_type="${2}"
			shift 2
			;;
		-m | --minimal)
			minimal_install=1
			shift
			;;
		-c | --clean-rootfs)
			clean_rootfs=1
			shift
			;;
		-i | --disk-image)
			output_disk_image=1
			shift
			;;
		--bootstrap-dir)
			bootstrap_dir="${2}"
			shift 2
			;;
		--output-dir)
			output_dir="${2}"
			shift 2
			;;
		--hostname)
			target_hostname="${2}"
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
		-g | --debug)
			set -x
			verbose=1
			debug=1
			keep_tmp_dir=1
			shift
			;;
		-d | --dry-run)
# 			dry_run=1
			shift
			;;
		-1 | --bootstrap)
			step_bootstrap=1
			shift
			;;
		-2 | --rootfs-setup)
			step_rootfs_setup=1
			shift
			;;
		-k | --kernel-modules)
			kernel_modules="${2}"
			shift 2
			;;
		-p | --extra-packages)
			extra_packages="${2}"
			shift 2
			;;
		-3 | --make-image)
			step_make_image=1
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

on_exit() {
	local result=${1}

	local sec="${SECONDS}"

	if [[ -d "${tmp_dir:-}" ]]; then
		if [[ ${keep_tmp_dir:-} ]]; then
			echo "${script_name}: INFO: tmp dir preserved: '${tmp_dir}'" >&2
		else
			rm -rf "${tmp_dir:?}"
		fi
	fi

	set +x
	echo "${script_name}: Done: ${result}, ${sec} sec." >&2
}

on_err() {
	local f_name=${1}
	local line_no=${2}
	local err_no=${3}

# 	{
# 		if [[ ${debug:-} ]]; then
# 			echo '------------------------'
# 			set
# 			echo '------------------------'
# 		fi
# 	} >&2

	echo "${script_name}: ERROR: function=${f_name}, line=${line_no}, result=${err_no}" >&2
	exit "${err_no}"
}

on_fail() {
	local chroot=${1}
	local mnt=${2}

	echo "${script_name}: Step ${current_step}: FAILED." >&2

	cleanup_chroot "${chroot}"

	local user_id
	user_id="$(id --user --real --name)"
	${sudo} find "${chroot}" -type f -o -type d -exec chown "${user_id}": '{}' ';'

	if [[ -d "${mnt}" ]]; then
		clean_make_disk_img "${mnt}"
		delete_dir "${mnt:?}"
	fi

	if [[ ${need_clean_rootfs} ]]; then
		delete_dir_sudo "${chroot:?}"
	fi

	on_exit 'Failed'
}

check_kernel_modules() {
	local dir=${1}

	if [[ ${dir} ]]; then
		if [[ ! -d "${dir}" ]]; then
			echo "${script_name}: ERROR: <kernel-modules> directory not found: '${dir}'" >&2
			usage
			exit 1
		fi

		local check="${dir%/*}"
		check="${check##*/}"

		if [[ "${check}" != 'modules' ]]; then
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

	echo "${target_hostname}" | sudo_write "${rootfs}/etc/hostname"

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

	echo "${target_hostname}" | sudo_write "${rootfs}/etc/hostname"

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

	ssh-keygen -q -f "${key_file}" -N ''
	sudo_append "${rootfs}/root/.ssh/authorized_keys2" < "${key_file}.pub"

	local user_key
	for user_key in "${HOME}"/.ssh/*.pub; do
		if [[ ! -f "${user_key}" ]]; then
			continue
		fi
		sudo_append "${rootfs}/root/.ssh/authorized_keys" < "${user_key}"
	done
}

setup_kernel_modules() {
	local rootfs=${1}
	local src=${2}

	if [[ ! ${src} ]]; then
		echo "${script_name}: WARNING: No kernel modules provided." >&2
		return
	fi

	local dest
	dest="${rootfs}/lib/modules/${src##*/}"

	local extra=''
	if [[ ${verbose} ]]; then
		local extra='-v'
	fi

	${sudo} mkdir -p "${dest}"
	${sudo} rsync -a --delete ${extra} \
		--exclude '/build' --exclude '/source' \
		"${src}/" "${dest}/"

	echo "${script_name}: INFO: Kernel modules size: $(file_size_human "${dest}")"
}

setup_password() {
	local rootfs=${1}
	local pw=${2}

	pw="${pw:-r}"
	echo "${script_name}: INFO: Login password = '${pw}'." >&2

	local i
	local hash
	for ((i = 0; ; i++)); do
		hash="$(openssl passwd -1 -salt "tdd${i}" "${pw}")"
		if [[ "${hash/\/}" == "${hash}" ]]; then
			break
		fi
	done

	${sudo} sed --in-place "s/root:x:0:0/root:${hash}:0:0/" \
		"${rootfs}/etc/passwd"
	${sudo} sed --in-place '/^root:.*/d' "${rootfs}/etc/shadow"
}

delete_dir_sudo() {
	local dir=${1}

	if [[ -d "${dir}" ]]; then
		${sudo} rm -rf "${dir:?}"
	fi
}

delete_dir() {
	local dir=${1}

	if [[ -d "${dir}" ]]; then
		rm -rf "${dir:?}"
	fi
}

clean_make_disk_img() {
	local mnt=${1}

	${sudo} umount "${mnt}" || :
}

make_disk_img() {
	local rootfs=${1}
	local img=${2}
	local mnt=${3}

	tmp_img="${tmp_dir}/tdd-disk.img"

	dd if='/dev/zero' of="${tmp_img}" bs=1M count=1536
	mkfs.ext4 "${tmp_img}"

	mkdir -p "${mnt}"

	${sudo} mount  "${tmp_img}" "${mnt}"
	${sudo} cp -a "${rootfs}"/* "${mnt}"

	${sudo} umount "${mnt}" || :
	cp "${tmp_img}" "${img}"
	rm -f "${tmp_img}"
}

make_ramfs() {
	local fs=${1}
	local out_file=${2}

	(cd "${fs}" && ${sudo} find . | ${sudo} cpio --create --format='newc' --owner=root:root | gzip) > "${out_file}"
}

make_manifest() {
	local rootfs=${1}
	local out_file=${2}

	(cd "${rootfs}" && ${sudo} find . -ls | sort --key=11) > "${out_file}"
}

print_usage_summary() {
	local rootfs_dir=${1}
	local kernel_modules=${2}

	local rootfs_size

	rootfs_size="$(file_size_human "${rootfs_dir}")"

	echo "${script_name}: INFO: Rootfs size:  ${rootfs_size}"

	if [[ -d "${kernel_modules}" ]]; then
		local rootfs_bytes
		local modules_bytes
		local base_size

		rootfs_bytes="$(file_size_bytes "${rootfs_dir}")"
		modules_bytes="$(file_size_bytes "${kernel_modules}")"
		base_size="$(bc <<< "(${rootfs_bytes} - ${modules_bytes}) / 1048576")"
		echo "${script_name}: INFO: Base size:    ${base_size}M"

		local modules_size

		modules_size="$(file_size_human "${kernel_modules}")"
		echo "${script_name}: INFO: Modules size: ${modules_size}"
	fi

	if [[ -f "${initrd}" ]]; then
		local initrd_size

		initrd_size="$(file_size_human "${initrd}")"
		echo "${script_name}: INFO: Initrd size:  ${initrd_size}"
	fi
}

write_tdd_client_script() {
	local out_file=${1}
	local timeout=${2:-241}

	sudo cp -vf "${RELAY_TOP}/tdd-relay-client.sh" "${out_file}"
	sudo sed --in-place "{s/@@timeout@@/${timeout}/}" "${out_file}"

	${sudo} chmod u+x "${out_file}"
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"

SECONDS=0
# start_time="$(date +%Y.%m.%d-%H.%M.%S)"

trap "on_exit 'Failed'" EXIT
trap 'on_err ${FUNCNAME[0]:-main} ${LINENO} ${?}' ERR
trap 'on_err SIGUSR1 ? 3' SIGUSR1

set -eE
set -o pipefail
set -o nounset

real_source="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

RELAY_TOP="${RELAY_TOP:-$(realpath "${SCRIPT_TOP}/../relay")}"

# shellcheck source=./tdd-lib/util.sh
source "${SCRIPT_TOP}/tdd-lib/util.sh"
# shellcheck source=./lib/chroot.sh
source "${SCRIPT_TOP}/lib/chroot.sh"

sudo='sudo -S'
host_arch="$(get_host_arch)"

target_arch="${host_arch}"
rootfs_type='debian'
minimal_install=''
clean_rootfs=''
output_disk_image=''
bootstrap_dir=''
output_dir=''
target_hostname='tdd-tester'
usage=''
verbose=''
debug=''
# dry_run=''
step_bootstrap=''
step_rootfs_setup=''
kernel_modules=''
extra_packages=''
step_make_image=''

keep_tmp_dir=''

process_opts "${@}"

# shellcheck source=./rootfs-plugin/rootfs-plugin.sh
source "${SCRIPT_TOP}/rootfs-plugin/rootfs-plugin.sh"
source "${SCRIPT_TOP}/rootfs-plugin/${rootfs_type}.sh"

output_dir="${output_dir:-$(realpath "$(pwd)/${target_arch}-${rootfs_type}-rootfs")}"
image_dir="$(realpath -m "${output_dir}/${target_arch}-${rootfs_type}.image")"
bootstrap_dir="${bootstrap_dir:-$(realpath -m "${output_dir}/${target_arch}-${rootfs_type}.bootstrap")}"

rootfs_dir="${image_dir}/rootfs"
disk_img="${image_dir}/disk.img"
initrd="${image_dir}/initrd"
manifest="${image_dir}/manifest"
server_key="${image_dir}/server-key"
login_key="${image_dir}/login-key"

test_step_code

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${extra_args} ]]; then
	set +o xtrace
	echo "${script_name}: ERROR: Got extra args: '${extra_args}'" >&2
	usage
	exit 1
fi

${sudo} true

cleanup_chroot "${rootfs_dir}"
cleanup_chroot "${bootstrap_dir}"

tmp_dir="$(mktemp --tmpdir --directory "${script_name}".XXXX)"
need_clean_rootfs=''

if [[ ${step_bootstrap} ]]; then
	current_step="bootstrap"

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Start."
	} >&2

	delete_dir "${bootstrap_dir:?}"
	mkdir -p "${bootstrap_dir}"

	trap 'on_fail ${bootstrap_dir} none' EXIT
	bootstrap_rootfs "${bootstrap_dir}"

	user_id="$(id --user --real --name)"
	${sudo} find "${bootstrap_dir}" -type f -o -type d -exec chown "${user_id}": '{}' ';'

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Done."
		echo "${script_name}: INFO: Bootstrap files in '${bootstrap_dir}'."
		echo "${script_name}: INFO: Bootstrap size: $(file_size_human "${bootstrap_dir}")"
	} >&2
fi

if [[ ${step_rootfs_setup} ]]; then
	current_step='rootfs_setup'

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Start."
		echo "${script_name}: INFO: Step ${current_step}: Using bootstrap '${bootstrap_dir}'."
		echo "${script_name}: INFO: Step ${current_step}: Using modules '${kernel_modules}'."
	} >&2

	check_directory "${bootstrap_dir}" ' bootstrap dir' ''
	check_directory "${bootstrap_dir}/usr/bin" ' bootstrap/usr/bin' ''

	if [[ "${kernel_modules}" != 'none' ]]; then
		check_directory "${kernel_modules}" ' kernel modules' ''
		check_kernel_modules "${kernel_modules}"
	fi

	trap 'on_fail ${rootfs_dir} none' EXIT

	mkdir -p "${rootfs_dir}"
	${sudo} rsync -a --delete "${bootstrap_dir}/" "${rootfs_dir}/"

	if [[ ${minimal_install} ]]; then
		setup_packages "${rootfs_dir}" "$(get_base_packages) ${extra_packages}"
		setup_initrd_boot "${rootfs_dir}"
		setup_login "${rootfs_dir}" ''
		setup_network "${rootfs_dir}"
		setup_sshd "${rootfs_dir}" "${server_key}"
		setup_ssh_keys "${rootfs_dir}" "${login_key}"
	else
		setup_packages "${rootfs_dir}" "$(get_all_packages) ${extra_packages}"
		setup_initrd_boot "${rootfs_dir}"
		setup_login "${rootfs_dir}" ''
		setup_network "${rootfs_dir}"
		setup_sshd "${rootfs_dir}" "${server_key}"
		setup_ssh_keys "${rootfs_dir}" "${login_key}"
		if [[ "${kernel_modules}" != 'none' ]]; then
			setup_kernel_modules "${rootfs_dir}" "${kernel_modules}"
		fi
		setup_relay_client "${rootfs_dir}"
	fi

	rootfs_cleanup "${rootfs_dir}"

	user_id="$(id --user --real --name)"
	${sudo} find "${rootfs_dir}" -type f -o -type d -exec chown "${user_id}": '{}' ';'

	print_usage_summary "${rootfs_dir}" "${kernel_modules}"

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Done."
		echo "${script_name}: INFO: Bootstrap files in '${bootstrap_dir}'."
		echo "${script_name}: INFO: Rootfs files in '${rootfs_dir}'."
	} >&2
fi

if [[ ${step_make_image} ]]; then
	current_step='make_image'

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Start."
		echo "${script_name}: INFO: Step ${current_step}: Using rootfs '${rootfs_dir}'."
	} >&2

	check_directory "${rootfs_dir}" ' rootfs_dir' ''

	tmp_mnt=''

	if [[ ${output_disk_image} ]]; then
		tmp_mnt="${tmp_dir}/tdd-disk-mnt"
		trap 'on_fail ${rootfs_dir} ${tmp_mnt}' EXIT
		make_disk_img "${rootfs_dir}" "${disk_img}" "${tmp_mnt}"
		trap 'on_fail ${rootfs_dir} none' EXIT
		clean_make_disk_img "${tmp_mnt}"
	fi

	make_ramfs "${rootfs_dir}" "${initrd}"
	make_manifest "${rootfs_dir}" "${manifest}"

	need_clean_rootfs="${clean_rootfs}"

	print_usage_summary "${rootfs_dir}" "${kernel_modules}"

	{
		echo "${script_name}: INFO: Step ${current_step} (${rootfs_type}): Done."
		echo "${script_name}: INFO: Image files in '${image_dir}'"
	} >&2

fi

if [[ ${need_clean_rootfs} ]]; then
	delete_rootfs "${rootfs_dir:?}"
fi


trap "on_exit 'Success'" EXIT
exit 0
