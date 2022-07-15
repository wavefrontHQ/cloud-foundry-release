#!/usr/bin/env bash
set -efuo pipefail

which ytt || (
  echo "This requires ytt to be installed"
  echo "Download the binary from https://github.com/vmware-tanzu/carvel-ytt/releases"
  exit 1
)
which fly || (
  echo "This requires fly to be installed"
  echo "Download the binary from https://github.com/concourse/concourse/releases or from the hw-denver Concourse: https://concourse.cf-denver.com/"
  exit 1
)

fly -t tas2to sync || (
  echo "This requires the tas2to target to be set"
  echo "Create this target by running 'fly -t tas2to login -c https://concourse.cf-denver.com/ -n tas2to'"
  exit 1
)

scripts_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd "${scripts_dir}"/.. && pwd)

fly --target tas2to set-pipeline \
    --pipeline legacy-wf-nozzle-main \
    --config <(ytt -f "${project_dir}/ci/pipeline.yml") \
    --var initial-version="0.5.0" \
    --var docker-host="10.0.1.5"