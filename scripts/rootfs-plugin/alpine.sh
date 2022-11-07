#!/usr/bin/env bash
#
# Alpine linux plug-in routines for build-rootfs.sh.
#
# @PACKAGE_NAME@ ${script_name}"
# Version: @PACKAGE_VERSION@"
# Home: @PACKAGE_URL@"
#

download_minirootfs() {
	local download_dir=${1}
	local -n _download_minirootfs__archive_file=${3}

	unset _download_minirootfs__archive_file

	case "${target_arch}" in
	amd64)
		alpine_arch='x86_64'
		;;
	arm64)
		alpine_arch='aarch64'
		;;
	*)
		echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
		exit 1
		;;
	esac

	local base_url="${alpine_os_mirror}/${alpine_arch}"

	mkdir -p "${download_dir}"

	pushd "${download_dir}" || exit 1

	local releases_yaml='latest-releases.yaml'

	wget "${base_url}/${releases_yaml}"

	local latest
	latest="$(grep --only-matching "file: alpine-minirootfs-[0-9.]*-${alpine_arch}.tar.gz" "${releases_yaml}")"

	if [[ ! ${latest} ]]; then
		echo "${script_name}: ERROR: Bad releases file '${releases_yaml}'." >&2
		cat "${releases_yaml}"
		exit 1
	fi

	latest="${latest##* }"
	wget "${base_url}/${latest}"

	popd || exit 1

	echo "${script_name}: INFO: Download '${latest}'." >&2

	_download_minirootfs__archive_file="${download_dir}/${latest}"
}

extract_minirootfs() {
	local archive=${1}
	local out_dir=${2}

	mkdir -p "${out_dir}"
	tar -C "${out_dir}" -xf "${archive}"
}

bootstrap_rootfs() {
	local bootstrap_dir=${1}

	local download_dir="${tmp_dir}/downloads"
	local archive_file

# 	delete_dir "${bootstrap_dir:?}"

	download_minirootfs "${download_dir}" "${alpine_os_mirror}" archive_file
	extract_minirootfs "${archive_file}" "${bootstrap_dir}"

# 	delete_dir "${download_dir:?}"

	setup_resolv_conf "${bootstrap_dir}"

	enter_chroot "${bootstrap_dir}" "
		set -e
		apk update
		apk upgrade
		cat /etc/os-release
		apk info | sort
	"

	local alpine_conf

	if [[ -f "${bootstrap_dir}/lib/sysctl.d/00-alpine.conf" ]]; then
		alpine_conf="${bootstrap_dir}/lib/sysctl.d/00-alpine.conf"
	elif [[ -f "${bootstrap_dir}/etc/sysctl.d/00-alpine.conf" ]]; then
		alpine_conf="${bootstrap_dir}/etc/sysctl.d/00-alpine.conf"
	else
		echo "${script_name}: ERROR: Can't find '00-alpine.conf' file." >&2
		exit 1
	fi

	${sudo} sed --in-place 's/^net.ipv4.tcp_syncookies/# net.ipv4.tcp_syncookies/' \
		"${alpine_conf}"
	${sudo} sed --in-place 's/^kernel.panic/# kernel.panic/' \
		"${alpine_conf}"
}

setup_network() {
	local rootfs=${1}

	setup_network_ifupdown "${rootfs}"
}

rootfs_cleanup() {
	local rootfs=${1}

	delete_dir_sudo "${rootfs:?}/var/cache/apk"
}

setup_packages() {
	local rootfs_dir=${1}
	shift 1
	local packages="${*//,/ }"

	echo "packages: @${packages}@"

	enter_chroot "${rootfs_dir}" "
		set -e
		apk add ${packages}
		apk info | sort
	"

	${sudo} ln -s "/etc/init.d/"{hwclock,modules,sysctl,hostname,bootmisc,syslog} \
		"${rootfs_dir}/etc/runlevels/boot/"

	${sudo} ln -s "/etc/init.d"/{devfs,dmesg,mdev,hwdrivers} \
		"${rootfs_dir}/etc/runlevels/sysinit/"

	${sudo} ln -s "/etc/init.d/networking" \
		"${rootfs_dir}/etc/runlevels/default/"

	${sudo} ln -s "/etc/init.d/"{mount-ro,killprocs,savecache} \
		"${rootfs_dir}/etc/runlevels/shutdown/"

	${sudo} ln -s /etc/init.d/{haveged,dropbear} \
		"${rootfs_dir}/etc/runlevels/sysinit/"

	if [[ ${m_of_the_day} ]]; then
		echo "${m_of_the_day}" | sudo_write "${rootfs_dir}/etc/motd"
	fi

	# for openrc debugging
	echo 'rc_logger="YES"' | sudo_append "${rootfs_dir}/etc/rc.conf"
	echo 'rc_verbose="YES"' | sudo_append "${rootfs_dir}/etc/rc.conf"
}

setup_initrd_boot() {
	local rootfs=${1}

	ln -s 'sbin/init' "${rootfs}/init"
}

setup_login() {
	local rootfs=${1}
	local pw=${2}

	setup_password "${rootfs}" "${pw}"

	${sudo} sed --in-place \
		's|/sbin/getty|/sbin/getty -n -l /bin/sh|g' \
		"${rootfs}/etc/inittab"

	${sudo} sed --in-place \
		's|#ttyS0|ttyS0|g' \
		"${rootfs}/etc/inittab"

	if [[ "${target_arch}" = 'arm'* ]]; then
		grep 'ttyS0' "${rootfs}/etc/inittab" | \
			sed 's|ttyS0|ttyAMA0|g' | \
			sudo_append "${rootfs}/etc/inittab"
	fi
}

setup_sshd() {
	local rootfs=${1}
	local srv_key=${2}

	${sudo} mkdir -p "${rootfs}/etc/dropbear"

	if [[ ${#server_keys[@]} -gt 0 ]]; then
		${sudo} cp -avf "${server_keys[@]}" "${rootfs}/etc/dropbear/"
	else
		enter_chroot "${rootfs}" "
			set -e
			/usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
			/usr/bin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
			/usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
		"
	fi

	echo "${script_name}: USER=@$(id --user --real --name)@" >&2
	# ${sudo} cp -f "${rootfs}/etc/dropbear/dropbear_rsa_host_key" "${srv_key}"
	# ${sudo} chown "$(id --user --real --name)": "${srv_key}"

	#echo 'DROPBEAR_OPTS=""' | sudo_write ${rootfs}/etc/conf.d/dropbear
}

setup_relay_client() {
	local rootfs=${1}

	local tdd_script="/usr/sbin/tdd-relay-client.sh"
	local tdd_service="/etc/init.d/tdd-relay-client"
	local tdd_log="/var/log/tdd-relay-client.log"

	write_tdd_client_script "${rootfs}${tdd_script}"

	sudo_write "${rootfs}/${tdd_service}" <<EOF
#!/sbin/openrc-run

#set
#set -x

command="${tdd_script}"
command_background="yes"
pidfile="/run/tdd-relay-client.pid"
start_stop_daemon_args="--verbose --nocolor --stdout ${tdd_log} --stderr ${tdd_log}"

depend() {
	need net
	after firewall dropbear
}

EOF

	${sudo} chmod u+x "${rootfs}${tdd_service}"
	${sudo} ln -s "${tdd_service}" "${rootfs}/etc/runlevels/sysinit/"
}

alpine_os_mirror="http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases"

get_packages() {
	local type=${1}

	local base_packages="
		busybox-initscripts
		dropbear
		haveged
		openrc
	"

	local extra_packages="
		dropbear-scp
		efibootmgr
		efivar-libs
		file
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
