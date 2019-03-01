#!/bin/bash

read -r -d '' BLOBS_FILES <<- EOM
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/commons-daemon.tar
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/openjdk-1.8.0_121.tar.gz
EOM

PROXY_FILE='https://s3-us-west-2.amazonaws.com/wavefront-cdn/bsd/proxy-4.26-uber.jar'
NOZZLE_FILE='https://github.com/wavefrontHQ/cloud-foundry-nozzle-go/archive/v1-beta.1.tar.gz'

DOWNLOAD=NO
DEBUG=NO
FINAL=NO    #will use '--force' on bosh command

for i in "$@"; do
case $i in
    --DEBUG)
    DEBUG=YES
    shift
    ;;
    --download)
    DOWNLOAD=YES
    shift
    ;;
    --final)
    FINAL=YES
    shift
    ;;
esac
done

echo
echo "###"
echo -e "\033[1;32m Building Proxy Bosh release \033[0m"
echo "###"
echo
# get proxy release fileS
(
    cd proxy-bosh-release/blobs
    for url in ${BLOBS_FILES}; do
        file=$(echo "${url##*/}")
        [ "${DOWNLOAD}" == "YES" ] && rm ${file}
        if [ ! -f "${file}" ]; then
            echo "Downloading File '${file}' => ${url}"
            curl -L "${url}" --output ${file}
            [ $? -ne 0 ] && exit -1
        fi
    done
)

(
    cd proxy-bosh-release/src
    file=$(echo "${PROXY_FILE##*/}")
    [ "${DOWNLOAD}" == "YES" ] && rm file
    if [ ! -f "${file}" ]; then
        echo "Downloading File '${file}' => ${PROXY_FILE}"
        curl -L "${PROXY_FILE}" --output ${file}
        [ $? -ne 0 ] && exit -1
    fi
)

# build proxy release
(
    cd proxy-bosh-release
    [ "${FINAL}" == "NO" ] && BOSH_OPTS="--force"
    [ "${DEBUG}" == "YES" ] && BOSH_LOG_LEVEL=debug
    bosh create-release $BOSH_OPTS --name wavefront-proxy --tarball ../resources/wf-proxy-bosh-release.tgz
)

echo
echo "###"
echo -e "\033[1;32m Building PCF Tile \033[0m"
echo "###"
echo
# nozzle
(
    cd resources
    file='cloud-foundry-nozzle-go'
    tgz="${file}.tgz"
    [ "${DOWNLOAD}" == "YES" ] && rm ${file}*
    if [ ! -f "${tgz}" ]; then
        echo "Downloading File '${tgz}' => ${NOZZLE_FILE}"
        curl -L "${NOZZLE_FILE}" --output "${tgz}"
        [ $? -ne 0 ] && exit -1
    fi
    tar -zxf "${tgz}"

    #TEMP
    file='wavefront-cloudfoundry-broker-0.9.2-SNAPSHOT.jar'
    [ "${DOWNLOAD}" == "YES" ] && rm ${file}
    if [ ! -f "${file}" ]; then
        cp "/Users/glaullon/Downloads/cloud-foundry-servicebroker-0.9.2/target/${file}" .
    fi

)

tile build

echo
echo "###"
echo -e "\033[1;32m Done \033[0m"
echo "###"
echo
