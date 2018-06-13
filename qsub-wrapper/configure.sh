#!/bin/bash
set -x

# define host local and shared global data paths
EXEC_HOST_LOCAL_DATA_DIR=/tmp/sge_local_data
SHARED_DATA_DIR=/scratch/sge_data

# create those directories via qsub
cat > /tmp/create-dir.sh <<EOF
#!/bin/bash
set -x
dr=\$1
if [ ! -d \$dr ]; then
  sudo mkdir -p \$dr
  sudo chmod a+rwx \$dr
fi
EOF
chmod a+x /tmp/create-dir.sh

for h in $(qconf -sconfl); do
  qsub -l h=$h -j y /tmp/create-dir.sh $EXEC_HOST_LOCAL_DATA_DIR
  qsub -l h=$h -j y /tmp/create-dir.sh $SHARED_DATA_DIR
done


# copy files to UGE shared space and update
sudo cp prolog-hash.sh epilog-hash.sh qsub-cloud.sh $SGE_ROOT/$SGE_CELL
sudo cp hash-ls.sh $SGE_ROOT/$SGE_CELL/hash-local-ls.sh
sudo sed -i "s|%%SGE_CACHE_DATA_DIR%%|$EXEC_HOST_LOCAL_DATA_DIR|; s|%%SGE_COMPLEX_NAME%%|hash_local|" $SGE_ROOT/$SGE_CELL/hash-local-ls.sh
sudo cp hash-ls.sh $SGE_ROOT/$SGE_CELL/hash-shared-ls.sh
sudo sed -i "s|%%SGE_CACHE_DATA_DIR%%|$SHARED_DATA_DIR|; s|%%SGE_COMPLEX_NAME%%|hash_shared|" $SGE_ROOT/$SGE_CELL/hash-shared-ls.sh
sudo sed -i "s|%%EXEC_HOST_LOCAL_DATA_DIR%%|$EXEC_HOST_LOCAL_DATA_DIR|; s|%%SHARED_DATA_DIR%%|SHARED_DATA_DIR|" $SGE_ROOT/$SGE_CELL/qsub-cloud.sh

# add complex
TMP_COMPLEX_FILE=/tmp/complex
qconf -sc > $TMP_COMPLEX_FILE
echo "hash_local                hash_local       RESTRING    ==    YES         NO         NONE     0       NO" >> $TMP_COMPLEX_FILE
echo "hash_shared                hash_shared       RESTRING    ==    YES         NO         NONE     0       NO" >> $TMP_COMPLEX_FILE
qconf -Mc $TMP_COMPLEX_FILE

# set prolog/epilog timeout for longer time (default is 2 minutes)
#qconf -mconf execd_params SCRIPT_TIMEOUT=10

# add and configure cloud queue
EDITOR=/bin/true qconf -aq cloud.q
qconf -rattr queue load_thresholds NONE cloud.q
qconf -mattr queue hostlist @allhosts cloud.q
qconf -mattr queue slots 5 cloud.q
qconf -mattr queue prolog $SGE_ROOT/$SGE_CELL/prolog-hash.sh cloud.q
qconf -mattr queue epilog $SGE_ROOT/$SGE_CELL/epilog-hash.sh cloud.q

for h in $(qconf -sconfl); do
  hf=/tmp/$h
  qconf -sconf $h > $hf
  if ! grep 'hash-local-ls.sh' $hf ; then
    echo "Adding load sensor on $h"
    echo "load_sensor $SGE_ROOT/$SGE_CELL/hash-local-ls.sh" >> $hf
    qconf -Mconf $hf
  fi
done


# consider to move ssh keys management to separate script
cat > /tmp/ssh-key.sh <<EOF
#!/bin/bash
set -x
if [ ! -f \$HOME/.ssh/id_rsa.pub ]; then
  ssh-keygen -q -f \$HOME/.ssh/id_rsa -t rsa -N ''  
fi
cat \$HOME/.ssh/id_rsa.pub
EOF
chmod a+x /tmp/ssh-key.sh

# install users' ssh remote keys on submit host to allow rsync in prolog and epilog to use ssh transport
for h in $(qconf -sconfl|grep -v solaris); do
  key=$(qrsh -l h=$h -b y "bash -c 'if [ ! -f \$HOME/.ssh/id_rsa.pub ]; then ssh-keygen -q -f \$HOME/.ssh/id_rsa -t rsa -N ''; fi; cat \$HOME/.ssh/id_rsa.pub'")
  if ! grep "$key" ~/.ssh/authorized_keys ; then
    echo "Adding ssh key for $h"
    echo "$key" >> ~/.ssh/authorized_keys
  else
    echo "ssh key for $h already exists"
  fi
done
