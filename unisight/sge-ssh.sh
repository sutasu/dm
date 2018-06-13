#!/bin/bash
# generate ssh key for sge user on installer node and
# install puppet module responsible for installing sge user ssh key on compute nodes

SGE_USER_HOME=/home/sge

clean() {
  rm -rf $SGE_USER_HOME/.ssh
  rm -f /etc/puppetlabs/code/environments/production/modules/sge_ssh_key/manifests/init.pp
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
