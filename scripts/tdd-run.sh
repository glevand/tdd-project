#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Builds TDD container image, Linux kernel, root file system images, runs test suites." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  --arch            - Target architecture {${known_arches}}. Default: ${target_arch}." >&2
	echo "  -a --help-all     - Show test help and exit." >&2
	echo "  -c --config-file  - ${script_name} config file. Default: '${config_file}'." >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	echo "  --build-name      - Build name. Default: '${build_name}'." >&2
	echo "  --linux-config    - URL of an alternate kernel config file. Default: '${linux_config}'." >&2
	echo "  --linux-source    - Linux kernel source tree path. Default: '${linux_source}'." >&2
	echo "  --linux-repo      - Linux kernel git repository URL. Default: '${linux_repo}'." >&2
	echo "  --linux-branch    - Linux kernel git repository branch. Default: '${linux_branch}'." >&2
	echo "  --linux-src-dir   - Linux kernel git repository path. Default: '${linux_src_dir}'." >&2
	echo "  --test-machine    - Test machine name {$(clean_ws ${TDD_TARGET_LIST}) qemu}. Default: '${test_machine}'." >&2
	echo "  --systemd-debug   - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  --rootfs-types    - Rootfs types to build {$(clean_ws ${known_rootfs_types}) all}. Default: '${rootfs_types}'." >&2
	echo "  --test-types      - Test types to run {$(clean_ws ${known_test_types}) all}. Default: '${test_types}'." >&2
	echo "  --hostfwd-offset  - QEMU hostfwd port offset. Default: '${hostfwd_offset}'." >&2
	echo "Option steps:" >&2
	echo "  --enter               - Enter container, no builds." >&2
	echo "  -1 --build-kernel     - Build kernel." >&2
	echo "  -2 --build-bootstrap  - Build rootfs bootstrap." >&2
	echo "  -3 --build-rootfs     - Build rootfs." >&2
	echo "  -4 --build-tests      - Build tests." >&2
	echo "  -5 --run-tests        - Run tests on test machine '${test_machine}'." >&2
	echo "Environment:" >&2
	echo "  TDD_PROJECT_ROOT    - Default: '${TDD_PROJECT_ROOT}'." >&2
	echo "  TDD_TEST_ROOT       - Default: '${TDD_TEST_ROOT}'." >&2
	echo "  TDD_CHECKOUT_SERVER - Default: '${TDD_CHECKOUT_SERVER}'." >&2
	echo "  TDD_RELAY_SERVER    - Default: '${TDD_RELAY_SERVER}'." >&2
	echo "  TDD_TFTP_SERVER     - Default: '${TDD_TFTP_SERVER}'." >&2
	echo "  TDD_HISTFILE        - Default: '${TDD_HISTFILE}'." >&2
	eval "${old_xtrace}"
}

test_usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "Test Plugin Info:" >&2
	for test in ${known_test_types}; do
		test_usage_${test/-/_}
		echo "" >&2
	done
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="ac:hv12345"
	local long_opts="\
arch:,help-all,config-file:,help,verbose,\
build-name:,\
linux-config:,linux-source:,linux-repo:,linux-branch:,linux-src-dir:,\
test-machine:,systemd-debug,rootfs-types:,test-types:,hostfwd-offset:,\
enter,build-kernel,build-bootstrap,build-rootfs,build-tests,run-tests"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		# echo "${FUNCNAME[0]}: (${#}) '${*}'"
		case "${1}" in
		--arch)
			target_arch=$(get_arch "${2}")
			shift 2
			;;
		-a | --help-all)
			help_all=1
			shift
			;;
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--build-name)
			build_name="${2}"
			shift 2
			;;
		--linux-config)
			linux_config="${2}"
			shift 2
			;;
		--linux-source)
			linux_source="${2}"
			shift 2
			;;
		--linux-repo)
			linux_repo="${2}"
			shift 2
			;;
		--linux-branch)
			linux_branch="${2}"
			shift 2
			;;
		--linux-src-dir)
			linux_src_dir="${2}"
			shift 2
			;;
		--test-machine)
			test_machine="${2}"
			shift 2
			;;
		--systemd-debug)
			systemd_debug=1
			shift
			;;
		--rootfs-types)
			rootfs_types="${2}"
			shift 2
			;;
		--test-types)
			test_types="${2}"
			shift 2
			;;
		--hostfwd-offset)
			hostfwd_offset="${2}"
			shift 2
			;;
		--enter)
			step_enter=1
			shift
			;;
		-1 | --build-kernel)
			step_build_kernel=1
			shift
			;;
		-2 | --build-bootstrap)
			step_build_bootstrap=1
			shift
			;;
		-3 | --build-rootfs)
			step_build_rootfs=1
			shift
			;;
		-4 | --build-tests)
			step_build_tests=1
			shift
			;;
		-5 | --run-tests)
			step_run_tests=1
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
	local result=${1}

	if [[ -d ${image_dir} ]]; then
		${sudo} chown -R $(id --user --real --name): ${image_dir}
	fi

	local end_time
	end_time="$(date)"
	local sec="${SECONDS}"

	set +x
	echo "${script_name}: start time: ${start_time}" >&2
	echo "${script_name}: end time:   ${end_time}" >&2
	echo "${script_name}: duration:   ${sec} sec ($(sec_to_min ${sec} min) min)" >&2
	echo "${script_name}: Done:       ${result}" >&2
}

check_machine() {
	local machine=${1}

	if [[ ${machine} == "qemu" ]]; then
		return
	fi

	set +e
	${SCRIPTS_TOP}/checkout-query.sh -v ${machine}
	result=${?}
	set -e

	if [[ ${result} -eq 0 ]]; then
		return
	elif [[ ${result} -eq 1 ]]; then
		echo "${script_name}: ERROR: unknown machine: '${machine}'" >&2
		usage
		exit 1
	fi
	exit ${result}
}

check_rootfs_types() {
	local given
	local known
	local found
	local all

	for given in ${rootfs_types}; do
		found="n"
		if [[ "${given}" == "all" ]]; then
			all=1
			continue
		fi
		for known in ${known_rootfs_types}; do
			if [[ "${given}" == "${known}" ]]; then
				found="y"
				break
			fi
		done
		if [[ "${found}" != "y" ]]; then
			echo "${script_name}: ERROR: Unknown rootfs-type '${given}'." >&2
			exit 1
		fi
		#echo "${FUNCNAME[0]}: Found '${given}'." >&2
	done

	if [[ ${all} ]]; then
		rootfs_types="$(clean_ws ${known_rootfs_types})"
	fi
}

check_test_types() {
	local given
	local known
	local found
	local all

	for given in ${test_types}; do
		found="n"
		if [[ "${given}" == "all" ]]; then
			all=1
			continue
		fi
		for known in ${known_test_types}; do
			if [[ "${given}" == "${known}" ]]; then
				found="y"
				break
			fi
		done
		if [[ "${found}" != "y" ]]; then
			echo "${script_name}: ERROR: Unknown test-type '${given}'." >&2
			usage
			exit 1
		fi
		#echo "${FUNCNAME[0]}: Found '${given}'." >&2
	done

	if [[ ${all} ]]; then
		test_types="$(clean_ws ${known_test_types})"
	fi
}

build_kernel_from_src() {
	local config=${1}
	local fixup_spec=${2}
	local platform_args=${3}
	local src_dir=${4}
	local build_dir=${5}
	local install_dir=${6}

	rm -rf "${build_dir}" "${install_dir}"

	local DEBUG="${DEBUG:-bash -x}"

	# build defconfig
	${DEBUG} "${SCRIPTS_TOP}/build-linux-kernel.sh" \
		${verbose:+--verbose} \
		--build-dir="${build_dir}" \
		--install-dir="${install_dir}" \
		${toolchain_prefix:+--toolchain-prefix="${toolchain_prefix}"} \
		"${target_arch}" "${src_dir}" defconfig

	# build config
	if [[ "${config}" && "${config}" != "defconfig" ]]; then
		if [[ -f "${config}" ]]; then
			cp -vf "${config}" "${build_dir}/.config"
			${DEBUG} "${SCRIPTS_TOP}/build-linux-kernel.sh" \
				${verbose:+--verbose} \
				--build-dir="${build_dir}" \
				--install-dir="${install_dir}" \
				${toolchain_prefix:+--toolchain-prefix="${toolchain_prefix}"} \
				"${target_arch}" "${src_dir}" olddefconfig
		else
			${DEBUG} "${SCRIPTS_TOP}/build-linux-kernel.sh" \
				${verbose:+--verbose} \
				--build-dir="${build_dir}" \
				--install-dir="${install_dir}" \
				${toolchain_prefix:+--toolchain-prefix="${toolchain_prefix}"} \
				"${target_arch}" "${src_dir}" "${config}"
		fi
	fi

	${DEBUG} "${SCRIPTS_TOP}/set-config-opts.sh" \
		--verbose \
		${platform_args:+--platform-args="${platform_args}"} \
		"${fixup_spec}" "${build_dir}/.config"


	# build all
	${DEBUG} "${SCRIPTS_TOP}/build-linux-kernel.sh" \
		${verbose:+--verbose} \
		--build-dir="${build_dir}" \
		--install-dir="${install_dir}" \
		${toolchain_prefix:+--toolchain-prefix="${toolchain_prefix}"} \
		"${target_arch}" "${src_dir}" all
}

build_kernel_from_repo() {
	local repo=${1}
	local branch=${2}
	local config=${3}
	local fixup_spec=${4}
	local platform_args=${5}
	local src_dir=${6}
	local build_dir=${7}
	local install_dir=${8}

	git_checkout_safe ${src_dir} ${repo} ${branch}

	build_kernel_from_src \
		"${config}" \
		"${fixup_spec}" \
		"${platform_args}" \
		"${src_dir}" \
		"${build_dir}" \
		"${install_dir}"
}

build_kernel_with_initrd() {
	local src_dir=${1}
	local build_dir=${2}
	local install_dir=${3}
	local image_dir=${4}

	check_file ${image_dir}/initrd
	ln -sf ./initrd ${image_dir}/initrd.cpio

	#export make_options_user="CONFIG_INITRAMFS_SOURCE=${image_dir}/initrd.cpio"

	make_options_user="CONFIG_INITRAMFS_SOURCE=${image_dir}/initrd.cpio" ${SCRIPTS_TOP}/build-linux-kernel.sh \
		--build-dir=${build_dir} \
		--install-dir=${install_dir} \
		${verbose:+--verbose} \
		${target_arch} ${src_dir} Image.gz
}

build_bootstrap() {
	local rootfs_type=${1}
	local bootstrap_dir=${2}

	${sudo} rm -rf ${bootstrap_dir}

	${SCRIPTS_TOP}/build-rootfs.sh \
		--arch=${target_arch} \
		--rootfs-type=${rootfs_type} \
		--bootstrap-dir="${bootstrap_dir}" \
		--image-dir="NA" \
		--bootstrap \
		--verbose
}

build_rootfs() {
	local rootfs_type=${1}
	local test_name=${2}
	local bootstrap_dir=${3}
	local image_dir=${4}
	local kernel_dir=${5}

	check_directory "${bootstrap_dir}"
	check_directory "${kernel_dir}"

	rm -rf ${image_dir}
	mkdir -p ${image_dir}

	local modules
	modules="$(find ${kernel_dir}/lib/modules/* -maxdepth 0 -type d)"
	check_directory "${modules}"

	local extra_packages
	extra_packages+="$(test_packages_${test_name//-/_} ${rootfs_type} ${target_arch})"

	${SCRIPTS_TOP}/build-rootfs.sh \
		--arch=${target_arch} \
		--rootfs-type=${rootfs_type} \
		--bootstrap-dir="${bootstrap_dir}" \
		--image-dir=${image_dir} \
		--kernel-modules="${modules}" \
		--extra-packages="${extra_packages}" \
		--rootfs-setup \
		--make-image \
		--verbose

	test_setup_${test_name//-/_} ${rootfs_type} ${image_dir}/rootfs
}

create_sysroot() {
	local rootfs_type=${1}
	local rootfs=${2}
	local sysroot=${3}

	check_directory "${rootfs}"

	mkdir -p ${sysroot}
	${sudo} rsync -a --delete ${rootfs}/ ${sysroot}/
	${sudo} chown $(id --user --real --name): ${sysroot}

	${SCRIPTS_TOP}/prepare-sysroot.sh \
		${verbose:+--verbose} \
		${sysroot}
}

build_tests() {
	local rootfs_type=${1}
	local test_name=${2}
	local tests_dir=${3}
	local sysroot=${4}
	local kernel_src=${5}

	check_directory "${sysroot}"
	check_directory "${kernel_src}"

	test_build_${test_name//-/_} ${rootfs_type} ${tests_dir} ${sysroot} \
		${kernel_src}
}

run_tests() {
	local kernel=${1}
	local image_dir=${2}
	local tests_dir=${3}
	local results_dir=${4}

	echo "${script_name}: run_tests: ${test_machine}" >&2

	check_file ${kernel}
	check_directory ${image_dir}
	check_file ${image_dir}/initrd
	check_file ${image_dir}/login-key
	check_directory ${tests_dir}

	local test_script
	local extra_args

	if [[ ${test_machine} == 'qemu' ]]; then
		test_script="${SCRIPTS_TOP}/run-kernel-qemu-tests.sh"
		extra_args+=" --arch=${target_arch} ${hostfwd_offset:+--hostfwd-offset=${hostfwd_offset}}"
	else
		test_script="${SCRIPTS_TOP}/run-kernel-remote-tests.sh"
		extra_args+=" --test-machine=${test_machine}"
	fi

	if [[ ${systemd_debug} ]]; then
		extra_args+=" --systemd-debug"
	fi

	bash -x ${test_script} \
		--kernel=${kernel} \
		--initrd=${image_dir}/initrd \
		--ssh-login-key=${image_dir}/login-key \
		--test-name=${test_name} \
		--tests-dir=${tests_dir} \
		--out-file=${results_dir}/${test_machine}-console.txt \
		--result-file=${results_dir}/${test_machine}-result.txt \
		${extra_args} \
		--verbose
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-main}):\[\e[0m\] '

script_name="${0##*/}"

trap "on_exit '[setup] failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
DOCKER_TOP=${DOCKER_TOP:-"$(cd "${SCRIPTS_TOP}/../docker" && pwd)"}

source "${SCRIPTS_TOP}/tdd-lib/util.sh"
source "${SCRIPTS_TOP}/rootfs-plugin/rootfs-plugin.sh"
source "${SCRIPTS_TOP}/test-plugin/test-plugin.sh"

for test in ${known_test_types}; do
	if [[ -f ${SCRIPTS_TOP}/test-plugin/${test}/${test}.sh ]]; then
		source "${SCRIPTS_TOP}/test-plugin/${test}/${test}.sh"
	else
		echo "${script_name}: ERROR: Test plugin '${test}.sh' not found." >&2
		exit 1
	fi
done

set -x

sudo="sudo -S"
parent_ops="$@"

start_time="$(date)"
SECONDS=0

process_opts "${@}"

config_file="${config_file:-${SCRIPTS_TOP}/tdd-run.conf}"
check_file ${config_file} " --config-file" "usage"
source ${config_file}

container_work_dir=${container_work_dir:-"/tdd--test"}

test_machine=${test_machine:-"qemu"}
test_machine=${test_machine%-bmc}

build_name=${build_name:-"${script_name%.*}-$(date +%m.%d)"}
target_arch=${target_arch:-"arm64"}
host_arch=$(get_arch "$(uname -m)")

top_build_dir="$(pwd)/${build_name}"

TDD_PROJECT_ROOT=${TDD_PROJECT_ROOT:-"$(cd ${SCRIPTS_TOP}/.. && pwd)"}
TDD_TEST_ROOT=${TDD_TEST_ROOT:-"$(pwd)"}
TDD_HISTFILE=${TDD_HISTFILE:-"${container_work_dir}/${build_name}--bash_history"}

rootfs_types=${rootfs_types:-"debian"}
rootfs_types="${rootfs_types//,/ }"

test_types=${test_types:-"sys-info"}
test_types="${test_types//,/ }"

linux_config=${linux_config:-"defconfig"}

if [[ ${linux_source} ]]; then
	check_not_opt 'linux-source' 'linux-repo' ${linux_repo}
	check_not_opt 'linux-source' 'linux-branch' ${linux_branch}
	check_not_opt 'linux-source' 'linux-src-dir' ${linux_src_dir}

	check_directory ${linux_source} "" "usage"
	linux_src_dir="${linux_source}"
else
	linux_repo=${linux_repo:-"https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"}
	linux_branch=${linux_branch:-"linux-5.3.y"}
	linux_src_dir=${linux_src_dir:-"${top_build_dir}/$(git_get_repo_name ${linux_repo})"}
fi

kernel_build_dir="${top_build_dir}/${target_arch}-kernel-build"
kernel_install_dir="${top_build_dir}/${target_arch}-kernel-install"

case ${target_arch} in
arm64)
	fixup_spec="${SCRIPTS_TOP}/targets/arm64/tx2/tx2-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/Image"
	;;
ppc*)
	fixup_spec="${SCRIPTS_TOP}/targets/powerpc/powerpc-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/vmlinux.strip"
	;;
*)
	fixup_spec="${SCRIPTS_TOP}/targets/generic-fixup.spec"
	kernel_image="${kernel_install_dir}/boot/vmlinux.strip"
	;;
esac

if [[ ${help_all} ]]; then
	set +o xtrace
	usage
	echo "" >&2
	test_usage
	trap - EXIT
	exit 0
fi

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${TDD_BUILDER} ]]; then
	if [[ ${step_enter} ]]; then
		echo "${script_name}: ERROR: Already in tdd-builder." >&2
		exit 1
	fi
else
	check_directory ${TDD_PROJECT_ROOT} "" "usage"
	check_directory ${TDD_TEST_ROOT} "" "usage"

	${DOCKER_TOP}/builder/build-builder.sh

	echo "${script_name}: Entering ${build_name} container..." >&2

	if [[ ${step_enter} ]]; then
		docker_cmd="/bin/bash"
	else
		docker_cmd="/tdd/scripts/tdd-run.sh ${parent_ops}"
	fi

	${SCRIPTS_TOP}/run-builder.sh \
		--verbose \
		--container-name="${build_name}" \
		--docker-args="\
			-e build_name \
			-v ${TDD_PROJECT_ROOT}:/tdd-project:ro \
			-e TDD_PROJECT_ROOT=/tdd-project \
			-v ${TDD_TEST_ROOT}:${container_work_dir}:rw,z \
			-e TDD_TEST_ROOT=${container_work_dir} \
			-w ${container_work_dir} \
			-e HISTFILE=${TDD_HISTFILE} \
		" \
		-- "${docker_cmd}"

	trap "on_exit 'container success.'" EXIT
	exit 0
fi

check_rootfs_types
check_test_types
if [[ ${step_run_tests} ]]; then
	check_machine "${test_machine}"
fi

step_code="${step_build_kernel:-"0"}${step_build_bootstrap:-"0"}\
${step_build_rootfs:-"0"}${step_build_tests:-"0"}${step_run_tests:-"0"}\
${step_run_remote_tests:-"0"}"

if [[ "${step_code}" == "000000" ]]; then
	echo "${script_name}: ERROR: No step options provided." >&2
	usage
	exit 1
fi

printenv

if [[ ${step_build_bootstrap} || ${step_build_rootfs} ]]; then
	${sudo} true
fi

mkdir -p ${top_build_dir}

if [[ ${step_build_kernel} ]]; then
	trap "on_exit '[build_kernel] failed.'" EXIT

	if [[ ${linux_source} ]]; then
		build_kernel_from_src \
			"${linux_config}" \
			"${fixup_spec}" \
			"${kernel_platform_args}" \
			"${linux_src_dir}" \
			"${kernel_build_dir}" \
			"${kernel_install_dir}"
	else
		build_kernel_from_repo \
			"${linux_repo}" \
			"${linux_branch}" \
			"${linux_config}" \
			"${fixup_spec}" \
			"${kernel_platform_args}" \
			"${linux_src_dir}" \
			"${kernel_build_dir}" \
			"${kernel_install_dir}"
	fi
fi

for rootfs_type in ${rootfs_types}; do

	bootstrap_prefix="${top_build_dir}/${target_arch}-${rootfs_type}"
	bootstrap_dir="${bootstrap_prefix}.bootstrap"

	if [[ ${step_build_bootstrap} ]]; then
		trap "on_exit '[build_bootstrap] failed.'" EXIT
		build_bootstrap ${rootfs_type} ${bootstrap_dir}
	fi

	for test_name in ${test_types}; do
		trap "on_exit 'test loop failed.'" EXIT

		output_prefix="${bootstrap_prefix}-${test_name}"
		image_dir=${output_prefix}.image
		tests_dir=${output_prefix}.tests
		results_dir=${output_prefix}.results
	
		echo "${script_name}: INFO: ${test_name} => ${output_prefix}" >&2

		if [[ ${step_build_rootfs} ]]; then
			trap "on_exit '[build_rootfs] failed.'" EXIT
			build_rootfs ${rootfs_type} \
				${test_name} \
				${bootstrap_dir} \
				${image_dir} \
				${kernel_install_dir}
			create_sysroot ${rootfs_type} ${image_dir}/rootfs \
				${image_dir}/sysroot
			#build_kernel_with_initrd ${linux_src_dir} \
			#	${kernel_build_dir} ${kernel_install_dir} \
			#	${image_dir}
		fi

		if [[ ${step_build_tests} ]]; then
			trap "on_exit '[build_tests] failed.'" EXIT
			build_tests ${rootfs_type} ${test_name} ${tests_dir} \
				${image_dir}/sysroot ${linux_src_dir}
		fi

		if [[ ${step_run_tests} ]]; then
			trap "on_exit '[run_tests] failed.'" EXIT
			run_tests ${kernel_image} ${image_dir} ${tests_dir} \
				${results_dir}
		fi
	done
done

trap "on_exit 'Success.'" EXIT
exit 0
