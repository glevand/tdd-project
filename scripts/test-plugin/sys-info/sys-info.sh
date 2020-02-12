# System info test plug-in.

test_usage_sys_info() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - Collect system information." >&2
	eval "${old_xtrace}"
}

test_packages_sys_info() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}-${target_arch}" in
	alpine-arm64)
		echo "dmidecode"
		;;
	debian-arm64)
		echo "dmidecode"
		;;
	*)
		;;
	esac
}

test_setup_sys_info() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_sys_info() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_sys_info() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_sys_info__ssh_opts=${4}
	local ssh_opts="${_test_run_sys_info__ssh_opts}"

	local test_driver="sys-info-test.sh"
	local results_archive="${tests_dir}/sys-info-results.tar.gz"
	local remote_results_archive="/sys-info-results.tar.gz"
	local timeout=${sys_info_timeout:-"5m"}

	rm -rf ${results_archive}

	scp ${ssh_opts} ${TEST_TOP}/${test_driver} ${ssh_host}:/
	ssh ${ssh_opts} ${ssh_host} chmod +x /${test_driver}

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} \
		"TEST_NAME='sys-info' RESULTS_FILE='${remote_results_archive}' sh -c '/${test_driver}'"
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, sys-info failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		echo "${FUNCNAME[0]}: Done, sys-info failed: '${result}'." >&2
	else
		echo "${FUNCNAME[0]}: Done, sys-info success." >&2
	fi

	scp ${ssh_opts} ${ssh_host}:${remote_results_archive} ${results_archive}
}

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

TEST_TOP=${TEST_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
