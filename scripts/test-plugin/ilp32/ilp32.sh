#!/usr/bin/env bash
#
# ILP32 hello world test plug-in.

test_usage_ilp32() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - Build and run ILP32 hello world program." >&2
	eval "${old_xtrace}"
}

test_packages_ilp32() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}-${target_arch}" in
	alpine-*)
		;;
	debian-*)
		;;
	*)
		;;
	esac
	echo ""
}

test_setup_ilp32() {
	return
}

ilp32_build_sub_test() {
	local sub_test=${1}

	${src_dir}/scripts/build-ilp32-test-program.sh \
		--build-top=${build_dir}/tests/${sub_test} \
		--src-top=${src_dir}/tests/${sub_test} \
		--prefix=${tool_prefix}

	tar -czf ${tests_dir}/ilp32-${sub_test}-tests.tar.gz \
		-C ${build_dir}/tests ${sub_test} \
		-C ${src_dir} docker scripts
}

test_build_ilp32() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local src_repo=${ilp32_src_repo:-"https://github.com/glevand/ilp32--builder.git"}
	local repo_branch=${ilp32_repo_branch:-"master"}
	local src_dir="${tests_dir}/ilp32-src"
	local build_dir="${tests_dir}/ilp32-build"
	local results_archive="${tests_dir}/ilp32-results.tar.gz"
	local ilp32_libs_file="${tests_dir}/ilp32-libraries.tar.gz"
	local tool_prefix="/opt/ilp32"

	rm -rf ${build_dir} ${results_archive} ${tests_dir}/ilp32*-tests.tar.gz

	# FIXME: For debug.
	#src_repo="/tdd--test/ilp32--builder.git-copy"

	git_checkout_force ${src_dir} ${src_repo} ${repo_branch}

	mkdir -p ${build_dir}
	pushd ${build_dir}

	# FIXME: For debug.
	#force_toolup="--force"
	#force_builder="--force"
	#force_runner="--force"

	${src_dir}/scripts/build-ilp32-docker-image.sh \
		--build-top=${build_dir}/toolchain \
		${force_toolup} \
		--toolup

	${src_dir}/scripts/build-ilp32-docker-image.sh \
		--build-top=${build_dir}/toolchain \
		${force_builder} \
		--builder

	if [[ -d ${build_dir}/toolchain ]]; then
		cp -vf --link ${build_dir}/toolchain/ilp32-toolchain-*.tar.gz ${tests_dir}/
		# FIXME: Need this???
		cp -vf --link ${build_dir}/toolchain/ilp32-libraries-*.tar.gz ${tests_dir}/
	else
		echo "${script_name}: INFO (${FUNCNAME[0]}): No toolchain archives found." >&2
	fi

	if [[ ${host_arch} == ${target_arch} ]]; then
		${src_dir}/scripts/build-ilp32-docker-image.sh \
			--build-top=${build_dir}/toolchain \
			${force_runner} \
			--runner
	fi

	ilp32_build_sub_test "hello-world"
	ilp32_build_sub_test "vdso-tests"
	ilp32_build_sub_test "gcc-tests"

	#tar -czf ${tests_dir}/ilp32-spec-cpu-tests.tar.gz \
	#	-C ${src_dir}/tests lib spec-cpu \
	#	-C ${??} cpu2017-src

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

ilp32_run_sub_test() {
	local sub_test=${1}
	local test_driver=${2}

	local tests_archive="${tests_dir}/ilp32-${sub_test}-tests.tar.gz"
	local results_archive="${tests_dir}/ilp32-${sub_test}-results.tar.gz"
	local remote_results_archive="/ilp32-${sub_test}-results.tar.gz"

	rm -rf ${results_archive}

	scp ${ssh_opts} ${tests_archive} ${ssh_host}:/
	scp ${ssh_opts} ${TEST_TOP}/${test_driver} ${ssh_host}:/
	ssh ${ssh_opts} ${ssh_host} chmod +x /${test_driver}
	ssh ${ssh_opts} ${ssh_host} "TEST_NAME=${sub_test} sh -c 'ls -l / && env'"

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} \
		"TEST_NAME=${sub_test} RESULTS_FILE=${remote_results_archive} sh -c '/${test_driver}'"
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, ilp32-${sub_test} failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		echo "${FUNCNAME[0]}: Done, ilp32-${sub_test} failed: '${result}'." >&2
	else
		echo "${FUNCNAME[0]}: Done, ilp32-${sub_test} success." >&2
	fi

	scp ${ssh_opts} ${ssh_host}:${remote_results_archive} ${results_archive}
}

ilp32_run_spec_cpu() {
	local sub_test=spec-cpu

	local tests_archive="${tests_dir}/ilp32-${sub_test}-tests.tar.gz"
	local results_archive="${tests_dir}/ilp32-${sub_test}-results.tar.gz"
	local remote_results_archive="/ilp32-${sub_test}-results.tar.gz"

	rm -rf ${results_archive}

	scp ${ssh_opts} ${tests_archive} ${ssh_host}:/
}

test_run_ilp32() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_ilp32__ssh_opts=${4}
	local ssh_opts="${_test_run_ilp32__ssh_opts}"

	local src_repo=${ilp32_src_repo:-"https://github.com/glevand/ilp32--builder.git"}
	local repo_branch=${ilp32_repo_branch:-"master"}
	local src_dir="${tests_dir}/ilp32-src"
	local build_dir="${tests_dir}/ilp32-build"
	local timeout=${ilp32_timeout:-"5m"}

	echo "ssh_opts = @${ssh_opts}@"

	set -x

	for ((i = 0; i < 1; i++)); do
		ilp32_run_sub_test "hello-world" "generic-test.sh"
		ilp32_run_sub_test "vdso-tests" "generic-test.sh"
		ilp32_run_sub_test "gcc-tests" "generic-test.sh"
		#ilp32_run_sub_test "spec-cpu" "spec-cpu-test.sh"
	done

}

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

TEST_TOP=${TEST_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
