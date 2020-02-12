#!/usr/bin/env bash

usage() {
	local target_list
	target_list="$(clean_ws "${targets}")"
	local op_list
	op_list="$(clean_ws "${ops}")"

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Builds linux kernel." >&2
	echo "Usage: ${script_name} [flags] <target> <kernel_src> <op>" >&2
	echo "Option flags:" >&2
	echo "  -h --help             - Show this help and exit." >&2
	echo "  -v --verbose          - Verbose execution." >&2
	echo "  -b --build-dir        - Build directory. Default: '${build_dir}'." >&2
	echo "  -i --install-dir      - Target install directory. Default: '${install_dir}'." >&2
	echo "  -l --local-version    - Default: '${local_version}'." >&2
	echo "  -p --toolchain-prefix - Default: '${toolchain_prefix}'." >&2
	echo "Args:" >&2
	echo "  <target> - Build target {${target_list}}." >&2
	echo "  Default target: '${target}'." >&2
	echo "  <kernel-src> - Kernel source directory." >&2
	echo "  Default kernel-src: '${kernel_src}'." >&2
	echo "  <op> - Build operation {${op_list}}." >&2
	echo "  Default op: '${op}'." >&2
	echo "Info:" >&2
	echo "  ${cpus} CPUs available." >&2

	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvb:i:l:p:"
	local long_opts="help,verbose,\
build-dir:,install-dir:,local-version:,toolchain-prefix:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			verbose=1
			set -x
			shift
			;;
		-b | --build-dir)
			build_dir="${2}"
			shift 2
			;;
		-l | --local-version)
			local_version="${2}"
			shift 2
			;;
		-t | --install-dir)
			install_dir="${2}"
			shift 2
			;;
		-p | --toolchain-prefix)
			toolchain_prefix="${2}"
			shift 2
			;;
		--)
			target=${2}
			kernel_src=${3}
			op=${4}
			if [[ ${check} ]]; then
				break
			fi
			if ! shift 4; then
				echo "${script_name}: ERROR: Missing args:" >&2
				echo "${script_name}:        <target>='${target}'" >&2
				echo "${script_name}:        <kernel_src>='${kernel_src}'" >&2
				echo "${script_name}:        <op>='${op}'" >&2
				usage
				exit 1
			fi
			if [[ -n "${1}" ]]; then
				echo "${script_name}: ERROR: Got extra args: '${*}'" >&2
				usage
				exit 1
			fi
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
	local result=${?}
	local end_time
	end_time="$(date)"
	local sec="${SECONDS}"

	if [ -d "${tmp_dir}" ]; then
		rm -rf "${tmp_dir}"
	fi

	set +x
	echo "" >&2
	echo "${script_name}: Done:          result=${result}" >&2
	echo "${script_name}: target:        ${target}" >&2
	echo "${script_name}: op:            ${op}" >&2
	echo "${script_name}: kernel_src:    ${kernel_src}" >&2
	echo "${script_name}: build_dir:     ${build_dir}" >&2
	echo "${script_name}: install_dir:   ${install_dir}" >&2
	echo "${script_name}: local_version: ${local_version}" >&2
	echo "${script_name}: make_options:  ${make_options}" >&2
	echo "${script_name}: start_time:    ${start_time}" >&2
	echo "${script_name}: end_time:      ${end_time}" >&2
	echo "${script_name}: duration:      ${sec} sec ($(sec_to_min ${sec} min) min)" >&2
	exit ${result}
}

run_make_fresh() {
	cp "${build_dir}/.config" "${tmp_dir}/config.tmp"
	rm -rf "${build_dir:?}"/{*,.*} &>/dev/null || :
	eval "${make_cmd} ${make_options} mrproper"
	eval "${make_cmd} ${make_options} defconfig"
	cp "${tmp_dir}/config.tmp" "${build_dir}/.config"
	eval "${make_cmd} ${make_options} olddefconfig"
}

run_make_targets() {
	eval "${make_cmd} ${make_options} savedefconfig"
	eval "${make_cmd} ${make_options} ${target_make_targets}"
}

run_install_image() {
	mkdir -p "${install_dir}/boot"
	cp "${build_dir}"/{defconfig,System.map,vmlinux} "${install_dir}/boot/"
	cp "${build_dir}/.config" "${install_dir}/boot/config"
	"${toolchain_prefix}strip" -s -R .comment "${build_dir}/vmlinux" -o "${install_dir}/boot/vmlinux.strip"

	if [[ -z "${target_copy}" ]]; then
		eval "${make_cmd} ${make_options} install"
	else
		for ((i = 0; i <= ${#target_copy[@]} - 1; i += 2)); do
			cp --no-dereference "${build_dir}/${target_copy[i]}" "${install_dir}/${target_copy[i+1]}"
		done
	fi

	if [[ -n "${target_copy_extra}" ]]; then
		for ((i = 0; i <= ${#target_copy_extra[@]} - 1; i += 2)); do
			if [[ -f "${target_copy_extra[i]}" ]]; then
				cp --no-dereference "${build_dir}/${target_copy_extra[i]}" "${install_dir}/${target_copy_extra[i+1]}"
			fi
		done
	fi
}

run_install_modules() {
	mkdir -p "${install_dir}/lib/modules"
	eval "${make_cmd} ${make_options} modules_install"
}

default_toolchain_prefix() {
	local target="${1}"

	case "${target}" in
	amd64)
		echo "x86_64-linux-gnu-"
		;;
	arm64|arm64_be)
		echo "aarch64-linux-gnu-"
		;;
	ppc32|ppc64)
		echo "powerpc-linux-gnu-"
		;;
	ppc64le)
		echo "powerpc64le-linux-gnu-"
		;;
	ps3)
		echo "powerpc-linux-gnu-"
		;;
	*)
		echo ""
		;;
	esac
}

set_target_variables() {
	local target="${1}"

# target_make_options: 
# target_defconfig: 
# target_copy: (src dest)
# target_copy_extra: (src dest)
# target_make_targets

	case "${target}" in
	amd64)
		target_make_options="ARCH=x86_64 CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
		)
		;;
	arm64|arm64_be)
		target_make_options="ARCH=arm64 CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_copy=(
			vmlinux boot/
			arch/arm64/boot/Image boot/
		)
		;;
	native)
		target_make_options="CROSS_COMPILE='${ccache}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_make_targets="all"
		;;
	ppc32|ppc64)
		target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
		)
		;;
	ppc64le)
		target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_copy=(
			vmlinux boot/
		)
		;;
	ps3)
		target_make_options="ARCH=powerpc CROSS_COMPILE='""${ccache}${toolchain_prefix}""'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
			arch/powerpc/boot/dtbImage.ps3.bin boot/linux
		)
		target_copy_extra=(
			arch/powerpc/boot/otheros.bld boot/
		)
		;;
	*)
		echo "${script_name}: ERROR: Unknown target: '${target}'" >&2
		usage
		exit 1
		;;
	esac
}
#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source "${SCRIPTS_TOP}/lib/util.sh"

trap "on_exit 'failed.'" EXIT

targets="
	amd64
	arm64
	arm64_be
	native
	ppc32
	ppc64
	ppc64le
	ps3
	x86_64
"
ops="
	all: fresh targets install_image install_modules
	build: targets
	defconfig
	fresh
	headers: mrproper defconfig prepare
	image_install
	install: install_image install_modules
	modules_install
	rebuild: clean targets
	savedefconfig
	targets
	gconfig
	menuconfig
	oldconfig
	olddefconfig
	xconfig
"

cpus="$(cpu_count)"

make_cmd="${make_cmd:-env PS4='+ \${0##*/}: ' make}"

process_opts "${@}"

if [[ ${build_dir} ]]; then
	build_dir="$(realpath "${build_dir}")"
else
	build_dir="$(pwd)/${target}-kernel-build"
fi

if [[ ${install_dir} ]]; then
	mkdir -p "${install_dir}"
	install_dir="$(realpath "${install_dir}")"
else
	install_dir="${build_dir%-*}-install"
	mkdir -p "${install_dir}"
fi

if [[ ! ${local_version} ]]; then
	local_version="${kernel_src##*/}"
fi

toolchain_prefix="${toolchain_prefix:-$(default_toolchain_prefix "${target}")}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

check_directory "${kernel_src}" "" "usage"

if test -x "$(command -v ccache)"; then
	ccache='ccache '
else
	echo "${script_name}: INFO: Please install ccache" >&2
fi

declare -a target_copy
declare -a target_copy_extra

set_target_variables "${target}"

declare -A target_args

if [[ ${verbose} ]]; then
	make_options_extra="V=1"
fi

make_options_user="${make_options_user:-}"

make_options="-j${cpus} ${target_make_options} INSTALL_MOD_PATH='${install_dir}' INSTALL_PATH='${install_dir}/boot' INSTALLKERNEL=non-existent-file O='${build_dir}' ${make_options_extra} ${make_options_user}"

start_time="$(date)"
SECONDS=0

export CCACHE_DIR=${CCACHE_DIR:-"${build_dir}.ccache"}

mkdir -p "${build_dir}"
mkdir -p "${CCACHE_DIR}"

cd "${kernel_src}"

tmp_dir="$(mktemp --tmpdir --directory "${script_name}.XXXX")"

case "${op}" in
all)
	run_make_fresh
	run_make_targets
	run_install_image
	run_install_modules
	;;
defconfig)
	if [[ -n ${target_defconfig} ]]; then
		eval "make ${make_options} ${target_defconfig}"
	else
		eval "make ${make_options} defconfig"
	fi
	eval "make ${make_options} savedefconfig"
	;;
fresh)
	run_make_fresh
	;;
headers)
	eval "${make_cmd} ${make_options} mrproper"
	eval "${make_cmd} ${make_options} defconfig"
	eval "${make_cmd} ${make_options} prepare"
	;;
image_install)
	run_install_image
	;;
install)
	run_install_image
	run_install_modules
	;;
modules_install)
	run_install_modules
	;;
rebuild)
	eval "${make_cmd} ${make_options} clean"
	run_make_targets
	;;
savedefconfig)
	eval "${make_cmd} ${make_options} savedefconfig"
	;;
build|targets)
	run_make_targets
	;;
gconfig | menuconfig | oldconfig | olddefconfig | xconfig)
	eval "${make_cmd} ${make_options} ${op}"
	eval "${make_cmd} ${make_options} savedefconfig"
	;;
*)
	echo "${script_name}: INFO: Unknown op: '${op}'" >&2
	eval "${make_cmd} ${make_options} ${op}"
	;;
esac
