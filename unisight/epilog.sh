#/bin/bash
set -x
RSYNC_HOME_MODULE=HOME
RSYNC_SHARED_MODULE=SCRATCH
echo "Epilog $(date): begin"

if [ ! -z "$SGE_DATA_OUT" ]; then
  if [ -d $SGE_DATA_OUT ]; then
#    rsync -avzhe "ssh -o StrictHostKeyChecking=no" $SGE_DATA_OUT $SGE_O_LOGNAME@$SGE_O_HOST:$SGE_DATA_OUT_BACK/
    module=
    if [ -z "$SGE_DATA_OUT_BACK" ]; then
      SGE_DATA_OUT_BACK=/home/$SGE_O_LOGNAME
      module=$RSYNC_HOME_MODULE
      echo "Epilog $(date): transfer data back: home used: $SGE_DATA_OUT_BACK"
    else
      module=$RSYNC_SHARED_MODULE
    fi
    RSYNC_PASSWORD=ugersync rsync -rtv $SGE_STDERR_PATH $SGE_STDOUT_PATH $SGE_DATA_OUT rsync://ugersync@$SGE_O_HOST/$module/$SGE_DATA_OUT_BACK/
    if [ $? -ne 0 ]; then
      echo "Epilog $(date): rsync error transferring data back from remote directory $SGE_DATA_OUT to local $SGE_DATA_OUT_BACK"
      echo "local directory $SGE_DATA_OUT_BACK has to exist and have write prmissions for all"
    fi
  else
    echo "Epilog $(date): no output directory: $SGE_DATA_OUT"
  fi
else
  echo "Epilog $(date): no $SGE_DATA_OUT"
fi
echo "Epilog $(date): end"
