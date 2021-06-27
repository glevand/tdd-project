#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace

	local target_list
	target_list="$(clean_ws "${targets}")"

	local op_list
	op_list="$(clean_ws "${ops}")"

	{
		echo "${script_name} - Builds linux kernel."
		echo "Usage: ${script_name} [flags] <target> <kernel_src> <op>"
		echo ''
		echo 'Option flags:'
		echo "  -b --build-dir        - Build directory. Default: '${build_dir}'."
		echo "  -i --install-dir      - Target install directory. Default: '${install_dir}'."
		echo "  -l --local-version    - Default: '${local_version}'."
		echo "  -p --toolchain-prefix - Default: '${toolchain_prefix}'."
		echo "  -V --vbuild           - Verbose kernel build."
		echo "  -h --help             - Show this help and exit."
		echo "  -v --verbose          - Verbose execution."
		echo "  -g --debug            - Extra verbose execution."
		echo ''
		echo 'Args:'
		echo "  <target>     - Build target.  Default: '${target}'."
		echo "  <kernel-src> - Kernel source directory.  Default : '${kernel_src}'."
		echo "  <op>         - Build operation.  Default: '${op}'."
		echo ''
		echo "  Known targets: ${target_list}"
		echo ''
		echo "  Known ops: ${op_list}"
		echo ''
		echo 'System Info:'
		echo "  ${cpus} CPUs available."
		echo ''
		echo 'Info:'
		echo "  ${script_name} (@PACKAGE_NAME@) version @PACKAGE_VERSION@"
		echo "  @PACKAGE_URL@"
		echo "  Send bug reports to: Geoff Levand <geoff@infradead.org>."
	} >&2

	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="b:i:l:p:Vhvg"
	local long_opts="build-dir:,install-dir:,local-version:,\
toolchain-prefix:,vbuild,help,verbose,debug"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		-b | --build-dir)
			build_dir="${2}"
			shift 2
			;;
		-i | --install-dir)
			install_dir="${2}"
			shift 2
			;;
		-l | --local-version)
			local_version="${2}"
			shift 2
			;;
		-p | --toolchain-prefix)
			toolchain_prefix="${2}"
			shift 2
			;;
		-V | --vbuild)
			vbuild=1
			shift
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
			shift
			;;
		--)
			shift
			target="${1:-}"
			kernel_src="${2:-}"
			op="${3:-}"
			if [[ ${4:-} ]]; then
				shift 3
				extra_args="${*}"
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

	if [ -d "${tmp_dir:-}" ]; then
		rm -rf "${tmp_dir:?}"
	fi

	{
		echo ''
		echo '======================================================================'
		echo 'ccache info:'
		echo '======================================================================'
		echo ''
		#${ccache} --show-config
		${ccache} --show-stats

		if [[ -s "${stderr_out}" ]]; then
			echo ''
			echo '======================================================================'
			echo 'stderr:'
			echo '======================================================================'
			echo ''
			cat "${stderr_out}"
		fi

		echo ''
		echo '======================================================================'
	} >&2

	local color
	local word
	if [[ ${result} -eq 0 ]]; then
		color="${ansi_green}"
		word="OK"
	else
		color="${ansi_red}"
		word="failed"
	fi

	set +x
	echo "" >&2
	echo -e "${script_name}: Done:          ${color}result = ${word} (${result})${ansi_reset}" >&2
	echo "${script_name}: target:        '${target}'" >&2
	echo "${script_name}: op:            '${op}'" >&2
	echo "${script_name}: kernel_src:    '${kernel_src}'" >&2
	echo "${script_name}: build_dir:     '${build_dir}'" >&2
	echo "${script_name}: install_dir:   '${install_dir}'" >&2
	echo "${script_name}: local_version: '${local_version}'" >&2
	echo "${script_name}: make_options:  ${make_options}" >&2
	echo "${script_name}: start_time:    ${start_time}" >&2
	echo "${script_name}: end_time:      ${end_time}" >&2
	echo "${script_name}: duration:      ${sec} sec ($(sec_to_min ${sec} min) min)" >&2
	exit ${result}
}

on_err() {
	local f_name=${1}
	local line_no=${2}
	local err_no=${3}

	if [[ ${debug} ]]; then
		echo '------------------------' >&2
		set >&2
		echo '------------------------' >&2
	fi
	echo "${script_name}: ERROR: (${err_no}) at ${f_name}:${line_no}." >&2
	exit "${err_no}"
}

run_cmd_tee () {
	eval "${*} 2> >(tee --append '${stderr_out}' >&2)"
}

run_make_fresh() {
	cp "${build_dir}/.config" "${tmp_dir}/config.tmp"
	rm -rf "${build_dir:?}"/{*,.*} &>/dev/null || :
	eval "${make_cmd} ${make_options} mrproper"
	eval "${make_cmd} ${make_options} defconfig"
	cp "${tmp_dir}/config.tmp" "${build_dir}/.config"
	eval "${make_cmd} ${make_options} olddefconfig"
}

run_make_target_ops() {
	local real_ops
	if [[ "${target_ops}" == 'defaults' ]]; then
		real_ops=''
	else
		real_ops="${target_ops}"
	fi
	eval "${make_cmd} ${make_options} savedefconfig"
	run_cmd_tee "${make_cmd} ${make_options} ${real_ops}"
}

run_install_image() {
	mkdir -p "${install_dir}/boot"
	cp "${build_dir}"/{defconfig,System.map,vmlinux} "${install_dir}/boot/"
	cp "${build_dir}/.config" "${install_dir}/boot/config"
	"${toolchain_prefix}strip" -s -R .comment "${build_dir}/vmlinux" -o "${install_dir}/boot/vmlinux.strip"

	if (( ${#target_copy[@]} == 0 )); then
		run_cmd_tee "${make_cmd} ${make_options} install"
	else
		for ((i = 0; i <= ${#target_copy[@]} - 1; i += 2)); do
			if [[ -e "${build_dir}/${target_copy[i]}" ]]; then
				cp --no-dereference "${build_dir}/${target_copy[i]}" "${install_dir}/${target_copy[i+1]}"
			else
				echo "${script_name}: INFO: target_copy file not found: '${build_dir}/${target_copy[i]}'" >&2
			fi
		done
	fi

	if (( ${#target_copy_extra[@]} != 0 )); then
		for ((i = 0; i <= ${#target_copy_extra[@]} - 1; i += 2)); do
			if [[ -f "${target_copy_extra[i]}" ]]; then
				cp --no-dereference "${build_dir}/${target_copy_extra[i]}" "${install_dir}/${target_copy_extra[i+1]}"
			fi
		done
	fi
}

run_install_modules() {
	mkdir -p "${install_dir}/lib/modules"
	run_cmd_tee "${make_cmd} ${make_options} modules_install"
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
# target_ops

	case "${target}" in
	amd64|x86_64)
		target_make_options="ARCH=x86_64 CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
			arch/x86/boot/bzImage boot/
		)
		target_copy_extra=()
		target_ops='defaults'
		;;
	arm64|arm64_be)
		target_make_options="ARCH=arm64 CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_copy=(
			vmlinux boot/
			arch/arm64/boot/Image boot/
		)
		target_copy_extra=()
		target_ops='defaults'
		;;
	native)
		target_make_options="CROSS_COMPILE='${ccache}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_copy=()
		target_copy_extra=()
		target_ops='all'
		;;
	ppc32|ppc64)
		target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
		)
		target_copy_extra=()
		target_ops='defaults'
		;;
	ppc64le)
		target_make_options="ARCH=powerpc CROSS_COMPILE='${ccache}${toolchain_prefix}'"
		target_defconfig="${target_defconfig:-defconfig}"
		target_copy=(
			vmlinux boot/
		)
		target_copy_extra=()
		target_ops='defaults'
		;;
	ps3)
		target_make_options="ARCH=powerpc CROSS_COMPILE='""${ccache}${toolchain_prefix}""'"
		target_defconfig="${target_defconfig:-${target}_defconfig}"
		target_copy=(
			vmlinux boot/
			arch/powerpc/boot/otheros.bld boot/
			arch/powerpc/boot/dtbImage.ps3.bin boot/linux
		)
		target_copy_extra=()
		target_ops='defaults'
		;;
	*)
		echo "${script_name}: ERROR: Unknown target: '${target}'" >&2
		usage
		exit 1
		;;
	esac
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"
# base_name="${script_name%.sh}"

start_time="$(date +%Y.%m.%d-%H.%M.%S)"
SECONDS=0

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}

targets='
	amd64
	arm64
	arm64_be
	native
	ppc32
	ppc64
	ppc64le
	ps3
	x86_64
'

target_ops='defaults'

ops="
	all: fresh ${target_ops} install_image install_modules
	all-no-mod: fresh ${target_ops} install_image
	build: ${target_ops}
	build-install: ${target_ops} install_image install_modules
	defconfig
	fresh
	help
	headers: mrproper defconfig prepare
	image_install
	install: install_image install_modules
	modules_install
	rebuild: clean ${target_ops}
	savedefconfig
	gconfig
	menuconfig
	oldconfig
	olddefconfig
	xconfig
"

trap "on_exit 'Failed'" EXIT
trap 'on_err ${FUNCNAME[0]} ${LINENO} ${?}' ERR

set -eE
set -o pipefail
set -o nounset

source "${SCRIPTS_TOP}/tdd-lib/util.sh"

cpus="$(cpu_count)"

ccache="${ccache:-ccache }"

build_dir=''
install_dir=''
local_version=''
toolchain_prefix=''
vbuild=''
usage=''
verbose=''
debug=''
extra_args=''

make_options=''
stderr_out=''

process_opts "${@}"

toolchain_prefix="${toolchain_prefix:-$(default_toolchain_prefix "${target}")}"
set_target_variables "${target}"

echo "target_copy count = '${#target_copy[@]}'"

if [[ ! ${build_dir} ]]; then
	build_dir="$(pwd)/${target}-kernel-build"
fi

build_dir="$(realpath -m "${build_dir}")"

if [[ ! ${install_dir} ]]; then
	install_dir="${build_dir%-*}-install"
fi

install_dir="$(realpath -m "${install_dir}")"

if [[ ! ${local_version} ]]; then
	local_version="${kernel_src##*/}"
fi

stderr_out="${build_dir}/stderr.out"
make_cmd="${make_cmd:-env PS4='+ \${0##*/}: ' make}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ! ${target} || ! ${kernel_src} || ! ${op} ]]; then
	{
		echo "${script_name}: ERROR: Missing args:"
		echo "${script_name}:   <target> = '${target}'"
		echo "${script_name}:   <kernel_src> = '${kernel_src}'"
		echo "${script_name}:   <op> = '${op}'"
		echo ""
	} >&2
	usage
	exit 1
fi

if [[ ${extra_args} ]]; then
	echo "${script_name}: ERROR: Got extra args: '${extra_args}'" >&2
	usage
	exit 1
fi

mkdir -p "${build_dir}"
mkdir -p "${install_dir}"
rm -f "${stderr_out}"

check_directory "${kernel_src}" "" "usage"

if [[ ! -f "${kernel_src}/Documentation/CodingStyle" ]]; then
	echo "${script_name}: ERROR: Check kernel sources: '${kernel_src}'" >&2
	exit 1
fi

progs="bc bison ${ccache} flex ${toolchain_prefix}gcc"
declare -A pairs=(
	[libelf-dev]='/usr/include/libelf.h'
	[libssl-dev]='/usr/include/openssl/evp.h'
	[libncurses-dev]='/usr/include/ncurses.h'
)

if ! check_progs_and_pairs "${progs}" pairs; then
	exit 2
fi

declare -a target_copy
declare -a target_copy_extra

make_options_extra=''

if [[ ${vbuild} ]]; then
	make_options_extra+=' V=1'
fi

make_options_user="${make_options_user:-}"

if test -x "$(command -v "depmod")"; then
	depmod=''
else
	depmod="${depmod:- DEPMOD=/bin/true}"
fi

make_options=" \
 -j${cpus} \
 ${target_make_options}${depmod} \
 INSTALL_MOD_PATH='${install_dir}' \
 INSTALL_PATH='${install_dir}/boot' \
 INSTALLKERNEL=non-existent-file \
 O='${build_dir}' \
 ${make_options_extra} \
 ${make_options_user} \
"

export CCACHE_DIR=${CCACHE_DIR:-"${build_dir}.ccache"}
export CCACHE_MAXSIZE="8G"
export CCACHE_NLEVELS="4"

mkdir -p "${build_dir}"
mkdir -p "${CCACHE_DIR}"

cd "${kernel_src}"

tmp_dir="$(mktemp --tmpdir --directory "${script_name}.XXXX")"

case "${op}" in
all)
	run_make_fresh
	run_make_target_ops
	run_install_image
	run_install_modules
	;;
all-no-mod)
	run_make_fresh
	run_make_target_ops
	run_install_image
	;;
build|targets)
	run_make_target_ops
	;;
build-install)
	run_make_target_ops
	run_install_image
	run_install_modules
	;;
defconfig)
	#if [[ ${target_defconfig} ]]; then
	#	eval "${make_cmd} ${make_options} ${target_defconfig}"
	#else
		eval "${make_cmd} ${make_options} defconfig"
	#fi
	eval "${make_cmd} ${make_options} savedefconfig"
	;;
fresh)
	run_make_fresh
	;;
help)
	eval "${make_cmd} ${make_options} help"
	;;
headers)
	eval "${make_cmd} ${make_options} mrproper"
	run_cmd_tee "${make_cmd} ${make_options} defconfig"
	run_cmd_tee "${make_cmd} ${make_options} prepare"
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
	run_make_target_ops
	;;
savedefconfig)
	eval "${make_cmd} ${make_options} savedefconfig"
	;;
gconfig | menuconfig | oldconfig | olddefconfig | xconfig)
	eval "${make_cmd} ${make_options} ${op}"
	eval "${make_cmd} ${make_options} savedefconfig"
	;;
*)
	echo "${script_name}: INFO: Unknown op: '${op}'" >&2
	run_cmd_tee "${make_cmd} ${make_options} ${op}"
	;;
esac
