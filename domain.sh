#!/usr/bin/env bash

if [ -z "${DOMAIN_DC}" ] || [ -z "${DOMAIN_EMAIL}" ]; then
	echo 'You must have env variables set of:
DOMAIN_DC="dc=corp,dc=example,dc=com"
DOMAIN_EMAIL="example.com"
'
	exit
fi

#--------------------------------------------

ST="samba-tool"
WI="wbinfo"
LD="ldapsearch"

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
	domain add-user-to-group <user> <group>
	domain remove-user-from-group <user> <group>
	domain update-ip <domain> <controller> <oldip> <newip>
';
}

case "${1}" in
	info)
		${WI} -D CORP
		;;
	ldapinfo)
		${LD} -b "${DOMAIN_DC}"
		;;
	groups)
		${WI} -g
		;;
	group)
		echo ""
		echo "Info"
		echo "----"
		${WI} --group-info ${2}
		echo ""
		echo "Members"
		echo "-------"
		${ST} group listmembers ${2}
		echo ""
		;;
	users)
		#${ST} user list
		${WI} -u
		;;
	user)
		echo ""
		echo "User:"
		echo "-----"
		${WI} -i ${2}
		echo ""
		echo "Groups:"
		echo "-----"
		GL=$(${WI} -r ${2} | sed 's/\r//g')
		for G in ${GL}; do
			${WI} --gid-info ${G}
		done
		echo ""
		;;
	create-group)
		${ST} group add ${2}
		;;
	delete-group)
		${ST} group delete ${2}
		;;
	create-user)
		echo -n "Firstname: "
		read F
		echo -n "Lastname: "
		read L
		E="${2}@${DOMAIN_EMAIL}"
		${ST} user create ${2} --surname ${L} --given-name ${F} --mail-address ${E}
		${ST} user setexpiry ${2} --noexpiry
		;;
	delete-user)
		${ST} user delete ${2}
		;;
	change-password)
		${ST} user setpassword ${2}
		;;
	add-user-to-group)
		${ST} group addmembers "${3}" "${2}"
		;;
	remove-user-from-group)
		${ST} group removemembers "${3}" "${2}"
		;;
	update-ip)
		${ST} dns update 127.0.0.1 ${2} ${3} A ${4} ${5} -U administrator
		${ST} dns update 127.0.0.1 ${2} @ A ${4} ${5} -U administrator
		;;
	*)
		usage;
esac
