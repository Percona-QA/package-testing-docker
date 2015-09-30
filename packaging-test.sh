#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# Tests packaging across various supported OS distributions

# User Variables
# <none>

# Internal Variables 
SCRIPT_PWD=$(cd `dirname $0` && pwd)  # percona-qa/packaging-testing/
ISSUE_COUNT=0  # Counts the number of issues seen
ERROR_STATE=0  # Set to 1 as soon as an error is encountered, remains one until next OS is being tested
ISSUE_LOG=""   # Keeps track of all issues seen

# Redefine the '!' bash history command (ref https://www.gnu.org/software/bash/manual/html_node/History-Interaction.html & percona-qa/handy_gnu.txt)
histchars=

# Output functions (screen+file)
echoit(){ # $1: output text. $2: 1||not present||anything else: standard output, 2: standard, but no newlines, 3: no date/time, 4: no date/time + no newlines, 5: Error
  case ${2} in 
    2) echo -n "[$(date +'%T')] $(if [ "${IMAGE}" != "" ]; then echo "[${IMAGE}] "; fi)${1}"
       echo -n "[$(date +'%T')] ${1}" >>${LOG};;
    3) echo "${1}"
       echo "${1}" >>${LOG};;
    4) echo -n "${1}"
       echo -n "${1}" >>${LOG};;
    5) echo "[$(date +'%T')] [ERROR] ${1} Check log file @ ${LOG}"
       echo "[$(date +'%T')] [ERROR] ${1} Check output above" >> ${LOG}
       ISSUE_COUNT=$[ ${ISSUE_COUNT} + 1 ]
       ERROR_STATE=1
       ISSUE_LOG="$ISSUE_LOG | ${IMAGE}:${1}";;
    *) echo "[$(date +'%T')] ${1}"  # "*" includes "1"
       echo "[$(date +'%T')] ${1}" >>${LOG};;
  esac
}

# ==== Main script ====

# Work directory/log file creation
RANDOMD=""
while [ -d /dev/shm/${RANDOMD} ]; do
  RANDOMD=$(echo ${RANDOM}${RANDOM}${RANDOM} | sed 's/..\(......\).*/\1/')  # Random number generator (6 digits)
done
WORKDIR=/dev/shm/${RANDOMD}
mkdir ${WORKDIR}
LOG=${WORKDIR}/packaging-test.log
touch ${LOG} 2>&1
if [ ! -r ${LOG} ]; then
  echo "Assert: ${LOG} does not exist after creation attempt. Terminating"
  exit 1
fi
echoit "Workdir: ${WORKDIR} | Logfile: ${LOG}"
echoit "[ContainerID] Info: ContainerID's relevant to the message displayed are shown as at the start of this line"

# Ctrl+c/SIGINT trap (can only be done once workdir exists)
ctrl-c(){
  echoit "CTRL+C Was pressed. Attempting to terminate running processes."
  KILL_PIDS=`ps -ef | grep "$RANDOMD" | grep -v "grep" | awk '{print $2}' | tr '\n' ' '`
  if [ "${KILL_PIDS}" != "" ]; then
    echoit "Terminating following PID's: ${KILL_PIDS}"
    kill -9 ${KILL_PIDS} 2>&1 | tee -a ${LOG}
  else
    echoit "OK: No processes to terminate"
  fi
  echoit "Removing work directory"
  rm -Rf ${WORKDIR} 2>&1 | tee -a ${LOG}
  echoit "Done. Terminating pquery-run.sh with exit code 2"
  exit 2
}
trap ctrl-c SIGINT

# Ensure we can use sudo
echoit "Verifying we can use sudo on this machine: " 2
if [ "`sudo whoami`" == "root" ]; then
  echoit "OK" 3
else
  echoit "Assert: user `whoami` is not able to use sudo (or sudo is not installed), which is a requirement for this script. Removing work directory and terminating."
  rm -Rf ${WORKDIR}
  exit 1
fi

# Ensure the docker daemon is running
echoit "Verifying Docker daemon is running on this machine: " 2
sudo docker info 2>&1 | if egrep -qi "Images"; then
  echoit "OK" 3
else
  echoit "NOK" 3
  echoit "Docker deamon not running. Attempting to start it. " 2
  sudo service docker start 2>&1 | tee -a ${LOG} | grep -v ".*"
  sleep 5; sync  # Sleep/sync is not strictly necessary
  sudo docker info 2>&1 | if egrep -qi "Images"; then
    echoit "STARTED" 3
  else
    echoit "NOK" 3
    echoit "Assert: Docker deamon not running after startup attempt. Removing work directory and terminating."
    rm -Rf ${WORKDIR}
    exit 1
  fi
fi

# Check and log Docker version + log other relevant system info
echoit "Docker version: `sudo docker --version`"
DOCKER_MAJOR_VERSION=`sudo docker version | grep "Client version" | sed 's|[[:alpha:]||g;s|[ :\.]||g;s|^\(..\).*|\1|'` # Parse first two digits out of version
if [ ${DOCKER_MAJOR_VERSION} -lt 14 ]; then
  echoit "Assert: we detected docker (major) version `echo ${DOCKER_MAJOR_VERSION} | sed 's|\(.\)|\1.|'`, but the minimum version required is 1.4. Removing work directory and terminating."
  echoit "Upgrade: sudo service docker stop;sudo wget https://get.docker.com/builds/Linux/x86_64/docker-latest -O /usr/bin/docker;sudo service docker start"
  rm -Rf ${WORKDIR}
  exit 1
fi
echoit "Logging detailed Docker version info and other relevant system info to the log: " 2
echo "" >>${LOG}  # Newline in log required for readability purposes only
sudo docker version >>${LOG} 2>&1
sudo docker info >>${LOG} 2>&1
echoit "DONE" 3

pull_update_os_images(){
  # Pull or update Docker OS distribution images
  echoit "Pulling and/or updating all Docker OS distribution images using pull-docker-os-images.sh"
  ${SCRIPT_PWD}/pull-docker-os-images.sh 2>&1 | tee -a ${LOG} | egrep -v ": Already exists$|: Download complete$|: The image you are pulling has been verified$|Pulling dependent layers$|Pulling.*ubuntu"  # The packaging-test.log has the full output
}

validate_image(){  # $1: name of Docker OS image to be validated for presence, for example "centos:centos5"
  echoit "Validating presence of image ${1} " 2
  sudo docker images | if egrep -qi "`echo ${1} | sed 's|:|[ \\t]*|'`"; then
    echoit "OK" 3
  else
    echoit "Assert: Docker OS distribution image ${1} is not present (yet we tried to pull/update it using ${SCRIPT_PWD}/pull-docker-os-images.sh above). Check 'sudo docker images' list. Removing work directory and terminating"
    rm -Rf ${WORKDIR}
    exit 1
  fi
}

validate_images(){
  # Validate Docker OS distribution images are present...
  echoit "Validating presence of Docker OS distribution images"
  validate_image "centos:centos5"
  validate_image "centos:centos6"
  validate_image "centos:centos7"
  validate_image "oraclelinux:6"
  validate_image "oraclelinux:7"
  validate_image "fedora:20"
  validate_image "fedora:21"
  validate_image "opensuse:latest"
  validate_image "ubuntu:12.04"
  validate_image "ubuntu:14.04"
  validate_image "ubuntu:14.10"
  validate_image "ubuntu:15.04"
  validate_image "debian:6"
  validate_image "debian:7"
  validate_image "debian:8"
}

# Global variables that work accross functions (single threaded execution)
# ${CONTAINER} / ${IMAGE} / ${CMD} / ${SKIP_ERROR} (skip this trial if an error occured with Docker)

short_id(){  # Prints the shortened version of a Docker image or container ID
  printf "%.12s" ${1}
}

setup_container(){ # This procedure is used for setting up 1) an original container (which will promoted to an image which has the base OS + the basics 
  # installed, aptly named pkgtest:OS, for example pkgtest:centos_centos5), based on a [official] OS image, and 2) a container spinned off the image created
  # in (1) which will be used for installing a Percona product onto and/or all types of testing against that product. The process lifecycle is thus;
  # base OS image (centos:centos5) > container with basics (ref setup_base_image) (some container ID) > promoted to image (pkgtest:centos_centos5) > 
  # subsequent container (some container ID) used for testing. The lifespan of the first image (base OS image) is as long as the official distro maintainer
  # leaves it in place, the lifespan of the (first) container with basics is very short (only used to create new image), the lifespan of the pkgtest image
  # is as long as there are products being tested against that OS (image is dropped once all products were tested against that OS), and finally the lifespan
  # of the testing containers is either short (single test quick container spin/drop) or medium (used for installing a product + subsequently testing it)
  CONTAINER=;TMP_FILENAME=;SKIP_ERROR=0;
  # Start a Docker container, in daemon mode, writing the container ID to /tmp/${1} (for example /tmp/centos:centos5), and start a sleep as the primary process
  # The sleep is basically there to keep the container "running" while we execute various commands against it using exec
  sudo rm -f /tmp/${1}
  if [ "${IMAGE}" == "" ]; then
    echoit "Starting new container based on OS image ${1}, in order to create a new (temporary) packaging testing base image for this OS"
  else
    BASE_IMAGE_ID=$(sudo docker images | grep "$(echo ${1}|sed 's|:|[ \t]*|')" | awk '{print $3}')
    echoit "Starting new container based on packaging testing base image ${1} [$(short_id ${BASE_IMAGE_ID})], in order to execute actual testing"
  fi
  sudo docker run --cidfile /tmp/${1} ${1} /bin/sleep $(( 60 * 20 )) &  # 20 minutes (safety mechanism; works like 'timeout')
  for i in {1..10}; do  # Wait a maximum of 10 seconds for the container to be created
    CONTAINER=$(cat /tmp/${1} 2>/dev/null)
    TMP_FILENAME=/tmp/${1}
    if [ "${CONTAINER}" != "" ]; then
      break
    fi
    sleep 1
  done
  sync; sleep 3; sync;  # WORKAROUND for "Error getting container ... from driver devicemapper: Error mounting ... no such file or directory" (Docker #4036)
  if [ "${CONTAINER}" == "" ]; then
    echoit "" 3
    echoit "Error: we attempted to start a container based on OS image ${1}, but no container ID was returned by the Docker run command"
    SKIP_ERROR=1
  else
    echoit "[$(short_id ${CONTAINER})] New Container"
    CMD="sudo docker exec ${CONTAINER}"
    CMDI="sudo docker exec -i ${CONTAINER}"
  fi
}

stop_container(){
  container_check;
  echoit "[$(short_id ${CONTAINER})] Stop Container"
  sudo docker stop --time=2 ${CONTAINER} >>${LOG} 2>&1
  sync; sleep 2; sync;  # Ensure the container is stopped properly
}

drop_container(){
  container_check;
  echoit "[$(short_id ${CONTAINER})] Drop Container"
  sudo docker rm -f ${CONTAINER} >>${LOG} 2>&1
  sudo rm -f ${TMP_FILENAME}
  sync; sleep 1; sync;  # Ensure the container is gone
  CONTAINER=;CMD=;CMDI=;
}

drop_base_image(){
  echoit "[$(short_id ${BASE_IMAGE_ID})] Drop Base Image ${IMAGE}"
  sudo docker rmi -f ${IMAGE} >>${LOG} 2>&1
  sync; sleep 1; sync;  # Ensure the image is gone
  IMAGE=;BASE_IMAGE_ID=;CMD=;CMDI=;ERROR_STATE=0;
}

setup_base_image(){  # Creates an image, using a container branched off from a base OS image, with the basic necessities (but no products) installed
  CMD=;CMDI=;IMAGE=;
  setup_container "${1}"  # Create a container, based on an OS image, for example centos:centos7
  if [ ${SKIP_ERROR} -eq 0 ]; then
    cmd_check
    echoit "[$(short_id ${CONTAINER})] Installing required utilities"
    ${CMD} yum install -y which wget >>${LOG} 2>&1
    cat ${SCRIPT_PWD}/../pxc-pquery/new/ldd_files.sh | ${CMDI} sh -c 'cat > /usr/bin/ldd_files.sh' >>${LOG} 2>&1
    ${CMD} chmod 755 /usr/bin/ldd_files.sh >>${LOG} 2>&1
    echoit "[$(short_id ${CONTAINER})] Configuring coredump/kernel settings"
    ${CMD} sh -c 'echo "kernel.core_pattern=core.%p.%u.%g.%s.%t.%e.DOCKER" >> /etc/sysctl.conf' >>${LOG} 2>&1
    ${CMD} sh -c 'echo "fs.suid_dumpable=1" >> /etc/sysctl.conf' >>${LOG} 2>&1
    ${CMD} sh -c 'echo "fs.aio-max-nr=300000" >> /etc/sysctl.conf' >>${LOG} 2>&1
    ${CMD} sh -c 'echo "* soft core unlimited" >> /etc/security/limits.conf' >>${LOG} 2>&1
    ${CMD} sh -c 'echo "* hard core unlimited" >> /etc/security/limits.conf' >>${LOG} 2>&1
    stop_container
    IMAGE="pkgtest:$(echo ${1} | sed 's|:|_|')"
    image_check
    container_check
    echoit "[$(short_id ${CONTAINER})] Creating packaging testing base image ${IMAGE} based on current container"
    sudo docker commit --author="packaging-test.sh" --message="${1} Packaging Testing Base Image" ${CONTAINER} ${IMAGE} >>${LOG} 2>&1
    sync; sleep 2; sync;  # Ensure commit is complete
    drop_container
  fi
}

image_check(){
  if [ "${IMAGE}" == "" ]; then
    echoit "Assert: Impossibility: \${IMAGE} is empty in a place in the code where it should not be (called from function $(caller 0 | awk '{print $2}'))"
    exit 1
  fi
  # Add a 'sudo docker images ... | grep ...' here for ${IMAGE}
}

cmd_check(){
  if [ "${CMD}" == "" ]; then
    echoit "Assert: Impossibility: \${CMD} is empty in a place in the code where it should not be (called from function $(caller 0 | awk '{print $2}'))"
    exit 1
  fi
}

container_check(){
  if [ "${CONTAINER}" == "" ]; then
    echoit "Assert: Impossibility: \${CONTAINER} is empty in a place in the code where it should not be (called from function $(caller 0 | awk '{print $2}'))"
    exit 1
  fi
}

install_repo(){
  image_check
  if [ "$(echo ${IMAGE} | grep "centos5" 2>/dev/null)" != "" ]; then
    ${CMD} wget http://www.percona.com/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm >>${LOG} 2&1
    ${CMD} rpm -iv percona-release-0.1-3.noarch.rpm >>${LOG} 2>&1
  else
    ${CMD} yum install -y http://www.percona.com/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm >>${LOG} 2>&1
  fi
}

install_ps55(){
  echoit "[$(short_id ${CONTAINER})] Installing Percona Server 5.5 from Percona Repo"
  ${CMD} yum install -y Percona-Server-client-55 Percona-Server-server-55 >>${LOG} 2>&1
}

install_ps56(){
  echoit "[$(short_id ${CONTAINER})] Installing Percona Server 5.6 from Percona Repo"
  ${CMD} yum install -y Percona-Server-client-56 Percona-Server-server-56 >>${LOG} 2>&1
  # Percona-Server-devel-56.x86_64 Percona-Server-shared-56.x86_64 Percona-Server-test-56.x86_64
  echoit "[$(short_id ${CONTAINER})] Installing TokuDB x64 for Percona Server 5.6"
  ${CMD} yum install -y Percona-Server-tokudb-56.x86_64 >> ${LOG} 2>&1
  echoit "[$(short_id ${CONTAINER})] Enabling TokuDB using ps_tokudb_admin"
  ${CMD} ps_tokudb_admin --enable -uroot >> ${LOG} 2>&1
}

install_xb(){
  echoit "[$(short_id ${CONTAINER})] Installing XtraBackup (percona-xtrabackup.x86_64) from Percona Repo"
  ${CMD} yum install -y percona-xtrabackup.x86_64 >>${LOG} 2>&1
}

start_service(){
  echoit "[$(short_id ${CONTAINER})] Starting mysqld"
  ${CMD} service mysql start >>${LOG} 2>&1
}

create_lib_functions(){
  ${CMD} mysql -e "CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'" >>${LOG} 2>&1
  ${CMD} mysql -e "CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'" >>${LOG} 2>&1
  ${CMD} mysql -e "CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'" >>${LOG} 2>&1
}

disable_thp(){
  # THP Needs to be disabled on the host, NOT inside the Docker image (Docker in this case takes the host setting accross)
  echoit "For TokuDB, disabling THP (Transparent Huge Pages) on the host; Docker takes this setting accross into the running container"
  sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
  sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
}

# Usage: contains "word" ("array" "of" "words")returns 0 on success
contains () {
    local e
    for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}

sanity_check(){
  sanity_check_skipping ""
}

sanity_check_skipping(){
  local SKIP=("${@}");
  if [ ${ERROR_STATE} -eq 0 ]; then
    sanity_check_cli;
    local ENG
    for ENG in "InnoDB" "TokuDB" "Memory" "MyISAM"
    do
      if [ ${ERROR_STATE} -eq 0 ]; then
        if contains "${ENG}" "${SKIP[@]}"; then
          echoit "Skipping ${ENG} Sanity Check intentionally."
        else
          sanity_check_cli_engine "${ENG}";
        fi
      else
        echoit "Skipping InnoDB Sanity Check because of previous error"
      fi
    done
  else 
    echoit "Skipping 'Hello Percona' and Engine Sanity Check because of previous error"; 
  fi
}

sanity_check_cli(){
  echoit "[$(short_id ${CONTAINER})] Sanity 'Hello Percona' mysql CLI check (using SELECT)"
  ${CMD} mysql -e "SELECT 'Hello Percona'" >>${LOG} 2>&1
  if ! grep -qm1 "^Hello Percona" ${LOG}; then
    echo "[$(short_id ${CONTAINER})] Sanity 'Hello Percona' mysql CLI check failed!" 5
  else 
    echoit "[$(short_id ${CONTAINER})] Text 'Hello Percona' found in log: OK"
  fi
}

sanity_check_cli_engine(){
  echoit "[$(short_id ${CONTAINER})] ${1} Sanity check"
  ${CMD} mysql -e "CREATE DATABASE IF NOT EXISTS test; USE test; CREATE TABLE t1 (c1 INT) ENGINE=${1}; SHOW CREATE TABLE t1;" >>${LOG} 2>&1
  if ! grep -qim1 " ENGINE=${1} " ${LOG}; then
    echoit "[$(short_id ${CONTAINER})] ${1} Sanity check failed! (CREATE TABLE)" 5
  else
    echoit "[$(short_id ${CONTAINER})] Successful ${1} table creation found in log: OK"
  fi
  ${CMD} mysql test -e "DROP TABLE IF EXISTS t1;" >>${LOG} 2>&1
  if [[ $(tail -n1 ${LOG} | grep -c '^ERROR') -gt 0 ]]; then
    echoit "[$(short_id ${CONTAINER})] ${1} Sanity check failed! (DROP TABLE)" 5
  fi
  
}

report(){
  echoit "Total issues seen: ${ISSUE_COUNT}"
  echoit "Run complete, exiting normally"
  exit 0
}

# Prepatory work: pull or update OS distribution images, and validate/verify their presence
# TEMP DISABLED FOR TEST SPEEDUP pull_update_os_images() 
# TEMP DISABLED FOR TEST SPEEDUP validate_images;
disable_thp  # Disable THP on the host

# Actual packaging testing
#setup_base_image "centos:centos5"; if [ ${SKIP_ERROR} -eq 0 ]; then 
setup_base_image "centos:centos6"; 
if [ ${SKIP_ERROR} -eq 0 ]; then 
#setup_base_image "fedora:21"; if [ ${SKIP_ERROR} -eq 0 ]; then 
  setup_container "${IMAGE}"; 
  if [ ${SKIP_ERROR} -eq 0 ]; then 
    cmd_check; 
    install_repo; 
    install_ps55; 
    install_xb; 
    start_service; 
    create_lib_functions; 
    sanity_check_skipping "TokuDB"; 
    drop_container; 
  fi; 
  setup_container "${IMAGE}"; 
  if [ ${SKIP_ERROR} -eq 0 ]; then 
    cmd_check; 
    install_repo; 
    install_ps56; 
    install_xb; 
    start_service; 
    create_lib_functions; 
    sanity_check_skipping "TokuDB"; 
    drop_container; 
  fi;
  drop_base_image
  report
fi

# Potential other checks
  #RUN yum -y install rpm-devel yum-utils
  #RUN repoquery --requires --recursive Percona-Server-client-55
  #RUN repoquery --requires --recursive Percona-Server-server-55
  #RUN rpmgraph Percona-Server-server-55

