#!/bin/bash

if [[ ${1} ]]; then
	echo "Usage: ${0##*/} < file.rpm" >&2
	exit 1
fi

set -x

rpm2cpio - | cpio --extract --unconditional --make-directories --preserve-modification-time
