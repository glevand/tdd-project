#!/usr/bin/env bash

set -e

script_name="${0##*/}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

source "${SCRIPTS_TOP}/tdd-lib/util.sh"
source "${SCRIPTS_TOP}/lib/ipmi.sh"
source "${SCRIPTS_TOP}/lib/relay.sh"

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Run Linux kernel tests on remote machine." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -i --initrd         - Initrd image. Default: '${initrd}'." >&2
	echo "  -k --kernel         - Kernel image. Default: '${kernel}'." >&2
	echo "  -m --test-machine   - Test machine name. Default: '${test_machine}'." >&2
	echo "  -n --no-known-hosts - Do not setup known_hosts file. Default: '${no_known_hosts}'." >&2
	echo "  -o --out-file       - stdout, stderr redirection file. Default: '${out_file}'." >&2
	echo "  -s --systemd-debug  - Run systemd with debug options. Default: '${systemd_debug}'." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  --bmc-host          - Test machine BMC hostname or address. Default: '${bmc_host}'." >&2
	echo "  --relay-server      - Relay server host[:port]. Default: '${relay_server}'." >&2
	echo "  --result-file       - Result file. Default: '${result_file}'." >&2
	echo "  --ssh-login-key     - SSH login private key file. Default: '${ssh_login_key}'." >&2
	echo "  --test-name         - Tests name. Default: '${test_name}'." >&2
	echo "  --tests-dir         - Test directory. Default: '${tests_dir}'." >&2
	echo "  --tftp-triple       - tftp triple.  File name or 'user:server:root'. Default: '${tftp_triple}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hi:k:m:no:sv"
	local long_opts="help,initrd:,kernel:,test-machine:,no-known-hosts,\
out-file:,systemd-debug,verbose,\
bmc-host:,relay-server:,result-file:,ssh-login-key:,test-name:,tests-dir:,\
tftp-triple:"

	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-i | --initrd)
			initrd="${2}"
			shift 2
			;;
		-k | --kernel)
			kernel="${2}"
			shift 2
			;;
		-m | --test-machine)
			test_machine="${2}"
			shift 2
			;;
		-n | --no-known-hosts)
			no_known_hosts=1
			shift
			;;
		-o | --out-file)
			out_file="${2}"
			shift 2
			;;
		-s | --systemd-debug)
			systemd_debug=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--bmc-host)
			bmc_host="${2}"
			shift 2
			;;
		--relay-server)
			relay_server="${2}"
			shift 2
			;;
		--result-file)
			result_file="${2}"
			shift 2
			;;
		--ssh-login-key)
			ssh_login_key="${2}"
			shift 2
			;;
		--test-name)
			test_name="${2}"
			shift 2
			;;
		--tests-dir)
			tests_dir="${2}"
			shift 2
			;;
		--tftp-triple)
			tftp_triple="${2}"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${@}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}
	local sol_pid

	set +e

	if [[ -n "${sol_pid_file}" ]]; then
		sol_pid=$(cat ${sol_pid_file})
		rm -f ${sol_pid_file}
	fi

	if [[ -f ${test_kernel} ]]; then
		rm -f ${test_kernel}
	fi

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo '*** on_exit ***'
	echo "*** result      = @${result}@" >&2
	echo "*** sol_pid_fil = @${sol_pid_file}@" >&2
	echo "*** sol_pid     = @${sol_pid}@" >&2
	echo "*** ipmi_args   = @${ipmi_args}@" >&2
	eval "${old_xtrace}"

	if [[ ${sol_pid} ]]; then
		kill -0 ${sol_pid}
		${sudo} kill ${sol_pid} || :
	fi

	if [[ ${ipmi_args} ]]; then
		ipmitool ${ipmi_args} -I lanplus sol deactivate || :
		ipmitool ${ipmi_args} -I lanplus chassis power off || :
	fi

	if [[ ${sol_pid} ]]; then
		wait ${sol_pid}
	fi

	if [[ ${checkout_token} ]]; then
		${SCRIPTS_TOP}/checkin.sh ${checkout_token}
	fi

	echo "${script_name}: ${result}" >&2
}

#===============================================================================
# program start
#===============================================================================
sudo="sudo -S"

trap "on_exit 'failed.'" EXIT

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")
start_extra_args=""
out_file=${out_file:-"${test_machine}.out"}
result_file=${result_file:-"${test_machine}-result.txt"}

relay_triple=$(relay_init_triple ${relay_server})
relay_token=$(relay_triple_to_token ${relay_triple})

if [[ ! ${bmc_host} ]]; then
	bmc_host="${test_machine}-bmc"
	echo "${script_name}: INFO: BMC host: '${bmc_host}'" >&2
fi

if [[ ${usage} ]]; then
	usage
	exit 0
fi

check_opt 'test-machine' ${test_machine}

check_opt 'kernel' ${kernel}
check_file "${kernel}"

check_opt 'initrd' ${initrd}
check_file "${initrd}"

check_opt 'ssh-login-key' ${ssh_login_key}
check_file "${ssh_login_key}"

check_opt 'test-name' ${test_name}

check_opt 'tests-dir' ${tests_dir}
check_directory "${tests_dir}"

tmp_kernel=${kernel}.tmp
test_kernel=${kernel}.${relay_token}

if [[ ! ${systemd_debug} ]]; then
	tmp_kernel=${kernel}
else
	tmp_kernel=${kernel}.tmp

	${SCRIPTS_TOP}/set-systemd-debug.sh \
		--in-file=${kernel} \
		--out-file=${tmp_kernel} \
		--verbose
fi

${SCRIPTS_TOP}/set-relay-triple.sh \
	--relay-triple="${relay_triple}" \
	--kernel=${tmp_kernel} \
	--out-file=${test_kernel} \
	--verbose

if [[ "${tmp_kernel}" != ${kernel} ]]; then
	rm -f ${tmp_kernel}
fi

if [[ "${test_machine}" == "qemu" ]]; then
	echo "${script_name}: ERROR: '--test-machine=qemu' not yet supported." >&2
	exit 1
fi

set +e
checkout_token=$(${SCRIPTS_TOP}/checkout.sh -v ${test_machine} 1200) # 20 min.
result=${?}
set -e

if [[ ${result} -ne 0 ]]; then
	unset checkout_token
	echo "${script_name}: ERROR: checkout '${test_machine}' failed (${result})." >&2
	exit 1
fi

if [[ ${no_known_hosts} ]]; then
	tftp_upload_extra="--no-known-hosts"
fi

${SCRIPTS_TOP}/tftp-upload.sh --kernel=${test_kernel} --initrd=${initrd} \
	--ssh-login-key=${ssh_login_key} --tftp-triple=${tftp_triple} \
	--tftp-dest="${test_machine}" ${tftp_upload_extra} --verbose

# ===== secrets section ========================================================
old_xtrace="$(shopt -po xtrace || :)"
set +o xtrace
if [[ ! ${TDD_BMC_CREDS_USR} || ! ${TDD_BMC_CREDS_PSW} ]]; then
	echo "${script_name}: Using creds file ${test_machine}-bmc-creds" >&2
	check_file "${test_machine}-bmc-creds" ': Need environment variables or credentials file [user:passwd]'
	TDD_BMC_CREDS_USR="$(cat ${test_machine}-bmc-creds | cut -d ':' -f 1)"
	TDD_BMC_CREDS_PSW="$(cat ${test_machine}-bmc-creds | cut -d ':' -f 2)"
fi
if [[ ! ${TDD_BMC_CREDS_USR}  ]]; then
	echo "${script_name}: ERROR: No TDD_BMC_CREDS_USR defined." >&2
	exit 1
fi
if [[ ! ${TDD_BMC_CREDS_PSW}  ]]; then
	echo "${script_name}: ERROR: No TDD_BMC_CREDS_PSW defined." >&2
	exit 1
fi
export IPMITOOL_PASSWORD="${TDD_BMC_CREDS_PSW}"
eval "${old_xtrace}"
# ==============================================================================

ping -c 1 -n ${bmc_host}
ipmi_args="-H ${bmc_host} -U ${TDD_BMC_CREDS_USR} -E"

mkdir -p ${out_file%/*}
ipmitool ${ipmi_args} chassis status > ${out_file}
echo '-----' >> ${out_file}

ipmitool ${ipmi_args} -I lanplus sol deactivate && result=1

if [[ ${result} ]]; then
	# wait for ipmitool to disconnect.
	sleep 5s
fi

sol_pid_file="$(mktemp --tmpdir tdd-sol-pid.XXXX)"

(echo "${BASHPID}" > ${sol_pid_file}; exec sleep 24h) | ipmitool ${ipmi_args} -I lanplus sol activate &>>"${out_file}" &

sol_pid=$(cat ${sol_pid_file})
echo "sol_pid=${sol_pid}" >&2

sleep 5s
if ! kill -0 ${sol_pid} &> /dev/null; then
	echo "${script_name}: ERROR: ipmitool sol seems to have quit early." >&2
	exit 1
fi

ipmi_power_off "${ipmi_args}"
sleep 5s
ipmi_power_on "${ipmi_args}"

relay_get "420" "${relay_triple}" remote_addr

echo "${script_name}: remote_addr = '${remote_addr}'" >&2

remote_host="root@${remote_addr}"
remote_ssh_opts=''

# The remote host address could come from DHCP, so don't use known_hosts.
ssh_no_check="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ -f ${SCRIPTS_TOP}/test-plugin/${test_name}/${test_name}.sh ]]; then
	source "${SCRIPTS_TOP}/test-plugin/${test_name}/${test_name}.sh"
else
	echo "${script_name}: ERROR: Test plugin '${test_name}.sh' not found." >&2
	exit 1
fi

run_ssh_opts="${ssh_no_check} -i ${ssh_login_key} ${remote_ssh_opts}"
test_run_${test_name/-/_} ${tests_dir} ${test_machine} ${remote_host} run_ssh_opts

ssh ${ssh_no_check} -i ${ssh_login_key} ${remote_ssh_opts} ${remote_host} \
	'/sbin/poweroff &'

echo "${script_name}: Waiting for shutdown at ${remote_addr}..." >&2

ipmi_wait_power_state "${ipmi_args}" 'off' 120

trap - EXIT

on_exit 'Done, success.' ${sol_pid_file} "${ipmi_args}"
