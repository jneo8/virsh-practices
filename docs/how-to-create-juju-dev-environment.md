
```sh
$ ./launch-vm.sh ctrl noble 4G 2 20G ~/.ssh/id_ed25519.pub

$ ./list-vms.sh 
Virtual Machines:
NAME                 STATE      IP ADDRESSES             
----                 -----      -------------            
ctrl                 running    192.168.122.179

Commands:
  Start VM:   virsh start <vm-name>
  Stop VM:    virsh shutdown <vm-name>
  Delete VM:  virsh destroy <vm-name> && virsh undefine <vm-name> --remove-all-storage

$ juju add-cloud --client manual-cloud 
Cloud Types
  lxd
  maas
  manual
  openstack
  vsphere

Select cloud type: manual

Enter the ssh connection string for controller, username@<hostname or IP> or <hostname or IP>: ubuntu@192.168.122.26

Cloud "manual-cloud" successfully added to your local client.

$ juju bootstrap manual-cloud manual-ctrl

$ juju add-model machines

$ ./launch-vm.sh k8s-0 noble 16G 8 100G ~/.ssh/id_ed25519.pub
$  ./attach-ip.sh k8s-0 192.168.122.10,192.168.122.11,192.168.122.12,192.168.122.13,192.168.122.14,192.168.122.15,192.168.122.16,192.168.122.17,192.168.122.18,192.168.122.19,192.168.122.20

$ ./list-vms.sh
Virtual Machines:
NAME                 STATE      IP ADDRESSES
----                 -----      -------------
ctrl                 running    192.168.122.179
k8s-0                running    192.168.122.223,192.168.122.10,192.168.122.11,192.168.122.12,192.168.122.13,192.168.122.14,192.168.122.15,192.168.122.16,192.168.122.17,192.168.122.18,192.168.122.19,192.168.122.20,192.168.122.128

Commands:
  Start VM:   virsh start <vm-name>
  Stop VM:    virsh shutdown <vm-name>
  Delete VM:  virsh destroy <vm-name> && virsh undefine <vm-name> --remove-all-storage

$ juju add-machine ssh:ubuntu@192.168.122.223
$ juju deploy k8s --to 0 --config load-balancer-enabled=true --config load-balancer-cidrs=192.168.122.10-192.168.122.20 --config dns-enabled=true
$ juju run k8s/leader get-kubeconfig --format yaml | yq -r '."k8s/0".results.kubeconfig' | juju add-k8s k8scloud --client
$ juju bootstrap k8scloud k8s-ctrl --debug --config controller-service-type=loadbalancer --config 'controller-external-ips=[192.168.122.10]'


# (Optional)
$ juju exec --unit k8s/leader -- sudo snap install kubectl --classic
$ juju run k8s/leader get-kubeconfig --format yaml | yq -r '."k8s/0".results.kubeconfig'  > ~/.kube/config 
$ juju exec --unit k8s/leader -- mkdir /home/ubuntu/.kube
$ juju exec --unit k8s/leader -- bash -c "sudo k8s config > /home/ubuntu/.kube/config"
```
