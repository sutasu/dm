#!/bin/bash
#
# Usage: -src-uri uri [-dest LOCAL|SHARED] [-out-dir dir] qsub_parameters
#
#
set -x
THIS_SCRIPT=$0

EXEC_HOST_LOCAL_DATA_DIR=%%EXEC_HOST_LOCAL_DATA_DIR%%
SHARED_DATA_DIR=%%SHARED_DATA_DIR%%

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
  "-src-uri")
    shift
    export SGE_DATA_IN="$1"
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
    SGE_DATA_OUT_BACK="${1##*:}"
    shift
    ((done++))
    ;;
  *)
    break
    ;;
  esac
done

if [ -z "$SGE_DATA_IN" ]; then
  echo "missing -src-uri parameter"
  exit 1
fi

if [ -z "$local_shared" ]; then
  local_shared=LOCAL
fi

if [ "$local_shared" == "LOCAL" ]; then
  export SGE_CACHE_DATA_DIR=$EXEC_HOST_LOCAL_DATA_DIR
  lhash=hash_local
elif [ "$local_shared" == "SHARED" ]; then
  export SGE_CACHE_DATA_DIR=$SHARED_DATA_DIR
  lhash=hash_shared
else
  echo "Incorrect -dest parameter: $local_shared. Should be LOCAL or SHARED"
  exit 1
fi

hash=$(find $SGE_DATA_IN -type f -exec md5sum {} \; | sort | md5sum | awk '{print $1}')

qsub -v SGE_DATA_HASH=$hash \
     -v SGE_DATA_IN=$SGE_DATA_IN \
     -v SGE_DATA_OUT=$SGE_DATA_OUT \
     -v SGE_DATA_OUT_BACK=$SGE_DATA_OUT_BACK \
     -v SGE_CACHE_DATA_DIR=$SGE_CACHE_DATA_DIR \
     -v SGE_JOB_DATA_IN=$SGE_CACHE_DATA_DIR/$hash \
     -v SGE_JOB_DATA_OUT=$SGE_DATA_OUT \
     "$@" \
     -soft -l $lhash=$hash

