#!/usr/bin/env sh
# generic test driver

on_exit() {
	local result=${1}

	tar -czvf "${RESULTS_FILE}" "${results_dir}"

	echo "GENERIC TEST RESULT: ilp32-${TEST_NAME}: Done: ${result}" >&2
}

print_sys_info() {
	rootfs_type=$(grep -E '^ID=' /etc/os-release)
	rootfs_type=${rootfs_type#ID=}

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
	} 2>&1 | tee -a "${log_file}"
	set -x
}

print_fs_info() {
	local lib_info=${1}

	set +x
	{
		echo '-----------------------------'
		echo 'ilp32-libraries info:'
		cat "${lib_info}"
		echo '-----------------------------'
		echo 'manifest:'
		find . -type f -exec ls -l {} \;
		echo '-----------------------------'
	} 2>&1 | tee -a "${log_file}"
	set -x
}

run_test_prog() {
	local msg=${1}
	local prog_path=${2}
	local prog_name=${3}

	set +e
	#set +x
	{
		echo "============================="
		file "${prog_path}/${prog_name}"
		echo "-----------------------------"
		echo "test ${prog_name} '${msg}': strace start"
		strace "${prog_path}/${prog_name}"
		echo "test ${prog_name} '${msg}': result = ${?}"
		echo "-----------------------------"
		echo "test ${prog_name} '${msg}': run start"
		"${prog_path}/${prog_name}"
		echo "test ${prog_name} '${msg}': result = ${?}"
		echo "test ${prog_name} '${msg}': end"
		echo "============================="
	} 2>&1 | tee -a "${log_file}"
	#set -x
	set -e
}

run_test_prog_verbose() {
	local msg=${1}
	local prog_path=${2}
	local prog_name=${3}

	set +e
	#set +x
	{
		echo "============================="
		file "${prog_path}/${prog_name}"
		echo "-----------------------------"
		echo "test ${prog_name} '${msg}': verbose start"

		ls -l /opt/ilp32/lib64/ld-2.30.so
		file /opt/ilp32/lib64/ld-2.30.so
		/opt/ilp32/lib64/ld-2.30.so --list "${prog_path}/${prog_name}"

		LD_SHOW_AUXV=1 "${prog_path}/${prog_name}"
		LD_TRACE_LOADED_OBJECTS=1 LD_VERBOSE=1 "${prog_path}/${prog_name}"
		LD_DEBUG=libs "${prog_path}/${prog_name}"

		echo "test ${prog_name} '${msg}': verbose end"
		echo "============================="
	} 2>&1 | tee -a "${log_file}"
	#set -x
	set -e
}

install_tests() {
	tar -C "${test_home}" -xf "/ilp32-${TEST_NAME}-tests.tar.gz"

	mkdir -p /opt/ilp32/
	cp -a "${test_home}/${TEST_NAME}/ilp32-libraries/opt/ilp32"/* /opt/ilp32/
}

#===============================================================================
# program start
#===============================================================================
TEST_NAME=${TEST_NAME:-"${1}"}

export PS4='+ generic-test.sh (ilp32-${TEST_NAME}): '
set -x

trap "on_exit 'failed.'" EXIT
set -e

test_home="/ilp32-${TEST_NAME}"
mkdir -p "${test_home}"
cd "${test_home}"

results_dir="${test_home}/results"
mkdir -p "${results_dir}"

log_file="${results_dir}/test.log"
rm -f "${log_file}"

print_sys_info
install_tests
print_fs_info "${test_home}/${TEST_NAME}/ilp32-libraries/opt/ilp32/info.txt"

which sh
ls -l $(which sh)

test_progs=$(cat "${test_home}/${TEST_NAME}/test_manifest")

orig_limit=$(ulimit -s)

for prog in ${test_progs}; do
	echo "Running '${prog}'." >&2

	ulimit -s "${orig_limit}"
	ulimit -s
	run_test_prog "limited" "${test_home}/${TEST_NAME}" "${prog}"
	#run_test_prog_verbose "limited" "${test_home}/${TEST_NAME}" "${prog}"

	#ulimit -s unlimited
	#ulimit -s
	#run_test_prog "unlimited" "${test_home}/${TEST_NAME}" "${prog}"
done

ulimit -s "${orig_limit}"

checks='Segmentation fault|Internal error'
checks_IFS='|'

IFS="${checks_IFS}"
for check in ${checks}; do
	if grep "${check}" "${log_file}"; then
		echo "ilp32-${TEST_NAME}: ERROR: '${check}' detected." >&2
		check_failed=1
	fi
done
unset IFS

if [ ${check_failed} ]; then
	exit 1
fi

trap "on_exit 'Success.'" EXIT
exit 0
