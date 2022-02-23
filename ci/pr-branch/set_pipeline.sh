#!/usr/bin/env bash
set -efuo pipefail

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
project_dir=$(cd "${scripts_dir}"/../.. && pwd)
BRANCHNAME=${BRANCHNAME:-$(git branch --show-current)}

echo "setting $BRANCHNAME pr pipeline..."
fly --target tas2to set-pipeline \
    --pipeline wf-nozzle-"${BRANCHNAME}" \
    --config "${project_dir}"/ci/pr-branch/pipeline.yml \
    --var branch="${BRANCHNAME}"


## If logging in got the first time
## fly login --target tas2to -c https://concourse.cf-denver.com/ --team-name tas2to
