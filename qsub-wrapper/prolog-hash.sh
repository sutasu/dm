#/bin/bash
set -x
echo "Prolog $(date)"
#printenv

if [ -z $SGE_CACHE_DATA_DIR ]; then
  echo "Prolog $(date): SGE_CACHE_DATA_DIR is not defined"
  exit 0
fi

#SGE_CACHE_DATA_DIR=${SGE_CACHE_DATA_DIR:-/tmp/sge_local_data}
#mkdir -p $SGE_CACHE_DATA_DIR

#hash=$(find $SGE_DATA_IN -type f -exec md5sum {} \; | sort | md5sum | awk '{print $1}')

export SGE_JOB_DATA_IN=$SGE_CACHE_DATA_DIR/$SGE_DATA_HASH
if [ ! -d $SGE_JOB_DATA_IN ]; then
  mkdir $SGE_JOB_DATA_IN
  if [ "$($SGE_ROOT/utilbin/$SGE_ARCH/gethostbyname -name $HOSTNAME)" == "$($SGE_ROOT/utilbin/$SGE_ARCH/gethostbyname -name $SGE_O_HOST)" ]; then
    cp -r $SGE_DATA_IN $SGE_JOB_DATA_IN
    if [ $? -ne 0 ]; then
      echo "Prolog $(date): cp error."
    fi
  else
    rsync -avzhe "ssh -o StrictHostKeyChecking=no" $SGE_O_LOGNAME@$SGE_O_HOST:$SGE_DATA_IN $SGE_JOB_DATA_IN/
    if [ $? -ne 0 ]; then
      echo "Prolog $(date): rsync error."
    fi
  fi
else
  echo "Prolog $(date): already there: $SGE_JOB_DATA_IN"
fi

