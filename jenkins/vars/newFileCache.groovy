#!groovy
// File caching routines.

void info() {
    echo 'version:2'
}

Map stage(String fileStagingDir, String fileCacheDir, String inPath) {
    String stage = "${fileStagingDir}/${inPath}"
    String cache = "${fileCacheDir}/${inPath}"

    String stageData = "${stage}/data"
    String stageStamp = "${stage}/stamp"
    String stageSum = "${stage}/sum"
    String stageType = "${stage}/type"
    String cacheData = "${cache}/data"
    String cacheStamp = "${cache}/stamp"
    String cacheSum = "${cache}/sum"
    String cacheType = "${cache}/type"

    //echo 'fileCache.stage: stage:  ' + stage
    //echo 'fileCache.stage: cache:  ' + cache
    //echo 'fileCache.stage: inPath: ' + inPath

    def result = sh(returnStatus: true,
    script: """#!/bin/bash -ex
export PS4='+fileCache.stage (script):\${LINENO}: '

if [[ -e ${stage} ]]; then
        echo "fileCache.stage: ERROR: Stage exists: '${stage}'" >&2
        exit 2
fi

if [[ -f ${inPath} ]]; then
    mkdir -p ${stage}
    cp -f ${inPath} ${stageData}
    echo "file" > ${stageType}
elif  [[ -d ${inPath} ]]; then
    mkdir -p ${stage}
    sudo tar -C ${inPath} -cf ${stageData} .
    echo "tar" > ${stageType}
else
    echo "fileCache.stage: ERROR: Bad inPath: '${inPath}'" >&2
    exit 2
fi

sudo chown \$(id --user --real --name): ${stageData}
sum=\$(md5sum ${stageData} | cut -d ' ' -f 1)

if [[ -f ${cacheStamp} && -f ${cacheSum} \
    && "\${sum}" == "\$(cat ${cacheSum})" ]]; then
    rm -rf ${stage}
    echo "fileCache.stage: Found '${inPath}' in '${fileCacheDir}'." >&2
    exit 1
fi

echo "\${sum}" > ${stageSum}

echo "version:2" > ${stageStamp}
echo "item:${inPath}" >> ${stageStamp}
echo "date:\$(date)" >> ${stageStamp}
echo "md5sum:\${sum}" >> ${stageStamp}

echo "fileCache.stage: Wrote '${inPath}' to '${stage}'." >&2
exit 0

""")

    echo "fileCache.stage result: @${result}@"

     return result ? [:] : [stage_dir:"${stage}", cache_dir:"${cache}"]
}

void commit(Map token, String stampInfo) {
    String stage = token.stage_dir
    String cache = token.cache_dir

    String stageStamp = "${stage}/stamp"

    //echo 'fileCache.stage: stage:      ' + stage
    //echo 'fileCache.stage: cache:      ' + cache
    //echo 'fileCache.commit: stampInfo: ' + stampInfo

    sh("""#!/bin/bash -ex
export PS4='+fileCache.commit (script):\${LINENO}: '
echo "${stampInfo}" >> ${stageStamp}
mkdir -p ${cache}
rsync -av --delete ${stage}/ ${cache}/
rm -rf ${stage}
""")
}

void put(String fileStagingDir, String fileCacheDir, String inPath,
    String stampInfo) {
    Map token = stage(fileStagingDir, fileCacheDir, inPath)
    if (! token.isEmpty()) {
        commit(token, stampInfo)
    }
}

boolean get(String fileCacheDir, String inPath, String outPath = '') {
    String cache = "${fileCacheDir}/${inPath}"

    String cacheData = "${cache}/data"
    String cacheStamp = "${cache}/stamp"
    String cacheSum = "${cache}/sum"
    String cacheType = "${cache}/type"

    if (outPath.isEmpty()) {
        outPath = inPath
    }

    echo 'fileCache.get: inPath:  ' + inPath
    echo 'fileCache.get: outPath: ' + outPath
    echo 'fileCache.get: cache:   ' + cache

    def result = sh(returnStatus: true,
        script: """#!/bin/bash -ex
export PS4='+fileCache.get (script):\${LINENO}: '

if [[ ! -d ${cache} ]]; then
    echo "fileCache.get: '${cache}' not found." >&2
    exit 1
fi

if [[ ! -f ${cacheData} ]]; then
    echo "fileCache.get: ERROR: '${cacheData}' not found in ${cache}." >&2
    exit 2
fi

if [[ ! -f ${cacheStamp} ]]; then
    echo "fileCache.get: ERROR: '${cacheStamp}' not found in ${cache}." >&2
    exit 2
fi

if [[ ! -f ${cacheSum} ]]; then
    echo "fileCache.get: ERROR: '${cacheSum}' not found in ${cache}." >&2
    exit 2
fi

if [[ ! -f ${cacheType} ]]; then
    echo "fileCache.get: ERROR: '${cacheType}' not found in ${cache}." >&2
    exit 2
fi

echo "fileCache.get: Using '${inPath}' from ${cache}." >&2

cat "${cacheStamp}"

if [[ -e  ${outPath} ]]; then
    mv -f ${outPath} ${outPath}.old
fi

data_type="\$(cat ${cacheType})"

case "\${data_type}" in
file)
        tmp="${outPath}"
        mkdir -p \${tmp%/*}
        cp -af ${cacheData} ${outPath}
    ;;
tar)
        mkdir -p ${outPath}
        sudo tar -C ${outPath} -xf ${cacheData}
    ;;
*)
    echo "fileCache.commit: ERROR: Bad data type: '\${data_type}" >&2
    exit 2
    ;;
esac

exit 0
""")

    echo "fileCache.get result: @${result}@"

    /* Return true if found. */
    return result ? false : true
}
