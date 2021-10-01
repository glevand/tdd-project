#!/usr/bin/env bash

real_source="$(realpath "${BASH_SOURCE}")"
SCRIPT_TOP="$(realpath "${SCRIPT_TOP:-${real_source%/*}}")"

files=$(find ${SCRIPT_TOP} -name '*.sh' -type f)

set +e
for f in ${files}; do
	echo "=== ${f} ====================================" >&2
	shellcheck ${f}
done
