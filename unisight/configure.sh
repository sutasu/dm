#!/bin/bash
# generate ssh key for sge user on installer node and
# install puppet module responsible for installing sge user ssh key on compute nodes
# add complexes

SGE_USER_HOME=/home/sge
COMPLEX_NAME=path
SYNC_BACK_COMPLEX_NAME=sync_back

clean() {
  rm -rf $SGE_USER_HOME/.ssh
  rm -f /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp
  pkill -f "rsync --daemon"
}

add_complex() {
  local nm=$1
  COMPLEX_STR="$nm $nm RESTRING == YES NO NONE 0 NO"
  TMP_COMPLEX_FILE=/tmp/complex
  qconf -sc > $TMP_COMPLEX_FILE
  if ! grep '$COMPLEX_STR' $TMP_COMPLEX_FILE ; then
    echo "$COMPLEX_STR" >> $TMP_COMPLEX_FILE
    qconf -Mc $TMP_COMPLEX_FILE
  else
    echo "Complex $nm is already present"
  fi
}

FORCE=0
if [ "$1" == '--force' ]; then
  FORCE=1
  clean
fi

if [ ! -f $SGE_USER_HOME/.ssh/id_rsa.pub ]; then
  mkdir -p $SGE_USER_HOME/.ssh
  ssh-keygen -q -f $SGE_USER_HOME/.ssh/id_rsa -t rsa -N ''
  touch $SGE_USER_HOME/.ssh/authorized_keys
  chmod 0600 $SGE_USER_HOME/.ssh/authorized_keys
  chown -R sge.sge $SGE_USER_HOME/.ssh
else
  echo "ssh key for sge user already exists"
fi


if [ ! -f /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp ]; then
  ssh_key=$(awk '{print $2}' $SGE_USER_HOME/.ssh/id_rsa.pub)
  mkdir -p /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests
  cat > /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp <<EOF
class sge_ssh_key {
  ssh_authorized_key { 'sge_ssh_key':
    ensure => present,
    key    => '$ssh_key',
    type   => 'ssh-rsa',
    user   => 'sge'
  }
}
EOF
else
  echo "sge ssh puppet module already exists"
fi

# add module to regular software profile (separate software profile may be created later)

if ! grep sge_ssh_key /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml ; then
  cat >> /etc/puppetlabs/code/environments/production/data/tortuga-extra.yaml <<EOF
classes:
  - sge_ssh_key

EOF
else
  echo "sge puppet module is already in hiera"
fi

if true; then
  sudo yum install rsync
  cat > /etc/rsyncd.conf <<EOF
[HOME]
        path = /home
        comment = home
        read only = no
        write only = yes
        uid = $(id -u sge)
        gid = $(id -g sge)
        incoming chmod = a+w
        auth users = ugersync
        secrets file = /etc/rsyncd.secrets
[SCRATCH]
        path = /tmp/sge_shared
        comment = shared
        read only = no
        write only = yes
        uid = $(id -u sge)
        gid = $(id -g sge)
        incoming chmod = a+w
        auth users = ugersync
        secrets file = /etc/rsyncd.secrets
EOF
  cat > /etc/rsyncd.secrets <<EOF
ugersync:ugersync
EOF
  sudo chmod 600 /etc/rsyncd.secrets
  rsync --daemon
  echo "Started rsync daemon"
else
# install rsyncd in installer node
pusudo chmod 600 /etc/ppet module install puppetlabs-rsync --version 1.1.0
if [ ! -f /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests/init.pp ]; then
  mkdir -p /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests
  cat > /etc/puppetlabs/code/environments/production/modules/rsyncd/manifests/init.pp <<EOF
rsync::server::module{ 'rsyncd_home':
  path    => \$base,
  require => File[\$base],
}
rsync::server::module{ 'rsyncd_scratch':
  path    => \$base,
  require => File[\$base],
}
EOF
else
  echo "rsyncd puppet module already exists"
fi
# add rsyncd variables to hiera
if ! grep 'rsync::server::modules' /etc/puppetlabs/code/environments/production/hiera.yaml; then
cat >> /etc/puppetlabs/code/environments/production/hiera.yaml <<EOF
rsync::server::modules:
  rsyncd_home:
    path: /home
    incoming_chmod: false
    outgoing_chmod: false
  rsyncd_scratch:
    path: /tmp
    read_only: false
EOF
else
  echo "rsync is already in hiera"
fi
fi

# add complex
add_complex $COMPLEX_NAME
#add_complex $SYNC_BACK_COMPLEX_NAME


