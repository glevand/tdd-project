# phoronix test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/chroot.sh

test_usage_phoronix() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - Phoronix Test Suite." >&2
	echo "    The Phoronix Test Suite itself is an open-source framework for conducting automated"
	echo "    tests along with reporting of test results, detection of installed system"
	echo "    software/hardware, and other features."
	echo "  More Info:" >&2
	echo "    https://github.com/phoronix-test-suite/phoronix-test-suite/blob/master/README.md" >&2
	eval "${old_xtrace}"
}

test_packages_phoronix() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}" in
	alpine)
		echo 'php-cli'
		;;
	debian)
		echo 'php-cli'
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_setup_phoronix() {
	local rootfs_type=${1}
	local rootfs=${2}

	case "${rootfs_type}" in
	alpine)
		;;
	debian)
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_build_phoronix() {
	local rootfs_type=${1}
	local tests_dir=${2}
	local sysroot=${3}
	local kernel_src_dir=${4}

	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	sysroot="$(cd ${sysroot} && pwd)"
	kernel_src_dir="$(cd ${kernel_src_dir} && pwd)"

	local test_name='phoronix'
	local src_tar_url="https://phoronix-test-suite.com/releases/phoronix-test-suite-8.8.1.tar.gz"

	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"
	rm -rf ${archive_file} ${results_file}

	curl --silent --show-error --location ${src_tar_url} > ${archive_file}

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_phoronix() {
	local tests_dir=${1}
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_phoronix__ssh_opts=${4}
	local ssh_opts="${_test_run_phoronix__ssh_opts}"

	tests_dir="$(cd ${tests_dir} && pwd)"

	local test_name='phoronix'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${phoronix_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	case "${machine_type}" in
	qemu)
		phoronix_RUN_OPTS='-b /dev/vda -z /dev/vdb'
		;;
	remote)
		;;
	esac

	scp ${ssh_opts} ${archive_file} ${ssh_host}:phoronix.tar.gz

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} phoronix_RUN_OPTS="'${phoronix_RUN_OPTS}'" 'sh -s' <<'EOF'
export PS4='+phoronix-test-script:${LINENO}: '
set -ex

cat /proc/partitions
printenv

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

mkdir -p phoronix-test
tar -C phoronix-test -xf phoronix.tar.gz
cd ./phoronix-test/

ls -lah ./bin/phoronix-pan
echo "skippping tests for debug!!!"
mkdir -p ./results

set -e

tar -czvf ${HOME}/phoronix-results.tar.gz ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:phoronix-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:phoronix-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
