
# Openshift ARO Installer


```shell
Usage:
 ./aro.sh [command] [options]
 ./aro.sh --help

COMMANDS:
   deploy_postgres          Deploy azureflexible postgres cluster        
   install_aro              Install AzureRedhat Openshift Cluster        
   install_platform         Install Astronomer Platform                  
   obtain_aro_info          Obtain information about the ARO4 Cluster    
   delete_postgres          Delete azureflexible postgres cluster        
   delete_aro               Delete ARO cluster                           
   delete_all               Cleanup all azure resources                                      

```

## Pre-requisties 
```
# Define these env vars before executing the script
export RESOURCE_GROUP_NAME=""
export ARO_CLUSTER_NAME=""
export BASE_DOMAIN=""
export PLATFORM_VERSION=""
```

## Install Steps
```
$ ./aro.sh deploy_postgres
$ ./aro.sh install_aro
$ ./aro.sh install_platform
```

## Cleanup Stels
```
$ helm uninstall astronomer --debug
$ ./aro.sh delete_all

```