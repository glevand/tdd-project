#!/usr/bin/env bash
#
# CoreOS plug-in routines for build-rootfs.sh.
#
# @PACKAGE_NAME@ ${script_name}"
# Version: @PACKAGE_VERSION@"
# Home: @PACKAGE_URL@"
#

script_name="${script_name:?}"
coreos_installer="${coreos-installer:-coreos-installer}"

debug_check() {
	local info=${1}

	if [[ ${verbose} ]]; then
	{
		echo "debug_check: vvvvv (${info}) vvvvvvvvvvvvvvvvvvvv"
		set +e
		${sudo} true
		mount
		${sudo} ls -l '/var/run/sudo/ts'
		set -e
		echo "debug_check: ^^^^^ (${info}) ^^^^^^^^^^^^^^^^^^^^"
	} >&2
	fi
}

bootstrap_rootfs() {
	local rootfs=${1}

# 	if ! check_prog "${coreos_installer}"; then
# 		exit 1
# 	fi

	debug_check "${FUNCNAME[0]}:${LINENO}"

	case ${target_arch} in
	amd64)
		coreos_arch='amd64'
		coreos_os_release="${coreos_os_release:-???}"
		coreos_os_mirror="${coreos_os_mirror:-http://ftp.us.coreos.org/coreos}"
		coreos_installer_extra=''
		;;
	arm32)
		coreos_arch='armel'
# 		coreos_arch='armhf'
		coreos_os_release="${coreos_os_release:-???}"
		coreos_os_mirror="${coreos_os_mirror:-http://ftp.us.coreos.org/coreos}"
		coreos_installer_extra=''
		;;
	arm64)
		coreos_arch='arm64'
		coreos_os_release="${coreos_os_release:-???}"
		coreos_os_mirror="${coreos_os_mirror:-http://ftp.us.coreos.org/coreos}"
		coreos_installer_extra=''
		;;
	ppc32|ppc64)
		coreos_arch='powerpc'
		coreos_os_release="${coreos_os_release:-???}"
		coreos_os_mirror="${coreos_os_mirror:-http://ftp.ports.coreos.org/coreos-ports}"
		coreos_installer_extra='--include=coreos-ports-archive-keyring --exclude=powerpc-ibm-utils,powerpc-utils,vim-tiny'
		;;
	*)
		echo "${script_name}: ERROR: Unsupported target-arch '${target_arch}'." >&2
		exit 1
		;;
	esac

	${sudo} chown root: "${rootfs}/"

	(${sudo} "${coreos_installer}" --foreign --arch "${coreos_arch}" --no-check-gpg \
		${coreos_installer_extra} \
		"${coreos_os_release}" "${rootfs}" "${coreos_os_mirror}")

	stat "${rootfs}/" "${rootfs}/dev" "${rootfs}/var" || :

	cat "${rootfs}/etc/apt/sources.list" || :
	cat "${rootfs}/etc/apt/sources.list.d/"* || :

	debug_check "${FUNCNAME[0]}:${LINENO}"

	copy_qemu_static "${rootfs}"

	${sudo} mount -l -t proc
	${sudo} ls -la "${rootfs}"
	${sudo} find "${rootfs}" -type l -exec ls -la {} \; | grep ' -> /'

	setup_chroot_mounts "${rootfs}"

	${sudo} LANG=C.UTF-8 chroot "${rootfs}" /bin/sh -x <<EOF
/coreos_installer/coreos_installer --second-stage
EOF

	clean_qemu_static "${rootfs}"
	clean_chroot_mounts "${rootfs}"

	debug_check "${FUNCNAME[0]}:${LINENO}"

	${sudo} sed --in-place 's/$/ contrib non-free/' \
		"${rootfs}/etc/apt/sources.list"

	enter_chroot "${rootfs}" "
		DEBIAN_FRONTEND=noninteractive apt-get update
		DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
	"

	debug_check "${FUNCNAME[0]}:${LINENO}"
}

setup_packages() {
	local rootfs=${1}
	shift 1
	local packages="${*//,/ }"

	debug_check "${FUNCNAME[0]}:${LINENO}"

	enter_chroot "${rootfs}" "
		DEBIAN_FRONTEND=noninteractive apt-get -y install ${packages}
	"
	debug_check "${FUNCNAME[0]}:${LINENO}"
}

rootfs_cleanup() {
	local rootfs=${1}

	debug_check "${FUNCNAME[0]}:${LINENO}"
	enter_chroot "${rootfs}" "
		DEBIAN_FRONTEND=noninteractive apt-get -y clean
		rm -rf /var/lib/apt/lists/*
	"
	debug_check "${FUNCNAME[0]}:${LINENO}"
}

setup_initrd_boot() {
	local rootfs=${1}

	${sudo} ln -sf "lib/systemd/systemd" "${rootfs}/init"
	${sudo} cp -a "${rootfs}/etc/os-release" "${rootfs}/etc/initrd-release"
}

setup_login() {
	local rootfs=${1}
	local pw=${2}

	setup_password "${rootfs}" "${pw}"

	${sudo} sed --in-place \
		's|-/sbin/agetty -o|-/sbin/agetty --autologin root -o|' \
		"${rootfs}/lib/systemd/system/serial-getty@.service"

	${sudo} sed --in-place \
		's|-/sbin/agetty -o|-/sbin/agetty --autologin root -o|' \
		"${rootfs}/lib/systemd/system/getty@.service"
}

setup_network() {
	local rootfs=${1}

	setup_network_systemd "${rootfs}"
}

setup_sshd() {
	local rootfs=${1}
	local srv_key=${2}

	sshd_config() {
		local key=${1}
		local value=${2}
		
		${sudo} sed --in-place "s/^${key}.*$//" \
			"${rootfs}/etc/ssh/sshd_config"
		echo "${key} ${value}" | sudo_append "${rootfs}/etc/ssh/sshd_config"
	}

	sshd_config "PermitRootLogin" "yes"
	sshd_config "UseDNS" "no"
	sshd_config "PermitEmptyPasswords" "yes"

	if [[ ! -f "${rootfs}/etc/ssh/ssh_host_rsa_key" ]]; then
		echo "${script_name}: ERROR: Not found: ${rootfs}/etc/ssh/ssh_host_rsa_key" >&2
		exit 1
	fi

	${sudo} cp -f "${rootfs}/etc/ssh/ssh_host_rsa_key" "${srv_key}"
	echo "${script_name}: USER=@$(id --user --real --name)@" >&2
	#printenv
	#${sudo} chown $(id --user --real --name): ${srv_key}
}

setup_relay_client() {
	local rootfs=${1}

	local tdd_script="/bin/tdd-relay-client.sh"
	local tdd_service="tdd-relay-client.service"

	write_tdd_client_script "${rootfs}${tdd_script}"

	sudo_write "${rootfs}/etc/systemd/system/${tdd_service}" <<EOF
[Unit]
Description=TDD Relay Client Service
#Requires=network-online.target ssh.service
BindsTo=network-online.target ssh.service
After=network-online.target ssh.service default.target

[Service]
Type=simple
Restart=on-failure
RestartSec=30
StandardOutput=journal+console
StandardError=journal+console
ExecStart=${tdd_script}

[Install]
WantedBy=default.target network-online.target
EOF

# FIXME
#[  139.055550] systemd-networkd-wait-online[2293]: Event loop failed: Connection timed out
#systemd-networkd-wait-online.service: Main process exited, code=exited, status=1/FAILURE
#systemd-networkd-wait-online.service: Failed with result 'exit-code'.
#Startup finished in 16.250s (kernel) + 0 (initrd) + 2min 2.838s (userspace) = 2min 19.089s.

	enter_chroot "${rootfs}" "
		systemctl enable \
			${tdd_service} \
			systemd-networkd-wait-online.service \
	"
}

get_packages() {
	local type=${1}

	local base_packages="
		haveged
		openssh-server
	"

	local extra_packages="
		efibootmgr
		file
		login
		net-tools
		netcat-openbsd
		pciutils
		strace
		tcpdump
	"

	case "${type}" in
	'base')
		str_trim_space "${base_packages}"
		return
		;;
	'all')
		str_trim_space "${base_packages} ${extra_packages}"
		return
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Bad type: '${type}'" >&2
		exit 1
		;;
	esac
}

get_base_packages() {
	get_packages 'base'
}

get_all_packages() {
	get_packages 'all'
}

