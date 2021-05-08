#!/bin/bash
set -eu -o pipefail

unset ROOT_DIR
unset OBJ_DIR
ROOT_DIR=$1
[[ -z "$ROOT_DIR" ]] && { echo "you need to specify the directory to scan as the only argument"; exit 1; }
[[ -z "$APP" ]] && { echo "APP environment variable must be set"; exit 1; }
[[ -z "$KUBE_NAMESPACE" ]] && { echo "KUBE_NAMESPACE environment variable must be set"; exit 1; }
[[ -z "$KUBE_CONTEXT" ]] && { echo "KUBE_CONTEXT environment variable must be set"; exit 1; }

# map_from_file will use kubectl create --from-file to generate a configmap. where each
# file in the directory will become a key in the map with its file contents as the
# map data.
map_from_file() {
    local map_path=$1
    local map_name=$2

    echo "Processing $map_name from $map_path"
    kubectl delete configmap "$map_name" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT" > /dev/null 2>&1 || true;
    kubectl create configmap "$map_name" --from-file="$map_path" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
    # shellcheck disable=SC2086
    kubectl label configmap "$map_name" ${LABELS} --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
}

# map_literal uses kubectl create with the --from-literal to create a configmap from a file
# the File is expected to contain lines of "k=v" entries. These will be converted to
# map keys and data.
map_literal() {
    local map_path=$1
    local map_name=$2

    # construct the args array for each line in the file
    literal_args=()
    # use awk to filter comment lines with or without space
    while read -r kvpair ; do
      literal_args+=("--from-literal=$kvpair")
    done <<<"$(awk '!/^ *#/ && NF' "$map_path")"

    kubectl delete configmap "$map_name" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT" > /dev/null 2>&1 || true;
    kubectl create configmap "$map_name" "${literal_args[@]}" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
    # shellcheck disable=SC2086
    kubectl label configmap "$map_name" ${LABELS} --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
}


# secret_from_file will use kubectl create secret generic --from-file to generate a secret.
# Where each file in the directory will become a key
# and the file contents the secret data.
secret_from_file() {
    local secret_path=$1
    local secret_name=$2

    kubectl delete secret "$secret_name" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT" > /dev/null 2>&1 || true;
    kubectl create secret generic "$secret_name" --from-file="$secret_path" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
    # shellcheck disable=SC2086
    kubectl label  secret "$secret_name" ${LABELS} --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
}


# secret_literal uses kubectl create with the --from-literal to create secrets from a file.
# The File is expected to contain lines of "k=v" entries.  These will be converted to secret
# keys and data.
secret_literal() {
    local secret_path=$1
    local secret_name=$2

    # construct the args array for each line in the file
    literal_args=()
    for i in $(<"$secret_path") ; do
        literal_args+=("--from-literal=$i")
    done

    kubectl delete secret "$secret_name" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT" > /dev/null 2>&1 || true
    kubectl create secret generic "$secret_name" "${literal_args[@]}" --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
    # shellcheck disable=SC2086
    kubectl label secret "$secret_name" ${LABELS} --namespace="$KUBE_NAMESPACE" --context "$KUBE_CONTEXT"
}

update() {
    local path=$1
    local obj_type=$2
    local name

    name="$APP-$(basename "$path")"

    # if this is a file or a directory treat it differently. We want to use
    # kube --from file for dirs and kube --literal for files.
    if [[ -f "$path" ]] ;  then
        eval "${obj_type}_literal \"$path\" \"$name\""
    else
        eval "${obj_type}_from_file \"$path\" \"$name\""
    fi
}

find_obj_dir() {
    # We need to detect the right directory to use, but want to allow the use of
    # namespaces named "production" in non-production contexts.
    # Use 'non-prod' by default.
    # If the namespace is production AND the context is not sandbox, set the
    # dir to production.
    # If the namespace is not production then we use a dir named the same as the
    # namespace if it exists.
    # If a directory exists named using the full context, use that as the base.
    # Objects can be customized for each Kube context (e.g. different keys for different
    # geographic regions)
    SUB_DIR="$ROOT_DIR"
    if [[ -d "$ROOT_DIR/$KUBE_CONTEXT" ]] ; then
        SUB_DIR="$ROOT_DIR/$KUBE_CONTEXT"
    fi

    OBJ_DIR="$SUB_DIR/non-prod"

    if [[ "$KUBE_NAMESPACE" == "production" && "$KUBE_CONTEXT" != *_sandbox-* ]] ; then
        OBJ_DIR="$SUB_DIR/production"
    fi

    if [[ -d $SUB_DIR/$KUBE_NAMESPACE && "$KUBE_NAMESPACE" != "production" ]] ; then
        OBJ_DIR="$SUB_DIR/$KUBE_NAMESPACE"
    fi
}

main() {
    local type
    local func_prefix

    find_obj_dir "$ROOT_DIR"
    if [[ -z "$OBJ_DIR" ]] ; then
        echo "Could not locate a suitable object directory for $KUBE_NAMESPACE"
        exit 1
    fi
    if [[ -z "${LABELS:-}" ]] ; then
        echo "Variable LABELS is undefined"
        exit 1
    fi
    LABELS=${LABELS//,/ }

    # divine if this is something we can manage and what it should dispatch too
    type=$(basename "$ROOT_DIR")
    case $type in
        # because these will be eval'd lets not passthrough user input
        configmaps) func_prefix="map"  ;;
        secrets) func_prefix="secret" ;;
        *)
            echo "Don't know how to process '$i'"
            exit 1
            ;;
    esac


    echo "Using objects from directory '$OBJ_DIR'"
    for object in "$OBJ_DIR"/* ; do
        echo "Processing $object"
        update "$object" "$func_prefix"
    done
}

main "$@"
