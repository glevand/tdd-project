# wrk - HTTP benchmark test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

test_usage_http_wrk() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - wrk - a HTTP benchmarking tool." >&2
	echo "    wrk is a modern HTTP benchmarking tool capable of generating significant"
	echo "    load when run on a single multi-core CPU. It combines a multithreaded"
	echo "    design with scalable event notification systems such as epoll and kqueue."
	echo "  More Info:" >&2
	echo "    https://github.com/wg/wrk/blob/master/README.md" >&2
	eval "${old_xtrace}"
}

test_packages_http_wrk() {
	local rootfs_type=${1}
	local target_arch=${2}

	echo ''
}

test_setup_http_wrk() {
	local rootfs_type=${1}
	local rootfs=${2}

	return
}

test_build_http_wrk() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='http-wrk'
	local src_repo=${http_wrk_src_repo:-"https://github.com/wg/wrk.git"}
	local repo_branch=${http_wrk_repo_branch:-"master"}
	local src_dir="${tests_dir}/${test_name}-src"
	local build_dir="${tests_dir}/${test_name}-build"
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"

	check_directory "${sysroot}"

	rm -rf ${build_dir} ${archive_file} ${results_file}

	git_checkout_safe ${src_dir} ${src_repo} ${repo_branch}

	mkdir -p ${build_dir}
	rsync -av --delete --exclude='.git' ${src_dir}/ ${build_dir}/

	pushd ${build_dir}

	if [[ "${host_arch}" != "${target_arch}" ]]; then
		make_opts="CC=$(get_triple ${target_arch})-gcc"
	fi

	export SYSROOT="${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"
	export DESTDIR="${build_dir}/install"
	export SKIP_IDCHECK=1

	echo "${FUNCNAME[0]}: TODO." >&2
	touch ${archive_file}

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_http_wrk() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_http_wrk__ssh_opts=${4}
	local ssh_opts="${_test_run_sys_info__ssh_opts}"

	local test_name='http-wrk'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${http_wrk_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${_test_run_http_wrk__ssh_opts}@"

	echo "${FUNCNAME[0]}: TODO." >&2
	touch ${results_file}

	echo "${FUNCNAME[0]}: Done, success." >&2
}
