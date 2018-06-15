#/bin/bash
set -x 
echo "Epilog $(date)"

if [ ! -z "$SGE_DATA_OUT" ]; then
  if [ -d $SGE_DATA_OUT ]; then
    rsync -avzhe "ssh -o StrictHostKeyChecking=no" $SGE_DATA_OUT $SGE_O_LOGNAME@$SGE_O_HOST:$SGE_DATA_OUT_BACK/
    if [ $? -ne 0 ]; then
      echo "Epilog $(date): rsync error."
    fi
  else
    echo "Epilog $(date): no output directory: $SGE_DATA_OUT"
  fi
else
  echo "Epilog $(date): no $SGE_DATA_OUT"
fi

