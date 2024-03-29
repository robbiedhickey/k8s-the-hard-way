# start all vms in a resource group
az vm start --ids $(az vm list -g MyResourceGroup --query "[].id" -o tsv)

# stop all vms in a resource group
az vm deallocate --ids $(az vm list -g MyResourceGroup --query "[].id" -o tsv)