#!/bin/bash -e

if [[ -z $RUNNER_NAME ]]; then
    export RUNNER_NAME=`hostname`
fi

if [[ -z $RUNNER_REPOSITORY_URL ]]; then
    echo "Error : You need to set the RUNNER_REPOSITORY_URL environment variable."
    exit 1
fi

if [[ -z $RUNNER_TOKEN ]] && [[ -z $GITHUB_ACCESS_TOKEN ]]; then
    echo "Error : You need to set the RUNNER_TOKEN or GITHUB_ACCESS_TOKEN environment variable."
    exit 1
fi

if [[ -f ".runner" ]]; then
    echo "Runner already configured. Skipping config."
else
    if [[ -z $RUNNER_TOKEN ]]; then
        _PATH_="$(echo $RUNNER_REPOSITORY_URL | cut -d/ -f4-)"

        RUNNER_TOKEN="$(curl -XPOST -fsSL \
            -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${_PATH_}/actions/runners/registration-token" \
            | jq -r '.token')"
    fi

    /app/config.sh \
        --url $RUNNER_REPOSITORY_URL \
        --token $RUNNER_TOKEN \
        --name $RUNNER_NAME \
        --work $RUNNER_WORK_FOLDER \
        --replace \
        --unattended
fi

exec /app/bin/Runner.Listener run --startuptype service
