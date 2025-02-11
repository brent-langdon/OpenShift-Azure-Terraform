#!/bin/bash

# Only needs to run on Master 0
if hostname -f|grep -- "-0" >/dev/null
then
  echo $(date) " - Installing OpenShift on Master"
else
  echo $(date) " - Skipping OpenShift Install - Not Master 0"
  exit 0
fi

set -e

SUDOUSER=$1
PASSWORD="$2"
PRIVATEKEY=$3
MASTER=$4
MASTERPUBLICIPHOSTNAME=$5
INFRA=$6
INFRAPUBLICIPADDRESS=$7
NODE=$8
NODECOUNT=$9
INFRACOUNT=${10}
MASTERCOUNT=${11}
ROUTING=${12}
REGISTRYSA=${13}
ACCOUNTKEY="${14}"
TENANTID=${15}
SUBSCRIPTIONID=${16}
AADCLIENTID=${17}
AADCLIENTSECRET="${18}"
RESOURCEGROUP=${19}
LOCATION=${20}
STORAGEACCOUNT1=${21}
SAKEY1=${22}
OANSIBLEURL="${23}"
OANSIBLEBRANCH="${24}"

MASTERLOOP=$((MASTERCOUNT - 1))
INFRALOOP=$((INFRACOUNT - 1))
NODELOOP=$((NODECOUNT - 1))

# Generate private keys for use by Ansible
echo $(date) " - Generating Private keys for use by Ansible for OpenShift Installation"
runuser -l $SUDOUSER -c "(echo \"$PRIVATEKEY\" | base64 -d) > ~/.ssh/id_rsa"
runuser -l $SUDOUSER -c "chmod 600 ~/.ssh/id_rsa*"

# echo $(date) "- Updating ansible.cfg to disable host_key_checking"
sed -i -e "s/^#host_key_checking = False/host_key_checking = False/" /etc/ansible/ansible.cfg

# Create Ansible Playbooks for Post Installation tasks
echo $(date) " - Create Ansible Playbooks for Post Installation tasks"

# Run on all masters - Create Inital OpenShift User on all Masters
cat > /home/${SUDOUSER}/addocpuser.yml <<EOF
---
- hosts: masters
  gather_facts: no
  remote_user: ${SUDOUSER}
  become: yes
  become_method: sudo
  vars:
    description: "Create OpenShift Users"
  tasks:
  - name: create directory
    file: path=/etc/origin/master state=directory
  - name: add initial OpenShift user
    shell: htpasswd -cb /etc/origin/master/htpasswd ${SUDOUSER} "${PASSWORD}"
EOF

# Run on MASTER-0 - Make initial OpenShift User a Cluster Admin
cat > /home/${SUDOUSER}/assignclusteradminrights.yml <<EOF
---
- hosts: master0
  gather_facts: no
  remote_user: ${SUDOUSER}
  become: yes
  become_method: sudo
  vars:
    description: "Make user cluster admin"
  tasks:
  - name: make OpenShift user cluster admin
    shell: oc adm policy add-cluster-role-to-user cluster-admin $SUDOUSER
EOF

# Run on MASTER-0 - configure registry to use Azure Storage
cat > /home/${SUDOUSER}/dockerregistry.yml <<EOF
---
- hosts: master0
  gather_facts: no
  remote_user: ${SUDOUSER}
  become: yes
  become_method: sudo
  vars:
    description: "Set registry to use Azure Storage"
  tasks:
  - name: Configure docker-registry to use Azure Storage
    shell: oc set env dc docker-registry -e REGISTRY_STORAGE=azure -e REGISTRY_STORAGE_AZURE_ACCOUNTNAME=$REGISTRYSA -e REGISTRY_STORAGE_AZURE_ACCOUNTKEY=$ACCOUNTKEY -e REGISTRY_STORAGE_AZURE_CONTAINER=registry
EOF

# Run on MASTER-0 - configure Storage Class
cat > /home/${SUDOUSER}/configurestorageclass.yml <<EOF
---
- hosts: master0
  gather_facts: no
  remote_user: ${SUDOUSER}
  become: yes
  become_method: sudo
  vars:
    description: "Create Storage Class"
  tasks:
  - name: Create Storage Class with StorageAccountPV1
    shell: oc create -f /home/${SUDOUSER}/scgeneric1.yml
EOF

# Create vars.yml file for use by setup-azure-config.yml playbook
cat > /home/${SUDOUSER}/vars.yml <<EOF
g_tenantId: $TENANTID
g_subscriptionId: $SUBSCRIPTIONID
g_aadClientId: $AADCLIENTID
g_aadClientSecret: $AADCLIENTSECRET
g_resourceGroup: $RESOURCEGROUP
g_location: $LOCATION
EOF

# Create Azure Cloud Provider configuration Playbook for Master Config
if [ $MASTERCOUNT -eq 1 ]
then

# Single Master Configuration
cat > /home/${SUDOUSER}/setup-azure-master.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: masters
  gather_facts: no
  serial: 1
  vars_files:
  - vars.yml
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    master_conf: /etc/origin/master/master-config.yaml
  handlers:
  - name: restart origin-master-api
    systemd:
      state: restarted
      name: origin-master-api

  - name: restart origin-master-controllers
    systemd:
      state: restarted
      name: origin-master-controllers

  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientID" : "{{ g_aadClientId }}",
          "aadClientSecret" : "{{ g_aadClientSecret }}",
          "subscriptionID" : "{{ g_subscriptionId }}",
          "tenantID" : "{{ g_tenantId }}",
          "resourceGroup": "{{ g_resourceGroup }}",
        }
    notify:
    - restart origin-master-api
    - restart origin-master-controllers

  - name: insert the azure disk config into the master
    modify_yaml:
      dest: "{{ master_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubernetesMasterConfig.apiServerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.apiServerArguments.cloud-provider
      value:
      - azure

    - key: kubernetesMasterConfig.controllerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.controllerArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-master-api
    - restart origin-master-controllers
EOF

else

# Multiple Master Configuration
cat > /home/${SUDOUSER}/setup-azure-master.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: masters
  gather_facts: no
  serial: 1
  vars_files:
  - vars.yml
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    master_conf: /etc/origin/master/master-config.yaml
  handlers:
  - name: restart origin-master-api
    systemd:
      state: restarted
      name: origin-master-api

  - name: restart origin-master-controllers
    systemd:
      state: restarted
      name: origin-master-controllers

  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientID" : "{{ g_aadClientId }}",
          "aadClientSecret" : "{{ g_aadClientSecret }}",
          "subscriptionID" : "{{ g_subscriptionId }}",
          "tenantID" : "{{ g_tenantId }}",
          "resourceGroup": "{{ g_resourceGroup }}",
        }
    notify:
    - restart origin-master-api
    - restart origin-master-controllers

  - name: insert the azure disk config into the master
    modify_yaml:
      dest: "{{ master_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubernetesMasterConfig.apiServerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.apiServerArguments.cloud-provider
      value:
      - azure

    - key: kubernetesMasterConfig.controllerArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubernetesMasterConfig.controllerArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-master-api
    - restart origin-master-controllers
EOF

fi

# Create Azure Cloud Provider configuration Playbook for Node Config (Master Nodes)
cat > /home/${SUDOUSER}/setup-azure-node-master.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: masters
  serial: 1
  gather_facts: no
  vars_files:
  - vars.yml
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    node_conf: /etc/origin/node/node-config.yaml
  handlers:
  - name: restart origin-node
    systemd:
      state: restarted
      name: origin-node
  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientID" : "{{ g_aadClientId }}",
          "aadClientSecret" : "{{ g_aadClientSecret }}",
          "subscriptionID" : "{{ g_subscriptionId }}",
          "tenantID" : "{{ g_tenantId }}",
          "resourceGroup": "{{ g_resourceGroup }}",
        }
    notify:
    - restart origin-node
  - name: insert the azure disk config into the node
    modify_yaml:
      dest: "{{ node_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubeletArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubeletArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-node
EOF

# Create Azure Cloud Provider configuration Playbook for Node Config (Non-Master Nodes)
cat > /home/${SUDOUSER}/setup-azure-node.yml <<EOF
#!/usr/bin/ansible-playbook
- hosts: nodes:!masters
  serial: 1
  gather_facts: no
  vars_files:
  - vars.yml
  become: yes
  vars:
    azure_conf_dir: /etc/azure
    azure_conf: "{{ azure_conf_dir }}/azure.conf"
    node_conf: /etc/origin/node/node-config.yaml
  handlers:
  - name: restart origin-node
    systemd:
      state: restarted
      name: origin-node
  post_tasks:
  - name: make sure /etc/azure exists
    file:
      state: directory
      path: "{{ azure_conf_dir }}"

  - name: populate /etc/azure/azure.conf
    copy:
      dest: "{{ azure_conf }}"
      content: |
        {
          "aadClientID" : "{{ g_aadClientId }}",
          "aadClientSecret" : "{{ g_aadClientSecret }}",
          "subscriptionID" : "{{ g_subscriptionId }}",
          "tenantID" : "{{ g_tenantId }}",
          "resourceGroup": "{{ g_resourceGroup }}",
        }
    notify:
    - restart origin-node
  - name: insert the azure disk config into the node
    modify_yaml:
      dest: "{{ node_conf }}"
      yaml_key: "{{ item.key }}"
      yaml_value: "{{ item.value }}"
    with_items:
    - key: kubeletArguments.cloud-config
      value:
      - "{{ azure_conf }}"

    - key: kubeletArguments.cloud-provider
      value:
      - azure
    notify:
    - restart origin-node
  - name: delete the node so it can recreate itself
    command: oc delete node {{inventory_hostname}}
    delegate_to: ${MASTER}-0
  - name: sleep to let node come back to life
    pause:
       seconds: 90
EOF

# Create Playbook to delete stuck Master nodes and set as not schedulable
cat > /home/${SUDOUSER}/deletestucknodes.yml <<EOF
- hosts: masters
  gather_facts: no
  become: yes
  vars:
    description: "Delete stuck nodes"
  tasks:
  - name: Delete stuck nodes so it can recreate itself
    command: oc delete node {{inventory_hostname}}
    delegate_to: ${MASTER}-0
  - name: sleep between deletes
    pause:
      seconds: 25
  - name: set masters as unschedulable
    command: oadm manage-node {{inventory_hostname}} --schedulable=false
EOF

# Create Ansible Hosts File
echo $(date) " - Create Ansible Hosts file"
if [ $MASTERCOUNT -eq 1 ]
then

# Ansible Host file for Single Master Configuration
cat > /etc/ansible/hosts <<EOF
# Create an OSEv3 group that contains the masters and nodes groups
[OSEv3:children]
masters
master0
etcd
nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=$SUDOUSER
ansible_become=yes
openshift_deployment_type=origin

# cloudprovider settings for azure
openshift_cloudprovider_kind=azure
openshift_cloudprovider_azure_client_id=$AADCLIENTID
openshift_cloudprovider_azure_client_secret=$AADCLIENTSECRET
openshift_cloudprovider_azure_tenant_id=$TENANTID
openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID
openshift_cloudprovider_azure_resource_group=$RESOURCEGROUP
openshift_cloudprovider_azure_location=$LOCATION

openshift_master_cluster_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_default_subdomain=$INFRAPUBLICIPADDRESS.nip.io
#openshift_console_hostname=console.$MASTERPUBLICIPHOSTNAME

# Enable HTPasswdPasswordIdentityProvider for username / password authentication for OpenShift Cluster
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider'}]

# host group for masters
[masters]
$MASTER-0

[master0]
$MASTER-0

# host group for etcd
[etcd]
$MASTER-0

# host group for nodes
[nodes]
$MASTER-0 openshift_node_group_name='node-config-master'
EOF

# Loop to add Infra Nodes
for (( c=0; c<$INFRACOUNT; c++ ))
do
  echo "$INFRA-$c openshift_node_group_name='node-config-infra'" >> /etc/ansible/hosts
done

# Loop to add Compute Nodes
for (( c=0; c<$NODECOUNT; c++ ))
do
  echo "$NODE-$c openshift_node_group_name='node-config-compute'" >> /etc/ansible/hosts
done

else

# Ansible Host file for Multiple Master Configuration
cat > /etc/ansible/hosts <<EOF
# Create an OSEv3 group that contains the masters and nodes groups
[OSEv3:children]
masters
etcd
master0
nodes

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=$SUDOUSER
ansible_become=yes
openshift_deployment_type=origin

# cloudprovider settings for azure
openshift_cloudprovider_kind=azure
openshift_cloudprovider_azure_client_id=$AADCLIENTID
openshift_cloudprovider_azure_client_secret=$AADCLIENTSECRET
openshift_cloudprovider_azure_tenant_id=$TENANTID
openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID
openshift_cloudprovider_azure_resource_group=$RESOURCEGROUP
openshift_cloudprovider_azure_location=$LOCATION

openshift_master_cluster_method=native
openshift_master_cluster_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_cluster_public_hostname=$MASTERPUBLICIPHOSTNAME
openshift_master_default_subdomain=$INFRAPUBLICIPADDRESS.nip.io
#openshift_console_hostname=console.$MASTERPUBLICIPHOSTNAME

# Enable HTPasswdPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider'}]

# host group for masters
[masters]
$MASTER-[0:${MASTERLOOP}]

# host group for etcd
[etcd]
$MASTER-[0:${MASTERLOOP}]

[master0]
$MASTER-0

# host group for nodes
[nodes]
EOF

# Loop to add Masters
for (( c=0; c<$MASTERCOUNT; c++ ))
do
  echo "$MASTER-$c openshift_node_group_name='node-config-master'" >> /etc/ansible/hosts
done

# Loop to add Infra Nodes
for (( c=0; c<$INFRACOUNT; c++ ))
do
  echo "$INFRA-$c openshift_node_group_name='node-config-infra'" >> /etc/ansible/hosts
done

# Loop to add Compute Nodes
for (( c=0; c<$NODECOUNT; c++ ))
do
  echo "$NODE-$c openshift_node_group_name='node-config-compute'" >> /etc/ansible/hosts
done

fi

# Initiating installation of OpenShift Container Platform using Ansible Playbook
echo $(date) " - Installing OpenShift Container Platform via Ansible Playbook"
runuser -l $SUDOUSER -c "git clone ${OANSIBLEURL} /home/$SUDOUSER/openshift-ansible && cd /home/$SUDOUSER/openshift-ansible && git checkout ${OANSIBLEBRANCH}"
echo $(date) " - Running prerequisites.yml playbook"
runuser -l $SUDOUSER -c "ansible-playbook openshift-ansible/playbooks/prerequisites.yml"
echo $(date) " - Running deploy_cluster.yml playbook"
runuser -l $SUDOUSER -c "ansible-playbook openshift-ansible/playbooks/deploy_cluster.yml"

# echo $(date) " - Modifying sudoers"
# sed -i -e "s/Defaults    requiretty/# Defaults    requiretty/" /etc/sudoers
# sed -i -e '/Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"/aDefaults    env_keep += "PATH"' /etc/sudoers

# Deploying Registry
# echo $(date) "- Registry automatically deployed to infra nodes"

# Deploying Router
# echo $(date) "- Router automaticaly deployed to infra nodes"

# echo $(date) "- Re-enabling requiretty"
# sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers

# Adding user to OpenShift authentication file
echo $(date) "- Adding OpenShift user"
runuser -l $SUDOUSER -c "ansible-playbook ~/addocpuser.yml"

# Assigning cluster admin rights to OpenShift user
echo $(date) "- Assigning cluster admin rights to user"
runuser -l $SUDOUSER -c "ansible-playbook ~/assignclusteradminrights.yml"

# Create Storage Class
# echo $(date) "- Creating Storage Class"
#runuser -l $SUDOUSER -c "ansible-playbook ~/configurestorageclass.yml"

# Configure Docker Registry to use Azure Storage Account
# echo $(date) "- Configuring Docker Registry to use Azure Storage Account"
#runuser -l $SUDOUSER -c "ansible-playbook ~/dockerregistry.yml"

# echo $(date) "- Sleep for 120"
# sleep 120

# Execute setup-azure-master and setup-azure-node playbooks to configure Azure Cloud Provider
# echo $(date) "- Configuring OpenShift Cloud Provider to be Azure"

#runuser -l $SUDOUSER -c "ansible-playbook ~/setup-azure-master.yml"
#runuser -l $SUDOUSER -c "ansible-playbook ~/setup-azure-node-master.yml"
#runuser -l $SUDOUSER -c "ansible-playbook ~/setup-azure-node.yml"
#runuser -l $SUDOUSER -c "ansible-playbook ~/deletestucknodes.yml"

# Delete postinstall files
# echo $(date) "- Deleting post installation files"
rm /home/${SUDOUSER}/addocpuser.yml
rm /home/${SUDOUSER}/assignclusteradminrights.yml
rm /home/${SUDOUSER}/dockerregistry.yml
rm /home/${SUDOUSER}/vars.yml
rm /home/${SUDOUSER}/setup-azure-master.yml
rm /home/${SUDOUSER}/setup-azure-node-master.yml
rm /home/${SUDOUSER}/setup-azure-node.yml
rm /home/${SUDOUSER}/deletestucknodes.yml

echo $(date) "- Script complete"
