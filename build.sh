#!/bin/bash -x

read -r -d '' BLOBS_FILES <<- EOM
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/commons-daemon.tar
https://s3-us-west-2.amazonaws.com/wavefront-cdn/pcf/bosh-artifacts/openjdk-1.8.0_121.tar.gz
EOM

set -e

TELEGRAF_SOURCE='https://dl.influxdata.com/telegraf/releases/telegraf-1.10.0-static_linux_amd64.tar.gz'
TELEGRAF_TGZ='telegraf.tgz'

PROXY_SOURCE='https://github.com/wavefrontHQ/java/archive/wavefront-4.36.tar.gz'
PROXY_TGZ='proxy.tgz'

NOZZLE_SOURCE='https://github.com/wavefrontHQ/cloud-foundry-nozzle-go/archive/v1-beta.5.tar.gz'
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
[ "${DEBUG}" == "YES" ] && export BOSH_LOG_LEVEL=debug
[ "${DEBUG}" == "YES" ] && MVN_OPTS='-B' || MVN_OPTS='-q'

[ -d "tmp" ] && rm -rf tmp/* || mkdir -p tmp

[ -f proxy-bosh-release/src/wavefront-proxy.jar ] && rm proxy-bosh-release/src/wavefront-proxy.jar
[ -f resources/proxy-bosh-release.tgz ] && rm resources/proxy-bosh-release.tgz
[ -f resources/wavefront-broker.jar ] && rm resources/wavefront-broker.jar
[ -d resources/cloud-foundry-nozzle-go ] && rm -rf resources/cloud-foundry-nozzle-go

# rm telegraf-bosh-release/dev_releases/wavefront-telegraf/*

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
echo -e "\033[1;32m Building Wavefront Telegraf \033[0m"
echo "###"
echo

(
    cd tmp
    echo "Downloading File '${TELEGRAF_TGZ}' => ${TELEGRAF_SOURCE}"
    curl -L "${TELEGRAF_SOURCE}" --output "${TELEGRAF_TGZ}"

    cp ${TELEGRAF_TGZ} ../telegraf-bosh-release/src/

    cd ../telegraf-bosh-release
    bosh create-release $BOSH_OPTS --name wavefront-telegraf --tarball ../resources/telegraf-bosh-release.tgz
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

    cd java*
    mvn ${MVN_OPTS} clean install -DskipTests
    cp proxy/target/proxy-*-uber.jar ../../proxy-bosh-release/src/wavefront-proxy.jar
)

# echo
# echo "###"
# echo -e "\033[1;32m Building Wavefront nozzle \033[0m"
# echo "###"
# echo
# (
#     cd tmp
#     echo "Downloading File '${NOZZLE_TGZ}' => ${NOZZLE_SOURCE}"
#     curl -L "${NOZZLE_SOURCE}" --output "${NOZZLE_TGZ}"

#     tar -zxf "${NOZZLE_TGZ}"
#     mv cloud-foundry-nozzle-go* ../resources/cloud-foundry-nozzle-go
# )

# echo
# echo "###"
# echo -e "\033[1;32m Building Wavefront Servicebroker \033[0m"
# echo "###"
# echo

# (
#     cd tmp
#     echo "Downloading File '${BROKER_TGZ}' => ${BROKER_SOURCE}"
#     curl -L "${BROKER_SOURCE}" --output "${BROKER_TGZ}"

#     tar -zxf "${BROKER_TGZ}"

#     cd cloud-foundry-servicebroker-*
#     mvn ${MVN_OPTS} clean install -DskipTests
#     cp target/wavefront-cloudfoundry-broker-*-SNAPSHOT.jar ../../resources/wavefront-broker.jar
# )

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
echo -e "\033[1;32m Building PCF Nozzle Tile \033[0m"
echo "###"
echo

(
    cd nozzle_tile
    tile build
    cp product/*.pivotal ../
)

echo
echo "###"
echo -e "\033[1;32m Building PCF Telegraf Tile \033[0m"
echo "###"
echo

(
    VERSION_FILE=$(ls -rt telegraf-bosh-release/dev_releases/wavefront-telegraf/wavefront-telegraf-*.yml | tail -1)
    VERSION=$(grep "version" ${VERSION_FILE} | head -1)
    sed -i -E "s/version\:[^#]*# UPDATE-ME/${VERSION} # UPDATE-ME/g" telegraf_tile/tile.yml

    cd telegraf_tile
    tile build
    cp product/*.pivotal ../
)

echo
echo "###"
echo -e "\033[1;32m Done \033[0m"
echo "###"
echo
