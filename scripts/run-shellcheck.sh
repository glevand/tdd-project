#!/usr/bin/env bash

SCRIPTS_TOP=${SCRIPTS_TOP:-"$( cd "${BASH_SOURCE%/*}" && pwd )"}

files=$(find ${SCRIPTS_TOP} -name '*.sh' -type f)

set +e
for f in ${files}; do
	echo "=== ${f} ====================================" >&2
	shellcheck ${f}
done
