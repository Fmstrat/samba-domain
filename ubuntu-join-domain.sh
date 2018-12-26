#!/bin/bash

# Configure here
# ======================================
HOSTNAME=VirtualUbuntu
DOMAIN=corp.example.com
COMPUTEROU="DC=corp,DC=example,DC=com"
PROVISIONINGUSER=administrator
OSNAME="Ubuntu Workstation"
OSVERSION=18.04
SUDOUSERS="user1 administrator"
USEDOMAININHOMEDIR="False"
# ======================================

UP_DOMAIN=${DOMAIN^^}
LO_DOMAIN=${DOMAIN,,}

echo "Setting hostnames..."
hostnamectl set-hostname ${HOSTNAME}

DEBIAN_FRONTEND=noninteractive apt install -y realmd sssd sssd-tools libnss-sss libpam-sss krb5-user adcli samba-common-bin

echo "" > /etc/krb5.conf
echo "[libdefaults]" >> /etc/krb5.conf
echo "	default_realm = ${UP_DOMAIN}" >> /etc/krb5.conf
echo "	kdc_timesync = 1" >> /etc/krb5.conf
echo "	ccache_type = 4" >> /etc/krb5.conf
echo "	forwardable = true" >> /etc/krb5.conf
echo "	proxiable = true" >> /etc/krb5.conf
echo "	fcc-mit-ticketflags = true" >> /etc/krb5.conf
echo "" >> /etc/krb5.conf
echo "[realms]" >> /etc/krb5.conf

echo " " >> /etc/realmd.conf
echo "[active-directory]" >> /etc/realmd.conf
echo " default-client = sssd" >> /etc/realmd.conf
echo " os-name = ${OSNAME}" >> /etc/realmd.conf
echo " os-version = ${OSVERSION}" >> /etc/realmd.conf
echo " " >> /etc/realmd.conf
echo "[service]" >> /etc/realmd.conf
echo " automatic-install = no" >> /etc/realmd.conf
echo " " >> /etc/realmd.conf
echo "[${UP_DOMAIN}]" >> /etc/realmd.conf
echo " fully-qualified-names = yes" >> /etc/realmd.conf
echo " automatic-id-mapping = no" >> /etc/realmd.conf
echo " user-principal = yes" >> /etc/realmd.conf
echo " manage-system = yes" >> /etc/realmd.conf

echo "Now, check off the box for auto-create home directory in the next configuration screen."
echo -n "Press enter to continue..."
read E
pam-auth-update

echo "Time to test..."
echo "Discovering..."
realm discover ${UP_DOMAIN}
echo "Testing admin connection..."
kinit ${PROVISIONINGUSER}
klist
kdestroy 

echo ""
echo -n "If the above test didn't error, press ENTER to join the domain."
read E

echo ""
echo "Joining domain"
realm join --verbose --user=${PROVISIONINGUSER} --computer-ou=${COMPUTEROU} ${UP_DOMAIN}

echo "Configuring SSSD..."
echo "[sssd]" > /etc/sssd/sssd.conf
echo "domains = ${LO_DOMAIN}" >> /etc/sssd/sssd.conf
echo "config_file_version = 2" >> /etc/sssd/sssd.conf
echo "services = nss, pam" >> /etc/sssd/sssd.conf
echo "" >> /etc/sssd/sssd.conf
echo "[domain/${LO_DOMAIN}]" >> /etc/sssd/sssd.conf
echo "ad_domain = ${LO_DOMAIN}" >> /etc/sssd/sssd.conf
echo "krb5_realm = ${UP_DOMAIN}" >> /etc/sssd/sssd.conf
echo "realmd_tags = manages-system joined-with-adcli" >> /etc/sssd/sssd.conf
echo "cache_credentials = True" >> /etc/sssd/sssd.conf
echo "id_provider = ad" >> /etc/sssd/sssd.conf
echo "krb5_store_password_if_offline = True" >> /etc/sssd/sssd.conf
echo "default_shell = /bin/bash" >> /etc/sssd/sssd.conf
echo "ldap_id_mapping = True" >> /etc/sssd/sssd.conf
if [ $USEDOMAININHOMEDIR == "False" ]; then
	echo "fallback_homedir = /home/%u" >> /etc/sssd/sssd.conf
else
	echo "fallback_homedir = /home/%d/%u" >> /etc/sssd/sssd.conf
fi
echo "access_provider = ad" >> /etc/sssd/sssd.conf

echo "Allowing users to log in"
realm permit --all

if [ $USEDOMAININHOMEDIR == "True" ]; then
	echo "Now, enter '/home/${LO_DOMAIN}/' with the trailing slash in the next configuration screen."
	echo -n "Press enter to continue..."
	read E
	dpkg-reconfigure apparmor
fi

echo "Adding domain users to sudoers..."
for U in $SUDOUSERS; do
	echo "Adding ${UP_DOMAIN}\\${U}..."
	sed -i "s/# User privilege specification/# User privilege specification\n${U} ALL=(ALL) ALL/g" /etc/sudoers
done

echo "All done! Time to reboot!"
