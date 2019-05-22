# https://github.com/ivanfioravanti/kubernetes-the-hard-way-on-azure/blob/master/docs/03-compute-resources.md


# Virtual Network 

## creates a virtual network with 254 potential compute instances
az network vnet create -g kubernetes `
  -n kubernetes-vnet `
  --address-prefix 10.240.0.0/24 `
  --subnet-name kubernetes-subnet

# Firewall

## Create a firewall network security group
az network nsg create -g kubernetes -n kubernetes-nsg

## Assign the nsg to the subnet
az network vnet subnet update -g kubernetes `
  -n kubernetes-subnet `
  --vnet-name kubernetes-vnet `
  --network-security-group kubernetes-nsg

## create a firewall rule that allows SSH and HTTPS
az network nsg rule create -g kubernetes `
  -n kubernetes-allow-ssh `
  --access allow `
  --destination-address-prefix '*' `
  --destination-port-range 22 `
  --direction inbound `
  --nsg-name kubernetes-nsg `
  --protocol tcp `
  --source-address-prefix '*' `
  --source-port-range '*' `
  --priority 1000

az network nsg rule create -g kubernetes `
  -n kubernetes-allow-api-server `
  --access allow `
  --destination-address-prefix '*' `
  --destination-port-range 6443 `
  --direction inbound `
  --nsg-name kubernetes-nsg `
  --protocol tcp `
  --source-address-prefix '*' `
  --source-port-range '*' `
  --priority 1001

## check output to ensure both rules were created for 22 + 6443
az network nsg rule list -g kubernetes --nsg-name kubernetes-nsg `
  --query "[].{Name:name, Direction:direction, Priority:priority, Port:destinationPortRange}" `
  -o table

# Public IP

## allocate a static ip address that will be attached to the external load balancer fronting k8s api servers
az network lb create -g kubernetes `
  -n kubernetes-lb `
  --backend-pool-name kubernetes-lb-pool `
  --public-ip-address kubernetes-pip `
  --public-ip-address-allocation static

## verify (mine is 40.65.96.199)
az network public-ip  list `
  --query="[?name=='kubernetes-pip'].{ResourceGroup:resourceGroup, Region:location,Allocation:publicIpAllocationMethod,IP:ipAddress}" `
  -o table

# Virtual Machines

## Find the latest stable ubuntu release and set its version
az vm image list --location westus2 --publisher Canonical --offer UbuntuServer --sku 18.04-LTS --all -o table
$ubuntu="Canonical:UbuntuServer:18.04-LTS:18.04.201905140"

## Create availability set for k8s controllers
az vm availability-set create -g kubernetes -n controller-as

## Create three compute instances that will host k8s control plane

### Create public IPs
1..3 | % { `
  az network public-ip create -n controller-$_-pip -g kubernetes `
}

### Create NIC
1..3 | % { `
  az network nic create -g kubernetes `
    -n controller-$_-nic `
    --private-ip-address 10.240.0.1$_ `
    --public-ip-address controller-$_-pip `
    --vnet kubernetes-vnet `
    --subnet kubernetes-subnet `
    --ip-forwarding `
    --lb-name kubernetes-lb `
    --lb-address-pools kubernetes-lb-pool `
}

### Create VMs
1..3 | % { `
  az vm create -g kubernetes `
    -n controller-$_ `
    --image $ubuntu `
    --generate-ssh-keys `
    --nics controller-$_-nic `
    --availability-set controller-as `
    --admin-username 'kuberoot' `
    --generate-ssh-keys `
}

## Kubernetes worker creation

### Create availability set for worker nodes
az vm availability-set create -g kubernetes -n worker-as

### Create public IPs
1..3 | % { `
  az network public-ip create -n worker-$_-pip -g kubernetes `
}

### Create NICs
1..3 | % { `
  az network nic create -g kubernetes `
    -n worker-$_-nic `
    --private-ip-address 10.240.0.2$_ `
    --public-ip-address worker-$_-pip `
    --vnet kubernetes-vnet `
    --subnet kubernetes-subnet `
    --ip-forwarding `
}

### Create VMs - The Kubernetes cluster CIDR range is defined by the Controller Manager's --cluster-cidr flag. In this tutorial the cluster CIDR range will be set to 10.240.0.0/16, which supports 254 subnets.
1..3 | % { `
  az vm create -g kubernetes `
    -n worker-$_ `
    --image $ubuntu `
    --nics worker-$_-nic `
    --tags pod-cidr=10.200.$_.0/24 `
    --availability-set worker-as `
    --admin-username 'kuberoot' `
    --generate-ssh-keys `
}

# Verify your VM creations
az vm list -d -g kubernetes -o table