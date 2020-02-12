# LTP test plug-in.

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/chroot.sh

test_usage_ltp() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "  ${BASH_SOURCE##*/} - Linux Kernel Selftests." >&2
	echo "    The LTP testsuite contains a collection of tools for testing the Linux kernel"
	echo "    and related features. Our goal is to improve the Linux kernel and system"
	echo "    libraries by bringing test automation to the testing effort."
	echo "  More Info:" >&2
	echo "    https://github.com/linux-test-project/ltp/blob/master/README.md" >&2
	eval "${old_xtrace}"
}

test_packages_ltp() {
	local rootfs_type=${1}
	local target_arch=${2}

	case "${rootfs_type}" in
	alpine)
		# FIXME: Error relocating /root/ltp-test/opt/ltp/bin/ltp-pan: __sprintf_chk: symbol not found
		echo "${FUNCNAME[0]}: TODO: Need to setup build wih alpine's musl glibc." >&2
		exit 1
		echo 'libaio-dev'
		;;
	debian)
		echo 'libaio-dev libnuma-dev'
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_setup_ltp() {
	local rootfs_type=${1}
	local rootfs=${2}

	case "${rootfs_type}" in
	alpine)
		enter_chroot ${rootfs} "
			set -e
			apk add numactl-dev --repository http://dl-3.alpinelinux.org/alpine/edge/main/ --allow-untrusted
		"
		;;
	debian)
		;;
	*)
		echo "${FUNCNAME[0]}: ERROR: Unknown rootfs type: '${rootfs_type}'" >&2
		exit 1
		;;
	esac
}

test_build_ltp() {
	local rootfs_type=${1}
	local tests_dir=${2}
	mkdir -p ${tests_dir}
	tests_dir="$(cd ${tests_dir} && pwd)"
	local sysroot="$(cd ${3} && pwd)"
	local kernel_src_dir="$(cd ${4} && pwd)"

	local test_name='ltp'
	local src_repo=${ltp_src_repo:-"https://github.com/linux-test-project/ltp.git"}
	local repo_branch=${ltp_repo_branch:-"master"}
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
		local triple="$(get_triple ${target_arch})"
		make_opts="--host=${triple} CC=${triple}-gcc"
	fi

	export SYSROOT="${sysroot}"
	export CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}"
	export LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib"
	export DESTDIR="${build_dir}/install"
	export SKIP_IDCHECK=1

	make autotools
	./configure \
		SYSROOT="${sysroot}" \
		CPPFLAGS="-I${SYSROOT}/usr/include -I${SYSROOT}/include -I${SYSROOT}" \
		LDFLAGS="-L${SYSROOT}/usr/lib -L${SYSROOT}/lib" \
		DESTDIR="${build_dir}/install" \
		${make_opts}
	(unset TARGET_ARCH; make)
	make DESTDIR="${build_dir}/install" install

	file ${build_dir}/install/opt/ltp/bin/ltp-pan
	tar -C ${DESTDIR} -czf ${archive_file} .

	popd
	echo "${FUNCNAME[0]}: Done, success." >&2
}

test_run_ltp() {
	local tests_dir="$(cd ${1} && pwd)"
	local machine_type=${2}
	local ssh_host=${3}
	local -n _test_run_ltp__ssh_opts=${4}
	local ssh_opts="${_test_run_ltp__ssh_opts}"

	local test_name='ltp'
	local archive_file="${tests_dir}/${test_name}.tar.gz"
	local results_file="${tests_dir}/${test_name}-results.tar.gz"
	local timeout=${ltp_timeout:-"5m"}

	echo "INSIDE @${BASH_SOURCE[0]}:${FUNCNAME[0]}@"
	echo "ssh_opts = @${ssh_opts}@"

	set -x
	rm -rf ${results_file}

	case "${machine_type}" in
	qemu)
		LTP_DEV='/dev/vda'
		LTP_RUN_OPTS='-b /dev/vdb -z /dev/vdc'
		;;
	remote)
		;;
	esac

	#echo "${FUNCNAME[0]}: tests_dir    = @${tests_dir}@"
	#echo "${FUNCNAME[0]}: machine_type = @${machine_type}@"
	#echo "${FUNCNAME[0]}: ssh_host     = @${ssh_host}@"
	#echo "${FUNCNAME[0]}: ssh_opts     = @${ssh_opts}@"
	echo "${FUNCNAME[0]}: archive_file  = @${archive_file}@"
	echo "${FUNCNAME[0]}: LTP_RUN_OPTS  = @${LTP_RUN_OPTS}@"

	scp ${ssh_opts} ${archive_file} ${ssh_host}:ltp.tar.gz

	set +e
	timeout ${timeout} ssh ${ssh_opts} ${ssh_host} \
		LTP_DEV="'${LTP_DEV}'" \
		LTP_RUN_OPTS="'${LTP_RUN_OPTS}'" 'sh -s' <<'EOF'
export PS4='+ ltp-test-script:${LINENO}: '
set -ex

cat /proc/partitions
printenv

rootfs_type=$(egrep '^ID=' /etc/os-release)
rootfs_type=${rootfs_type#ID=}

## Exclude sshd from oom-killer.
#sshd_pid=$(systemctl show --value -p MainPID ssh)
#if [[ ${sshd_pid} -eq 0 ]]; then
#	exit 1
#fi
#echo -17 > /proc/${sshd_pid}/oom_adj

mkfs.ext4 ${LTP_DEV}
mkdir -p ltp-test
mount ${LTP_DEV} ltp-test

tar -C ltp-test -xf ltp.tar.gz
cd ./ltp-test/opt/ltp

echo -e "oom01\noom02\noom03\noom04\noom05" > skip-tests
cat skip-tests

cat ./Version

set +e
ls -l ./bin/ltp-pan
ldd ./bin/ltp-pan

./runltp -S skip-tests ${LTP_RUN_OPTS}

result=${?}
set -e

tar -czvf ${HOME}/ltp-results.tar.gz ./output ./results
EOF
	result=${?}
	set -e

	if [[ ${result} -eq 124 ]]; then
		echo "${FUNCNAME[0]}: Done, failed: timeout." >&2
	elif [[ ${result} -ne 0 ]]; then
		scp ${ssh_opts} ${ssh_host}:ltp-results.tar.gz ${results_file} || :
		echo "${FUNCNAME[0]}: Done, failed: '${result}'." >&2
	else
		scp ${ssh_opts} ${ssh_host}:ltp-results.tar.gz ${results_file}
		echo "${FUNCNAME[0]}: Done, success." >&2
	fi
}
