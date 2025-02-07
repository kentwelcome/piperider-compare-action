#!/bin/bash -l
set -o pipefail

if [[ "${GITHUB_EVENT_NAME}" != "pull_request" ]]; then
  echo "[Error] This action is designed to work with pull_request events only."
  echo "::error::This action is designed to work with pull_request events only."
  exit 0
fi

export GITHUB_ACTION_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

echo "[PipeRider] Version: $(piperider version && rm .piperider/.unsend_events.json)"

# Replace the user_id with a unique id for the repository
uuid=$(uuidgen -n @oid -N "${GITHUB_REPOSITORY}" --sha1 | tr -d "-")
sed -i "s/^user_id: .*$/user_id: ${uuid}/" ~/.piperider/profile.yml

# Install the requirements if the file exists in the repository
if [ -f ${GITHUB_WORKSPACE}/requirements.txt ]; then
    echo "[PipeRider] Installing requirements.txt"
    pip install -q --no-cache-dir -r ${GITHUB_WORKSPACE}/requirements.txt
fi

# Install the piperider data connectors based on .piperider/config.yml
for datasource_type in "$(yq '.dataSources[].type' ${GITHUB_WORKSPACE}/.piperider/config.yml)"; do
    case "${datasource_type}" in
        sqlite)
            echo "[PipeRider] Skipping sqlite, it is built-in"
        ;;
        *)
            pip install -q --no-cache-dir piperider[${datasource_type}] || echo "[PipeRider] Failed to install piperider[${datasource_type}]"; true
        ;;
    esac
done

# Setup credentials for the data connectors if user provides
if [ "${INPUT_CREDENTIALS_YML:-}" != '' ]; then
    echo "[PipeRider] Setting up credentials.yml"
    echo "${INPUT_CREDENTIALS_YML}" > ${GITHUB_WORKSPACE}/.piperider/credentials.yml
fi

# work around for dev helper
# pip install -q git+https://github.com/InfuseAI/piperider.git@feature/sc-30601/make-compare-recipe-working-on-github-action -t /tmp/utils


# required by running compare with the GitHub action
git config --global --add safe.directory /github/workspace

# make the git merge-base working
git fetch --unshallow

set -e
# invoke the github-action helper script
python -m piperider_cli.recipes.github_action prepare_for_action
run_commands=$(python -m piperider_cli.recipes.github_action make_recipe_command)
for cmd in $run_commands; do
    echo "[PipeRider] CMD Execlute => $cmd"
    eval $cmd ; rc=$?
done

echo "status=${rc}" >> $GITHUB_OUTPUT
echo "uuid=${uuid}" >> $GITHUB_OUTPUT
echo "uuid=${uuid}" >> $GITHUB_STEP_SUMMARY

python -m piperider_cli.recipes.github_action attach_comment