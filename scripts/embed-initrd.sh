#!/usr/bin/env bash

# TODO: Not working yet.
#
# arm64 variables of interest:
#  ffff0000111a8120 g O .init.data 0000000000000008 phys_initrd_start
#  ffff0000111a8128 g O .init.data 0000000000000008 phys_initrd_size
#  ffff00001122d1f0 g   .init.data 0000000000000000 __initramfs_start
#  ffff00001eb61708 g   .init.data 0000000000000000 __initramfs_size
#  ffff00001ed21070 g O .bss       0000000000000008 initrd_end
#  ffff00001ed21078 g O .bss       0000000000000008 initrd_start

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Embed initrd into kernel (work in progress)." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "  --arch       - Target architecture. Default: '${target_arch}'." >&2
	echo "  --kernel     - Kernel image. Default: '${kernel}'." >&2
	echo "  --initrd     - Initrd image. Default: '${initrd}'." >&2
	echo "  --out-file   - Output image. Default: '${out_file}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose,arch:,kernel:,initrd:,out-file:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
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
		--kernel)
			kernel="${2}"
			shift 2
			;;
		--initrd)
			initrd="${2}"
			shift 2
			;;
		--out-file)
			out_file="${2}"
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

	if [[ -d ${tmp_dir} ]]; then
		rm -rf ${tmp_dir}
	fi

	echo "${script_name}: ${result}" >&2
}

embed_initrd() {
	local dir=${initrd%/*}
	local in_file=${initrd##*/}

	rm -f ${out_file}

	pushd ${dir}
	${target_tool_prefix}objcopy \
		-I binary \
		-O ${target_bfdname} \
		-B ${target_arch} \
-		-N initramfs_start \
-		-N initramfs_size \
		--redefine-sym phys_initrd_start=.init.ramfs \
		--redefine-sym phys_initrd_size=.init.ramfs + ??? \
		${in_file} ${initrd_elf}
	popd

	${target_tool_prefix}objcopy \
		-I ${target_bfdname} \
		-O ${target_bfdname} \
		-R .init.ramfs \
		--add-section .init.ramfs=${initrd_elf} \
		${kernel} ${out_file}
}

#===============================================================================
# program start
#===============================================================================

set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source ${SCRIPTS_TOP}/lib/util.sh

trap "on_exit 'failed.'" EXIT

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")

target_arch=${target_arch:-"${host_arch}"}

if [[ ! ${out_file} ]]; then
	out_file="${kernel}.embedded"
fi

if [[ -n "${usage}" ]]; then
	usage
	trap "on_exit 'Done, success.'" EXIT
	exit 0
fi

case ${target_arch} in
arm64|aarch64)
	target_arch="aarch64"
	target_bfdname="elf64-littleaarch64"
	target_tool_prefix=${target_tool_prefix:-"aarch64-linux-gnu-"}
	;;
amd64|x86_64)
	target_arch="x86_64"
	target_tool_prefix=${target_tool_prefix:-"x86_64-linux-gnu-"}
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'.  Must be arm64." >&2
	exit 1
	;;
*)
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'.  Must be arm64." >&2
	exit 1
	;;
esac


check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"
initrd_elf="${tmp_dir}/initrd.elf"

embed_initrd

${target_tool_prefix}objcopy  -O binary -R .note -R .note.gnu.build-id -R .comment -S ${out_file} ${out_file}.Image

${target_tool_prefix}objdump --syms ${kernel} > ${out_file}.orig.syms
${target_tool_prefix}objdump --syms ${initrd_elf} > ${out_file}.initrd.syms
${target_tool_prefix}objdump --syms ${out_file} > ${out_file}.syms

echo "${script_name}: INFO: Output file: '${out_file}'." >&2
trap "on_exit 'Done, success.'" EXIT
exit 0
