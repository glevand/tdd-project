#!/usr/bin/env sh
#
# spec-cpu test driver

on_exit() {
	local result=${1}

	tar -czvf ${RESULTS_FILE} ${results_dir}

	echo "ilp32-${TEST_NAME}: Done: ${result}" >&2
}

script_name="${0##*/}"
TEST_NAME=${TEST_NAME:-"${1}"}

export PS4='+ ilp32-${TEST_NAME}: '
set -x

trap "on_exit 'failed.'" EXIT
set -e

test_home="/ilp32-${TEST_NAME}"
mkdir -p ${test_home}
cd ${test_home}

results_dir=${test_home}/results
mkdir -p ${results_dir}

log_file=${results_dir}/test.log
rm -f ${log_file}

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

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
}  | tee -a ${log_file}

tar -C ${test_home} -xf /ilp32-${TEST_NAME}-tests.tar.gz
mkdir -p /opt/ilp32/
cp -a ${test_home}/${TEST_NAME}/ilp32-libraries/opt/ilp32/* /opt/ilp32/

{
	echo '-----------------------------'
	echo 'ilp32-libraries info:'
	cat ${test_home}/${TEST_NAME}/ilp32-libraries/opt/ilp32/info.txt
	echo '-----------------------------'
	echo 'manifest:'
	find . -type f -ls
	echo '-----------------------------'
} | tee -a ${log_file}

set +e
{
	echo 'test results:'
	echo "${test_home}/${TEST_NAME}: TODO"
} | tee -a ${log_file}

result=${?}

set -e

trap "on_exit 'Success.'" EXIT
exit 0
