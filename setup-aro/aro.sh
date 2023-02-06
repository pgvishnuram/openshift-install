#!/usr/bin/env bash

## USAGE
function usage() {
    echo
    echo "Usage:"
    echo " $0 [command] [options]"
    echo " $0 --help"
    echo
    echo "Example:"
    echo " $0 install_cluster"
    echo
    echo "COMMANDS:"
    echo "   deploy_postgres          Deploy azureflexible postgres cluster        "
    echo "   install_aro              Install AzureRedhat Openshift Cluster        "
    echo "   install_platform         Install Astronomer Platform                  "
    echo "   install_addons           Install Addons                               "
    echo "   obtain_aro_info          Obtain information about the ARO4 Cluster    "
    echo "   delete_postgres          Delete azureflexible postgres cluster        "
    echo "   delete_aro               Delete ARO cluster                           "
    echo "   delete_all               Cleanup all azure resources                  "
    echo "   deploy_all               Deploy all infrastructure                    "
    echo
}

RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-sreteam}"

LOCATION="${LOCATION:-centralus}"

export ARO_CLUSTER_NAME="${ARO_CLUSTER_NAME:-srearo}"

export VNET_NAME=$ARO_CLUSTER_NAME-vnet

export VNET_CIDR="10.0.0.0/8"

export MASTER_SUBNET="10.0.0.0/23"

export WORKER_SUBNET="10.0.2.0/23"

export DB_SUBNET="10.0.4.0/23"

export MASTER_SUBNET_NAME=$ARO_CLUSTER_NAME-master

export WORKER_SUBNET_NAME=$ARO_CLUSTER_NAME-worker

export MASTER_VM_SIZE="${ARO_MASTER_VM_SIZE:-Standard_D8s_v3}"

export WORKER_VM_SIZE="${ARO_WORKER_VM_SIZE:-Standard_D8s_v3}"

export DB_SUBNET_NAME=$ARO_CLUSTER_NAME-db

export WORKER_NODE_SIZE="${WORKER_NODE_SIZE:-6}"

export WORKER_AUTOSCALE_COUNT="${WORKER_AUTOSCALE_COUNT:-12}"

export POSTGRES_SERVER_NAME=$ARO_CLUSTER_NAME-dbserver

export KEDA_CHART_VERSION="${KEDA_CHART_VERSION:-2.2}"

export KEDA_NAMESPACE="${KEDA_NAMESPACE:-keda}"

DB_USERNAME="${DB_USERNAME:-astro}"

DB_PASSWORD="${DB_PASSWORD:-astro}"

# Defaults for Astronomer Platform ENV Vars

export BASE_DOMAIN="${BASE_DOMAIN:-vishnu-aks-028.astro-qa.link}"
export PLATFORM_VERSION="${PLATFORM_VERSION:-0.29.2}"
export PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-astronomer}"
export PLATFORM_RELEASE_NAME="${PLATFORM_RELEASE_NAME:-astronomer}"
export HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-astro-qa.link.}"
export HELM_TIMEOUT="${HELM_TIMEOUT:-600s}"

function check_resource_group_existence() {
    if [ "$(az group exists --name "$RESOURCE_GROUP_NAME")" == true ]; then
           echo "resource group $RESOURCE_GROUP_NAME already exists. reusing pre-created one"
        else
           echo 'creating new resource group'
           az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
    fi
}

function install_aro() {
    echo "Register Microsoft.RedHatOpenShift resource provider"

    az provider register -n Microsoft.RedHatOpenShift --wait

    echo "Register Microsoft.Compute resource provider"

    az provider register -n Microsoft.Compute --wait

    echo "Register Microsoft.Storage resource provider"

    az provider register -n Microsoft.Storage --wait

    if [ "$(az group exists --name "$RESOURCE_GROUP_NAME")" == true ]; then
           echo "resource group $RESOURCE_GROUP_NAME already exists. reusing pre-created one"
        else
           echo 'creating new resource group'
           az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
    fi

    if [[ $(az network vnet list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$VNET_NAME'] | length(@)")  -gt 0 ]]; then
       echo "vnet $VNET_NAME already exists. reusing pre-created one"
       else
       echo "creating $VNET_NAME vnet "
       az network vnet create --resource-group "$RESOURCE_GROUP_NAME" --name "$VNET_NAME" --address-prefixes "$VNET_CIDR"
       echo "vnet $VNET_NAME creation completed"
    fi


    if [[ $(az network vnet subnet list --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --query "[?name=='$MASTER_SUBNET_NAME'] | length(@)")  -gt 0 ]]; then
       echo "subnet $MASTER_SUBNET_NAME already exists. reusing pre-created one"
       else
       echo "creating master  subnet "
       az network vnet subnet create --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --name "$MASTER_SUBNET_NAME" --address-prefixes $MASTER_SUBNET --service-endpoints Microsoft.ContainerRegistry
       echo "subnet $MASTER_SUBNET_NAME creation completed"
    fi

    if [[ $(az network vnet subnet list --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --query "[?name=='$WORKER_SUBNET_NAME'] | length(@)")  -gt 0 ]]; then
       echo "subnet $WORKER_SUBNET_NAME already exists. reusing pre-created one"
       else
       echo "creating worker  subnet "
       az network vnet subnet create --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --name "$WORKER_SUBNET_NAME" --address-prefixes "$WORKER_SUBNET" --service-endpoints Microsoft.ContainerRegistry
       echo "subnet $WORKER_SUBNET_NAME creation completed"
    fi


    if [[ $(az network vnet subnet list --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --query "[?name=='$DB_SUBNET_NAME'] | length(@)")  -gt 0 ]]; then
       echo "subnet $DB_SUBNET_NAME already exists. reusing pre-created one"
       else
       echo "creating db subnet "
       az network vnet subnet create --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"  --name "$DB_SUBNET_NAME" --address-prefixes "$DB_SUBNET"
       echo "subnet $DB_SUBNET_NAME creation completed"
    fi


    echo "Disable subnet private endpoint policies on the master subnet"

    az network vnet subnet update --name "$MASTER_SUBNET_NAME"  --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --disable-private-link-service-network-policies true >/dev/null

    if [[ $(az aro list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$ARO_CLUSTER_NAME'] | length(@) ")  -gt 0 ]]; then
        echo "cluster $ARO_CLUSTER_NAME already exists"
       else
        echo "creating $ARO_CLUSTER_NAME aro cluster"
        az aro create --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" --vnet "$VNET_NAME" --master-subnet "$MASTER_SUBNET_NAME"  --worker-subnet "$WORKER_SUBNET_NAME" --master-vm-size "$MASTER_VM_SIZE" --worker-vm-size  "$WORKER_VM_SIZE" --worker-count "$WORKER_NODE_SIZE" --debug

    fi
}


function deploy_postgres() {

    if [[ $(az network vnet list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$VNET_NAME'] | length(@)")  -gt 0 ]]; then
      echo "vnet $VNET_NAME already exists. reusing pre-created one"
      else
      echo "creating $VNET_NAME vnet"
      az network vnet create --resource-group "$RESOURCE_GROUP_NAME" --name "$VNET_NAME"  --address-prefixes $VNET_CIDR
      echo "vnet $VNET_NAME creation completed"
    fi

    if [[ $(az network vnet subnet list --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"  --query "[?name=='$DB_SUBNET_NAME'] | length(@)")  -gt 0 ]]; then
      echo "subnet $DB_SUBNET_NAME already exists. reusing pre-created one"
      else
      echo "creating Database subnet $DB_SUBNET_NAME"
      az network vnet subnet create --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --address-prefixes "$DB_SUBNET"
      echo "subnet $DB_SUBNET_NAME creation completed"
    fi

    SUBNET_ID=$(az network vnet subnet show  --resource-group  "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"  --name "$DB_SUBNET_NAME" | jq -r '.id')

    if [[ $(az postgres flexible-server list --query "[?name=='$POSTGRES_SERVER_NAME'] | length(@) ")  -gt 0 ]]; then
       echo "PSQL $POSTGRES_SERVER_NAME already exists"
    else
      echo "Creating PSQL $POSTGRES_SERVER_NAME  in progress ......."
      az postgres flexible-server create --name "$POSTGRES_SERVER_NAME" --subnet "$SUBNET_ID" -g "$RESOURCE_GROUP_NAME" --admin-user "$DB_USERNAME" --admin-password "$DB_PASSWORD" --location "$LOCATION" -y
      az postgres flexible-server parameter set --resource-group "$RESOURCE_GROUP_NAME" --server-name "$POSTGRES_SERVER_NAME"  --name azure.extensions  --value pg_trgm
    fi

}

function obtain_aro_info() {
    echo "CLUSTER_CONSOLE_URL: $(az aro show --name "$ARO_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "consoleProfile.url" -o tsv)"

    echo "CLUSTER_ADMIN_USERNAME: $(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME"| jq -r '.kubeadminUsername')"

    echo "CLUSTER_ADMIN_PASSWORD: $(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" | jq -r '.kubeadminPassword')"
}



function delete_aro() {
    set -x
    az aro delete --resource-group "${RESOURCE_GROUP_NAME}" --name "${ARO_CLUSTER_NAME}" -y
}


function delete_all() {
    az postgres flexible-server delete --resource-group "$RESOURCE_GROUP_NAME" --name "$POSTGRES_SERVER_NAME" --yes
    az aro delete --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" --yes
    az network vnet subnet delete --name "$DB_SUBNET_NAME" --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"
    az network vnet subnet delete --name "$WORKER_SUBNET_NAME" --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"
    az network vnet subnet delete --name "$MASTER_SUBNET_NAME" --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"
    az network vnet delete --resource-group "$RESOURCE_GROUP_NAME" --name "$VNET_NAME"
}



function delete_postgres(){
    az postgres flexible-server delete --resource-group "$RESOURCE_GROUP_NAME" --name "$POSTGRES_SERVER_NAME" --yes
}


function install_platform(){
    if [[ ! -d live/$BASE_DOMAIN ]]; then
       echo "Generating SSL CERTIFICATE for $BASE_DOMAIN"
       yes | certbot certonly  --dns-route53 --dns-route53-propagation-seconds 30 -d "$BASE_DOMAIN" -d "*.$BASE_DOMAIN" --work-dir . --logs-dir . --config-dir .  -m infrastructure@astronomer.io --agree-tos
    else
      echo "Certificate Path for $BASE_DOMAIN  already exists"
      echo "Validating SSL CERTIFICATE for $BASE_DOMAIN "
      if openssl x509 -checkend 86400 -noout -in live/"$BASE_DOMAIN"/fullchain.pem ;
        then
            echo "$BASE_DOMAIN Certificate is still valid"
        else
            yes | certbot certonly  --dns-route53 --dns-route53-propagation-seconds 30 -d "$BASE_DOMAIN" -d "*.$BASE_DOMAIN" --work-dir . --logs-dir . --config-dir .  -m infrastructure@astronomer.io --agree-tos
        fi
    fi


    echo "Authenticating with ARO CLUSTER $ARO_CLUSTER_NAME"

    CLUSTER_API_URL=$(az aro show --name "$ARO_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "apiserverProfile.url" -o tsv)
    CLUSTER_ADMIN_USERNAME=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME"| jq -r '.kubeadminUsername')
    CLUSTER_ADMIN_PASSWORD=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" | jq -r '.kubeadminPassword')
    AZURE_FLEXI_POSTGRES=$(az postgres flexible-server list --query "[?name=='$POSTGRES_SERVER_NAME']" | jq -r '.[].fullyQualifiedDomainName')

    yes | oc login "$CLUSTER_API_URL" -u "$CLUSTER_ADMIN_USERNAME" -p "$CLUSTER_ADMIN_PASSWORD" --insecure-skip-tls-verify >/dev/null
    if [[ $? != 0 ]]; then
      echo "Login failed for Cluster $ARO_CLUSTER_NAME  exiting ..."
      exit 0
    fi

    echo "Creating Project $PLATFORM_NAMESPACE in $ARO_CLUSTER_NAME cluster"
    oc project "$PLATFORM_NAMESPACE" || oc new-project "$PLATFORM_NAMESPACE"

    echo "Applying AUTOSCALER Config for $ARO_CLUSTER_NAME"
    [ -d  platform-config/autoscaler ] || mkdir platform-config/autoscaler
    WORKER_MACHINESET_NAMES=$(oc get MachineSet  --no-headers  -n openshift-machine-api | awk '{print $1}')
    envsubst < platform-config/cluster-autoscaler.tpl > platform-config/autoscaler/cluster-autoscaler.yaml
    for WORKER_NAMES in $WORKER_MACHINESET_NAMES; do
      export WORKER_NAMES=$WORKER_NAMES
      envsubst < platform-config/machineautoscaler.tpl > platform-config/autoscaler/"$WORKER_NAMES".yaml
    done
    oc apply -f platform-config/autoscaler/

    echo "Creating kubernetes TLS Secret for $BASE_DOMAIN in $PLATFORM_NAMESPACE namespace."

    kubectl -n "$PLATFORM_NAMESPACE" get secret astronomer-tls ||  kubectl  -n "$PLATFORM_NAMESPACE" create secret tls astronomer-tls --cert live/"$BASE_DOMAIN"/fullchain.pem --key live/"$BASE_DOMAIN"/privkey.pem

    echo "Creating Bootstrap Secret  for Platform Installation in $PLATFORM_NAMESPACE namespace."
    kubectl -n "$PLATFORM_NAMESPACE" get secret astronomer-bootstrap || kubectl -n "$PLATFORM_NAMESPACE" create secret generic astronomer-bootstrap --from-literal connection="postgres://astro:astro@$AZURE_FLEXI_POSTGRES:5432"

    helm repo add astronomer-internal https://internal-helm.astronomer.io/
    helm repo update >/dev/null

    echo "Installing  Astronomer Software with version $PLATFORM_VERSION"

    envsubst < platform-config/config.tpl > platform-config/config.yaml
    helm -n "$PLATFORM_NAMESPACE"  upgrade --install "$PLATFORM_RELEASE_NAME" astronomer-internal/astronomer --version "$PLATFORM_VERSION"  -f platform-config/config.yaml --timeout $HELM_TIMEOUT --debug


    oc adm policy add-scc-to-user privileged system:serviceaccount:"$PLATFORM_NAMESPACE":"$PLATFORM_RELEASE_NAME-elasticsearch"

    oc adm policy add-scc-to-user privileged -z "$PLATFORM_RELEASE_NAME-fluentd"

    oc patch ds "$PLATFORM_RELEASE_NAME-fluentd" -p "spec:
      template:
        spec:
          containers:
          - name: fluentd
            securityContext:
              privileged: true"

    # Get LB IP
    export LB_IP=$(kubectl get svc  "$PLATFORM_RELEASE_NAME-nginx" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # Updates route53 Records
    envsubst < platform-config/route53record.tpl > platform-config/route53record.json
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name  --dns-name "$HOSTED_ZONE_NAME"  | jq -r '.HostedZones[0].Id' | cut -d'/' -f3)
    aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID"  --change-batch file://platform-config/route53record.json


}


function authenticate_aro() {

    echo "Authenticating with ARO CLUSTER $ARO_CLUSTER_NAME"

    CLUSTER_API_URL=$(az aro show --name "$ARO_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "apiserverProfile.url" -o tsv)
    CLUSTER_ADMIN_USERNAME=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME"| jq -r '.kubeadminUsername')
    CLUSTER_ADMIN_PASSWORD=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" | jq -r '.kubeadminPassword')
    AZURE_FLEXI_POSTGRES=$(az postgres flexible-server list --query "[?name=='$POSTGRES_SERVER_NAME']" | jq -r '.[].fullyQualifiedDomainName')

    yes | oc login "$CLUSTER_API_URL" -u "$CLUSTER_ADMIN_USERNAME" -p "$CLUSTER_ADMIN_PASSWORD" --insecure-skip-tls-verify >/dev/null
    if [[ $? != 0 ]]; then
      echo "Login failed for Cluster $ARO_CLUSTER_NAME  exiting ..."
      exit 0
    fi

}

function install_addons(){
    export AZURE_STORAGE_ACCOUNT_NAME="${ARO_CLUSTER_NAME}azurefs"
    if [[ $(az storage account list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$AZURE_STORAGE_ACCOUNT_NAME'] | length(@)")  -gt 0 ]]; then
      echo "Azure Storage Account $AZURE_STORAGE_ACCOUNT_NAME already exists. reusing pre-created one"
      else
      echo "creating $AZURE_STORAGE_ACCOUNT_NAME fileshare"
      az storage account create \
	    --name "$AZURE_STORAGE_ACCOUNT_NAME" \
	    --resource-group "$RESOURCE_GROUP_NAME" \
	    --kind StorageV2 \
	    --sku Standard_LRS
      echo "Azure storage account with name $AZURE_STORAGE_ACCOUNT_NAME creation completed"
    fi
    export ARO_SERVICE_PRINCIPAL_ID=$(az aro show -g "$RESOURCE_GROUP_NAME" -n "$ARO_CLUSTER_NAME" --query servicePrincipalProfile.clientId -o tsv)
    export GET_SUBSCRIPTION_ID=$(az group show  -g "$RESOURCE_GROUP_NAME"  | jq -r '.id' | awk -F'/' '{print $3}')
    az role assignment create --role Contributor --scope /subscriptions/"${GET_SUBSCRIPTION_ID}"/resourceGroups/"${RESOURCE_GROUP_NAME}" \
       --assignee "$ARO_SERVICE_PRINCIPAL_ID"


    cat << EOF >> "${ARO_CLUSTER_NAME}afs-file.yaml"
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: azure-file
  namespace: kube-system
provisioner: kubernetes.io/azure-file
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
  - noperm
parameters:
  location: $LOCATION
  secretNamespace: kube-system
  skuName: Standard_LRS
  storageAccount: ${AZURE_STORAGE_ACCOUNT_NAME}
  resourceGroup: ${RESOURCE_GROUP_NAME}
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF


    authenticate_aro
    oc get clusterrole azure-secret-reader || oc create clusterrole azure-secret-reader \
	   --verb=create,get \
	   --resource=secrets
    oc apply -f "${ARO_CLUSTER_NAME}"afs-file.yaml
    oc project monitoring || oc new-project monitoring
    kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring --overwrite=true
    oc project istio || oc new-project namespace istio
    kubectl label namespace istio app=istio --overwrite=true

    echo "Deploying KEDA with version ${KEDA_CHART_VERSION} ..."
    echo "running helm repo add kedacore https://kedacore.github.io/charts"
    helm repo add kedacore https://kedacore.github.io/charts
    echo "running helm repo update"
    helm repo update  >/dev/null
    oc project keda || oc new-project keda
    helm upgrade --install keda kedacore/keda --version ${KEDA_CHART_VERSION}  --namespace ${KEDA_NAMESPACE} --debug

}

## MAIN
case "$1" in
    install_aro)
        echo "Installing ARO4 Cluster"
        install_aro
        echo
        echo "Completed successfully!"
        ;;

    deploy_postgres)
        echo "Installing ARO4 Cluster"
        check_resource_group_existence
        deploy_postgres
        echo
        echo "Completed successfully!"
        ;;

    obtain_aro_info)
        echo "Obtaining Info..."
        echo
        obtain_aro_info
        echo
        echo "Completed successfully!"
        ;;

    delete_aro)
        echo "Deleting ARO4 Cluster"
        delete_aro
        echo
        echo "Completed successfully!"
        ;;

    delete_postgres)
        echo "Delete flexible postgresql Cluster"
        delete_postgres
        echo
        echo "Deleted successfully!"
        ;;

    install_platform)
        echo "Setup Astronomer Platform"
        install_platform
        echo
        ;;

    install_addons)
        echo "Deploying  Addons to ARO Cluster "
        install_addons
        echo
        ;;

    deploy_all)
        echo "Deploy All resources"
        check_resource_group_existence
        deploy_postgres
        install_aro
        install_platform
        echo
        echo "Deployed successfully!"
        ;;

    delete_all)
        echo "Delete All resources"
        delete_all
        echo
        echo "Deleted successfully!"
        ;;

    *)
        echo "Invalid command specified: '$1'"
        usage
        ;;
esac
