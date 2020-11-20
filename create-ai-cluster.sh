#!/bin/bash

export AI_URL=https://assisted-installer.apps.cnf20.cloud.lab.eng.bos.redhat.com
CLUSTER_NAME=cnf21
CLUSTER_NODES=3

#Clean
rm -rf $HOME/$CLUSTER_NAME/auth

aicli create cluster -P pull_secret=openshift_pull.json -P base_dns_domain=cloud.lab.eng.bos.redhat.com -P ssh_public_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCZnG8AIzlDAhpyENpK2qKiTT8EbRWOrz7NXjRzopbPu215mocaJgjjwJjh1cYhgPhpAp6M/ttTk7I4OI7g4588Apx4bwJep6oWTU35LkY8ZxkGVPAJL8kVlTdKQviDv3XX12l4QfnDom4tm4gVbRH0gNT1wzhnLP+LKYm2Ohr9D7p9NBnAdro6k++XWgkDeijLRUTwdEyWunIdW1f8G0Mg8Y1Xzr13BUo3+8aey7HLKJMDtobkz/C8ESYA/f7HJc5FxF0XbapWWovSSDJrr9OmlL9f4TfE+cQk3s+eoKiz2bgNPRgEEwihVbGsCN4grA+RzLCAOpec+2dTJrQvFqsD alosadag@sonnelicht.local' -P ingress_vip=10.19.140.28 ${CLUSTER_NAME}

aicli create iso -P ssh_public_key='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCZnG8AIzlDAhpyENpK2qKiTT8EbRWOrz7NXjRzopbPu215mocaJgjjwJjh1cYhgPhpAp6M/ttTk7I4OI7g4588Apx4bwJep6oWTU35LkY8ZxkGVPAJL8kVlTdKQviDv3XX12l4QfnDom4tm4gVbRH0gNT1wzhnLP+LKYm2Ohr9D7p9NBnAdro6k++XWgkDeijLRUTwdEyWunIdW1f8G0Mg8Y1Xzr13BUo3+8aey7HLKJMDtobkz/C8ESYA/f7HJc5FxF0XbapWWovSSDJrr9OmlL9f4TfE+cQk3s+eoKiz2bgNPRgEEwihVbGsCN4grA+RzLCAOpec+2dTJrQvFqsD alosadag@sonnelicht.local' ${CLUSTER_NAME}
if [ $? -eq 0 ]; then
 echo -e "\e[92m[OK] ISO is available to download. Run aicli download iso <cluster>"
else
 echo -e "\e[91m[ERROR]: An error happened while creating the discovery ISO"
 exit 1
fi

echo -e "\e[0m Downloading the ISO image locally"
aicli download iso ${CLUSTER_NAME}
if [ $? -eq 0 ]; then
 echo -e "\e[92m[OK] ISO downloaded successfully"
else
 echo -e "\e[91m[ERROR]: An error happened while downloading the discovery ISO"
 exit 1
fi

sudo mv ${CLUSTER_NAME}.iso /var/lib/libvirt/images/. && sudo chown qemu: /var/lib/libvirt/images/${CLUSTER_NAME}.iso

echo "\e[0m Booting up hosts with the discovery iso"
echo "Booting up master-0.cnf21.cloud.lab.eng.bos.redhat.com"
kcli create vm -P iso=${CLUSTER_NAME}.iso -P memory=16384 -P numcpus=4 -P disks=[120] -P nets=['{"name":"baremetal", "mac":"AA:BB:BB:BB:BB:03"}'] master-0.cnf21.cloud.lab.eng.bos.redhat.com
echo "Booting up master-1.cnf21.cloud.lab.eng.bos.redhat.com"
kcli create vm -P iso=${CLUSTER_NAME}.iso -P memory=16384 -P numcpus=4 -P disks=[120] -P nets=['{"name":"baremetal", "mac":"AA:BB:BB:BB:BB:04"}'] master-1.cnf21.cloud.lab.eng.bos.redhat.com
echo "Booting up master-2.cnf21.cloud.lab.eng.bos.redhat.com"
kcli create vm -P iso=${CLUSTER_NAME}.iso -P memory=16384 -P numcpus=4 -P disks=[120] -P nets=['{"name":"baremetal", "mac":"AA:BB:BB:BB:BB:05"}'] master-2.cnf21.cloud.lab.eng.bos.redhat.com

echo "Wait until nodes are ready in Assisted Installer"
while true; do
	hosts_ready=$(aicli list hosts | grep $CLUSTER_NAME | grep "pending-for-input" | wc -l)
        if [ "$hosts_ready" -eq "$CLUSTER_NODES" ]; then
		break
	fi
	echo "Waiting 10s more..."
	sleep 10
done

echo -e "\e[0m Nodes detected by Assisted Installer. Setting the API VIP..."
aicli update cluster -P api_vip=10.19.140.26 cnf21

echo -e "\e[0m Printing cluster information..."
aicli info cluster $CLUSTER_NAME

echo "Wait until cluster is ready to be installed"
while true; do
        cluster_ready=$(aicli list cluster | grep $CLUSTER_NAME | cut -d "|" -f4 | tr -d ' ')
        if [ $cluster_ready == "ready" ]; then
                break
        fi
        echo "Waiting 10s more..."
        sleep 10
done

aicli start cluster $CLUSTER_NAME

echo "Cluster installation started..."
while true; do
        cluster_installed=$(aicli list cluster | grep $CLUSTER_NAME | cut -d "|" -f4 | tr -d ' ')
        if [ $cluster_installed == "installed" ]; then
                break
        fi
        aicli list cluster
        sleep 30
        aicli list hosts
        echo "Waiting 30s......."
done

mkdir -p $CLUSTER_NAME/auth
aicli download kubeadmin-password --path $HOME/$CLUSTER_NAME/auth cnf21
aicli download kubeconfig --path $HOME/$CLUSTER_NAME/auth cnf21

echo "Installation completed. You can start using your new cluster. Credentials can be found in $PWD/$CLUSTER_NAME/auth"

command -v oc >/dev/null 2>&1 || { command -v kubectl >/dev/null 2>&1 || { echo "kubectl and oc are not installed. Install them to manage the new cluster"; exit 1; }; }
export KUBECONFIG=$HOME/$CLUSTER_NAME/auth/kubeconfig.$CLUSTER_NAME
oc get nodes,clusterversion

