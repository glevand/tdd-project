#!groovy
// File caching routines.

void info() {
    echo 'version:1'
}

boolean stage(String cache_path, String tag, String item, String stamp_info) {
// TODO
}

boolean commit(String cache_path, String tag) {
// TODO
}


void put(String cache_path, String item, String stamp_info) {

// FIXME: Need to avoid concurrent access by multiple runing jobs.

    sh(script: """#!/bin/bash -ex
    export PS4='+\${BASH_SOURCE##*/}:\${LINENO}:'

    sum_file=${cache_path}/${item}.sum
    stamp_file=${cache_path}/${item}.stamp
    tmp_file=${cache_path}/${item}.tmp

    mkdir -p ${cache_path}/${item}

    if [[ -f ${item} ]]; then
        cp -f ${item} \${tmp_file}
        dest=${cache_path}/${item}
    elif  [[ -d ${item} ]]; then
        sudo tar -cf \${tmp_file} ${item}
        dest=${cache_path}/${item}.tar
    else
        echo "ERROR: Bad item: '${item}" >&2
        exit 1
    fi

    sudo chown \$(id --user --real --name): \${tmp_file}
    sum=\$(md5sum \${tmp_file} | cut -d ' ' -f 1)

    if [[ -f \${stamp_file} && -f \${sum_file} \
        && "\${sum}" == "\$(cat \${sum_file})" ]]; then
        echo "cache-put: Found '${item}' in ${cache_path}." >&2
        rm -f \${tmp_file}
        exit 0
    fi

    rm -f \${stamp_file}
    echo "\${sum}" > \${sum_file}
    mv -f \${tmp_file} \${dest}

    echo "version:1" > \${stamp_file}
    echo "item:${item}" >> \${stamp_file}
    echo "date:\$(date)" >> \${stamp_file}
    echo "md5sum:\${sum}" >> \${stamp_file}
    echo "${stamp_info}" >> \${stamp_file}

    echo "cache-put: Wrote '${item}' to ${cache_path}." >&2
    exit 0
""")
}

boolean get(String cache_path, String item, boolean use_flag) {
    if (!use_flag) {
        echo 'cache-get: use_flag false, ignoring cache.'
        return false
    }
    echo 'cache-get: use_flag true, checking cache.'

    def result = sh(returnStatus: true,
    script: """#!/bin/bash -ex
    export PS4='+\${BASH_SOURCE##*/}:\${LINENO}:'

    sum_file=${cache_path}/${item}.sum
    stamp_file=${cache_path}/${item}.stamp

    if [[ -f ${cache_path}/${item} ]]; then
        src=${cache_path}/${item}
    elif  [[  -f ${cache_path}/${item}.tar ]]; then
        have_tar=1
        src=${cache_path}/${item}.tar
    else
        echo "cache-get: '${item}' not found in ${cache_path}." >&2
        exit 1
    fi

    if [[ ! -f \${stamp_file} ]]; then
        echo "cache-get: '\${stamp_file}' not found in ${cache_path}." >&2
        exit 1
    fi

    if [[ ! -f \${sum_file} ]]; then
        echo "cache-get: '\${sum_file}' not found in ${cache_path}." >&2
        exit 1
    fi

    if [[ ! -f \${src} ]]; then
        echo "cache-get: '\${src}' not found in ${cache_path}." >&2
        exit 1
    fi

    echo "cache-get: Using '${item}' from ${cache_path}." >&2

    cat "\${stamp_file}"

    rm -rf ${item}.old

    if [[ -e  ${item} ]]; then
        mv ${item} ${item}.old
    fi

    if [[ \${have_tar} ]]; then
        sudo tar -xf \${src}
    else
        cp -af \${src} ${item}
    fi
    exit 0
""")

    echo "cache-get result: @${result}@"

    /* Return true if found. */
    return result ? false : true
}
