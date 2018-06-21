#!/bin/bash
#
# Usage: -src-uri uri [-dest LOCAL|SHARED] [-out-dir dir] qsub_parameters
#
#
set -x
THIS_SCRIPT=$0

#SGE_LOCAL_STORAGE_ROOT=%%EXEC_HOST_LOCAL_DATA_DIR%%
#SGE_SHARED_STORAGE_ROOT=%%SHARED_DATA_DIR%%
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
SGE_SHARED_STORAGE_ROOT=/tmp/sge_shared
LOCAL_PATH_COMPLEX=path
SHARED_PATH_COMPLEX=spath

done=0
while [ $# -gt 0 ]; do
  if [ $done -ge 3 ]; then
    break
  fi
  case "$1" in
  "-help")
    Usage
    exit 0
    ;;
  "-src")
    shift
    SGE_DATA_IN_SRC_STORAGE=${1%%/*}
    SGE_DATA_IN_SRC=${1#*/}
    src_path=$SGE_DATA_IN_SRC
    shift
    ((done++))
    ;;
  "-dest")
    shift
    local_shared="$1"
    shift
    ((done++))
    ;;
  "-sync-back")
    shift
    SGE_DATA_OUT="${1%%:*}"
    p="${1#*:}"
    if [[ $p = "HOME/"* ]]; then
      SGE_DATA_OUT_BACK_STORAGE=HOME
      to="${p#HOME/}"
      SGE_DATA_OUT_BACK=$to
#      SGE_DATA_OUT_BACK=HOME/$USER/$to
    elif [[ $p = "SCRATCH/"* ]]; then
      SGE_DATA_OUT_BACK_STORAGE=SCRATCH
      to="${p#SCRATCH/}"
      SGE_DATA_OUT_BACK=$to
#      SGE_DATA_OUT_BACK=SCRATCH/$to
    else
      SGE_DATA_OUT_BACK_STORAGE=HOME
      echo "HOME or SCRATCH specifier expected in -sync-back parameter"
      exit 1
    fi
    shift
    ((done++))
    ;;
  *)
    echo "default case: $@"
    break
    ;;
  esac
done

if [ -z "$src_path" ]; then
  echo "missing -src-dir parameter"
  exit 1
fi

if [ -z "$local_shared" ]; then
  local_shared=LOCAL
fi

if [ "$local_shared" == "LOCAL" ]; then
  complex=$LOCAL_PATH_COMPLEX
  export SGE_DATA_IN="$SGE_LOCAL_STORAGE_ROOT/$USER/$(echo $src_path | base64)"
elif [ "$local_shared" == "SCRATCH" ]; then
  complex=$SHARED_PATH_COMPLEX
  export SGE_DATA_IN="$SGE_SHARED_STORAGE_ROOT/$USER/$(echo $src_path | base64)"
  SGE_DATA_IN_SRC=$src_path
else
  echo "Incorrect -dest parameter: $local_shared. Should be LOCAL or SCRATCH"
  exit 1
fi

qsub -v SGE_DATA_IN=$SGE_DATA_IN \
     -v SGE_DATA_IN_SRC=$SGE_DATA_IN_SRC \
     -v SGE_DATA_IN_SRC_STORAGE=$SGE_DATA_IN_SRC_STORAGE \
     -v SGE_DATA_OUT=$SGE_DATA_OUT \
     -v SGE_DATA_OUT_BACK=$SGE_DATA_OUT_BACK \
     -v SGE_DATA_OUT_BACK_STORAGE=$SGE_DATA_OUT_BACK_STORAGE \
     -soft -l $complex="*${src_path}*" -hard \
     "$@"

#     -hard -l $complex="*${src_path}*"
