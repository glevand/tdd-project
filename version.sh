#!/usr/bin/env bash
#
# version.sh: Create a version string for use by configure.ac
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 2 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

version=
datefmt='%Y.%m.%d'

GIT_DIR=$(dirname "${0}")/.git/
export GIT_DIR

if head="$(git rev-parse --short=8 --verify HEAD 2>/dev/null)"; then
	suffix=''
	# Add a '-dirty' suffix for uncommitted changes.
	if git diff-index HEAD | read -r dummy; then
		suffix='-dirty'
	fi

	if tag="$(git describe --tags --exact-match 2>/dev/null)"; then
		# use a tag; remove any 'v' prefix from v<VERSION> tags
		tag="${tag#v}"
		version="$(printf "%s%s" "${tag}" "${suffix}")"
	else
		# Use the git commit revision for the package version, and add
		# a date prefix for easy comparisons.
		date="$(git log --pretty=format:"%ct" -1 HEAD)"
		version="$(printf "%($datefmt)T.g%s%s" "${date}" "${head}" "${suffix}")"
	fi
else
	# Check if a specific version is set, eg: by buildroot
	if [ -n "${PACKAGE_VERSION}" ]; then
		# Full git hash
		len="$(echo -n "${PACKAGE_VERSION}" | wc -c)"
		if [[ ${len} == 40 ]]; then
			version="$(echo -n "${PACKAGE_VERSION}" | sed 's/^\([0-9a-f]\{7\}\).*/\1/;')"
		else
			version="${PACKAGE_VERSION}"
		fi
	else
		# Default to current date and time.
		version="$(date +dev.${datefmt})"
	fi
fi

echo "${version}"
