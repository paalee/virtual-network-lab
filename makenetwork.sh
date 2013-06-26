#!/bin/bash

#VBoxManage registervm /Users/paalee/VirtualBox\ VMs/HostTemplate/HostTemplate.vbox

# HOSTS CONFIGURATION (for PCs etc with one interface, i.e. one straigt-through cable connected)
NHosts=5
#HostIPs=( "192.168.1.1" "192.168.1.2" "192.168.1.3" "192.168.1.4" "192.168.1.5" )
HostIPs=( "192.168.1.1" "192.168.1.2" "192.168.2.3" "192.168.2.4" "192.168.2.5" )
#for IPaddress in "${HostIPs[@]}"; do echo "Listed address: $IPaddress"; done

# SWITCH CONFIGURATION
#Switch1=( "hostcable1" "hostcable2" "crosscable1" "crosscable2" )  
#Switch1=( "hostcable1" "hostcable2" "crosscable1" )  
Switch1=( "hostcable1" "hostcable2" "crosscable1" )  
Switch2=( "hostcable3" "hostcable4" "hostcable5" "crosscable2" )  
SWITCHES=( Switch1 Switch2 )  
  
# ROUTER CONFIGURATION
#Router1=("crosscable2:192.168.1.99" "crosscable3:192.168.2.1")  
#Router2=("crosscable3:192.168.2.2")  
Router1=("crosscable1:192.168.1.99" "crosscable3:192.168.3.1")  
Router2=("crosscable2:192.168.2.99"  "crosscable3:192.168.3.2")    
ROUTERS=( Router1 Router2 )  

# PARAMETERS NOT TO BE CONFIGURED:
ManagementPrefix="192.168.100"
HostSuffixStart=200
HostIPdummy="192.168.1.1"
SwitchSuffixStart=140
RouterSuffixStart=170
netmask="255.255.255.0"

if [ "$1" = "clone" ]
  then
    # CLONING HOSTS
    for (( i=1; i<=$NHosts; i++ ))
    do
       echo "Cloning: Generating host AutoHost$i..."
       VboxManage clonevm HostTemplate --name "AutoHost$i" --register
       echo "Adding Adapter2 for non-management (production) communicaton"
       VboxManage modifyvm "AutoHost$i" --nic2 intnet --nictype2 virtio --cableconnected2 on --intnet2 "hostcable$i" --nicpromisc2 allow-all
       OrigManagementIPaddress="$ManagementPrefix.$HostSuffixStart"
       NewManagementIPaddress="$ManagementPrefix.$(($HostSuffixStart+$i))"
       VboxManage startvm "AutoHost$i"
       echo "Updating bootlocal.sh at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sed 's/$OrigManagementIPaddress/$NewManagementIPaddress/g' /opt/bootlocal.sh_template > /opt/bootlocal.sh"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "echo 'sudo hostname AutoHost$i' >> /opt/bootlocal.sh"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "echo 'sudo ifconfig eth1 ${HostIPs[$(($i-1))]}  netmask $netmask' >> /opt/bootlocal.sh"
       echo "Storing bootlocal.sh change persistently at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sh /usr/bin/filetool.sh -b"
#       echo "Assigning ip address $NewManagementIPaddress to AutoHost$i (changed from $OrigManagementIPaddress)..."
#       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo ifconfig eth0 $NewManagementIPaddress" &
#       orphanProcessID=$!
#       kill $orphanProcessID
       echo "Powering off AutoHost$i..."
       VBoxManage controlvm AutoHost$i poweroff
       echo "Done the cloning of AutoHost$i"
    done
    # END (Cloning hosts)

    # CLONING SWITCHES
    SWITCHID=0
    for SWITCH in ${SWITCHES[*]}
    do  
       SWITCHID=$(($SWITCHID+1))  
       echo "Considering switch: $SWITCH (assumed to be AutoSwitch number $SWITCHID)..."
       VboxManage clonevm SwitchTemplate --name "Auto$SWITCH" --register

       echo "Adding Adapters for non-management (production) communicaton"
       TEMP="\${$SWITCH[*]}"
       eval "SWITCHCABLE=$TEMP"
       ADAPTER=1
       for ELEMENT in $SWITCHCABLE  
       do  
            ADAPTER=$(($ADAPTER+1))
            echo "   Connecting Adapter$ADAPTER to $ELEMENT"
            echo "VboxManage modifyvm" "Auto$SWITCH" "--nic$ADAPTER" intnet "--nictype$ADAPTER" virtio "--cableconnected$ADAPTER" on "--intnet$ADAPTER" "$ELEMENT" "--nicpromisc$ADAPTER" allow-all
	    VboxManage modifyvm "Auto$SWITCH" "--nic$ADAPTER" intnet "--nictype$ADAPTER" virtio "--cableconnected$ADAPTER" on "--intnet$ADAPTER" "$ELEMENT" "--nicpromisc$ADAPTER" allow-all
       done  
       # you can call individual element with ${SWITCH[0]} etc.

       echo "Starting VM..."
       OrigManagementIPaddress="$ManagementPrefix.$SwitchSuffixStart"
       NewManagementIPaddress="$ManagementPrefix.$(($SwitchSuffixStart+$SWITCHID))"
       VboxManage startvm "Auto$SWITCH"
       echo "Updating bootlocal.sh at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sed 's/$OrigManagementIPaddress/$NewManagementIPaddress/g' /opt/bootlocal.sh_template > /opt/bootlocal.sh"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "echo 'sudo hostname Auto$SWITCH' >> /opt/bootlocal.sh"
       echo "Configuring default switch functionality (without VLAN trunking)"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo ovs-vsctl add-br br-default-all"
       ETH=0
       for ELEMENT in $SWITCHCABLE  
       do  
            ETH=$(($ETH+1))
            ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo ovs-vsctl add-port br-default-all eth$ETH"
       done  
       echo "Storing bootlocal.sh and other changes persistently at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sh /usr/bin/filetool.sh -b"
       echo "Powering off Auto$SWITCHID..."
       VBoxManage controlvm "Auto$SWITCH" poweroff
       echo "Done the cloning of Auto$SWITCHID"
    done

    # END (Cloning switchess)

    # CLONING ROUTERS
    ROUTERID=0  
    for ROUTER in ${ROUTERS[*]}  
    do  
       ROUTERID=$(($ROUTERID+1))  
       echo "Considering router: $ROUTER (assumed to be AutoRouter number $ROUTERID)..."
       VboxManage clonevm RouterTemplate --name "Auto$ROUTER" --register
       echo "Adding Adapters for non-management (production) communicaton"
       TEMP="\${$ROUTER[*]}"
       eval "ROUTERCABLEandIPADDR=$TEMP"
       ADAPTER=1
       for ELEMENT in $ROUTERCABLEandIPADDR  
       do  
            ADAPTER=$(($ADAPTER+1))
            ROUTERCABLE="$(echo $ELEMENT | cut -d: -f1)"
            echo "   Connecting Adapter$ADAPTER to $ROUTERCABLE"
            #echo "VboxManage modifyvm" "Auto$ROUTER" "--nic$ADAPTER" intnet "--nictype$ADAPTER" virtio "--cableconnected$ADAPTER" on "--intnet$ADAPTER" "$ROUTERCABLE" "--nicpromisc$ADAPTER" allow-all
	    VboxManage modifyvm "Auto$ROUTER" "--nic$ADAPTER" intnet "--nictype$ADAPTER" virtio "--cableconnected$ADAPTER" on "--intnet$ADAPTER" "$ROUTERCABLE" "--nicpromisc$ADAPTER" allow-all
       done  
       # you can call individual element with ${SWITCH[0]} etc.

       echo "Starting VM..."
       OrigManagementIPaddress="$ManagementPrefix.$RouterSuffixStart"
       NewManagementIPaddress="$ManagementPrefix.$(($RouterSuffixStart+$ROUTERID))"
       VboxManage startvm "Auto$ROUTER"
       echo "Updating bootlocal.sh at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sed 's/$OrigManagementIPaddress/$NewManagementIPaddress/g' /opt/bootlocal.sh_template > /opt/bootlocal.sh"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "echo 'sudo hostname Auto$ROUTER' >> /opt/bootlocal.sh"
       echo "Configuring default router functionality (using OSPF routing protocol)"
       #ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo ovs-vsctl add-br br-default-all"
       ETH=0
       for ELEMENT in $ROUTERCABLEandIPADDR  
       do  
            IPADDR="${ELEMENT##*:}"
            ETH=$(($ETH+1))
            ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo echo sudo ifconfig eth$ETH $IPADDR netmask 255.255.255.0 >> /opt/bootlocal.sh"
       done  
       echo "Storing bootlocal.sh and other changes persistently at clone"
       ssh -o "StrictHostKeyChecking no" "tc@$OrigManagementIPaddress" "sudo sh /usr/bin/filetool.sh -b"
       echo "Powering off Auto$ROUTERID..."
       VBoxManage controlvm "Auto$ROUTER" poweroff
       echo "Done the cloning of Auto$ROUTERID"
       # you can call individual element with ${ROUTER[0]} etc.
    done
    # END (Cloning routers)

fi

if [ "$1" = "start" ] || [ "$1" = "clone" ]
  then
    # STARTING HOSTS
    for (( i=1; i<=$NHosts; i++ ))
    do
       echo "Starting: AutoHost$i..."
       VboxManage startvm "AutoHost$i"
    done
    # STARTING SWITCHES
    for SWITCH in ${SWITCHES[*]}
    do  
       echo "Starting switch: $SWITCH..."
       VboxManage startvm "Auto$SWITCH"
    done
    # STARTING ROUTERS
    for ROUTER in ${ROUTERS[*]}
    do  
       echo "Starting router: $ROUTER ..."
       VboxManage startvm "Auto$ROUTER"
    done
fi

if [ "$1" = "stop" ] || [ "$1" = "destroy" ]
  then
    # STOPPING HOSTS
    for (( i=1; i<=$NHosts; i++ ))
    do
       echo "Stopping: AutoHost$i..."
       VBoxManage controlvm "AutoHost$i" poweroff
    done
    # STOPPING SWITCHES
    for SWITCH in ${SWITCHES[*]}
    do  
       echo "Stopping switch: $SWITCH ..."
       VBoxManage controlvm "Auto$SWITCH" poweroff
    done
    # STOPPING ROUTERS
    for ROUTER in ${ROUTERS[*]}
    do  
       echo "Stopping router: $ROUTER ..."
       VBoxManage controlvm "Auto$ROUTER" poweroff
    done
    echo "stopping done"
fi


if [ "$1" = "destroy" ]
  then
    echo "destroying..."
    # DESTROYING HOSTS
    for (( i=1; i<=$NHosts; i++ ))
    do
       echo "Destroying: AutoHost$i..."
       VBoxManage unregistervm "AutoHost$i" --delete
    done
    # STOPPING SWITCHES
    for SWITCH in ${SWITCHES[*]}
    do  
       echo "Destroying switch: $SWITCH (assumed to be AutoSwitch number $SWITCHID)..."
       VBoxManage unregistervm "Auto$SWITCH" --delete
    done
    # STOPPING ROUTERS
    for ROUTER in ${ROUTERS[*]}
    do  
       echo "Destroying routers: $ROUTER (assumed to be AutoRouter number $ROUTERID)..."
       VBoxManage unregistervm "Auto$ROUTER" --delete
    done
    echo "destroying done"
fi

if [ "$1" = "modify" ]
  then
    echo "modyfying not implemented yet..."
    #VboxManage modifyvm AutoHost1 --nic1 intnet --nictype1 virtio --cableconnected1 on --intnet1 cable1 --nicpromisc1 allow-all
    exit 0
fi

if [ "$1" = "create" ]
  then
    echo "creating"
    VboxManage createvm --name AutoHost --register
    VBoxManage clonevdi linux-microcore-4.0.2-clean.vdi AutoHost.vdi
    VBoxManage storagectl AutoHost --name "IDE" --add ide
    VBoxManage modifyvm AutoHost --hda AutoHostcx.vdi
    exit 0
fi


echo "Script finished ok"
exit 0

