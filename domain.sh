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
	domain set-user-ssh-key <user> <pubkey>
	domain set-user-photo-from-file <user> <"$(base64 -w0 /path/to/img)>">
	domain set-user-photo-from-url <user> <url>
	domain add-user-to-group <user> <group>
	domain remove-user-from-group <user> <group>
	domain update-ip <domain> <controller> <oldip> <newip>
	domain flush-cache
	domain reload-config
	domain db-check-and-fix
';
}

case "${1}" in
	info)
		wbinfo -D "$(wbinfo --own-domain)"
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
		wbinfo --group-info "${2}"
		echo ""
		echo "Members"
		echo "-------"
		samba-tool group listmembers "${2}"
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
		wbinfo -i "${2}"
		echo ""
		echo "Groups:"
		echo "-----"
		GL=$(wbinfo -r "${2}" | sed 's/\r//g')
		for G in ${GL}; do
			wbinfo --gid-info "${G}"
		done
		echo ""
		;;
	create-group)
		samba-tool group add "${2}"
		;;
	delete-group)
		samba-tool group delete "${2}"
		;;
	create-user)
		echo -n "Firstname: "
		read F
		echo -n "Lastname: "
		read L
		E="${2}@${DOMAIN_EMAIL}"
		samba-tool user create "${2}" --surname "${L}" --given-name "${F}" --mail-address "${E}"
		samba-tool user setexpiry "${2}" --noexpiry
		;;
	delete-user)
		samba-tool user delete "${2}"
		;;
	change-password)
		samba-tool user setpassword "${2}"
		;;
	add-user-to-group)
		samba-tool group addmembers "${3}" "${2}" --object-types=user
		;;
	remove-user-from-group)
		samba-tool group removemembers "${3}" "${2}" --object-types=user
		;;
	update-ip)
		samba-tool dns update 127.0.0.1 ${2} ${3} A ${4} ${5} -U administrator
		samba-tool dns update 127.0.0.1 ${2} @ A ${4} ${5} -U administrator
		;;
	flush-cache)
		net cache flush
		;;
	reload-config)
		if [ -f /etc/samba/external/smb.conf ]; then
			cp -f /etc/samba/external/smb.conf /etc/samba/smb.conf
		fi
		net cache flush
		;;
	db-check-and-fix)
		samba-tool dbcheck --cross-ncs --fix --yes
		;;
	set-user-ssh-key)
		DN=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | grep ^dn: |sed 's/^dn: //g')
		CURKEY=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | { grep ^sshPublicKey: || true; })
		if [ -z "${CURKEY}" ]; then
			MOD="dn: ${DN}
changetype: modify
add: objectClass
objectClass: ldapPublicKey"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
			MOD="dn: ${DN}
changetype: modify
add: sshPublicKey
sshPublicKey: ${3}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		else
			MOD="dn: ${DN}
changetype: modify
replace: sshPublicKey
sshPublicKey: ${3}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		fi
		;;
	set-user-photo-from-file)
		DN=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | grep ^dn: |sed 's/^dn: //g')
		CURPHOTO=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | { grep ^jpegPhoto: || true; })
		if [ -z "${CURPHOTO}" ]; then
			MOD="dn: ${DN}
changetype: modify
add: jpegPhoto
jpegPhoto::${3}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		else
			MOD="dn: ${DN}
changetype: modify
replace: jpegPhoto
jpegPhoto::${3}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		fi
		;;
	set-user-photo-from-url)
		DN=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | grep ^dn: |sed 's/^dn: //g')
		CURPHOTO=$(ldbedit -H /var/lib/samba/private/sam.ldb -e cat "samaccountname=${2}" | { grep ^jpegPhoto: || true; })
		B64=$(curl -s "${3}" |base64 -w0)
		if [ -z "${CURPHOTO}" ]; then
			MOD="dn: ${DN}
changetype: modify
add: jpegPhoto
jpegPhoto::${B64}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		else
			MOD="dn: ${DN}
changetype: modify
replace: jpegPhoto
jpegPhoto::${B64}"
			echo "${MOD}" | ldbmodify -H /var/lib/samba/private/sam.ldb
		fi
		;;
	*)
		usage;
esac
