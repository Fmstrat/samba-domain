FROM arm32v7/ubuntu

LABEL maintainer="Fmstrat <fmstrat@NOSPAM.NO>"

ENV DEBIAN_FRONTEND noninteractive

# Install all apps
# The second "apt-get install" is for multi-site config (ping is for testing later)
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
        pkg-config \
        attr \
        acl \
        samba \
        smbclient \
        ldap-utils \
        winbind \
        libnss-winbind \
        libpam-winbind \
        krb5-user \
        krb5-kdc \
        supervisor \
    && apt-get install -y openvpn inetutils-ping \
    && apt-get clean autoclean \
    && apt-get autoremove --yes \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/ \
    && rm -fr /tmp/* /var/tmp/*

# Set up script and run
COPY init.sh /init.sh
RUN chmod 755 /init.sh

CMD /init.sh setup
