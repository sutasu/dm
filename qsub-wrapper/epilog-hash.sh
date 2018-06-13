#/bin/bash
set -x 
echo "Epilog $(date)"

if [ ! -z "$SGE_DATA_OUT" ]; then
  if [ -d $SGE_DATA_OUT ]; then
    if [ "$($SGE_ROOT/utilbin/$SGE_ARCH/gethostbyname -name $HOSTNAME)" == "$($SGE_ROOT/utilbin/$SGE_ARCH/gethostbyname -name $SGE_O_HOST)" ]; then
      mkdir -p ~/$SGE_DATA_OUT_BACK
      cp -r $SGE_DATA_OUT ~/$SGE_DATA_OUT_BACK
      if [ $? -ne 0 ]; then
        echo "Epilog $(date): cp error."
      fi
    else
      rsync -avzhe "ssh -o StrictHostKeyChecking=no" $SGE_DATA_OUT $SGE_O_LOGNAME@$SGE_O_HOST:$SGE_DATA_OUT_BACK/
      if [ $? -ne 0 ]; then
        echo "Epilog $(date): rsync error."
      fi
    fi
  else
    echo "Epilog $(date): no output directory: $SGE_DATA_OUT"
  fi
else
  echo "Epilog $(date): no $SGE_DATA_OUT"
fi

