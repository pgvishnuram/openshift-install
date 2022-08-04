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
    echo "   install_aro              Install AzureRedhat Openshift Cluster        "
    echo "   deploy_postgres          Deploy azureflexible postgres cluster        "
    echo "   delete_postgres          Delete azureflexible postgres cluster        "
    echo "   obtain_aro_info          Obtain information about the ARO4 Cluster    "
    echo "   delete_aro               Delete ARO cluster                           "
    echo "   delete_all               Cleanup all azure resources                  "
    echo "   install_platform                                                      "
    echo
}

RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-sreteam}"

echo "$RESOURCE_GROUP_NAME"

LOCATION="${LOCATION:-centralus}"

ARO_CLUSTER_NAME="${ARO_CLUSTER_NAME:-srearo}"

export VNET_NAME=$RESOURCE_GROUP_NAME-vnet

export VNET_CIDR="10.0.0.0/8"

export MASTER_SUBNET="10.0.0.0/23"

export WORKER_SUBNET="10.0.2.0/23"

export DB_SUBNET="10.0.4.0/23"

export MASTER_SUBNET_NAME=$RESOURCE_GROUP_NAME-master

export WORKER_SUBNET_NAME=$RESOURCE_GROUP_NAME-worker

export DB_SUBNET_NAME=$RESOURCE_GROUP_NAME-db

WORKER_NODE_SIZE="${WORKER_NODE_SIZE:-6}"

export POSTGRES_SERVER_NAME=$ARO_CLUSTER_NAME-dbserver

DB_PASSWORD="${DB_PASSWORD:-astro}"

export BASE_DOMAIN="${BASE_DOMAIN:-vishnu-aks-028.astro-qa.link}"
export PLATFORM_VERSION="${PLATFORM_VERSION:-0.29.2}"
export PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-astronomer}"


function check_resource_group_existence() {
if [ "$(az group exists --name "$RESOURCE_GROUP_NAME")" == true ]; then
       echo "resource group $RESOURCE_GROUP_NAME alredy exists. reusing pre-created one"
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
       echo "resource group $RESOURCE_GROUP_NAME alredy exists. reusing pre-created one"
    else
       echo 'creating new resource group'
       az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
fi

if [[ $(az network vnet list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$VNET_NAME'] | length(@)")  -gt 0 ]]; then
   echo "vnet $VNET_NAME already exists. reusing pre-created one"
   else
   echo "create $VNET_NAME vnet "
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
    az aro create --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" --vnet "$VNET_NAME" --master-subnet "$MASTER_SUBNET_NAME"  --worker-subnet "$WORKER_SUBNET_NAME" --worker-count "$WORKER_NODE_SIZE" --debug
fi
}


function deploy_postgres() {

    if [[ $(az network vnet list --resource-group "$RESOURCE_GROUP_NAME" --query "[?name=='$VNET_NAME'] | length(@)")  -gt 0 ]]; then
      echo "vnet $VNET_NAME already exists. reusing pre-created one"
      else
      echo "create $VNET_NAME vnet "
      az network vnet create --resource-group "$RESOURCE_GROUP_NAME" --name "$VNET_NAME"  --address-prefixes $VNET_CIDR
      echo "vnet $VNET_NAME creation completed"
    fi

    if [[ $(az network vnet subnet list --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"  --query "[?name=='$DB_SUBNET_NAME'] | length(@)")  -gt 0 ]]; then
      echo "subnet $DB_SUBNET_NAME already exists. reusing pre-created one"
      else
      echo "creating db subnet "
      az network vnet subnet create --resource-group "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME" --name "$DB_SUBNET_NAME" --address-prefixes "$DB_SUBNET"
      echo "subnet $DB_SUBNET_NAME creation completed"
    fi

    SUBNET_ID=$(az network vnet subnet show  --resource-group  "$RESOURCE_GROUP_NAME" --vnet-name "$VNET_NAME"  --name "$DB_SUBNET_NAME" | jq -r '.id')

    if [[ $(az postgres flexible-server list --query "[?name=='$POSTGRES_SERVER_NAME'] | length(@) ")  -gt 0 ]]; then
       echo "PSQL $POSTGRES_SERVER_NAME already exists"
    else
      echo "Creating PSQL $POSTGRES_SERVER_NAME  in progress......."
      az postgres flexible-server create --name "$POSTGRES_SERVER_NAME" --subnet "$SUBNET_ID" -g "$RESOURCE_GROUP_NAME"--admin-user astro --admin-password "$DB_PASSWORD" --location "$LOCATION" -y
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
    echo "yes" | certbot certonly  --dns-route53 --dns-route53-propagation-seconds 30 -d "$BASE_DOMAIN" -d "*.$BASE_DOMAIN" --work-dir . --logs-dir . --config-dir .  -m infrastructure@astronomer.io --agree-tos

    else 
      echo "CERT DIR already exists"
      echo "checking ssl validity"
      if openssl x509 -checkend 86400 -noout -in live/$BASE_DOMAIN/fullchain.pem
        then
                echo "Certificate is still valid"
        else
                echo "yes" | certbot certonly  --dns-route53 --dns-route53-propagation-seconds 30 -d "$BASE_DOMAIN" -d "*.$BASE_DOMAIN" --work-dir . --logs-dir . --config-dir .  -m infrastructure@astronomer.io --agree-tos
        fi
fi


echo "setup astronomer enterprise"
CLUSTER_API_URL=$(az aro show --name "$ARO_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "apiserverProfile.url" -o tsv)
CLUSTER_ADMIN_USERNAME=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME"| jq -r '.kubeadminUsername')
CLUSTER_ADMIN_PASSWORD=$(az aro list-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$ARO_CLUSTER_NAME" | jq -r '.kubeadminPassword')
AZURE_FLEXI_POSTGRES=$(az postgres flexible-server list --query "[?name=='$POSTGRES_SERVER_NAME']" | jq -r '.[].fullyQualifiedDomainName')

oc login $CLUSTER_API_URL -u $CLUSTER_ADMIN_USERNAME -p $CLUSTER_ADMIN_PASSWORD

oc new-project $PLATFORM_NAMESPACE || oc project $PLATFORM_NAMESPACE

kubectl -n $PLATFORM_NAMESPACE get secret astronomer-tls ||  kubectl  -n $PLATFORM_NAMESPACE create secret tls astronomer-tls --cert live/$BASE_DOMAIN/fullchain.pem --key live/$BASE_DOMAIN/privkey.pem
kubectl -n $PLATFORM_NAMESPACE get secret astronomer-bootstrap || kubectl -n $PLATFORM_NAMESPACE create secret generic astronomer-bootstrap --from-literal connection="postgres://astro:astro@$AZURE_FLEXI_POSTGRES:5432"

helm repo add astronomer-internal https://internal-helm.astronomer.io/
helm repo update

envsubst < platform-config/config.tpl > platform-config/config.yaml
helm -n $PLATFORM_NAMESPACE  upgrade --install astronomer astronomer-internal/astronomer --version $PLATFORM_VERSION  -f platform-config/config.yaml --debug

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
