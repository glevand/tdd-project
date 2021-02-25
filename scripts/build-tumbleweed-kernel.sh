#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Builds OpenSUSE tumbleweed kernel." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help             - Show this help and exit." >&2
	echo "  -v --verbose          - Verbose execution." >&2
	echo "  -c --config-file      - Default: '${config_file}'." >&2
	echo "  -p --toolchain-prefix - Default: '${toolchain_prefix}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --get              - Get rpms." >&2
	echo "  -2 --prepare          - Prepare sources." >&2
	echo "  -3 --build            - Build kernel." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvc:p:123"
	local long_opts="help,verbose,config-file:,toolchain-prefix:,get,prepare,build"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	if [ $? != 0 ]; then
		echo "${script_name}: ERROR: Internal getopt" >&2
		exit 1
	fi

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			shift
			set -x
			verbose=1
			;;
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-p | --toolchain-prefix)
			toolchain_prefix="${2}"
			shift 2
			;;
		-1 | --get)
			step_get=1
			shift
			;;
		-2 | --prepare)
			step_prepare=1
			shift
			;;
		-3 | --build)
			step_build=1
			shift
			;;
		--)
			shift
			if [[ ${@} ]]; then
				set +o xtrace
				echo "${script_name}: ERROR: Got extra args: '${@}'" >&2
				usage
				exit 1
			fi
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	if [ -d ${tmp_dir} ]; then
		rm -rf "${tmp_dir:?}"
	fi

	local end_time=${SECONDS}
	set +x
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

get_rpms() {
	#local base_url="http://download.opensuse.org/ports/aarch64/tumbleweed/repo/oss"
	local base_url="http://download.opensuse.org/repositories/devel:/ARM:/Factory:/Contrib:/ILP32/standard"

	local k_bin_url="${base_url}/aarch64/${k_bin}.rpm"
	local k_bin_dev_url="${base_url}/aarch64/${k_bin_dev}.rpm"
	local k_src_url="${base_url}/noarch/${k_src}.rpm"
	local k_dev_url="${base_url}/noarch/${k_dev}.rpm"
	local k_mac_url="${base_url}/noarch/${k_mac}.rpm"

	echo "out_dir = '${out_dir}'"

	mkdir -p "${out_dir}"

	pushd "${out_dir}"
	wget "${k_bin_url}"
	wget "${k_src_url}"
	wget "${k_dev_url}"
	wget "${k_bin_dev_url}"
	#wget "${k_mac_url}"
	popd

	mkdir -p "${out_dir}/${k_bin}"
	(cd "${out_dir}/${k_bin}" && ${SCRIPTS_TOP}/rpm2files.sh < "${out_dir}/${k_bin}.rpm")

	mkdir -p "${out_dir}/${k_src}"
	(cd "${out_dir}/${k_src}" && ${SCRIPTS_TOP}/rpm2files.sh < "${out_dir}/${k_src}.rpm")

	mkdir -p "${out_dir}/${k_dev}"
	(cd "${out_dir}/${k_dev}" && ${SCRIPTS_TOP}/rpm2files.sh < "${out_dir}/${k_dev}.rpm")

	#mkdir -p "${out_dir}/${k_bin_dev}"
	#(cd "${out_dir}/${k_bin_dev}" && ${SCRIPTS_TOP}/rpm2files.sh < "${out_dir}/${k_bin_dev}.rpm")

	#mkdir -p "${out_dir}/${k_mac}"
	#(cd "${out_dir}/${k_mac}" && ${SCRIPTS_TOP}/rpm2files.sh < "${out_dir}/${k_mac}.rpm")

	{
		echo -e "${k_src_url}\n${k_dev_url}\n${k_mac_url}\n${k_bin_url}\n${k_def_url}\n"
		ls -l "${out_dir}"
	} > "${out_dir}/kernel-${k_ver}.manifest"
	cat "${out_dir}/kernel-${k_ver}.manifest"
}

prepare_sources() {
	if [[ ! -d "${out_dir}/${k_bin}" ]]; then
		echo "${script_name}: ERROR: Binary RPM directory not found: '${out_dir}/${k_bin}'" >&2
		exit 1
	fi

	if [[ ! -d "${out_dir}/${k_src}" ]]; then
		echo "${script_name}: ERROR: Source RPM directory not found: '${out_dir}/${k_src}'" >&2
		exit 1
	fi

	if [[ ! -d "${out_dir}/${k_dev}" ]]; then
		echo "${script_name}: ERROR: Devel RPM directory not found: '${out_dir}/${k_dev}'" >&2
		exit 1
	fi

	rm -rf "${src_dir}"
	mkdir -p "${src_dir}"

	cp -a --link "${out_dir}/${k_src}/usr/src/"linux*/* "${out_dir}/${k_dev}/usr/src/"linux*/* "${src_dir}/"
	cp -v "${out_dir}/${k_bin}/boot"/config-*-64kb "${suse_config}"
}

build_kernel() {
	if [[ ! -d "${src_dir}" ]]; then
		echo "${script_name}: ERROR: Source directory not found: '${src_dir}'" >&2
		exit 1
	fi

	rm -rf "${build_dir}" "${install_dir}"
	mkdir -p "${build_dir}" "${install_dir}"
	
	local log_file="${out_dir}/build.log"

	${SCRIPTS_TOP}/build-linux-kernel.sh \
		${verbose_build:+--verbose} \
		--build-dir="${build_dir}" \
		--install-dir="${install_dir}" \
		arm64 "${src_dir}" defconfig 2>&1 | tee --append "${log_file}"


	cp -vf ${config_file} ${build_dir}/.config
	${SCRIPTS_TOP}/build-linux-kernel.sh \
		${verbose_build:+--verbose} \
		--build-dir="${build_dir}" \
		--install-dir="${install_dir}" \
		arm64 "${src_dir}"  olddefconfig 2>&1 | tee --append "${log_file}"

	${SCRIPTS_TOP}/build-linux-kernel.sh \
		${verbose_build:+--verbose} \
		--build-dir="${build_dir}" \
		--install-dir="${install_dir}" \
		arm64 "${src_dir}" all 2>&1 | tee --append "${log_file}"
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '

script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

trap "on_exit 'failed.'" EXIT
set -o pipefail
set -e

process_opts "${@}"

#k_ver=${k_ver:-"5.3.8-217.1"}
#k_ver=${k_ver:-"5.3.12-2.1"}
k_ver=${k_ver:-"5.4.7-227.1"}

k_bin="kernel-64kb-${k_ver}.aarch64"
k_bin_dev="kernel-64kb-devel-${k_ver}.aarch64"

k_src="kernel-source-${k_ver}.noarch"
k_dev="kernel-devel-${k_ver}.noarch"
k_mac="kernel-macros-${k_ver}.noarch"

out_dir=${out_dir:-"$(cd . && pwd)/kernel-${k_ver}"}

src_dir="${out_dir}/src"
build_dir="${out_dir}/build"
install_dir="${out_dir}/install"

suse_config="${src_dir}/suse-config"
config_file="${config_file:-${suse_config}}"

#verbose_build=1

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

SECONDS=0

if [[ ${step_get} ]]; then
	trap "on_exit '[get] failed.'" EXIT
	get_rpms
fi

if [[ ${step_prepare} ]]; then
	trap "on_exit '[prepare] failed.'" EXIT
	prepare_sources
fi

if [[ ${step_build} ]]; then
	trap "on_exit '[build] failed.'" EXIT
	build_kernel
fi

trap "on_exit 'Success.'" EXIT
exit 0
