#!/usr/bin/env sh
# generic test driver

on_exit() {
	local result=${1}

	set -x
	tar -czvf ${RESULTS_FILE} ${results_dir}
	echo "${TEST_NAME}: Done: ${result}" >&2
}

print_sys_info() {
	local log_file=${1}

	local rootfs_type=$(egrep '^ID=' /etc/os-release)
	local rootfs_type=${rootfs_type#ID=}

	set +x
	{
		echo '-----------------------------'
		echo -n 'date: '
		date
		echo -n 'uname: '
		uname -a
		echo "test name: ${TEST_NAME}"
		echo "rootfs_type: ${rootfs_type}"
		echo '-----------------------------'
		echo 'os-release:'
		cat /etc/os-release
		echo '-----------------------------'
		echo 'env:'
		env
		echo '-----------------------------'
		echo 'set:'
		set
		echo '-----------------------------'
		echo 'id:'
		id
		echo '-----------------------------'
		echo '/proc/partitions:'
		cat /proc/partitions
		echo '-----------------------------'
		echo 'dmidecode:'
		if [ -f /usr/sbin/dmidecode ]; then
			/usr/sbin/dmidecode
		else
			echo '/usr/sbin/dmidecode not found.'
		fi
		echo '-----------------------------'
	} 2>&1 | tee -a "${log_file}"
	set -x
}

#===============================================================================
# program start
#===============================================================================
set -x
export PS4='+ sys-info-test.sh: ${LINENO:-"?"}: '

TEST_NAME=${TEST_NAME:-"${1}"}

trap "on_exit 'failed.'" EXIT
set -e

test_home="/${TEST_NAME}"
mkdir -p "${test_home}"
cd "${test_home}"

results_dir=${test_home}/results
rm -rf "${results_dir}"
mkdir -p "${results_dir}"

print_sys_info "${results_dir}/test.log"

trap "on_exit 'Success.'" EXIT
exit 0
