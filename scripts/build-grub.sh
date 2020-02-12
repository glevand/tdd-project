#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build grub bootloader." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help       - Show this help and exit." >&2
	echo "  --src-dir       - Top of sources. Default: '${src_dir}'." >&2
	echo "  --grub-src      - Grub source directory.  Default: '${grub_src}'." >&2
	echo "  --gnulib-src    - Gnulib source directory.  Default: '${gnulib_src}'." >&2
	echo "  --dest-dir      - Make DESTDIR. Default: '${dest_dir}'." >&2
	echo "  --grub-config   - Path to grub config file. Default: '${grub_config}'." >&2
	echo "  --mok-key       - Path to signing key (PEM format). Default: '${mok_key}'." >&2
	echo "  --mok-cert      - Path to signing certificate (PEM format). Default: '${mok_cert}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --git-clone  - Clone git repos." >&2
	echo "  -2 --configure  - Run configure." >&2
	echo "  -3 --build      - Build grub." >&2
	echo "  -4 --mk-image   - Build grub image." >&2
	echo "  -5 --sign-image - Sign grub image." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="h12345"
	local long_opts="help,\
src-dir:,grub-src:,gnulib-src:,dest-dir:,grub-config:,mok-key:,mok-cert:,\
git-clone,configure,build,mk-image,sign-image"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"
	
	if [[ ${1} == '--' ]]; then
		echo "${script_name}: ERROR: Must specify an option step." >&2
		usage
		exit 1
	fi

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		--src-dir)
			src_dir="${2}"
			shift 2
			;;
		--grub-src)
			grub_src="${2}"
			shift 2
			;;
		--gnulib-src)
			gnulib_src="${2}"
			shift 2
			;;
		--dest-dir)
			dest_dir="${2}"
			shift 2
			;;
		--grub-config)
			grub_config="${2}"
			shift 2
			;;
		--mok-key)
			mok_key="${2}"
			shift 2
			;;
		--mok-cert)
			mok_cert="${2}"
			shift 2
			;;
		-1 | --git-clone)
			step_git_clone=1
			shift
			;;
		-2 | --configure)
			step_configure=1
			shift
			;;
		-3 | --build)
			step_build=1
			shift
			;;
		-4 | --mk-image)
			step_mk_image=1
			shift
			;;
		-5 | --sign-image)
			step_sign_image=1
			shift
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

	local end_time=${SECONDS}
	set +x
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

test_for_src() {
	if [[ ! -d "${grub_src}/grub-core" ]]; then
		echo -e "${script_name}: ERROR: Bad grub_src: '${grub_src}'" >&2
		echo -e "${script_name}: ERROR: Must set grub_src to root of grub sources." >&2
		usage
		exit 1
	fi

	if [[ ! -f "${gnulib_src}/gnulib-tool" ]]; then
		echo -e "${script_name}: ERROR: Bad gnulib_src: '${gnulib_src}'" >&2
		echo -e "${script_name}: ERROR: Must set gnulib_src to root of gnulib sources." >&2
		usage
		exit 1
	fi
}

git_clone() {
	git_checkout_safe ${gnulib_src} ${gnulib_repo} ${gnulib_branch}
	git_checkout_safe ${grub_src} ${grub_repo} ${grub_branch}
}

configure() {
	local host=${1}

	test_for_src

	pushd "${grub_src}"
	./bootstrap --gnulib-srcdir=${gnulib_src}
	./configure
	make -j ${cpus} distclean
	popd

	make -j ${cpus} maintainer-clean || :
	${grub_src}/configure --host=${host} --enable-mm-debug \
		--prefix=${install_prefix}
}

build_grub() {
	test_for_src

	make clean
	#make -j ${cpus} CFLAGS='-DMM_DEBUG=1'
	make -j ${cpus}
	make -j ${cpus} DESTDIR=${dest_dir} install
}

mk_image() {
	local image=${1}
	local format=${2}
	local config=${3}

	if ! test -x "$(command -v ${mkstandalone})"; then
		echo "${script_name}: ERROR: Please install '${mkstandalone}'." >&2
		exit 1
	fi

	rm -f ${image}

	echo "configfile ${config}" > grub.cfg

	${mkstandalone} \
		--directory="./grub-core" \
		--output=${image} \
		--format=${format} \
		--modules="part_gpt part_msdos ls help echo minicmd" \
		--locales="" \
		--verbose \
		/boot/grub/grub.cfg=./grub.cfg

	file ${image}
	ls -lh ${image}
}

sign_image() {
	local image=${1}
	local key=${2}
	local cert=${3}
	local out_file=${4}

	if ! test -x "$(command -v ${sbsign})"; then
		echo "${script_name}: ERROR: Please install '${sbsign}'." >&2
		exit 1
	fi

	if ! test -x "$(command -v ${sbverify})"; then
		echo "${script_name}: ERROR: Please install '${sbverify}'." >&2
		exit 1
	fi

	rm -f ${out_file}
	${sbsign} --key ${key} --cert ${cert} --output ${out_file} ${image}
	
	file ${out_file}
	ls -lh ${out_file}
	${sbverify} --list ${out_file}
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -ex

script_name="${0##*/}"
trap "on_exit 'failed.'" EXIT

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

src_dir=${src_dir:-"$(pwd)/src"}
grub_src=${grub_src:-"${src_dir}/grub"}

if [[ -d "${grub_src}/../gnulib" ]]; then
	gnulib_src=${gnulib_src:-"$( cd "${grub_src}/../gnulib" && pwd )"}
else
	gnulib_src=${gnulib_src:-"${src_dir}/gnulib"}
fi

grub_config=${grub_config:-"(hd11,gpt2)/grub/grub.cfg"}

gnulib_repo=${gnulib_repo:-'git://git.sv.gnu.org/gnulib'}
gnulib_branch=${gnulib_branch:-'master'}

#grub_repo=${grub_repo:='git://git.savannah.gnu.org/grub.git'}
grub_repo=${grub_repo:='https://github.com/glevand/grub.git'}
grub_branch=${grub_branch:='master'}

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

host_arch="$(uname -m)"
target_arch="arm64"

case ${target_arch} in
arm64)
	target_triple="aarch64-linux-gnu"
	image_file=${image_file:-"$(pwd)/grubaa64.efi"}
	image_format="arm64-efi"
	;;
*)
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
	;;
esac

if [[ ${host_arch} != ${target_arch} ]]; then
	mkstandalone=${mkstandalone:-"grub-mkstandalone"}
	dest_dir=${dest_dir:-"$(pwd)/target-out"}
else
	mkstandalone=${mkstandalone:-"./grub-mkstandalone"}
	dest_dir=${dest_dir:-''}
fi

sbsign=${sbsign:-"sbsign"}
sbverify=${sbverify:-"sbverify"}

install_prefix=${install_prefix:-"$(pwd)/install"}

cpus=$(cpu_count)
SECONDS=0

while true; do
	if [[ ${step_git_clone} ]]; then
		git_clone
		unset step_git_clone
	elif [[ ${step_configure} ]]; then
		configure ${target_triple}
		unset step_configure
	elif [[ ${step_build} ]]; then
		build_grub
		unset step_build
	elif [[ ${step_mk_image} ]]; then
		mk_image ${image_file} ${image_format} ${grub_config}
		unset step_mk_image
	elif [[ ${step_sign_image} ]]; then
		check_file ${image_file}
		check_opt 'mok-key' ${mok_key}
		check_file ${mok_key}
		check_opt 'mok-cert' ${mok_cert}
		check_file ${mok_cert}

		sign_image ${image_file} ${mok_key} ${mok_cert} \
			"${image_file%.efi}-signed.efi"
		unset step_sign_image
	else
		break
	fi
done

trap "on_exit 'Success.'" EXIT
