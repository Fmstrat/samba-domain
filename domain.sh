#!/usr/bin/env bash

if [ -z "${DOMAIN_DC}" ] || [ -z "${DOMAIN_EMAIL}" ]; then
	echo 'You must have env variables set of:
DOMAIN_DC="dc=corp,dc=example,dc=com"
DOMAIN_EMAIL="example.com"
'
	exit
fi

#--------------------------------------------

function usage() {
	echo '
Usage:
	domain info
	domain ldapinfo
	domain groups
	domain group <group>
	domain users
	domain user <user>
	domain create-group <group>
	domain delete-group <group>
	domain create-user <user>
	domain delete-user <user>
	domain change-password <user>
	domain edit <user or group>
	domain add-user-to-group <user> <group>
	domain remove-user-from-group <user> <group>
	domain update-ip <domain> <controller> <oldip> <newip>
';
}

case "${1}" in
	info)
		wbinfo -D CORP
		;;
	ldapinfo)
		ldapsearch -b "${DOMAIN_DC}"
		;;
	edit)
		ldbedit -H /var/lib/samba/private/sam.ldb "samaccountname=${2}"
		;;
	groups)
		wbinfo -g
		;;
	group)
		echo ""
		echo "Info"
		echo "----"
		wbinfo --group-info ${2}
		echo ""
		echo "Members"
		echo "-------"
		samba-tool group listmembers ${2}
		echo ""
		;;
	users)
		#samba-tool user list
		wbinfo -u
		;;
	user)
		echo ""
		echo "User:"
		echo "-----"
		wbinfo -i ${2}
		echo ""
		echo "Groups:"
		echo "-----"
		GL=$(wbinfo -r ${2} | sed 's/\r//g')
		for G in ${GL}; do
			wbinfo --gid-info ${G}
		done
		echo ""
		;;
	create-group)
		samba-tool group add ${2}
		;;
	delete-group)
		samba-tool group delete ${2}
		;;
	create-user)
		echo -n "Firstname: "
		read F
		echo -n "Lastname: "
		read L
		E="${2}@${DOMAIN_EMAIL}"
		samba-tool user create ${2} --surname ${L} --given-name ${F} --mail-address ${E}
		samba-tool user setexpiry ${2} --noexpiry
		;;
	delete-user)
		samba-tool user delete ${2}
		;;
	change-password)
		samba-tool user setpassword ${2}
		;;
	add-user-to-group)
		samba-tool group addmembers "${3}" "${2}"
		;;
	remove-user-from-group)
		samba-tool group removemembers "${3}" "${2}"
		;;
	update-ip)
		samba-tool dns update 127.0.0.1 ${2} ${3} A ${4} ${5} -U administrator
		samba-tool dns update 127.0.0.1 ${2} @ A ${4} ${5} -U administrator
		;;
	*)
		usage;
esac
