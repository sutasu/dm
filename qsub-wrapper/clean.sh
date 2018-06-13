#!/bin/bash
set -x

sudo rm $SGE_ROOT/$SGE_CELL/prolog-hash.sh \
        $SGE_ROOT/$SGE_CELL/epilog-hash.sh \
        $SGE_ROOT/$SGE_CELL/qsub-cloud.sh \
        $SGE_ROOT/$SGE_CELL/hash-local-ls.sh \
        $SGE_ROOT/$SGE_CELL/hash-shared-ls.sh

for h in $(qconf -sconfl); do
  hf=/tmp/$h
  qconf -sconf $h > $hf
#  if grep 'hash-local-ls.sh' $hf ; then
  if grep 'hash' $hf ; then
    echo "Removing load sensor on $h"
    sed -i "s|.*load_sensor.*$SGE_ROOT/$SGE_CELL/hash.*||" $hf
#    sed -i "s|.*load_sensor $SGE_ROOT/$SGE_CELL/hash-local-ls.sh.*||" >> $hf
    qconf -Mconf $hf
  fi

  if grep $h ~/.ssh/authorized_keys ; then
    sed -i "s|^.*$USER@$h\$||" ~/.ssh/authorized_keys
  fi
done

qconf -dq cloud.q
