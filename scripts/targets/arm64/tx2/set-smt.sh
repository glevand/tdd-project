#!/usr/bin/env bash

usage() {
	local op_name
	local op_values
	local old_xtrace

	op_name=$(op_get_name)
	op_values=$(op_get_values)
	
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Set or display ThunderX2 ${op_name} value." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help        - Show this help and exit." >&2
	echo "  -s --set <value> - Set value {${op_values}}.  Default: '${set_value}'." >&2
	echo "  -v --verbose     - Verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hs:v"
	local long_opts="help,set:,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-s | --set)
			set_value="${2}"
			shift 2
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${script_name}: ERROR: Extra args found: '${@}'" >&2
				usage=1
			fi
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

	echo "${script_name}: Done: ${result}" >&2
	exit 0
}

print_efi_var() {
	local efi_file=${1}

	echo -n '0x'
	cat "${efi_file}" | hexdump -s 4 -v -e '/4 "%02X\n"'
}

set_efi_var() {
	local efi_file=${1}
	local value_hex=${2}
	local immutable

	if lsattr -l "${efi_file}" | egrep 'Immutable' >/dev/null; then
		immutable=1
		chattr -i "${efi_file}"
	fi

	echo -n -e "\x00\x00\x00\x00\x${value_hex#0x}\x00\x00\x00" > "${efi_file}"

	if [[ ${immutable} ]]; then
		chattr +i "${efi_file}"
	fi
}

print_value() {
	local msg=${1}
	local value_hex=${2}
	local value_dec

	value_dec=$(( 16#${value_hex#0x} ))
	echo "${msg}: ${value_hex} (${value_dec})" >&2
}

op_print_all() {
	local op
	local array

	for op in "smt turbo numcores"; do
		#echo "${LINENO}: op = '${op}'" >&2
		array="${op}_ops"[@]
		array=( "${!array}" )
		echo "${LINENO}: op = '${array[name_index]}', values = '${array[values_index]}', file = '${array[file_index]}'" >&2
	done
}

op_get_name() {
	echo "${op_array[name_index]}"
}

op_get_type() {
	echo "${op_array[type_index]}"
}

op_get_values() {
	echo "${op_array[values_index]}"
}

op_get_file() {
	echo "${op_array[file_index]}"
}

op_check_value() {
	local value_hex=${1}
	local type=$(op_get_type)

	case ${type} in
	range)
		local range=$(op_get_values)
		local min=${range%-*}
		local max=${range#*-}

		if [[ ${value_hex} -ge ${min} && ${value_hex} -le ${max} ]]; then
			return
		fi
		;;
	set)
		local v
		for v in $(op_get_values); do
			#echo "v = '${v}'" >&2
			if [[ ${v} -eq ${value_hex} ]]; then
				return
			fi
		done
		;;
	*)
		echo "${script_name}: ERROR: Internal type: ${type}" >&2
		exit 1
		;;
	esac

	echo "${script_name}: ERROR: Bad set value: '${value_hex}'" >&2
	usage
	exit 1
}

dmidecode_cpu_count() {
	if [[ ${dmidecode} ]]; then
		echo -n "DMI: "
		${dmidecode} -t processor | egrep --ignore-case --max-count=1 \
			--only-matching 'Core Count: [[:digit:]]{1,3}'
		echo -n "DMI: "
		${dmidecode} -t processor | egrep --ignore-case --max-count=1 \
			--only-matching 'Core Enabled: [[:digit:]]{1,3}'
	fi
}

#===============================================================================
# program start
#===============================================================================
PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}): \[\033[0;37m\]'

script_name="${0##*/}"

trap "on_exit 'failed.'" EXIT
set -e

process_opts "${@}"

host_arch="$(uname -m)"

efi_guid='a9f76944-9749-11e7-96d5-736f2e5d4e7e'

#	 	name		type	values		file
smt_ops=(	SMT		set	'1 2 4'		CvmHyperThread-${efi_guid})
turbo_ops=(	TURBO		set	'0 1 2'		CvmTurbo-${efi_guid})
numcores_ops=(	NUMCORES	range	'1-0x1E'	CvmNumCores-${efi_guid})

name_index=0
type_index=1
values_index=2
file_index=3

#op_print_all

op=${script_name%%.*}
op=${op##*-}

op_array="${op}_ops"[@]
op_array=( "${!op_array}" )

#echo "${LINENO}: op = '${op_array[name_index]}', values = '${op_array[values_index]}', file = '${op_array[file_index]}'" >&2

if [[ -x "$(command -v dmidecode)" ]]; then
	dmidecode="dmidecode"
fi

if [[ ${set_value} ]]; then
	set_value=$(printf "0x%X" ${set_value})
fi

efi_dir="/sys/firmware/efi/efivars"
efi_file="${efi_dir}/$(op_get_file)"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ "${host_arch}" != "aarch64" ]]; then
	echo "${script_name}: ERROR: For ARM64 machines only." >&2
	exit 1
fi

if [[ ${dmidecode} ]]; then
	if ! ${dmidecode} -s processor-version | egrep -i 'ThunderX' > /dev/null; then
		echo "${script_name}: ERROR: For ThunderX machines only." >&2
		exit 1
	fi
fi

if [[ ! -d ${efi_dir}  ]]; then
	mount | egrep efivars || :
	if [[ ${?} ]]; then
		echo "${script_name}: ERROR: efivars file system not mounted: '${efi_dir}'" >&2
	else
		echo "${script_name}: ERROR: Directory not found: '${efi_dir}'" >&2
	fi
	exit 1
fi

if [[ ! -f ${efi_file}  ]]; then
	echo "${script_name}: ERROR: File not found: '${efi_file}'" >&2
	echo "${script_name}: Check firmware version" >&2
	if [[ ${dmidecode} ]]; then
		${dmidecode} -s bios-version
	fi
	exit 1
fi

if [[ ${op} == "numcores" ]]; then
	dmidecode_cpu_count
fi

cur_value=$(print_efi_var ${efi_file})
print_value "current" ${cur_value}

if [[ ${set_value} ]]; then
	print_value "set" ${set_value}
	op_check_value ${set_value}

	if [[ ${cur_value} -eq ${set_value} ]]; then
		echo "${script_name}: INFO: Set value same as current value: '${cur_value}'" >&2
	else
		set_efi_var ${efi_file} ${set_value}
		new_value=$(print_efi_var ${efi_file})
		print_value "new" ${new_value}
	fi
fi

trap "on_exit 'Success.'" EXIT
