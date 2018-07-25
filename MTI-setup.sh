#!/bin/bash
# MTI Masternode Setup Script V1.3 for Ubuntu 16.04 LTS
# (c) 2018 by RUSH HOUR MINING for MTI
#
# Script will attempt to autodetect primary public IP address
# and generate Masternode private key unless specified in command line
#
# Usage:
# bash MTI-setup.sh [Masternode_Private_Key]
#
# Example 1: Existing genkey created earlier is supplied
# bash MTI-setup.sh 27dSmwq9CabKjo2L3UD1HvgBP3ygbn8HdNmFiGFoVbN1STcsypy
#
# Example 2: Script will generate a new genkey automatically
# bash MTI-setup.sh
#

#Color codes
RED='\033[0;91m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#Reden TCP port
PORT=16317


#Clear keyboard input buffer
function clear_stdin { while read -r -t 0; do read -r; done; }

#Delay script execution for N seconds
function delay { echo -e "${GREEN}Sleep for $1 seconds...${NC}"; sleep "$1"; }

#Stop daemon if it's already running
function stop_daemon {
    if pgrep -x 'MTId' > /dev/null; then
        echo -e "${YELLOW}Attempting to stop MTId${NC}"
        MTId stop
        delay 30
        if pgrep -x 'MTId' > /dev/null; then
            echo -e "${RED}MTId daemon is still running!${NC} \a"
            echo -e "${YELLOW}Attempting to kill...${NC}"
            pkill MTId
            delay 30
            if pgrep -x 'MTId' > /dev/null; then
                echo -e "${RED}Can't stop MTId! Reboot and try again...${NC} \a"
                exit 2
            fi
        fi
    fi
}

#Process command line parameters
genkey=$1

clear
echo -e "${YELLOW}MTI Masternode Setup Script V1.3 for Ubuntu 16.04 LTS${NC}"
echo -e "${GREEN}Updating system and installing required packages...${NC}"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y

# Determine primary public IP address
dpkg -s dnsutils 2>/dev/null >/dev/null || sudo apt-get -y install dnsutils
publicip=$(dig +short myip.opendns.com @resolver1.opendns.com)

if [ -n "$publicip" ]; then
    echo -e "${YELLOW}IP Address detected:" $publicip ${NC}
else
    echo -e "${RED}ERROR: Public IP Address was not detected!${NC} \a"
    clear_stdin
    read -e -p "Enter VPS Public IP Address: " publicip
    if [ -z "$publicip" ]; then
        echo -e "${RED}ERROR: Public IP Address must be provided. Try again...${NC} \a"
        exit 1
    fi
fi

# update packages and upgrade Ubuntu
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
sudo apt-get -y autoremove
sudo apt-get -y install wget nano htop jq
sudo apt-get -y install libzmq3-dev
sudo apt-get -y install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
sudo apt-get -y install libevent-dev

sudo apt -y install software-properties-common
sudo add-apt-repository ppa:bitcoin/bitcoin -y
sudo apt-get -y update
sudo apt-get -y install libdb4.8-dev libdb4.8++-dev

sudo apt-get -y install libminiupnpc-dev

sudo apt-get -y install fail2ban
sudo service fail2ban restart

sudo apt-get install ufw -y
sudo apt-get update -y

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow $PORT/tcp
sudo ufw allow 22/tcp
sudo ufw limit 22/tcp
echo -e "${YELLOW}"
sudo ufw --force enable
echo -e "${NC}"

#Generating Random Password for MTIond JSON RPC
rpcuser=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
rpcpassword=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

#Create 2GB swap file
if grep -q "SwapTotal" /proc/meminfo; then
    echo -e "${GREEN}Skipping disk swap configuration...${NC} \n"
else
    echo -e "${YELLOW}Creating 2GB disk swap file. \nThis may take a few minutes!${NC} \a"
    touch /var/swap.img
    chmod 600 swap.img
    dd if=/dev/zero of=/var/swap.img bs=1024k count=2000
    mkswap /var/swap.img 2> /dev/null
    swapon /var/swap.img 2> /dev/null
    if [ $? -eq 0 ]; then
        echo '/var/swap.img none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap was created successfully!${NC} \n"
    else
        echo -e "${YELLOW}Operation not permitted! Optional swap was not created.${NC} \a"
        rm /var/swap.img
    fi
fi

#Installing Daemon
cd ~
sudo rm -r .MTI
sudo rm /usr/bin/MTI*
sudo rm MTId-.Linux_Daemon.tar.gz
wget https://github.com/mticryptocoins/MTI-Coin/files/1829112/MTId-.Linux_Daemon.tar.gz
sudo tar -xvf MTId-.Linux_Daemon.tar.gz
sudo rm MTId-.Linux_Daemon.tar.gz
sudo mv ~/MTId ~/MTIMasternodesetup/

stop_daemon

# Deploy binaries to /usr/bin
sudo cp MTIMasternodesetup/MTId /usr/bin/
sudo chmod 755 -R ~/MTIMasternodesetup
sudo chmod 755 /usr/bin/MTI*

# Deploy Masternode monitoring script
cp ~/MTIMasternodesetup/MTImon.sh /usr/local/bin
sudo chmod 711 /usr/local/bin/MTImon.sh

#Create datadir
if [ ! -f ~/.MTI/MTI.conf ]; then 
	sudo mkdir ~/.MTI
fi

echo -e "${YELLOW}Creating MTI.conf...${NC}"

# If genkey was not supplied in command line, we will generate private key on the fly
if [ -z $genkey ]; then
    cat <<EOF > ~/.MTI/MTI.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
EOF

    sudo chmod 755 -R ~/.MTI/MTI.conf

    #Starting daemon first time just to generate Masternode private key
    MTId -daemon
    delay 30

    #Generate Masternode private key
    echo -e "${YELLOW}Generating Masternode private key...${NC}"
    genkey=$(MTId masternode genkey)
    if [ -z "$genkey" ]; then
        echo -e "${RED}ERROR: Can not generate Masternode private key.${NC} \a"
        echo -e "${RED}ERROR:${YELLOW}Reboot VPS and try again or supply existing genkey as a parameter.${NC}"
        exit 1
    fi
    
    #Stopping daemon to create MTI.conf
    stop_daemon
    delay 30
fi

# Create MTI.conf
cat <<EOF > ~/.MTI/MTI.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
rpcallowip=127.0.0.1
onlynet=ipv4
listen=1
server=1
daemon=1
maxconnections=64
externalip=$publicip
Masternode=1
Masternodeprivkey=$genkey
EOF

#Finally, starting MTI daemon with new MTI.conf
MTId
delay 5

#Setting auto star cron job for MTId
cronjob="@reboot sleep 30 && MTId"
crontab -l > tempcron
if ! grep -q "$cronjob" tempcron; then
    echo -e "${GREEN}Configuring crontab job...${NC}"
    echo $cronjob >> tempcron
    crontab tempcron
fi
rm tempcron

echo -e "========================================================================
${YELLOW}Masternode setup is complete!${NC}
========================================================================
Masternode was installed with VPS IP Address: ${YELLOW}$publicip${NC}
Masternode Private Key: ${YELLOW}$genkey${NC}
Now you can add the following string to the Masternode.conf file
for your Hot Wallet (the wallet with your MTI collateral funds):
======================================================================== \a"
echo -e "${YELLOW}mn1 $publicip:$PORT $genkey TxId TxIdx${NC}"
echo -e "========================================================================
Use your mouse to copy the whole string above into the clipboard by
tripple-click + single-click (Dont use Ctrl-C) and then paste it 
into your ${YELLOW}Masternode.conf${NC} file and replace:
    ${YELLOW}mn1${NC} - with your desired Masternode name (alias)
    ${YELLOW}TxId${NC} - with Transaction Id from Masternode outputs
    ${YELLOW}TxIdx${NC} - with Transaction Index (0 or 1)
     Remember to save the Masternode.conf and restart the wallet!
To introduce your new Masternode to the MTI network, you need to
issue a Masternode start command from your wallet, which proves that
the collateral for this node is secured."

clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "1) Wait for the node wallet on this VPS to sync with the other nodes
on the network. Eventually the 'IsSynced' status will change
to 'true', which will indicate a comlete sync, although it may take
from several minutes to several hours depending on the network state.
Your initial Masternode Status may read:
    ${YELLOW}Node just started, not yet activated${NC} or
    ${YELLOW}Node  is not in Masternode list${NC}, which is normal and expected.
2) Wait at least until 'IsBlockchainSynced' status becomes 'true'.
At this point you can go to your wallet and issue a start
command by either using Debug Console:
    Tools->Debug Console-> enter: ${YELLOW}Masternode start-alias mn1${NC}
    where ${YELLOW}mn1${NC} is the name of your Masternode (alias)
    as it was entered in the Masternode.conf file
    
or by using wallet GUI:
    Masternodes -> Select Masternode -> RightClick -> ${YELLOW}start alias${NC}
Once completed step (2), return to this VPS console and wait for the
Masternode Status to change to: 'Masternode successfully started'.
This will indicate that your Masternode is fully functional and
you can celebrate this achievement!
Currently your Masternode is syncing with the MTI network...
The following screen will display in real-time
the list of peer connections, the status of your Masternode,
node synchronization status and additional network and node stats.
"
clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "
${GREEN}...scroll up to see previous screens...${NC}
Here are some useful commands and tools for Masternode troubleshooting:
========================================================================
To view Masternode configuration produced by this script in reden.conf:
${YELLOW}cat ~/.MTI/MTI.conf${NC}
Here is your MTI.conf generated by this script:
-------------------------------------------------${YELLOW}"
cat ~/.MTI/MTI.conf
echo -e "${NC}-------------------------------------------------
NOTE: To edit MTI.conf, first stop the redend daemon,
then edit the reden.conf file and save it in nano: (Ctrl-X + Y + Enter),
then start the redend daemon back up:
to stop:   ${YELLOW}MTId stop${NC}
to edit:   ${YELLOW}nano ~/.MTI/MTI.conf${NC}
to start:  ${YELLOW}MTId${NC}
========================================================================
To view MTId debug log showing all MN network activity in realtime:
${YELLOW}tail -f ~/.MTI/debug.log${NC}
========================================================================
To monitor system resource utilization and running processes:
${YELLOW}htop${NC}
========================================================================
To view the list of peer connections, status of your Masternode, 
sync status etc. in real-time, run the MTImon.sh script:
${YELLOW}MTImon.sh${NC}
or just type 'node' and hit <TAB> to autocomplete script name.
========================================================================
Enjoy your MTI Masternode and thanks for using this setup script!
If you found it helpful, please donate MTI to:
ofQzJU37B2a7G2EZ52qyhKjV6pAqJ3KYpp
...and make sure to check back for updates!
"
# Run MTImon.sh
MTImon.sh

# EOF