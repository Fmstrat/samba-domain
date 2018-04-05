# Samba Active Directory Domain Controller for Docker

A well documented, tried and tested Samba Active Directory Domain Controller that works with the standard Windows management tools; built from scratch using internal DNS and kerberos and not based on existing containers.

## Environment variables for quick start
* `DOMAIN` defaults to `SAMDOM.LOCAL` and should be set to your domain
* `DOMAINPASS` should be set to your administrator password, be it existing or new. This can be removed from the environment after the first setup run.
* `HOSTIP` can be set to the IP you want to advertise.
* `JOIN` defaults to `false` and means the container will provision a new domain. Set this to `true` to join an existing domain.
* `JOINSITE` is optional and can be set to a site name when joining a domain, otherwise the default site will be used.
* `DNSFORWARDER` is optional and if an IP such as `192.168.0.1` is supplied will forward all DNS requests samba can't resolve to that DNS server
* `INSECURELDAP` defaults to `false`. When set to true, it removes the secure LDAP requirement. While this is not recommended for production it is required for some LDAP tools. You can remove it later from the smb.conf file stored in the config directory.
* `MULTISITE` defaults to `false` and tells the container to connect to an OpenVPN site via an ovpn file with no password. For instance, if you have two locations where you run your domain controllers, they need to be able to interact. The VPN allows them to do that.
* `NOCOMPLEXITY` defaults to `false`. When set to `true` it removes password complexity requirements including `complexity, history-length, min-pwd-age, max-pwd-age`

## Volumes for quick start
* `/etc/localtime:/etc/localtime:ro` - Sets the timezone to match the host
* `/data/docker/containers/samba/data/:/var/lib/samba` - Stores samba data so the container can be moved to another host if required.
* `/data/docker/containers/samba/config/samba:/etc/samba/external` - Stores the smb.conf so the container can be mored or updates can be easily made.
* `/data/docker/containers/samba/config/openvpn/docker.ovpn:/docker.ovpn` - Optional for connecting to another site via openvpn.
* `/data/docker/containers/samba/config/openvpn/credentials:/credentials` - Optional for connecting to another site via openvpn that requires a username/password. The format for this file should be two lines, with the username on the first, and the password on the second. Also, make sure your ovpn file contains `auth-user-pass /credentials`

## Downloading and building
```
mkdir -p /data/docker/builds
cd /data/docker/builds
git clone https://github.com/Fmstrat/samba-domain.git
cd samba-domain
docker build -t samba-domain .
```

Or just use the HUB:

```
docker pull nowsci/samba-domain
```

## Setting things up for the container
To set things up you will first want a new IP on your host machine so that ports don't conflict. A domain controller needs a lot of ports, and will likely conflict with things like dnsmasq. The below commands will do this, and set up some required folders.

```
ifconfig eno1:1 192.168.3.222 netmask 255.255.255.0 up
mkdir -p /data/docker/containers/samba/data
mkdir -p /data/docker/containers/samba/config/samba
```

If you plan on using a multi-site VPN, also run:

```
mkdir -p /data/docker/containers/samba/config/openvpn
cp /path/to/my/ovpn/MYSITE.ovpn /data/docker/containers/samba/config/openvpn/docker.ovpn
```

## Things to keep in mind
* In some cases on Windows clients, you would join with the domain of SAMDOM, but when entering the computer domain you must enter SAMDOM.LOCAL. This seems to be the case when using most any samba based DC.
* Make sure your client's DNS is using the DC, or that your mail DNS is relaying for the domain
* Ensure client's are using samdom.local as the search suffix
* If you're using a VPN, pay close attention to routes. You don't want to force all traffic through the VPN


## Enabling file sharing
While the Samba team does not recommend using a DC as a file server, it's understandable that some may wish to. Once the container is up and running and your `/data/docker/containers/samba/config/samba/smb.conf` file is set up after the first run, you can enable shares by shutting down the container, and making the following changes to the `smb.conf` file.

In the `[global]` section, add:
```
        security = user
        passdb backend = ldapsam:ldap://localhost
        ldap suffix = dc=nowsci,dc=local
        ldap user suffix = ou=Users
        ldap group suffix = ou=Groups
        ldap machine suffix = ou=Computers
        ldap idmap suffix = ou=Idmap
        ldap admin dn = cn=Administrator,cn=Users,dc=samdom,dc=local
        ldap ssl = off
        ldap passwd sync = no
        server string = MYSERVERHOSTNAME
        wins support = yes
        preserve case = yes
        short preserve case = yes
        default case = lower
        case sensitive = auto
        preferred master = yes
        unix extensions = yes
        follow symlinks = yes
        client ntlmv2 auth = yes
        client lanman auth = yes
        mangled names = no
```
Then add a share to the end based on how you mount the volume:
```
[storage]
        comment = storage
        path = /storage
        public = no
        read only = no
        writable = yes
        write list = @root NOWSCI\myuser
        force user = root
        force group = root
        guest ok = yes
        valid users = NOWSCI\myuser
```
Check the samba documentation for how to allow groups/etc.


## Keeping things updated
The container is stateless, so you can do a `docker rmi samba-domain` and then restart the container to rebuild packages when a security update occurs. However, this puts load on servers that isn't always required, so below are some scripts that can help minimize things by letting you know when containers have security updates that are required.

This script loops through running containers and sends you an email when security updates are required.
```
#!/bin/bash


function needsUpdates() {
        RESULT=$(docker exec ${1} bash -c ' \
                if [[ -f /etc/apt/sources.list ]]; then \
                grep security /etc/apt/sources.list > /tmp/security.list; \
                apt-get update > /dev/null; \
                apt-get upgrade -oDir::Etc::Sourcelist=/tmp/security.list -s; \
                fi; \
                ')
        RESULT=$(echo $RESULT)
        GOODRESULT="Reading package lists... Building dependency tree... Reading state information... Calculating upgrade... 0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."
        if [[ "${RESULT}" != "" ]] && [[ "${RESULT}" != "${GOODRESULT}" ]]; then
                return 0
        else
                return 1
        fi
}

function sendEmail() {
        echo "Container ${1} needs security updates";
        H=`hostname`
        ssh -i /data/keys/<KEYFILE> <USRER>@<REMOTEHOST>.com "{ echo \"MAIL FROM: root@${H}\"; echo \"RCPT TO: <USER>@<EMAILHOST>.com\"; echo \"DATA\"; echo \"Subject: ${H} - ${1} container needs security update\"; echo \"\"; echo -e \"\n${1} container needs update.\n\n\"; echo -e \"docker exec ${1} bash -c 'grep security /etc/apt/sources.list > /tmp/security.list; apt-get update > /dev/null; apt-get upgrade -oDir::Etc::Sourcelist=/tmp/security.list -s'\n\n\"; echo \"Remove the -s to run the update\"; echo \"\"; echo \".\"; echo \"quit\"; sleep 1; } | telnet <SMTPHOST> 25"
}

CONTAINERS=$(docker ps --format "{{.Names}}")
for CONTAINER in $CONTAINERS; do
        echo "Checking ${CONTAINER}"
        if needsUpdates $CONTAINER; then
                sendEmail $CONTAINER
        fi
done
```

And the following script keeps track of when new images are posted to hub.docker.com.
```
#!/bin/bash

DATAPATH='/data/docker/updater/data'

if [ ! -d "${DATAPATH}" ]; then
        mkdir "${DATAPATH}";
fi
IMAGES=$(docker ps --format "{{.Image}}")
for IMAGE in $IMAGES; do
        ORIGIMAGE=${IMAGE}
        if [[ "$IMAGE" != *\/* ]]; then
                IMAGE=library/${IMAGE}
        fi
        IMAGE=${IMAGE%%:*}
        echo "Checking ${IMAGE}"
        PARSED=${IMAGE//\//.}
        if [ ! -f "${DATAPATH}/${PARSED}" ]; then
                # File doesn't exist yet, make baseline
                echo "Setting baseline for ${IMAGE}"
                curl -s "https://registry.hub.docker.com/v2/repositories/${IMAGE}/tags/" > "${DATAPATH}/${PARSED}"
        else
                # File does exist, do a compare
                NEW=$(curl -s "https://registry.hub.docker.com/v2/repositories/${IMAGE}/tags/")
                OLD=$(cat "${DATAPATH}/${PARSED}")
                if [[ "${OLD}" == "${NEW}" ]]; then
                        echo "Image ${IMAGE} is up to date";
                else
                        echo ${NEW} > "${DATAPATH}/${PARSED}"
                        echo "Image ${IMAGE} needs to be updated";
                        H=`hostname`
                        ssh -i /data/keys/<KEYFILE> <USER>@<REMOTEHOST>.com "{ echo \"MAIL FROM: root@${H}\"; echo \"RCPT TO: <USER>@<EMAILHOST>.com\"; echo \"DATA\"; echo \"Subject: ${H} - ${IMAGE} needs update\"; echo \"\"; echo -e \"\n${IMAGE} needs update.\n\ndocker pull ${ORIGIMAGE}\"; echo \"\"; echo \".\"; echo \"quit\"; sleep 1; } | telnet <SMTPHOST> 25"
                fi

        fi
done;
```

# Examples with docker run
Keep in mind, for all examples replace `nowsci/samba-domain` with `samba-domain` if you build your own from GitHub.

Start a new domain, and forward non-resolvable queries to the main DNS server
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local main DNS is running on `192.168.3.1`

```
docker run -t -i \
	-e "DOMAIN=SAMDOM.LOCAL" \
	-e "DOMAINPASS=ThisIsMyAdminPassword" \
	-e "DNSFORWARDER=192.168.3.1" \
	-e "HOSTIP=192.168.3.222" \
	-p 192.168.3.222:53:53 \
	-p 192.168.3.222:53:53/udp \
	-p 192.168.3.222:88:88 \
	-p 192.168.3.222:88:88/udp \
	-p 192.168.3.222:135:135 \
	-p 192.168.3.222:137-138:137-138/udp \
	-p 192.168.3.222:139:139 \
	-p 192.168.3.222:389:389 \
	-p 192.168.3.222:389:389/udp \
	-p 192.168.3.222:445:445 \
	-p 192.168.3.222:464:464 \
	-p 192.168.3.222:464:464/udp \
	-p 192.168.3.222:636:636 \
	-p 192.168.3.222:1024-1044:1024-1044 \
	-p 192.168.3.222:3268-3269:3268-3269 \
	-v /etc/localtime:/etc/localtime:ro \
	-v /data/docker/containers/samba/data/:/var/lib/samba \
	-v /data/docker/containers/samba/config/samba:/etc/samba/external \
	--dns-search samdom.local \
	--dns 192.168.3.222 \
	--dns 192.168.3.1 \
	--add-host localdc.samdom.local:192.168.3.222 \
	-h localdc \
	--name samba \
	--privileged \
	nowsci/samba-domain
```

Join an existing domain, and forward non-resolvable queries to the main DNS server
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local existing DC is running DNS and has IP of `192.168.3.201`
* Local main DNS is running on `192.168.3.1`

```
docker run -t -i \
	-e "DOMAIN=SAMDOM.LOCAL" \
	-e "DOMAINPASS=ThisIsMyAdminPassword" \
	-e "JOIN=true" \
	-e "DNSFORWARDER=192.168.3.1" \
	-p 192.168.3.222:53:53 \
	-p 192.168.3.222:53:53/udp \
	-p 192.168.3.222:88:88 \
	-p 192.168.3.222:88:88/udp \
	-p 192.168.3.222:135:135 \
	-p 192.168.3.222:137-138:137-138/udp \
	-p 192.168.3.222:139:139 \
	-p 192.168.3.222:389:389 \
	-p 192.168.3.222:389:389/udp \
	-p 192.168.3.222:445:445 \
	-p 192.168.3.222:464:464 \
	-p 192.168.3.222:464:464/udp \
	-p 192.168.3.222:636:636 \
	-p 192.168.3.222:1024-1044:1024-1044 \
	-p 192.168.3.222:3268-3269:3268-3269 \
	-v /etc/localtime:/etc/localtime:ro \
	-v /data/docker/containers/samba/data/:/var/lib/samba \
	-v /data/docker/containers/samba/config/samba:/etc/samba/external \
	--dns-search samdom.local \
	--dns 192.168.3.222 \
	--dns 192.168.3.1 \
	--dns 192.168.3.201 \
	--add-host localdc.samdom.local:192.168.3.222 \
	-h localdc \
	--name samba \
	--privileged \
	nowsci/samba-domain
```

Join an existing domain, forward DNS, remove security features, and connect to a remote site via openvpn
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local existing DC is running DNS and has IP of `192.168.3.201`
* Local main DNS is running on `192.168.3.1`
* Remote site is `192.168.6.0`
* Remote DC hostname is `REMOTEDC` with IP of `192.168.6.222` (notice the DNS and host entries)

```
docker run -t -i \
	-e "DOMAIN=SAMDOM.LOCAL" \
	-e "DOMAINPASS=ThisIsMyAdminPassword" \
	-e "JOIN=true" \
	-e "DNSFORWARDER=192.168.3.1" \
	-e "MULTISITE=true" \
	-e "NOCOMPLEXITY=true" \
	-e "INSECURELDAP=true" \
	-p 192.168.3.222:53:53 \
	-p 192.168.3.222:53:53/udp \
	-p 192.168.3.222:88:88 \
	-p 192.168.3.222:88:88/udp \
	-p 192.168.3.222:135:135 \
	-p 192.168.3.222:137-138:137-138/udp \
	-p 192.168.3.222:139:139 \
	-p 192.168.3.222:389:389 \
	-p 192.168.3.222:389:389/udp \
	-p 192.168.3.222:445:445 \
	-p 192.168.3.222:464:464 \
	-p 192.168.3.222:464:464/udp \
	-p 192.168.3.222:636:636 \
	-p 192.168.3.222:1024-1044:1024-1044 \
	-p 192.168.3.222:3268-3269:3268-3269 \
	-v /etc/localtime:/etc/localtime:ro \
	-v /data/docker/containers/samba/data/:/var/lib/samba \
	-v /data/docker/containers/samba/config/samba:/etc/samba/external \
	-v /data/docker/containers/samba/config/openvpn/docker.ovpn:/docker.ovpn \
	-v /data/docker/containers/samba/config/openvpn/credentials:/credentials \
	--dns-search samdom.local \
	--dns 192.168.3.222 \
	--dns 192.168.3.1 \
	--dns 192.168.6.222 \
	--dns 192.168.3.201 \
	--add-host localdc.samdom.local:192.168.3.222 \
	--add-host remotedc.samdom.local:192.168.6.222 \
	--add-host remotedc:192.168.6.222 \
	-h localdc \
	--name samba \
	--privileged \
	--cap-add=NET_ADMIN --device /dev/net/tun \
	nowsci/samba-domain
```


# Examples with docker compose

Keep in mind for all examples `DOMAINPASS` can be removed after the first run.

Start a new domain, and forward non-resolvable queries to the main DNS server
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local main DNS is running on `192.168.3.1`

```
version: '2'

networks:
  extnet:
    external: true

services:

# ----------- samba begin ----------- #

  samba:
    image: nowsci/samba-domain
    container_name: samba
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /data/docker/containers/samba/data/:/var/lib/samba
      - /data/docker/containers/samba/config/samba:/etc/samba/external
    environment:
      - DOMAIN=SAMDOM.LOCAL
      - DOMAINPASS=ThisIsMyAdminPassword
      - DNSFORWARDER=192.168.3.1
    networks:
      - extnet
    ports:
      - 192.168.3.222:53:53
      - 192.168.3.222:53:53/udp
      - 192.168.3.222:88:88
      - 192.168.3.222:88:88/udp
      - 192.168.3.222:135:135
      - 192.168.3.222:137-138:137-138/udp
      - 192.168.3.222:139:139
      - 192.168.3.222:389:389
      - 192.168.3.222:389:389/udp
      - 192.168.3.222:445:445
      - 192.168.3.222:464:464
      - 192.168.3.222:464:464/udp
      - 192.168.3.222:636:636
      - 192.168.3.222:1024-1044:1024-1044
      - 192.168.3.222:3268-3269:3268-3269
    dns_search:
      - samdom.local
    dns:
      - 192.168.3.222
      - 192.168.3.1
    extra_hosts:
      - localdc.samdom.local:192.168.3.222
    hostname: localdc
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    privileged: true
    restart: always

# ----------- samba end ----------- #
```

Join an existing domain, and forward non-resolvable queries to the main DNS server
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local existing DC is running DNS and has IP of `192.168.3.201`
* Local main DNS is running on `192.168.3.1`

```
version: '2'

networks:
  extnet:
    external: true

services:

# ----------- samba begin ----------- #

  samba:
    image: nowsci/samba-domain
    container_name: samba
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /data/docker/containers/samba/data/:/var/lib/samba
      - /data/docker/containers/samba/config/samba:/etc/samba/external
    environment:
      - DOMAIN=SAMDOM.LOCAL
      - DOMAINPASS=ThisIsMyAdminPassword
      - JOIN=true
      - DNSFORWARDER=192.168.3.1
    networks:
      - extnet
    ports:
      - 192.168.3.222:53:53
      - 192.168.3.222:53:53/udp
      - 192.168.3.222:88:88
      - 192.168.3.222:88:88/udp
      - 192.168.3.222:135:135
      - 192.168.3.222:137-138:137-138/udp
      - 192.168.3.222:139:139
      - 192.168.3.222:389:389
      - 192.168.3.222:389:389/udp
      - 192.168.3.222:445:445
      - 192.168.3.222:464:464
      - 192.168.3.222:464:464/udp
      - 192.168.3.222:636:636
      - 192.168.3.222:1024-1044:1024-1044
      - 192.168.3.222:3268-3269:3268-3269
    dns_search:
      - samdom.local
    dns:
      - 192.168.3.222
      - 192.168.3.1
      - 192.168.3.201
    extra_hosts:
      - localdc.samdom.local:192.168.3.222
    hostname: localdc
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    privileged: true
    restart: always

# ----------- samba end ----------- #
```

Join an existing domain, forward DNS, remove security features, and connect to a remote site via openvpn
* Local site is `192.168.3.0`
* Local DC (this one) hostname is `LOCALDC` using the host IP of `192.168.3.222`
* Local existing DC is running DNS and has IP of `192.168.3.201`
* Local main DNS is running on `192.168.3.1`
* Remote site is `192.168.6.0`
* Remote DC hostname is `REMOTEDC` with IP of `192.168.6.222` (notice the DNS and host entries)

```
version: '2'

networks:
  extnet:
    external: true

services:

# ----------- samba begin ----------- #

  samba:
    image: nowsci/samba-domain
    container_name: samba
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /data/docker/containers/samba/data/:/var/lib/samba
      - /data/docker/containers/samba/config/samba:/etc/samba/external
      - /data/docker/containers/samba/config/openvpn/docker.ovpn:/docker.ovpn
      - /data/docker/containers/samba/config/openvpn/credentials:/credentials
    environment:
      - DOMAIN=SAMDOM.LOCAL
      - DOMAINPASS=ThisIsMyAdminPassword
      - JOIN=true
      - DNSFORWARDER=192.168.3.1
      - MULTISITE=true
      - NOCOMPLEXITY=true
      - INSECURELDAP=true
    networks:
      - extnet
    ports:
      - 192.168.3.222:53:53
      - 192.168.3.222:53:53/udp
      - 192.168.3.222:88:88
      - 192.168.3.222:88:88/udp
      - 192.168.3.222:135:135
      - 192.168.3.222:137-138:137-138/udp
      - 192.168.3.222:139:139
      - 192.168.3.222:389:389
      - 192.168.3.222:389:389/udp
      - 192.168.3.222:445:445
      - 192.168.3.222:464:464
      - 192.168.3.222:464:464/udp
      - 192.168.3.222:636:636
      - 192.168.3.222:1024-1044:1024-1044
      - 192.168.3.222:3268-3269:3268-3269
    dns_search:
      - samdom.local
    dns:
      - 192.168.3.222
      - 192.168.3.1
      - 192.168.6.222
      - 192.168.3.201
    extra_hosts:
      - localdc.samdom.local:192.168.3.222
      - remotedc.samdom.local:192.168.6.222
      - remotedc:192.168.6.222
    hostname: localdc
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    privileged: true
    restart: always

# ----------- samba end ----------- #
```

## Troubleshooting

The most common issue is when running multi-site and seeing the below DNS replication error when checking replication with `docker exec samba samba-tool drs showrepl`

```
CN=Schema,CN=Configuration,DC=samdom,DC=local
        Default-First-Site-Name\REMOTEDC via RPC
                DSA object GUID: faf297a8-6cd3-4162-b204-1945e4ed5569
                Last attempt @ Thu Jun 29 10:49:45 2017 EDT failed, result 2 (WERR_BADFILE)
                4 consecutive failure(s).
                Last success @ NTTIME(0)
```
This has nothing to do with docker, but does happen in samba setups. The key is to put the GUID host entry into the start script for docker, and restart the container. For instance, if you saw the above error, Add this to you docker command:
```
--add-host faf297a8-6cd3-4162-b204-1945e4ed5569._msdcs.samdom.local:192.168.6.222 \
```
Where `192.168.6.222` is the IP of `REMOTEDC`. You could also do this in `extra_hosts` in docker-compose.
