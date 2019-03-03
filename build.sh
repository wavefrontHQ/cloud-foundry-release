#!/bin/bash 

read -r -d '' BLOBS_FILES <<- EOM
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/commons-daemon.tar
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/openjdk-1.8.0_121.tar.gz
EOM

set -e

PROXY_SOURCE='https://github.com/wavefrontHQ/java/archive/wavefront-4.35.tar.gz'
PROXY_TGZ='proxy.tgz'

NOZZLE_SOURCE='https://github.com/wavefrontHQ/cloud-foundry-nozzle-go/archive/v1-beta.1.tar.gz'
NOZZLE_TGZ='nozzle.tgz'

BROKER_SOURCE='https://github.com/wavefrontHQ/cloud-foundry-servicebroker/archive/0.9.3.tar.gz'
BROKER_TGZ='broker.tgz'

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

[ "${FINAL}" == "NO" ] && BOSH_OPTS="--force"
[ "${DEBUG}" == "YES" ] && BOSH_LOG_LEVEL=debug
[ "${DEBUG}" == "YES" ] && MVN_OPTS='-B' || MVN_OPTS='-q'

mkdir -p tmp
mkdir -p wf_file

echo
echo "###"
echo -e "\033[1;32m Donwloading dependecies \033[0m"
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
        fi
    done
)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront Proxy \033[0m"
echo "###"
echo

(
    cd wf_files
    [ "${DOWNLOAD}" == "YES" ] && rm ${PROXY_TGZ}
    if [ ! -f "${PROXY_TGZ}" ]; then
        echo "Downloading File '${PROXY_TGZ}' => ${PROXY_SOURCE}"
        curl -L "${PROXY_SOURCE}" --output "${PROXY_TGZ}"
    fi

    cd ../tmp
    tar -zxf "../wf_files/${PROXY_TGZ}"

    cd java*
    mvn ${MVN_OPTS} clean install -DskipTests
    cp proxy/target/proxy-*-uber.jar ../../proxy-bosh-release/src/wavefront-proxy.jar
)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront nozzle \033[0m"
echo "###"
echo
(
    cd wf_files
    [ "${DOWNLOAD}" == "YES" ] && rm ${NOZZLE_TGZ}
    if [ ! -f "${NOZZLE_TGZ}" ]; then
        echo "Downloading File '${NOZZLE_TGZ}' => ${NOZZLE_SOURCE}"
        curl -L "${NOZZLE_SOURCE}" --output "${NOZZLE_TGZ}"
    fi

    cd ../resources
    tar -zxf "../wf_files/${NOZZLE_TGZ}"
)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront Servicebroker \033[0m"
echo "###"
echo

(
    cd wf_files
    [ "${DOWNLOAD}" == "YES" ] && rm ${BROKER_TGZ}
    if [ ! -f "${BROKER_TGZ}" ]; then
        echo "Downloading File '${BROKER_TGZ}' => ${BROKER_SOURCE}"
        curl -L "${BROKER_SOURCE}" --output "${BROKER_TGZ}"
    fi

    cd ../tmp
    tar -zxf "../wf_files/${BROKER_TGZ}"

    cd cloud-foundry-servicebroker-*
    mvn ${MVN_OPTS} clean install -DskipTests
    cp target/wavefront-cloudfoundry-broker-*-SNAPSHOT.jar ../../resources/wavefront-broker.jar
)

# build proxy release
echo
echo "###"
echo -e "\033[1;32m Building Proxy Bosh Release\033[0m"
echo "###"
echo
(
    cd proxy-bosh-release
    bosh create-release $BOSH_OPTS --name wavefront-proxy --tarball ../resources/proxy-bosh-release.tgz
)

echo
echo "###"
echo -e "\033[1;32m Building PCF Tile \033[0m"
echo "###"
echo

tile build

echo
echo "###"
echo -e "\033[1;32m Done \033[0m"
echo "###"
echo
