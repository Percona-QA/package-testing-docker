#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# Use with care. See below.
# Quick cleanup of the server: 1) remove all /dev/shm/ packaging test directories, 2) remove all Docker images with name "none", 3) remove all Docker containers

if [ "$1" != "DEL" ]; then
  echo "Assert: for safety purposes, this script requires a special argument, check the script to find it."
  echo "IMPORTANT WARNING: Use this script with care; it deletes directories in /dev/shm AND it kill -9's all running Docker containers AND it deletes certain Docker Images AND it deletes ALL Docker containers, and most of these commands are furthermore executed using sudo. See actual code inside script. Run only if you know what you are doing. This script is meant for automated packaging testing servers only (on which it's use should be much safer). Terminating."
  exit 1
else
  # Stop all running Docker containers
  sudo docker kill $(sudo docker ps -a -q | tr '\n' ' ') 2>/dev/null

  # Remove all /dev/shm/ packaging test directories
  ls /dev/shm/*/packaging-test.log 2>/dev/null | sed 's|packaging-test.log||' | grep "/dev/shm/" | xargs -I{} rm -Rfv {}

  # Remove all Docker images with name "none"
  sudo docker images | grep ".none." | awk '{print $3}' | xargs -I_ sudo docker rmi -f _

  # Remove all Docker containers
  sudo docker ps -a | awk '{print $1}' | grep -v "CONTAINER" | xargs -I{} sh -c 'echo -n "Deleting container: ";sudo docker rm -f {}'
fi
