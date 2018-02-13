#!/bin/bash
set -eou pipefail

# ref: https://stackoverflow.com/a/7069755/244009
# ref: https://jonalmeida.com/posts/2013/05/26/different-ways-to-implement-flags-in-bash/
# ref: http://tldp.org/LDP/abs/html/comparison-ops.html

export KUBEDB_NAMESPACE=kube-system
export KUBEDB_SERVICE_ACCOUNT=default
export KUBEDB_ENABLE_RBAC=false

show_help() {
    echo "webhook.sh - install kubedb operator"
    echo " "
    echo "webhook.sh [options]"
    echo " "
    echo "options:"
    echo "-h, --help                         show brief help"
    echo "-n, --namespace=NAMESPACE          specify namespace (default: kube-system)"
    echo "    --rbac                         create RBAC roles and bindings"
}

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n)
            shift
            if test $# -gt 0; then
                export KUBEDB_NAMESPACE=$1
            else
                echo "no namespace specified"
                exit 1
            fi
            shift
            ;;
        --namespace*)
            export KUBEDB_NAMESPACE=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --rbac)
            export KUBEDB_SERVICE_ACCOUNT=kubedb-webhook
            export KUBEDB_ENABLE_RBAC=true
            shift
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

env | sort | grep KUBEDB*
echo ""

echo "checking kubeconfig context"
kubectl config current-context || { echo "Set a context (kubectl use-context <context>) out of the following:"; echo; kubectl config get-contexts; exit 1; }
echo ""

# ref: https://stackoverflow.com/a/27776822/244009
case "$(uname -s)" in
    Darwin)
        curl -fsSL -o onessl https://github.com/appscode/onessl/releases/download/0.1.0/onessl-darwin-amd64
        chmod +x onessl
        export ONESSL=./onessl
        ;;

    Linux)
        curl -fsSL -o onessl https://github.com/appscode/onessl/releases/download/0.1.0/onessl-linux-amd64
        chmod +x onessl
        export ONESSL=./onessl
        ;;

    CYGWIN*|MINGW32*|MSYS*)
        curl -fsSL -o onessl.exe https://github.com/appscode/onessl/releases/download/0.1.0/onessl-windows-amd64.exe
        chmod +x onessl.exe
        export ONESSL=./onessl.exe
        ;;
    *)
        echo 'other OS'
        ;;
esac

# create necessary TLS certificates:
# - a local CA key and cert
# - a webhook server key and cert signed by the local CA
$ONESSL create ca-cert
$ONESSL create server-cert server --domains=kubedb-webhook.$KUBEDB_NAMESPACE.svc
export SERVICE_SERVING_CERT_CA=$(cat ca.crt | $ONESSL base64)
export TLS_SERVING_CERT=$(cat server.crt | $ONESSL base64)
export TLS_SERVING_KEY=$(cat server.key | $ONESSL base64)
export KUBE_CA=$($ONESSL get kube-ca | $ONESSL base64)
rm -rf $ONESSL ca.crt ca.key server.crt server.key

curl -fsSL https://raw.githubusercontent.com/kubedb/apiserver/master/hack/deploy/operator.yaml | envsubst | kubectl apply -f -

if [ "$KUBEDB_ENABLE_RBAC" = true ]; then
    kubectl create serviceaccount $KUBEDB_SERVICE_ACCOUNT --namespace $KUBEDB_NAMESPACE
    kubectl label serviceaccount $KUBEDB_SERVICE_ACCOUNT app=kubedb --namespace $KUBEDB_NAMESPACE
    curl -fsSL https://raw.githubusercontent.com/kubedb/apiserver/master/hack/deploy/rbac-list.yaml | envsubst | kubectl auth reconcile -f -
fi
