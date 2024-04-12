PRODUCT_NAME="sourcegraph"

unset USE_KIND
# Check if kubectl is available in the system
if kubectl 2>/dev/null >/dev/null; then
  # Check if kubectl can communicate with a Kubernetes cluster
  if kubectl get nodes 2>/dev/null >/dev/null; then
    echo "Kubernetes cluster is available. Using existing cluster."
    export USE_KIND=0
  else
    echo "Kubernetes cluster is not available. Creating a Kind cluster..."
    export USE_KIND=X
  fi
else
  echo "kubectl is not installed. Please install kubectl to interact with Kubernetes."
  export USE_KIND=X
fi

if [ "X${USE_KIND}" == "XX" ]; then
    # Make sure cluster exists if using Kind
    kind  get clusters 2>&1 | grep "kind-${PRODUCT_NAME}"
    if [ $? -gt 0 ]
    then
        envsubst < kind-config.yaml.template > kind-config.yaml
        kind create cluster --config kind-config.yaml --name "kind-${PRODUCT_NAME}"
    fi

    # Make sure create cluster succeeded
    kind  get clusters 2>&1 | grep "kind-${PRODUCT_NAME}"
    if [ $? -gt 0 ]
    then
        echo "Creation of cluster failed. Aborting."
        exit 666
    fi
fi

echo add metrics
kubectl apply -f https://dev.ellisbs.co.uk/files/components.yaml

echo install local storage
kubectl apply -f https://dev.ellisbs.co.uk/files/local-storage-class.yaml

echo "create ${PRODUCT_NAME} namespace, if it does not exist"
kubectl get ns "${PRODUCT_NAME}" 2> /dev/null
if [ $? -eq 1 ]
then
    kubectl create namespace "${PRODUCT_NAME}"
fi

# sort out persistent volume
if [ "X${USE_KIND}" == "XX" ]; then
  export NODE_NAME=$(kubectl get nodes |grep control-plane|cut -d\  -f1|head -1)
  envsubst < ${PRODUCT_NAME}.pv.kind.template > ${PRODUCT_NAME}.pv.yml
else
  export NODE_NAME=$(kubectl get nodes | grep -v ^NAME|grep -v control-plane|cut -d\  -f1|head -1)
  envsubst < ${PRODUCT_NAME}.pv.linux.template > ${PRODUCT_NAME}.pv.yml
  echo mkdir -p ${PWD}/${PRODUCT_NAME}-config|ssh -o StrictHostKeyChecking=no ${NODE_NAME}
fi
kubectl apply -f ${PRODUCT_NAME}.pv.yml

echo create deployment
kubectl apply -f ${PRODUCT_NAME}.deployment.yaml

echo create service
kubectl apply -f ${PRODUCT_NAME}.service.yaml

echo wait for indexserver deployment to be running
until kubectl get all -n ${PRODUCT_NAME}|grep ^pod/zoekt-indexserver|grep 1/1; do
  sleep 5
done

echo wait for webserver deployment to be running
until kubectl get all -n ${PRODUCT_NAME}|grep ^pod/zoekt-webserver|grep 1/1; do
  sleep 5
done

#echo create port-forward to access ${PRODUCT_NAME} on port 8080
#if ! nc -z -w1 0.0.0.0 8080; then
#  # Port 8080 is not already forwarded, so execute the port-forwarding command
#  kubectl port-forward service/caddy-service -n ${PRODUCT_NAME} --address 0.0.0.0 8080:80 &
#else
#  echo "Port 8080 is already forwarded."
#fi
