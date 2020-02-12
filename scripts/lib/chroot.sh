#!/usr/bin/env bash

get_qemu_static() {
	local qemu_static

	case "${host_arch}--${target_arch}" in
	amd64--arm64)
		qemu_static="/usr/bin/qemu-aarch64-static"
		;;
	amd64--ppc32)
		qemu_static="/usr/bin/qemu-ppc-static"
		;;
	amd64--ppc64)
		qemu_static="/usr/bin/qemu-ppc64-static"
		;;
	arm64--amd64)
		qemu_static="/usr/bin/qemu-x86_64-static"
		;;
	*)
		echo "${script_name}: ERROR: Unsupported host--target combo: '${"${host_arch}--${target_arch}"}'." >&2
		exit 1
		;;
	esac

	if ! test -x "$(command -v ${qemu_static})"; then
		echo "${script_name}: ERROR: Please install QEMU user emulation '${qemu_static}'." >&2
		exit 1
	fi

	echo "${qemu_static}"
}

clean_qemu_static() {
	local chroot=${1}
	local qemu_static

	if [ "${host_arch}" != "${target_arch}" ]; then
		qemu_static="$(get_qemu_static)"
		${sudo} rm -f ${chroot}${qemu_static}
	fi
}

copy_qemu_static() {
	local chroot=${1}
	local qemu_static

	if [ "${host_arch}" != "${target_arch}" ]; then
		qemu_static="$(get_qemu_static)"
		${sudo} cp -f ${qemu_static} ${chroot}${qemu_static}
	fi
}


enter_chroot() {
	local chroot=${1}
	shift
	local script=${@}

	check_directory ${chroot}
	copy_qemu_static ${chroot}

	${sudo} mount -l -t proc
	${sudo} umount  ${chroot}/proc || :

	mkdir -p  ${chroot}/proc ${chroot}/sys ${chroot}/dev ${chroot}/run

	${sudo} mount -t proc -o nosuid,nodev,noexec /proc ${chroot}/proc
	${sudo} mount --rbind /sys ${chroot}/sys
	${sudo} mount --rbind /dev ${chroot}/dev
	${sudo} mount --rbind /run ${chroot}/run

	${sudo} LANG=C.UTF-8 PS4="+ chroot: " chroot ${chroot} /bin/sh -x <<EOF
${script}
EOF
	cleanup_chroot ${chroot}
}

cleanup_chroot () {
	local chroot=${1}

	clean_qemu_static ${chroot}

	${sudo} umount --recursive ${chroot}/{proc,sys,dev,run} &> /dev/null || :

	mount | egrep ${chroot} || :
}
