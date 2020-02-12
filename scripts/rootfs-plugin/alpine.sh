# Alpine linux plug-in routines for build-rootfs.sh.

download_minirootfs() {
	local download_dir=${1}
	local -n _download_minirootfs__archive_file=${3}

	unset _download_minirootfs__archive_file

	case "${target_arch}" in
		amd64) 	alpine_arch="x86_64" ;;
		arm64) 	alpine_arch="aarch64" ;;
		*)
			echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
			exit 1
			;;
	esac
	local base_url="${alpine_os_mirror}/${alpine_arch}"

	mkdir -p ${download_dir}
	pushd ${download_dir}

	local releases_yaml="latest-releases.yaml"
	wget "${base_url}/${releases_yaml}"

	local latest
	latest="$(egrep --only-matching "file: alpine-minirootfs-[0-9.]*-${alpine_arch}.tar.gz" ${releases_yaml})"
	if [[ ! ${latest} ]]; then
		echo "${script_name}: ERROR: Bad releases file '${releases_yaml}'." >&2
		cat ${releases_yaml}
		exit 1
	fi
	latest=${latest##* }
	wget "${base_url}/${latest}"

	popd
	echo "${script_name}: INFO: Download '${latest}'." >&2
	_download_minirootfs__archive_file="${download_dir}/${latest}"
}

extract_minirootfs() {
	local archive=${1}
	local out_dir=${2}

	mkdir -p ${out_dir}
	tar -C ${out_dir} -xf ${archive}
}

bootstrap_rootfs() {
	local bootstrap_dir=${1}

	local download_dir="${tmp_dir}/downloads"
	local archive_file

	${sudo} rm -rf ${bootstrap_dir}

	download_minirootfs ${download_dir} ${alpine_os_mirror} archive_file
	extract_minirootfs ${archive_file} ${bootstrap_dir}

	rm -rf ${download_dir}

	setup_resolv_conf ${bootstrap_dir}

	enter_chroot ${bootstrap_dir} "
		set -e
		apk update
		apk upgrade
		apk add openrc \
			busybox-initscripts \
			dropbear \
			dropbear-scp \
			haveged \
			net-tools \
			strace
		cat /etc/os-release
		apk info | sort
	"

	${sudo} ln -s /etc/init.d/{hwclock,modules,sysctl,hostname,bootmisc,syslog} \
		${bootstrap_dir}/etc/runlevels/boot/
	${sudo} ln -s /etc/init.d/{devfs,dmesg,mdev,hwdrivers} \
		${bootstrap_dir}/etc/runlevels/sysinit/
	${sudo} ln -s /etc/init.d/{networking} \
		${bootstrap_dir}/etc/runlevels/default/
	${sudo} ln -s /etc/init.d/{mount-ro,killprocs,savecache} \
		${bootstrap_dir}/etc/runlevels/shutdown/

	${sudo} sed --in-place 's/^net.ipv4.tcp_syncookies/# net.ipv4.tcp_syncookies/' \
		${bootstrap_dir}/etc/sysctl.d/00-alpine.conf
	${sudo} sed --in-place 's/^kernel.panic/# kernel.panic/' \
		${bootstrap_dir}/etc/sysctl.d/00-alpine.conf
}

setup_network() {
	local rootfs=${1}

	setup_network_ifupdown ${rootfs}
}

rootfs_cleanup() {
	local rootfs=${1}

	#${sudo} rm -rf ${rootfs}/var/cache/apk
}

setup_packages() {
	local rootfs=${1}
	shift 1
	local packages="${@//,/ }"

	enter_chroot ${rootfs} "
		set -e
		apk add ${packages}
		apk add efivar-libs --repository http://dl-3.alpinelinux.org/alpine/edge/community --allow-untrusted
		apk add efibootmgr --repository http://dl-3.alpinelinux.org/alpine/edge/community --allow-untrusted
		apk info | sort
	"

	${sudo} ln -s /etc/init.d/{haveged,dropbear} \
		${rootfs}/etc/runlevels/sysinit/

	# for openrc debugging
	echo 'rc_logger="YES"' | sudo_append ${rootfs}/etc/rc.conf
	echo 'rc_verbose="YES"' | sudo_append ${rootfs}/etc/rc.conf
}

setup_initrd_boot() {
	local rootfs=${1}

	ln -s sbin/init ${rootfs}/init
}

setup_login() {
	local rootfs=${1}
	local pw=${2}

	setup_password ${rootfs} ${pw}

	${sudo} sed --in-place \
		's|/sbin/getty|/sbin/getty -n -l /bin/sh|g' \
		${rootfs}/etc/inittab

	${sudo} sed --in-place \
		's|#ttyS0|ttyS0|g' \
		${rootfs}/etc/inittab

	egrep 'ttyS0' ${rootfs}/etc/inittab | sed 's|ttyS0|ttyAMA0|g' | sudo_append ${rootfs}/etc/inittab
}

setup_sshd() {
	local rootfs=${1}
	local srv_key=${2}

	enter_chroot ${rootfs} "
		set -e
		mkdir -p /etc/dropbear/
		/usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
		/usr/bin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
		/usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
	"

	#echo "${script_name}: USER=@$(id --user --real --name)@" >&2
	${sudo} cp -f "${rootfs}/etc/dropbear/dropbear_rsa_host_key" ${srv_key}
	${sudo} chown $(id --user --real --name): ${srv_key}

	#echo 'DROPBEAR_OPTS=""' | sudo_write ${rootfs}/etc/conf.d/dropbear
}

setup_relay_client() {
	local rootfs=${1}

	local tdd_script="/usr/sbin/tdd-relay-client.sh"
	local tdd_service="/etc/init.d/tdd-relay-client"
	local tdd_log="/var/log/tdd-relay-client.log"

	write_tdd_client_script ${rootfs}${tdd_script}

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

	${sudo} chmod u+x ${rootfs}${tdd_service}
	${sudo} ln -s ${tdd_service} ${rootfs}/etc/runlevels/sysinit/
}

alpine_os_mirror="http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/"

get_default_packages() {
	local default_packages="
		file
		net-tools
		netcat-openbsd
		pciutils
		strace
		tcpdump
	"

	if [[ ${alpine_default_packages} ]]; then
		echo ${alpine_default_packages}
	else
		echo ${default_packages}
	fi
}
