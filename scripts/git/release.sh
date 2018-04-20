#!/usr/bin/env bash
# Copyright (c) Microsoft. All rights reserved.
# Note: Windows Bash doesn't support shebang extra params
set -e

VERSION=$1
ACCESS_TOKEN=$2
DOCKER_USER=$3
DOCKER_PWD=$4
FROM_DOCKERHUB_NAMESPACE=${5:-azureiotpcs}
TO_DOCKERHUB_NAMESPACE=${6:-azureiotpcs}
SOURCE_TAG="${7:-testing}"
DESCRIPTION=$8
PRE_RELEASE=${9:-false}
LOCAL=${10}
APP_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && cd .. && pwd )/"

NC="\033[0m" # no color
CYAN="\033[1;36m" # light cyan
YELLOW="\033[1;33m" # yellow
RED="\033[1;31m" # light red

failed() {
    SUB_MODULE=$1
    echo -e "${RED}Cannot find directory $SUB_MODULE${NC}"
    exit 1
}

check_input() {
    if [ ! -n "$VERSION" ]; then
        echo -e "${RED}Version is required parameter${NC}"
        exit 1
    elif [ ! -n "$ACCESS_TOKEN" ]; then
        echo -e "${RED}Acess_token is required parameter${NC}"
        exit 1
    elif [ ! -n "$DOCKER_USER" ]; then
        echo -e "${RED}Docker username is required parameter${NC}"
        exit 1
    elif [ ! -n "$DOCKER_PWD" ]; then
        echo -e "${RED}Docker password is required parameter${NC}"
        exit 1
    fi
    echo $DOCKER_PWD | docker login -u $DOCKER_USER --password-stdin
}

tag_build_publish_repo() {
    SUB_MODULE=$1
    REPO_NAME=$2
    DOCKER_CONTAINER_NAME=${3:-$2}
    DESCRIPTION=$4

    echo
    echo -e "${CYAN}====================================     Start: Tagging the $REPO_NAME repo     ====================================${NC}"
    echo
    echo -e "Current working directory ${CYAN}$APP_HOME$SUB_MODULE${NC}"
    echo
    cd $APP_HOME$SUB_MODULE || failed $SUB_MODULE

    if [ -n "$LOCAL" ]; then
        echo "Cleaning the repo"
        git reset --hard origin/master
        git clean -xdf
    fi
    git checkout master
    git pull --all --prune
    git fetch --tags

    git tag --force $VERSION
    git push https://$ACCESS_TOKEN@github.com/Azure/$REPO_NAME.git $VERSION

    echo
    echo -e "${CYAN}====================================     End: Tagging $REPO_NAME repo     ====================================${NC}"
    echo

    echo
    echo -e "${CYAN}====================================     Start: Release for $REPO_NAME     ====================================${NC}"
    echo

    DATA="{
        \"tag_name\": \"$VERSION\",
        \"target_commitish\": \"master\",
        \"name\": \"$VERSION\",
        \"body\": \"$DESCRIPTION\",
        \"draft\": false,
        \"prerelease\": $PRE_RELEASE
    }"

    curl -X POST --data "$DATA" https://api.github.com/repos/Azure/$REPO_NAME/releases?access_token=$ACCESS_TOKEN
    echo
    echo -e "${CYAN}====================================     End: Release for $REPO_NAME     ====================================${NC}"
    echo

    if [ -n "$SUB_MODULE" ] && [ "$REPO_NAME" != "pcs-cli" ]; then
        echo
        echo -e "${CYAN}====================================     Start: Building $REPO_NAME     ====================================${NC}"
        echo

        BUILD_PATH="scripts/docker/build"
        if [ "$SUB_MODULE" == "reverse-proxy" ]; then 
            BUILD_PATH="build"
        fi

        # Building docker containers
        /bin/bash $APP_HOME$SUB_MODULE/$BUILD_PATH

        echo
        echo -e "${CYAN}====================================     End: Building $REPO_NAME     ====================================${NC}"
        echo
        
        # Tag containers
        echo -e "${CYAN}Tagging $FROM_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$SOURCE_TAG ==> $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION${NC}"
        echo
        docker tag $FROM_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$SOURCE_TAG  $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION

        # Push containers
        echo -e "${CYAN}Pusing container $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION${NC}"
        docker push $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION
    fi
}

check_input

# Java Microservices
tag_build_publish_repo config             pcs-config-java
tag_build_publish_repo iothub-manager     iothub-manager-java
tag_build_publish_repo storage-adapter    pcs-storage-adapter-java
tag_build_publish_repo telemetry          device-telemetry-java                 telemetry-java
tag_build_publish_repo telemetry-agent    telemetry-agent-java

# Top Level repo
tag_build_publish_repo ""                 azure-iot-pcs-remote-monitoring-java  ""                  $DESCRIPTION

# Only dotnet exists
# tag_build_publish_repo auth               pcs-auth-dotnet
# tag_build_publish_repo device-simulation  device-simulation-dotnet

# Done through dotnet release script
# tag_build_publish_repo webui              pcs-remote-monitoring-webui
# tag_build_publish_repo cli                pcs-cli

set +e