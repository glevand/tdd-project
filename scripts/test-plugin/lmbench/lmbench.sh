# LmBench test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_lmbench() {
	return
}

test_packages_lmbench() {
	local rootfs_type=${1}
	local target_arch=${2}
	
	case "${rootfs_type}" in
	alpine)
		echo "make libc6-compat"
		;;
	debian)
		echo "make"
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac	
}

test_setup_lmbench() {
	return
}

test_build_lmbench() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"
	
	local test_name='lmbench'
	local src_repo=${lmbench_src_repo:-"https://github.com/intel/lmbench.git"}
	local repo_branch=${lmbench_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"
	rm -rf ${build_dir} ${archive_file} ${results_file}

	git_checkout_safe ${src_dir} ${src_repo} ${repo_branch}

	mkdir -p ${build_dir}/src
	rsync -av --delete --exclude='.git' ${src_dir}/ ${build_dir}/

	pushd ${build_dir}

	if [[ "${host_arch}" != "${target_arch}" ]]; then
		make_opts="CC=$(get_triple ${target_arch})-gcc"
	fi
	
	git apply ${SCRIPTS_TOP}/test-plugin/${test_name}/fix_aarch64.patch

	export SYSROOT="$(pwd)/${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"

	make ${make_opts}
	mv bin/x86_64-linux-gnu/ bin/aarch64-linux-gnu
	tar -C ${build_dir}/../ -czf ${archive_file} lmbench-build

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2	
}

test_run_lmbench() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_lmbench__ssh_opts=${4}
	local ssh_opts="${_test_run_lmbench__ssh_opts}"

	local test_name='lmbench'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"


	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	scp ${ssh_opts} ${archive_file} ${ssh_host}:lmbench.tar.gz

	set +e
	ssh ${ssh_opts} ${ssh_host} 'sh -s' <<'EOF'
export PS4='+lmbench-test-script:${LINENO}: '
set -ex

cat /proc/partitions
printenv

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

mkdir -p lmbench-test
tar -C lmbench-test -xf lmbench.tar.gz
cd ./lmbench-test/lmbench-build

set +e

cd src

echo "1
1
1000
all
no
no



/tmp
/dev/null
no
" | make results

cd ..

set -e

tar -czvf ${HOME}/lmbench-results.tar.gz ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:lmbench-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:lmbench-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
