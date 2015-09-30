#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# Pull all relevant docker images. "Always latest" means it is known that the tag used will always obtain the latest version available
# This script pulls images via 3 threads simultaneouslty. It can also be used to update images once they are already present on the system
# Not covered here yet: RHEL5, RHEL6 Current Stable
# All images x64. 32bit: docker 3rd party images to checkout: https://github.com/docker-32bit | https://github.com/docker-32bit/ubuntu

# number of concurrent image pulls
CONCURRENCY=3

cat << EOC |
centos:centos5  # Centos 5. Always latest
centos:centos6  # Centos 6. Always latest (6.6+)
centos:centos7  # Centos 7. Always latest
oraclelinux:6   # Oracle Linux 6. Always latest
oraclelinux:7   # Oracle Linux 7. Always latest
opensuse:latest # Open Suse. Always latest
fedora:20       # Fedora 20. Always latest
fedora:21       # Fedora 21. Always latest
ubuntu:12.04    # Ubuntu 12.04 LTS - precise
ubuntu:14.04    # Ubuntu 14.04 LTS - trusty
ubuntu:14.10    # Ubuntu 14.10 LTS - utopic
ubuntu:15.04    # Ubuntu 15.04 LTS - vivid - (Current Stable)
debian:6        # Debian 6 - squeeze - Always latest
debian:7        # Debian 7 - wheezy - Always latest
debian:8        # Debian 8 - jessie 
EOC
xargs -d"\n" -P${CONCURRENCY} -i^ sudo sh -c 'docker pull ^'

