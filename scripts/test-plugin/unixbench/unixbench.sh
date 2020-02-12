# UnixBench test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_unixbench() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - UnixBench - The original BYTE UNIX benchmark suite." >&2
	echo "    The purpose of UnixBench is to provide a basic indicator of the performance"
	echo "    of a Unix-like system; hence, multiple tests are used to test various"
	echo "    aspects of the system's performance. These test results are then compared"
	echo "    to the scores from a baseline system to produce an index value, which is"
	echo "    generally easier to handle than the raw scores. The entire set of index"
	echo "    values is then combined to make an overall index for the system."
	echo "  More Info:" >&2
	echo "    https://github.com/kdlucas/byte-unixbench/blob/master/README.md" >&2
	eval "${old_xtrace}"
}

test_packages_unixbench() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}" in
	alpine)
		echo 'make perl'
		;;
	debian)
		echo 'make libperl-dev'
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_setup_unixbench() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_unixbench() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='unixbench'
	local src_repo=${unixbench_src_repo:-"https://github.com/kdlucas/byte-unixbench.git"}
	local repo_branch=${unixbench_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"
	rm -rf ${build_dir} ${archive_file}

	git_checkout_safe ${src_dir} ${src_repo} ${repo_branch}

	mkdir -p ${build_dir}
	rsync -av --delete --exclude='.git' ${src_dir}/ ${build_dir}/

	if [[ "${host_arch}" != "${target_arch}" ]]; then
		make_opts="CC=$(get_triple ${target_arch})-gcc"
	fi

	export SYSROOT="$(pwd)/${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"

	make -C ${build_dir}/UnixBench ${make_opts} UB_GCC_OPTIONS='-O3 -ffast-math'

	tar -C ${build_dir} -czf ${archive_file} UnixBench
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_unixbench() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_unixbench__ssh_opts=${4}
	local ssh_opts="${_test_run_unixbench__ssh_opts}"

	local test_name='unixbench'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${unixbench_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	scp ${ssh_opts} ${archive_file} ${ssh_host}:unixbench.tar.gz

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} 'sh -s' <<'EOF'
export PS4='+unixbench-test-script:${LINENO}: '
set -ex

cat /proc/partitions
printenv

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

mkdir -p unixbench-test
tar -C unixbench-test -xf unixbench.tar.gz
cd ./unixbench-test/UnixBench

set +e
#./Run
echo "skippping tests for debug!!!"
result=${?}
set -e

tar -czvf ${HOME}/unixbench-results.tar.gz  ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:unixbench-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:unixbench-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
