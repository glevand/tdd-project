#!/usr/bin/env bash

print_gcc_info() {
	local gcc=${1}
	local log_file=${2:-"/dev/null"}

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set -o xtrace
	local old_errexit="$(shopt -po errexit || :)"
	set +o errexit

	echo "=============================" | tee --append ${log_file}
	echo "${gcc} --version" | tee --append ${log_file}
	${gcc} --version 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -dumpspecs" | tee --append ${log_file}
	${gcc} -dumpspecs 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -dumpversion" | tee --append ${log_file}
	${gcc} -dumpversion 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -dumpmachine" | tee --append ${log_file}
	${gcc} -dumpmachine 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-search-dirs" | tee --append ${log_file}
	${gcc} -print-search-dirs 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-libgcc-file-name" | tee --append ${log_file}
	${gcc} -print-libgcc-file-name 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-multiarch" | tee --append ${log_file}
	${gcc} -print-multiarch 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-multi-directory" | tee --append ${log_file}
	${gcc} -print-multi-directory 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-multi-lib" | tee --append ${log_file}
	${gcc} -print-multi-lib 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-multi-os-directory" | tee --append ${log_file}
	${gcc} -print-multi-os-directory 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-sysroot" | tee --append ${log_file}
	${gcc} -print-sysroot 2>&1 | tee --append ${log_file}
	echo "-----------------------------" | tee --append ${log_file}
	echo "${gcc} -print-sysroot-headers-suffix" | tee --append ${log_file}
	${gcc} -print-sysroot-headers-suffix 2>&1 | tee --append ${log_file}
	echo -e "=============================" | tee --append ${log_file}

	eval "${old_errexit}"
	eval "${old_xtrace}"
}
