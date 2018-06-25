#!/bin/bash
#
# Usage: -src-uri uri [-dest LOCAL|SHARED] [-out-dir dir] qsub_parameters
#
#
#set -x
THIS_SCRIPT=$0

#SGE_LOCAL_STORAGE_ROOT=%%EXEC_HOST_LOCAL_DATA_DIR%%
#SGE_SHARED_STORAGE_ROOT=%%SHARED_DATA_DIR%%
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
SGE_SHARED_STORAGE_ROOT=/tmp/sge_shared
LOCAL_PATH_COMPLEX=path
SHARED_PATH_COMPLEX=spath

Usage() {
  echo "This qsub wrapper script allows submitting UGE job which requires data to be"
  echo "transferred to the remote execution host which doesn't have shared data"
  echo "infrastructure with the submitter and job's output data to be transferred back."
  echo ""
  echo "Usage:"
  echo "$(basename  $THIS_SCRIPT) -src HOME|SCRATCH/dir_or_file"
  echo "    -dest LOCAL|SCRATCH"
  echo "    -sync-back remote/output/dir_or_file:HOME|SCRATCH/output_dir"
  echo "    qsub_parameters"
  echo ""
  echo "parameters:"
  echo "    -src HOME|SCRATCH/dir_or_file - data source directory"
  echo "         HOME: a keyword indicating user's home directory"
  echo "         SCRATCH: a keyword indicating shared data volume"
  echo "         dir_or_file data path pointing to the data to be transferred"
  echo "    -dest LOCAL|SCRATCH - execution host destination type"
  echo "         LOCAL: execution host local data storage"
  echo "         SCRATCH: data storage shared betweek multiple execution nodes"
  echo "    -sync-back remote/output/dir_or_file:HOME|SCRATCH/output_dir - data"
  echo "    transfer back to submitter specifier"
  echo "         remote/output/dir_or_file: directory ot file with job's output"
  echo "             to be transferred back"
  echo "         HOME: a keyword indicating user's home directory to be used as"
  echo "         a root for the data transferred back to the submitter side"
  echo "         SCRATCH: a keyword indicating shared data volume to be used as"
  echo "         a root for the data transferred back to the submitter side"
  echo "         output_dir: output directory"
  echo "    qsub_parameters - regular qsub parameters"
  echo ""
  echo "Following environment variables will be exported to the job :"
  echo "    SGE_DATA_IN - full path to the job's input data on execution host"
  echo "    SGE_DATA_OUT - full path job's output data directory"
  echo ""
  echo "Script example:"
  echo "$ mkdir -p ~/in; echo hello > ~/in/hello"
  echo "$ cat t.sh"
  echo "#!/bin/bash"
  echo "mkdir -p \$SGE_DATA_OUT"
  echo "cp \$SGE_DATA_IN/hello \$SGE_DATA_OUT"
  echo ""
  echo "Job submission:"
  echo "$ $(basename $THIS_SCRIPT) -src HOME/in -dest LOCAL -sync-back /home/$USER/out:HOME/out t.sh"
}

done=0
while [ $# -gt 0 ]; do
  if [ $done -ge 3 ]; then
    break
  fi
  case "$1" in
  "-help"|"-h")
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
  echo "missing -src parameter"
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

# create output directory and set permissions
SGE_SHARED_STORAGE_ROOT=/tmp/sge_shared
if [ "$SGE_DATA_OUT_BACK_STORAGE" == "HOME" ]; then
  mkdir -p ~/$SGE_DATA_OUT_BACK
  chmod a+rwx ~/$SGE_DATA_OUT_BACK
else
  mkdir -p $SGE_SHARED_STORAGE_ROOT/$SGE_DATA_OUT_BACK
  chmod a+rwx $SGE_SHARED_STORAGE_ROOT/$SGE_DATA_OUT_BACK
fi

# submit job with additional parameters
qsub -v SGE_DATA_IN=$SGE_DATA_IN \
     -v SGE_DATA_IN_SRC=$SGE_DATA_IN_SRC \
     -v SGE_DATA_IN_SRC_STORAGE=$SGE_DATA_IN_SRC_STORAGE \
     -v SGE_DATA_OUT=$SGE_DATA_OUT \
     -v SGE_DATA_OUT_BACK=$SGE_DATA_OUT_BACK \
     -v SGE_DATA_OUT_BACK_STORAGE=$SGE_DATA_OUT_BACK_STORAGE \
     -soft -l $complex="*${src_path}*" -hard \
     "$@"
