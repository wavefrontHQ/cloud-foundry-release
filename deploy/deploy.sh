#!/bin/bash
# A Simple Shell Script to Deploy Nozzle for PCF
set -e

parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml ../tile-history.yml "tile_")
eval $(parse_yaml metadata "target_")

tile_name=wavefront-nozzle
tile_file=../product/${tile_name}-${tile_version}.pivotal

echo
echo "###"
echo -e "\033[1;32m deploying \033[0m" ${tile_file}
echo -e "\033[1;32m        to \033[0m" ${target_opsmgr_url}
echo "###"
echo

echo "pcf import ..."
pcf import ${tile_file}
echo -e "import \033[1;32m OK \033[0m" 

echo "pcf install ..."
pcf install ${tile_name} ${tile_version}
echo -e "install \033[1;32m OK \033[0m" 

echo "pcf configure ..."
pcf configure ${tile_name} properties.yml
echo -e "configure \033[1;32m OK \033[0m" 

echo "pcf apply-changes ..."
pcf apply-changes
echo -e "apply-changes \033[1;32m OK \033[0m" 