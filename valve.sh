#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

THIS_REPO="opsnow-tools"
THIS_NAME="valve-ctl"
THIS_VERSION="v0.0.0"

SHELL_DIR=$(dirname $0)

CMD=

NAME=
VERSION=
NEMESPACE=

SECRET=
CHARTMUSEUM=
REGISTRY=

FORCE=
DELETE=
REMOTE=
VERVOSE=

CONFIG=${HOME}/.valve-ctl
touch ${CONFIG} && . ${CONFIG}

################################################################################

command -v fzf > /dev/null && FZF=true
command -v tput > /dev/null && TPUT=true

_echo() {
    if [ "${TPUT}" != "" ] && [ "$2" != "" ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
}

_read() {
    echo
    if [ "${2}" == "" ]; then
        if [ "${TPUT}" != "" ]; then
            read -p "$(tput setaf 6)$1$(tput sgr0)" ANSWER
        else
            read -p "$1" ANSWER
        fi
    else
        if [ "${TPUT}" != "" ]; then
            read -s -p "$(tput setaf 6)$1$(tput sgr0)" ANSWER
        else
            read -s -p "$1" ANSWER
        fi
        echo
    fi
}

_result() {
    echo
    _echo "# $@" 4
}

_command() {
    echo
    _echo "$ $@" 3
}

_success() {
    echo
    _echo "+ $@" 2
    exit 0
}

_error() {
    echo
    _echo "- $@" 1
    exit 1
}

_replace() {
    if [ "${OS_NAME}" == "darwin" ]; then
        sed -i "" -e "$1" $2
    else
        sed -i -e "$1" $2
    fi
}

_select_one() {
    OPT=$1

    SELECTED=

    CNT=$(cat ${LIST} | wc -l | xargs)
    if [ "x${CNT}" == "x0" ]; then
        return
    fi

    if [ "${OPT}" != "" ] && [ "x${CNT}" == "x1" ]; then
        SELECTED="$(cat ${LIST} | xargs)"
    else
        if [ "${FZF}" != "" ]; then
            SELECTED=$(cat ${LIST} | fzf --reverse --no-mouse --height=10 --bind=left:page-up,right:page-down)
        else
            echo

            IDX=0
            while read VAL; do
                IDX=$(( ${IDX} + 1 ))
                printf "%3s. %s\n" "${IDX}" "${VAL}"
            done < ${LIST}

            if [ "${CNT}" != "1" ]; then
                CNT="1-${CNT}"
            fi

            _read "Please select one. (${CNT}) : "

            if [ -z ${ANSWER} ]; then
                return
            fi
            TEST='^[0-9]+$'
            if ! [[ ${ANSWER} =~ ${TEST} ]]; then
                return
            fi
            SELECTED=$(sed -n ${ANSWER}p ${LIST})
        fi
    fi
}

################################################################################

_usage() {
    #figlet valve ctl
cat <<EOF
================================================================================
             _                  _   _
 __   ____ _| |_   _____    ___| |_| |
 \ \ / / _' | \ \ / / _ \  / __| __| |
  \ V / (_| | |\ V /  __/ | (__| |_| |
   \_/ \__,_|_| \_/ \___|  \___|\__|_|  ${THIS_VERSION}
================================================================================
Usage: `basename $0` {Command} [Name] [Arguments ..]

Commands:
    c, config               저장된 설정을 조회 합니다.

    i, init                 초기화를 합니다. Kubernetes 에 필요한 툴을 설치 합니다.
        -f, --force         가능하면 재설치 합니다.
        -d, --delete        기존 배포를 삭제 하고, 다음 작업을 수행합니다.

    g, gen                  프로젝트 배포에 필요한 패키지를 설치 합니다.
        -d, --delete        기존 패키지를 삭제 하고, 다음 작업을 수행합니다.

    u, up                   프로젝트를 Local Kubernetes 에 배포 합니다.
        -d, --delete        기존 배포를 삭제 하고, 다음 작업을 수행합니다.
        -r, --remote        Remote 프로젝트를 Local Kubernetes 에 배포 합니다.

    r, remote               Remote 프로젝트를 Local Kubernetes 에 배포 합니다.
        -v, --version=      프로젝트 버전을 알고 있을 경우 입력합니다.

    a, all                  배포된 리소스의 전체 list 를 조회 합니다.

    l, ls, list             배포된 리소스의 list 를 조회 합니다.
    d, desc                 배포된 리소스의 describe 를 조회 합니다.
    h, hpa                  배포된 리소스의 Horizontal Pod Autoscaler 를 조회 합니다.
    s, ssh                  배포된 리소스의 Pod 에 ssh 접속을 시도 합니다.
    log, logs               배포한 리소스의 logs 를 조회 합니다.
        -n, --namespace=    지정된 namespace 를 조회 합니다.

    rm, remove              배포한 프로젝트를 삭제 합니다.

    clean                   저장된 설정을 모두 삭제 합니다.
        -d, --delete        docker 이미지도 모두 삭제 합니다.

    tools                   개발에 필요한 툴을 설치 합니다. (MacOS, Ubuntu 만 지원)
    update                  valve 를 최신버전으로 업데이트 합니다.
    v, version              valve 버전을 확인 합니다.
================================================================================
EOF
    _success
}

_args() {
    if [ "${OS_NAME}" == "darwin" ]; then
        GETOPT=$(getopt 2>&1 | head -1 | xargs)
        if [ "${GETOPT}" == "--" ]; then
            brew install gnu-getopt
            brew link --force gnu-getopt
            _error
        fi
    fi

    OPTIONS=$(getopt -l "version:,namespace:,chartmuseum:,registry:,force,delete,remote,verbose" -o "v:n:c:g:fdrV" -a -- "$@")
    eval set -- "${OPTIONS}"

    while true; do
        case $1 in
        -v|--version)
            shift
            VERSION=$1
            ;;
        -n|--namespace)
            shift
            NAMESPACE=$1
            ;;
        -c|--chartmuseum)
            shift
            CHARTMUSEUM=$1
            ;;
        -g|--registry)
            shift
            REGISTRY=$1
            ;;
        -f|--force)
            FORCE=1
            ;;
        -d|--delete)
            DELETE=1
            ;;
        -r|--remote)
            REMOTE=1
            ;;
        -V|--verbose)
            VERVOSE=1
            set -xv  # Set xtrace and verbose mode.
            ;;
        --)
            shift
            break
            ;;
        esac
        shift
    done

    CMD=$1
    NAME=$2

    shift && shift
    EXTRA=$@
}

_run() {
    case ${CMD} in
        c|conf|config)
            _config
            ;;
        i|init)
            _init
            ;;
        g|gen)
            _gen
            ;;
        guard)
            _guard
            ;;
        secret)
            _secret ${NAME} ${NAMESPACE}
            ;;
        up)
            if [ -z ${REMOTE} ]; then
                _up
            else
                _remote
            fi
            ;;
        r|remote)
            _remote
            ;;
        ctx|context)
            _context
            ;;
        a|all)
            _all
            ;;
        l|ls|list)
            _list
            ;;
        d|desc|describe)
            _describe
            ;;
        h|hpa)
            _hpa
            ;;
        s|ssh)
            _ssh
            ;;
        log|logs)
            _logs
            ;;
        exe|exec)
            _exec
            ;;
        rm|remove)
            _remove
            ;;
        clean)
            _clean
            ;;
        tools)
            _tools
            ;;
        update)
            _update
            ;;
        v|version)
            _version
            ;;
        *)
            _usage
    esac
}

_tools() {
    curl -sL repo.opsnow.io/${THIS_NAME}/tools | bash
    exit 0
}

_update() {
    _echo "# version: ${THIS_VERSION}" 3
    curl -sL repo.opsnow.io/${THIS_NAME}/install | bash -s ${NAME}
    exit 0
}

_version() {
    _command "kubectl version"
    kubectl version --client --short | xargs | awk '{print $3}' | cut -d'+' -f1

    _command "helm version"
    helm version --client --short | xargs | awk '{print $2}' | cut -d'+' -f1

    _command "draft version"
    draft version --short | xargs | cut -d'+' -f1

    _command "valve version"
    _echo "${THIS_VERSION}"
}

_waiting_pod() {
    _NS=${1}
    _NM=${2}
    SEC=${3:-30}

    TMP=/tmp/${THIS_NAME}-pod-status

    _command "kubectl get pod -n ${_NS} | grep ${_NM}"

    IDX=0
    while [ 1 ]; do
        kubectl get pod -n ${_NS} | grep ${_NM} | head -1 > ${TMP}
        cat ${TMP}

        STATUS=$(cat /tmp/${THIS_NAME}-pod-status | awk '{print $3}')

        if [ "${STATUS}" == "Running" ] && [ "${_NS}" != "development" ]; then
            READY=$(cat /tmp/${THIS_NAME}-pod-status | awk '{print $2}' | cut -d'/' -f1)
        else
            READY="1"
        fi

        if [ "${STATUS}" == "Running" ] && [ "x${READY}" != "x0" ]; then
            break
        elif [ "${STATUS}" == "Error" ]; then
            _error "${STATUS}"
        elif [ "${STATUS}" == "CrashLoopBackOff" ]; then
            _error "${STATUS}"
        elif [ "x${IDX}" == "x${SEC}" ]; then
            _error "Timeout"
        fi

        IDX=$(( ${IDX} + 1 ))
        sleep 2
    done
}

_config() {
    echo
    cat ${CONFIG}
}

_config_save() {
    echo "# valve config" > ${CONFIG}
    echo "REGISTRY=${REGISTRY}" >> ${CONFIG}
    echo "CHARTMUSEUM=${CHARTMUSEUM}" >> ${CONFIG}
}

_init() {
    _helm_init
    _draft_init

    # kubernetes-dashboard url
    _result "kubernetes-dashboard: http://kubernetes-dashboard.127.0.0.1.nip.io/"

    # namespace
    _namespace "development" true
}

_helm_init() {
    _command "helm init --upgrade"
    helm init --upgrade

    _command "helm repo update"
    helm repo update

    # tiller
    _waiting_pod "kube-system" "tiller"

    # _command "helm version"
    # helm version

    if [ ! -z ${DELETE} ]; then
        _helm_delete "nginx-ingress"
        _helm_delete "docker-registry"
        _helm_delete "kubernetes-dashboard"
        _helm_delete "metrics-server"
        _helm_delete "heapster"
    fi

    # namespace
    NAMESPACE="${NAMESPACE:-kube-system}"

    _helm_install "${NAMESPACE}" "nginx-ingress"
    _helm_install "${NAMESPACE}" "docker-registry"
    _helm_install "${NAMESPACE}" "kubernetes-dashboard"
    _helm_install "${NAMESPACE}" "metrics-server"
    _helm_install "${NAMESPACE}" "heapster"

    _waiting_pod "${NAMESPACE}" "docker-registry"
    _waiting_pod "${NAMESPACE}" "nginx-ingress"
}

_helm_repo() {
    CNT=$(helm repo list | grep chartmuseum | wc -l | xargs)

    if [ "x${CNT}" == "x0" ] || [ ! -z ${FORCE} ]; then
        DEFAULT="${CHARTMUSEUM:-chartmuseum.opsnow.com}"
        _read "CHARTMUSEUM [${DEFAULT}] : "
        CHARTMUSEUM="${ANSWER:-$DEFAULT}"

        if [ -z ${CHARTMUSEUM} ]; then
            _error
        fi

        _command "helm repo add chartmuseum https://${CHARTMUSEUM}"
        helm repo add chartmuseum https://${CHARTMUSEUM}

        _config_save
    fi

    _command "helm repo update"
    helm repo update
}

_helm_delete() {
    _NM=$1

    CNT=$(helm ls ${_NM} | wc -l | xargs)

    if [ "x${CNT}" != "x0" ]; then
        _command "helm delete ${_NM} --purge"
        helm delete ${_NM} --purge
    fi
}

_helm_install() {
    _NS=$1
    _NM=$2

    CNT=$(helm ls ${_NM} | wc -l | xargs)

    if [ "x${CNT}" == "x0" ] || [ ! -z ${FORCE} ]; then
        CHART=/tmp/${_NM}.yaml

        _get_yaml "charts/${_NM}" "${CHART}"

        CHART_VERSION=$(cat ${CHART} | grep chart-version | awk '{print $3}' | xargs)

        if [ -z ${CHART_VERSION} ] || [ "${CHART_VERSION}" == "latest" ]; then
            _command "helm upgrade --install ${_NM} stable/${_NM}"
            helm upgrade --install ${_NM} stable/${_NM} --namespace ${_NS} -f ${CHART}
        else
            _command "helm upgrade --install ${_NM} stable/${_NM} --version ${CHART_VERSION}"
            helm upgrade --install ${_NM} stable/${_NM} --namespace ${_NS} -f ${CHART} --version ${CHART_VERSION}
        fi
    fi
}

_draft_init() {
    _command "draft init"
    draft init

    # _command "draft version"
    # draft version

    draft config set disable-push-warning 1

    # curl -sL docker-registry.127.0.0.1.nip.io:30500/v2/_catalog | jq '.'
    REGISTRY="${REGISTRY:-docker-registry.127.0.0.1.nip.io:30500}"

    # registry
    if [ -z ${REGISTRY} ]; then
        _command "draft config unset registry"
        draft config unset registry
    else
        _command "draft config set registry ${REGISTRY}"
        draft config set registry ${REGISTRY}
    fi

    _config_save
}

_namespace() {
    NAMESPACE=$1
    DEFAULT=$2

    CHECK=

    _command "kubectl get ns ${NAMESPACE}"
    kubectl get ns ${NAMESPACE} > /dev/null 2>&1 || export CHECK=CREATE

    if [ "${CHECK}" == "CREATE" ]; then
        _result "${NAMESPACE}"

        _command "kubectl create ns ${NAMESPACE}"
        kubectl create ns ${NAMESPACE}
    fi

    if [ "${DEFAULT}" == "true" ]; then
        kubectl config set-context $(kubectl config current-context) --namespace=${NAMESPACE}
    fi
}

_guard() {
    _read "USERNAME : "
    USERNAME=${ANSWER}

    _read "PASSWORD : " s
    PASSWORD=${ANSWER}

    _result "dev: https://kubernetes-dashboard-kube-system.dev.opsnow.com/"

    _result "token : $(echo -n "${USERNAME}:${PASSWORD}" | base64)"
}

_gen() {
    _result "draft package version: ${THIS_VERSION}"

    DIST=/tmp/${THIS_NAME}-draft-${THIS_VERSION}
    LIST=/tmp/${THIS_NAME}-draft-ls

    if [ "${THIS_VERSION}" == "v0.0.0" ]; then
        if [ ! -d ${SHELL_DIR}/draft ]; then
            _error
        fi

        rm -rf ${DIST}
        mkdir -p ${DIST}

        # copy local package
        _command "cp -rf ${SHELL_DIR}/draft/* ${DIST}"
        cp -rf ${SHELL_DIR}/draft/* ${DIST}

        _result "local package used."
    else
        if [ ! -d ${DIST} ]; then
            echo
            mkdir -p ${DIST}

            # download
            pushd ${DIST}
            curl -sL https://github.com/${THIS_REPO}/${THIS_NAME}/releases/download/${THIS_VERSION}/draft.tar.gz | tar xz
            popd

            _result "draft package downloaded."
        fi
    fi

    # package
    if [ -z ${PACKAGE} ]; then
        ls ${DIST} | sort > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi
        if [ ! -d ${DIST}/${SELECTED} ]; then
            _error
        fi

        _result "${SELECTED}"

        PACKAGE="${SELECTED}"
    fi

    NAMESPACE="${NAMESPACE:-development}"

    SERVICE_GROUP=
    SERVICE_NAME=

    # default
    if [ -f Jenkinsfile ]; then
        if [ "${NAME}" == "" ]; then
            SERVICE_GROUP=$(cat Jenkinsfile | grep "def SERVICE_GROUP = " | cut -d'"' -f2)
            SERVICE_NAME=$(cat Jenkinsfile | grep "def SERVICE_NAME = " | cut -d'"' -f2)
            if [ "${SERVICE_GROUP}" != "" ] && [ "${SERVICE_NAME}" != "" ]; then
                NAME="${SERVICE_GROUP}-${SERVICE_NAME}"
            fi
        fi
        if [ "${REPOSITORY_URL}" == "" ]; then
            REPOSITORY_URL=$(cat Jenkinsfile | grep "def REPOSITORY_URL = " | cut -d'"' -f2)
        fi
        if [ "${REPOSITORY_SECRET}" == "" ]; then
            REPOSITORY_SECRET=$(cat Jenkinsfile | grep "def REPOSITORY_SECRET = " | cut -d'"' -f2)
        fi
        if [ "${SLACK_TOKEN_DEV}" == "" ]; then
            SLACK_TOKEN_DEV=$(cat Jenkinsfile | grep "def SLACK_TOKEN_DEV = " | cut -d'"' -f2)
        fi
        if [ "${SLACK_TOKEN_DQA}" == "" ]; then
            SLACK_TOKEN_DQA=$(cat Jenkinsfile | grep "def SLACK_TOKEN_DQA = " | cut -d'"' -f2)
        fi
    fi
    if [ "${NAME}" == "" ]; then
        NAME=$(echo $(basename $(pwd)) | sed 's/\./-/g')
        SERVICE_GROUP=$(echo $NAME | cut -d- -f1)
        SERVICE_NAME=$(echo $NAME | cut -d- -f2)
    fi
    if [ "${REPOSITORY_URL}" == "" ]; then
        if [ -d .git ]; then
            REPOSITORY_URL=$(git config --get remote.origin.url | head -1 | xargs)
        fi
    fi

    # clear
    if [ ! -z ${DELETE} ]; then
        rm -rf charts
    fi

    # copy
    if [ -f ${DIST}/${PACKAGE}/dockerignore ] && [ ! -f .dockerignore ]; then
        cp -rf ${DIST}/${PACKAGE}/dockerignore .dockerignore
    fi
    if [ -f ${DIST}/${PACKAGE}/draftignore ] && [ ! -f .draftignore ]; then
        cp -rf ${DIST}/${PACKAGE}/draftignore .draftignore
    fi
    if [ -f ${DIST}/${PACKAGE}/valvesecret ] && [ ! -f .valvesecret ]; then
        cp -rf ${DIST}/${PACKAGE}/valvesecret .valvesecret
    fi
    if [ -f ${DIST}/${PACKAGE}/Dockerfile ]; then
        cp -rf ${DIST}/${PACKAGE}/Dockerfile Dockerfile
    fi
    if [ -f ${DIST}/${PACKAGE}/Jenkinsfile ]; then
        cp -rf ${DIST}/${PACKAGE}/Jenkinsfile Jenkinsfile
    fi
    if [ -f ${DIST}/${PACKAGE}/draft.toml ]; then
        cp -rf ${DIST}/${PACKAGE}/draft.toml draft.toml
    fi

    if [ -f Jenkinsfile ]; then
        # Jenkinsfile SERVICE_GROUP
        _chart_replace "Jenkinsfile" "def SERVICE_GROUP" "${SERVICE_GROUP}" true
        SERVICE_GROUP="${REPLACE_VAL}"

        # Jenkinsfile SERVICE_NAME
        _chart_replace "Jenkinsfile" "def SERVICE_NAME" "${SERVICE_NAME}" true
        SERVICE_NAME="${REPLACE_VAL}"

        if [ "${SERVICE_GROUP}" != "" ] && [ "${SERVICE_NAME}" != "" ]; then
            NAME="${SERVICE_GROUP}-${SERVICE_NAME}"
        fi
    fi

    # cp charts/acme/ to charts/${NAME}/
    if [ -d ${DIST}/${PACKAGE}/charts ]; then
        mkdir -p charts/${NAME}
        cp -rf ${DIST}/${PACKAGE}/charts/acme/* charts/${NAME}/
    fi

    if [ -f draft.toml ] && [ ! -z ${NAME} ]; then
        # draft.toml NAME
        _replace "s|NAMESPACE|${NAMESPACE}|" draft.toml
        _replace "s|NAME|${NAME}-${NAMESPACE}|" draft.toml
    fi

    if [ -d charts ] && [ ! -z ${NAME} ]; then
        # chart name
        _replace "s|name: .*|name: ${NAME}|" charts/${NAME}/Chart.yaml

        # values namespace
        _replace "s|namespace: .*|namespace: ${NAMESPACE}|" charts/${NAME}/values.yaml

        # values repository
        if [ -z ${REGISTRY} ]; then
            _replace "s|repository: .*|repository: ${NAME}|" charts/${NAME}/values.yaml
        else
            _replace "s|repository: .*|repository: ${REGISTRY}/${NAME}|" charts/${NAME}/values.yaml
        fi

        # values host
        _replace "s|subdomain: .*|subdomain: ${NAME}|" charts/${NAME}/values.yaml
        _replace "s|- acme|- ${NAME}|" charts/${NAME}/values.yaml
    fi

    if [ -f Jenkinsfile ]; then
        if [ "${REPOSITORY_URL}" != "" ]; then
            _chart_replace "Jenkinsfile" "def REPOSITORY_URL" "${REPOSITORY_URL}" true
        fi
        if [ "${REPOSITORY_SECRET}" != "" ]; then
            _chart_replace "Jenkinsfile" "def REPOSITORY_SECRET" "${REPOSITORY_SECRET}"
        fi
        if [ "${SLACK_TOKEN_DEV}" != "" ]; then
            _chart_replace "Jenkinsfile" "def SLACK_TOKEN_DEV" "${SLACK_TOKEN_DEV}"
        fi
        if [ "${SLACK_TOKEN_DQA}" != "" ]; then
            _chart_replace "Jenkinsfile" "def SLACK_TOKEN_DQA" "${SLACK_TOKEN_DQA}"
        fi
    fi

    _config_save
}

_secret() {
    if [ ! -f .valvesecret ]; then
        return
    fi

    CNT=$(cat .valvesecret | wc -l | xargs)
    if [ "x${CNT}" == "x0" ]; then
        return
    fi

    # name
    NAME="${1:-secret}"

    # namespace
    NAMESPACE="${2:-development}"

    # secret
    SECRET="${NAME}-${NAMESPACE}"

    # delete
    if [ ! -z ${DELETE} ]; then
        _command "kubectl delete secret ${SECRET} -n ${NAMESPACE}"
        kubectl delete secret ${SECRET} -n ${NAMESPACE}
    fi

    if [ -z ${FORCE} ]; then
        # has secret
        CNT=$(kubectl get secret -n ${NAMESPACE} | grep ${NAME}-${NAMESPACE} | wc -l | xargs)
        if [ "x${CNT}" != "x0" ]; then
            return
        fi
    fi

    TMP=/tmp/${THIS_NAME}-secret.yaml

    TARGET=/tmp/${SECRET}-secret.yaml

    # secret
    cat <<EOF > ${TARGET}
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET}
type: Opaque
data:
EOF

    LIST=$(cat .valvesecret)
    for VAL in ${LIST}; do
        _read "secret ${VAL} : "

        if [ "${ANSWER}" != "" ]; then
            echo -n ${ANSWER} | base64 > ${TMP}

            CNT=$(cat ${TMP} | wc -l | xargs)
            if [ "x${CNT}" == "x1" ]; then
                echo "  ${VAL}: $(cat ${TMP})" >> ${TARGET}
            else
                echo "  ${VAL}: |-" >> ${TARGET}
                sed "s/^/    /" ${TMP} >> ${TARGET}
            fi
        fi
    done

    # apply secret
    _command "kubectl apply -f ${TARGET} -n ${NAMESPACE}"
    kubectl apply -f ${TARGET} -n ${NAMESPACE}
}

_up() {
    if [ ! -f draft.toml ]; then
        _error "Not found draft.toml"
    fi
    if [ ! -d charts ]; then
        _error "Not found charts"
    fi

    # _init

    # name
    NAME="$(ls charts | head -1 | tr '/' ' ' | xargs)"

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    # make secret
    _secret "${NAME}" "${NAMESPACE}"

    # helm check FAILED
    CNT=$(helm ls -a | grep ${NAME} | grep ${NAMESPACE} | grep -v "DEPLOYED" | wc -l | xargs)
    if [ "x${CNT}" != "x0" ]; then
        DELETE=true
    fi

    # helm delete
    if [ ! -z ${DELETE} ]; then
        _command "helm delete ${NAME}-${NAMESPACE} --purge"
        helm delete ${NAME}-${NAMESPACE} --purge
    fi

    # charts/${NAME}/values.yaml
    if [ -z ${REGISTRY} ]; then
        _replace "s|repository: .*|repository: ${NAME}|" charts/${NAME}/values.yaml
    else
        _replace "s|repository: .*|repository: ${REGISTRY}/${NAME}|" charts/${NAME}/values.yaml
    fi

    # draft up
    _command "draft up -e ${NAMESPACE}"
    draft up -e ${NAMESPACE}

    DRAFT_LOGS=$(mktemp /tmp/${THIS_NAME}-draft-logs.XXXXXX)

    # find draft error
    draft logs | grep error > ${DRAFT_LOGS}
    CNT=$(cat ${DRAFT_LOGS} | wc -l | xargs)
    if [ "x${CNT}" != "x0" ]; then
        _command "draft logs"
        draft logs
        _error "$(cat ${DRAFT_LOGS})"
    fi

    _command "helm ls ${NAME}-${NAMESPACE}"
    helm ls ${NAME}-${NAMESPACE}

    CNT=$(helm ls ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${CNT}" == "x0" ]; then
        _error
    fi

    _waiting_pod "${NAMESPACE}" "${NAME}-${NAMESPACE}"

    _command "kubectl get pod,svc,ing -n ${NAMESPACE}"
    kubectl get pod,svc,ing -n ${NAMESPACE}
}

_remote() {
    # _helm_init

    _helm_repo

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    LIST=/tmp/${THIS_NAME}-charts-ls

    # chart name
    if [ -z ${NAME} ]; then
        curl -sL ${CHARTMUSEUM}/api/charts | jq 'keys[]' -r > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        _result "${SELECTED}"

        NAME="${SELECTED}"
    fi

    # version
    if [ -z ${VERSION} ]; then
        curl -sL ${CHARTMUSEUM}/api/charts/${NAME} | jq '.[] | {version} | .version' -r | sort -r | head -9 > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        _result "${SELECTED}"

        VERSION="${SELECTED}"
    fi

    # delete
    if [ ! -z ${DELETE} ]; then
        _command "helm delete ${NAME}-${NAMESPACE} --purge"
        helm delete ${NAME}-${NAMESPACE} --purge

        sleep 2
    fi

    # has configmap
    CNT=$(kubectl get configmap -n ${NAMESPACE} | grep ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${CNT}" != "x0" ]; then
        CONFIGMAP=true
    else
        CONFIGMAP=false
    fi

    # has secret
    CNT=$(kubectl get secret -n ${NAMESPACE} | grep ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${CNT}" != "x0" ]; then
        SECRET=true
    else
        SECRET=false
    fi

    # helm install
    _command "helm install ${NAME}-${NAMESPACE} chartmuseum/${NAME} --version ${VERSION} --namespace ${NAMESPACE}"
    helm upgrade --install ${NAME}-${NAMESPACE} chartmuseum/${NAME} --version ${VERSION} --namespace ${NAMESPACE} --devel \
                    --set fullnameOverride=${NAME}-${NAMESPACE} \
                    --set ingress.subdomain=${NAME}-${NAMESPACE} \
                    --set configmap.enabled=${CONFIGMAP} \
                    --set secret.enabled=${SECRET} \
                    --set namespace=${NAMESPACE}

    _command "helm ls ${NAME}-${NAMESPACE}"
    helm ls ${NAME}-${NAMESPACE}

    CNT=$(helm ls ${NAME}-${NAMESPACE} | wc -l | xargs)
    if [ "x${CNT}" == "x0" ]; then
        _error
    fi

    _waiting_pod "${NAMESPACE}" "${NAME}-${NAMESPACE}"

    _command "kubectl get pod,svc,ing -n ${NAMESPACE}"
    kubectl get pod,svc,ing -n ${NAMESPACE}
}

_context() {
    LIST=/tmp/${THIS_NAME}-ctx-ls

    _command "kubectl config current-context"
    kubectl config current-context

    if [ -z ${NAME} ]; then
        echo "$(kubectl config view -o json | jq '.contexts[].name' -r)" > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"
    fi

    _command "kubectl config use-context ${NAME}"
    kubectl config use-context ${NAME}
}

_all() {
    # _helm_init

    _command "helm ls --all"
    helm ls --all

    _command "kubectl get all --all-namespaces"
    kubectl get all --all-namespaces
}

_list() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    LIST=/tmp/${THIS_NAME}-helm-ls

    _command "helm ls --all | grep ${NAMESPACE}"
    helm ls --all > ${LIST}
    cat ${LIST} | head -1
    cat ${LIST} | grep ${NAMESPACE}

    _command "kubectl get pod,svc,ing -n ${NAMESPACE}"
    kubectl get pod,svc,ing -n ${NAMESPACE}
}

_describe() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    if [ -z ${NAME} ]; then
        LIST=/tmp/${THIS_NAME}-pod-ls

        # get pod list
        _command "kubectl get pod -n ${NAMESPACE}"
        kubectl get pod -n ${NAMESPACE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"

        _result "${NAME}"
    fi

    _command "kubectl describe pod -n ${NAMESPACE} ${NAME}"
    kubectl describe pod -n ${NAMESPACE} ${NAME}
}

_hpa() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    if [ -z ${NAME} ]; then
        LIST=/tmp/${THIS_NAME}-hpa-ls

        # get pod list
        _command "kubectl get hpa -n ${NAMESPACE}"
        kubectl get hpa -n ${NAMESPACE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"

        _result "${NAME}"
    fi

    _command "kubectl describe hpa -n ${NAMESPACE} ${NAME}"
    kubectl describe hpa -n ${NAMESPACE} ${NAME}
}

_ssh() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    if [ -z ${NAME} ]; then
        LIST=/tmp/${THIS_NAME}-pod-ls

        # get pod list
        _command "kubectl get pod -n ${NAMESPACE}"
        kubectl get pod -n ${NAMESPACE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"

        _result "${NAME}"
    fi

    _command "kubectl exec -n ${NAMESPACE} -it ${NAME} -- /bin/bash"
    kubectl exec -n ${NAMESPACE} -it ${NAME} -- /bin/bash
}

_logs() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    if [ -z ${NAME} ]; then
        LIST=/tmp/${THIS_NAME}-pod-ls

        # get pod list
        _command "kubectl get pod -n ${NAMESPACE}"
        kubectl get pod -n ${NAMESPACE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"

        # get pod containers
        kubectl get pod ${NAME} -n ${NAMESPACE} -o json | jq '.spec.containers[].name' -r > ${LIST}

        _select_one true

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${NAME} ${SELECTED}"

        _result "${NAME}"
    fi

    _command "kubectl logs -n ${NAMESPACE} ${NAME} -f"
    kubectl logs -n ${NAMESPACE} ${NAME} -f
}

_exec() {
    # _helm_init

    # namespace
    NAMESPACE="${NAMESPACE:-development}"

    LIST=/tmp/${THIS_NAME}-pod-ls

    # get pod list
    _command "kubectl get pod -n ${NAMESPACE}"
    kubectl get pod -n ${NAMESPACE} | grep -v "NAME" | awk '{print $1}' > ${LIST}

    HAS_NAME=false
    while read VAL; do
        if [ "${VAL}" == "${NAME}" ]; then
            HAS_NAME=true
        fi
    done < ${LIST}

    if [ "${HAS_NAME}" == "false" ]; then
        EXTRA="${NAME} ${EXTRA}"
        NAME=
    fi

    if [ -z ${NAME} ]; then
        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        NAME="${SELECTED}"

        _result "${NAME}"
    fi

    _command "kubectl exec -n ${NAMESPACE} ${NAME} -- ${EXTRA}"
    kubectl exec -n ${NAMESPACE} ${NAME} -- ${EXTRA}
}

_remove() {
    # _helm_init

    if [ -z ${NAME} ]; then
        LIST=/tmp/${THIS_NAME}-helm-ls

        # get helm list
        _command "helm ls --all"
        helm ls --all | grep -v "NAME" | awk '{print $1}' > ${LIST}

        _select_one

        if [ -z ${SELECTED} ]; then
            _error
        fi

        _result "${SELECTED}"

        NAME="${SELECTED}"
    fi

    _command "helm delete ${NAME} --purge"
    helm delete ${NAME} --purge
}

_clean() {
    # rm -rf ${CONFIG}
    rm -rf /tmp/${THIS_NAME}-*

    LIST=/tmp/${THIS_NAME}-docker-ls

    # delete
    if [ ! -z ${DELETE} ]; then
        docker ps -a -q > ${LIST}
        CNT=$(cat ${LIST} | wc -l | xargs)
        if [ "x${CNT}" != "x0" ]; then
            _command 'docker rm $(docker ps -a -q)'
            docker rm $(cat ${LIST})
        fi

        docker images -q > ${LIST}
        CNT=$(cat ${LIST} | wc -l | xargs)
        if [ "x${CNT}" != "x0" ]; then
            _command 'docker rmi -f $(docker images -q)'
            docker rmi -f $(cat ${LIST})
        fi
    fi
}

_chart_replace() {
    REPLACE_FILE=$1
    REPLACE_KEY=$2
    DEFAULT_VAL=$3
    REQUIRED=$4

    if [ "${DEFAULT_VAL}" == "" ]; then
        Q="${REPLACE_KEY} : "
    else
        Q="${REPLACE_KEY} [${DEFAULT_VAL}] : "
    fi

    _read "${Q}"

    REPLACE_VAL=${ANSWER:-${DEFAULT_VAL}}

    if [ "${REQUIRED}" == "true" ] && [ "${REPLACE_VAL}" == "" ]; then
        _error "Required: ${REPLACE_KEY}"
    fi

    if [ "${REPLACE_TYPE}" == "yaml" ]; then
        _command "sed -i -e s|${REPLACE_KEY}: .*|${REPLACE_KEY}: ${REPLACE_VAL}| ${REPLACE_FILE}"
        _replace "s|${REPLACE_KEY}: .*|${REPLACE_KEY}: ${REPLACE_VAL}|" ${REPLACE_FILE}
    else
        _command "sed -i -e s|${REPLACE_KEY} = .*|${REPLACE_KEY} = ${REPLACE_VAL}| ${REPLACE_FILE}"
        _replace "s|${REPLACE_KEY} = .*|${REPLACE_KEY} = \"${REPLACE_VAL}\"|" ${REPLACE_FILE}
    fi
}

_get_yaml() {
    _NAME=$1
    _DIST=$2

    if [ "${THIS_VERSION}" == "v0.0.0" ]; then
        cp -rf ${SHELL_DIR}/${_NAME}.yaml ${_DIST}
    else
        curl -sL https://raw.githubusercontent.com/${THIS_REPO}/${THIS_NAME}/master/${_NAME}.yaml > ${_DIST}
    fi
}

_args $*

_run

_success
