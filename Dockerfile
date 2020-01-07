FROM ubuntu:18.04

LABEL maintainer="Fmstrat <fmstrat@NOSPAM.NO>"

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
    && apt-get upgrade -y \
    # Install all required packages \
    && apt-get install -y pkg-config attr acl samba smbclient ldap-utils winbind libnss-winbind libpam-winbind krb5-user krb5-kdc supervisor \
    # line below is for multi-site config (ping is for testing later) \
    && apt-get install -y openvpn inetutils-ping \
    # Set up script \
    && chmod 755 /init.sh \
    # cleanup \
    && apt-get clean autoclean \
    && apt-get autoremove --yes \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/ \
    && rm -fr /tmp/* /var/tmp/*

COPY init.sh /init.sh

CMD /init.sh setup
