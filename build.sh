#!/bin/bash
# A Simple Shell Script to Build Nozzle for PCF

read -r -d '' BLOBS_FILES <<- EOM
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/commons-daemon-1.2.3-bin.tar.gz
https://wavefront-cdn.s3-us-west-2.amazonaws.com/pcf/bosh-artifacts/openjdk-11_28_linux-x64_bin.tar.gz
https://wavefront-cdn.s3-us-west-2.amazonaws.com/pcf/bosh-artifacts/jsvc-1.2.3.zip
EOM

set -e

PROXY_SOURCE='https://github.com/wavefrontHQ/java/archive/wavefront-9.2.tar.gz'
PROXY_TGZ='proxy.tgz'

NOZZLE_SOURCE='https://github.com/wavefrontHQ/cloud-foundry-nozzle-go/archive/v1.3.1.tar.gz'
# NOZZLE_SOURCE="${HOME}/go/src/github.com/wavefronthq/cloud-foundry-nozzle-go/"
NOZZLE_TGZ='nozzle.tgz'

BROKER_SOURCE='https://github.com/wavefrontHQ/cloud-foundry-servicebroker/archive/0.9.5.tar.gz'
# BROKER_SOURCE="${HOME}/wavefront/cloud-foundry-servicebroker/"
BROKER_TGZ='broker.tgz'

DOWNLOAD=NO
DEBUG=NO
FINAL=NO    #will use '--force' on bosh command

[ -f version.txt ] && VERSION=$(cat version.txt)

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
    *)
    VERSION=$i
esac
done

[ "${FINAL}" == "NO" ] && BOSH_OPTS="--force" || BOSH_OPTS="--final"
[ "${FINAL}" == "YES" ] && git clean -xdf
[ "${DEBUG}" == "YES" ] && export BOSH_LOG_LEVEL=debug
[ "${DEBUG}" == "YES" ] && MVN_OPTS='-B' || MVN_OPTS='-q'

# Checking 'tile' binary version

get_tile_latest_release() {
  curl --silent "https://api.github.com/repos/cf-platform-eng/tile-generator/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                                                        # Get tag line
    sed -E 's/.*"v([^"]+)".*/\1/'                                                                # Pluck JSON value
}

currentver=$(tile -v | cut -d" " -f3)
requiredver=$(get_tile_latest_release)
 if [ "$(printf '%s\n' "${requiredver}" "${currentver}" | sort -V | head -n1)" != "${requiredver}" ]; then 
        echo "'tile' binary version '${currentver}' is older than '${requiredver}', please update it. https://github.com/cf-platform-eng/tile-generator/releases/latest"
        exit 1
 fi

echo "Using version: '${VERSION}'"

[ -d "tmp" ] && rm -rf tmp/* || mkdir -p tmp

[ -f proxy-bosh-release/src/wavefront-proxy.jar ] && rm proxy-bosh-release/src/wavefront-proxy.jar
[ -f resources/proxy-bosh-release.tgz ] && rm resources/proxy-bosh-release.tgz
[ -f resources/wavefront-broker.jar ] && rm resources/wavefront-broker.jar
[ -d resources/cloud-foundry-nozzle-go ] && rm -rf resources/cloud-foundry-nozzle-go

echo
echo "###"
echo -e "\033[1;32m Downloading dependencies \033[0m"
echo "###"
echo
# get proxy release files
(
    mkdir -p proxy-bosh-release/blobs
    cd proxy-bosh-release/blobs
    for url in ${BLOBS_FILES}; do
        file=$(echo "${url##*/}")
        if [[ "${file}" == openjdk* ]]; then
            file="openjdk-11+28_linux-x64_bin.tar.gz"
        fi
        [ "${DOWNLOAD}" == "YES" ] && rm ${file}
        if [ ! -f "${file}" ]; then
            echo "Downloading File '${file}' => ${url}"
            curl -L "${url}" --output ${file}
            if [[ "${file}" == jsvc* ]]; then
                [ -f "jsvc" ] && rm jsvc
                unzip ${file}
            fi
        fi
    done
)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront Proxy \033[0m"
echo "###"
echo

(
    cd tmp
    echo "Downloading File '${PROXY_TGZ}' => ${PROXY_SOURCE}"
    curl -L "${PROXY_SOURCE}" --output "${PROXY_TGZ}"

    tar -zxf "${PROXY_TGZ}"

    cd wavefront-proxy-wavefront*
    mvn ${MVN_OPTS} clean install -DskipTests -Dlog4j.version=2.16.0
    cp proxy/target/proxy-*-uber.jar ../../proxy-bosh-release/src/wavefront-proxy.jar
)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront Nozzle \033[0m"
echo "###"
echo
(
    cd tmp
    if [[ -d ${NOZZLE_SOURCE} ]]; then
        [ "${FINAL}" == "YES" ] && echo "For final tile use Nozzle Git release" && exit 1
        echo "Copying files '${NOZZLE_SOURCE}' => $(pwd)/../resources/cloud-foundry-nozzle-go"
        cp -r ${NOZZLE_SOURCE} ../resources/cloud-foundry-nozzle-go
        (
            cd ../resources/cloud-foundry-nozzle-go
            rm -rf vendor
            go mod vendor
        )
    else
        echo "Downloading File '${NOZZLE_TGZ}' => ${NOZZLE_SOURCE}"
        curl -L "${NOZZLE_SOURCE}" --output "${NOZZLE_TGZ}"
        tar -zxf "${NOZZLE_TGZ}"
        mkdir -p src/github.com/wavefronthq
        mv cloud-foundry-nozzle-go* src/github.com/wavefronthq/cloud-foundry-nozzle-go
        tmp=$(pwd)
        cd src/github.com/wavefronthq/cloud-foundry-nozzle-go
        GOPATH=${tmp} go mod vendor
        cd ..
        cp -r cloud-foundry-nozzle-go ${tmp}/../resources/cloud-foundry-nozzle-go
    fi

)

echo
echo "###"
echo -e "\033[1;32m Building Wavefront Service Broker \033[0m"
echo "###"
echo

(
    cd tmp
    if [[ -d ${BROKER_SOURCE} ]]; then
        echo "Copying files '${BROKER_SOURCE}' => $(pwd)"
        mkdir cloud-foundry-servicebroker
        cp -r ${BROKER_SOURCE} cloud-foundry-servicebroker/
    else
        echo "Downloading File '${BROKER_TGZ}' => ${BROKER_SOURCE}"
        curl -L "${BROKER_SOURCE}" --output "${BROKER_TGZ}"
        tar -zxf "${BROKER_TGZ}"
        mv cloud-foundry-servicebroker-* cloud-foundry-servicebroker
    fi

    cd cloud-foundry-servicebroker
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
    bosh create-release $BOSH_OPTS --version ${VERSION} --name wavefront-proxy --tarball ../resources/proxy-bosh-release.tgz
)

echo
echo "###"
echo -e "\033[1;32m Building PCF Tile \033[0m"
echo "###"
echo

tile build ${VERSION}

echo
echo "###"
echo -e "\033[1;32m Done \033[0m"
echo "###"
echo

