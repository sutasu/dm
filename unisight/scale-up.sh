#!/bin/bash
# positional parameters:
# job_ids
# job_slots
# job_users
# queue_available_slots
# queue_total_slots
# queue_reserved_slots
# queue_names


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
QUEUE=all.q
TORTUGA_ROOT=/opt/tortuga
HARDWARE_PROFILE=aws
SOFTWARE_PROFILE=execd
SLOTS_ON_EXECD=2
LOCAL_PATH_COMPLEX=path
#SYNC_BACK_PATH_COMPLEX=sync_back
SYNC_BACK_ENV_VAR=SYNC_BACK
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
LOAD_SENSOR_DIR=$SGE_ROOT/setup
# local cluster shared directory
SCRATCH_ROOT=/tmp/sge_shared
#RSYNC="sudo su - sge -c "

ASYNC=0
RSYNC_PIDS=()

job_ids=(${1//,/ })
#IFS=',' read -ra job_ids <<< $1
echo "job_ids=${job_ids[@]}"
job_cnt=${#job_ids[@]}
echo "job_cnt=$job_cnt"

slots=(${2//,/ })
echo "slots=${slots[@]}"
slot_cnt=${#slots[@]}
echo "slot_cnt=$slot_cnt"

if [ $job_cnt -ne $slot_cnt ]; then
  echo "Job and slot arrays has different sizes: $job_cnt!=$slot_cnt"
  exit 1
fi

users=(${3//,/ })
echo "users=${users[@]}"

free_slots_array=(${4//,/ })
free_slots=0
for s in ${free_slots_array[@]}; do
  free_slots=$((free_slots + s))
done
echo "free_slots: $free_slots"

total_slots=0
for s in ${slots[@]}; do
  total_slots=$((total_slots + s))
done
echo "total_slots requested buy jobs: $total_slots"

total_slots=$((total_slots - free_slots))
if [ $total_slots -le 0 ]; then
  echo "Do not scale up, new slots requested: $total_slots, already available: $free_slots"
  # get nodes with free slots
  #qstat -f | awk '/all.q/ {printf("%s %s",$1,$3)}' | 
fi

new_nodes=$((total_slots / SLOTS_ON_EXECD))
extra=$((total_slots - new_nodes * SLOTS_ON_EXECD))
echo "extra=$extra"
if [ $extra -gt 0 ]; then
  new_nodes=$((new_nodes + 1))
fi
echo "new_nodes=$new_nodes"

if false; then
  echo "Adding $new_nodes new nodes"
  ret=0
else
  request_id=$(set -o pipefail; \
    $TORTUGA_ROOT/bin/add-nodes \
      --software-profile $SOFTWARE_PROFILE \
      --hardware-profile $HARDWARE_PROFILE \
      --count $new_nodes | \
    awk -F[ '{print $2}' | awk -F] '{print $1}')
  ret=$?
fi

if [ $ret -ne 0 ]; then
  echo "Error: add-nodes returned: $ret"
  exit 1
fi

job_ids_with_data=()
paths_from=()
paths_to=()
for ((cnt=0; cnt<${#job_ids[@]}; ++cnt)) {
  job_id=${job_ids[$cnt]}
  user=${users[$cnt]}
#for job_id in ${job_ids[@]}; do
  jarr=($(qstat -j $job_id | awk -F': ' '/hard resource_list|env_list/ {print $2}'))
  hard_list=${jarr[0]}
  env_list=${jarr[1]}
#  hard_list=$(qstat -j $job_id | awk '/hard resource_list/ {print $3}')
  hard_list_arr=(${hard_list//,/ })
  env_list_arr=(${env_list//,/ })
  qalter_params=
  for hl in ${hard_list_arr[@]}; do
    if [[ $hl = "$LOCAL_PATH_COMPLEX"* ]]; then
#      path="${hl##*=}"
      path="${hl##*=\*}"
      path="${path%%\*}"
      paths_from+=($path)
#      path_to="${path//\//_}"
      path_to=$SGE_LOCAL_STORAGE_ROOT/$user/$(echo $path | base64)
      paths_to+=($path_to)
      job_ids_with_data+=($job_id)
      qalter_params="$qalter_params -adds v SGE_DATA_IN $path_to"
    fi
  done
  for el in ${env_list_arr[@]}; do
    if [[ $el = "$SYNC_BACK_ENV_VAR="* ]]; then
      echo "sync_back: $el"
      path="${el#*=}"
      path_from="${path%%:*}"
      if [ ! -z "$path_from" ]; then
        qalter_params="$qalter_params -adds v SGE_DATA_OUT $path_from"
        path_to="${path##*:}"
        if [[ $path_to = "HOME/"* ]]; then
          to="${path_to#HOME/}"
          path_to="HOME/$user/$to"
        elif [[ $path_to = "SCRATCH/"* ]]; then
          to="${path_to#SCRATCH/}"
          path_to="SCRATCH/$to"
        else
          echo "HOME or SCRATCH specifier expected in $SYNC_BACK_ENV_VAR"
          path_to=
        fi
        if [ ! -z "$path_to" ]; then
          qalter_params="$qalter_params -adds v SGE_DATA_OUT_BACK $path_to"
        fi
      fi
#      qalter_params="$qalter_params -clears l_hard $SYNC_BACK_PATH_COMPLEX"
    fi    
  done
  if [ ! -z "$qalter_params" ]; then
    echo "qalter $qalter_params $job_id"
    qalter $qalter_params $job_id
  fi
#done
}

echo "job_ids_with_data=${job_ids_with_data[@]}"
echo "paths_from=${paths_from[@]}"
echo "paths_to=${paths_to[@]}"
  
while get-node-requests -r $request_id | fgrep pending ; do
  echo "Waiting for nodes to boot"
  sleep 1
done


data_total=${#paths_from[@]}
new_nodes=($(get-node-requests -r $request_id | tail -n +2))

new_nodes_total=${#new_nodes[@]}
ssh_available=($(for i in $(seq 1 $new_nodes_total); do echo 0; done))
node_cnt=0

# transfer data
for ((data_cnt=0; data_cnt<data_total; data_cnt++)) {
  if [ $node_cnt -ge $new_nodes_total ]; then
    node_cnt=0
  fi
  echo "data_cnt=$data_cnt, node_cnt=$node_cnt"
  node=${new_nodes[$node_cnt]}
  if [ ${ssh_available[$node_cnt]} -eq 0 ]; then
    echo "Checking if ssh is available for $node"
    sudo su - sge -c "ssh -q -o \"BatchMode=yes\" -o \"ConnectTimeout=5\" sge@$node \"echo 2>&1\""
    if [ $? -ne 0 ]; then
      echo "ssh not available on $node yet"
      data_cnt=$((data_cnt - 1))
      node_cnt=$((node_cnt + 1))
      sleep 5
      continue
    else
      ssh_available[$node_cnt]=1
      echo "ssh available on $node"
    fi
  fi
  data_path=${paths_from[$data_cnt]}
  path_to=${paths_to[$data_cnt]}
  if [ $ASYNC -eq 1 ]; then
    rsync -avzhe "ssh -o StrictHostKeyChecking=no" \
      --rsync-path="mkdir -p $SGE_LOCAL_STORAGE_ROOT/$path_to && rsync" \
      $data_path sge@$node:$path_to/ &
    RSYNC_PIDS+=($!)
  else
    echo "Transferring data from $data_path to sge@$node:$path_to/"
    sudo su - sge -c "rsync -avzhe \"ssh -o StrictHostKeyChecking=no\" \
      --rsync-path=\"mkdir -p $path_to && rsync\" \
      $data_path sge@$node:$path_to/"
    ret=$?
    if [ $ret -ne 0 ]; then
      echo "error code from rsync: $ret"
    fi
  fi
  node_cnt=$((node_cnt + 1))
}

# prepare load sensor
sed "s|%%SGE_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; s|%%SGE_COMPLEX_NAME%%|$LOCAL_PATH_COMPLEX|" $SCRIPT_DIR/load-sensor.sh > /tmp/lls.sh
chmod a+x /tmp/lls.sh
sed "s|%%SCRATCH_ROOT%%|$SCRATCH_ROOT|" $SCRIPT_DIR/epilog.sh > /tmp/epilog.sh
chmod a+x /tmp/epilog.sh

# wait for UGE become available on compute nodes
# install load sensor
max_cnt=100
max_err_cnt=$((10 * new_node_total))
err_cnt=0
new_nodes_copy=("${new_nodes[@]}")
for((cnt=0;cnt<max_cnt;++cnt)) { 
  tmp=()
  for node in ${new_nodes_copy[@]}; do
    echo "Waiting for UGE on $node"
    node_short=${node%%.*}
  #  for((i=0;i<new_nodes_total;++i)); do
#    if [ -z "$(qstat -f | grep $node)" ]; then
    if ! qstat -f | grep $node_short ; then
      echo "No execd on $node yet"
      err_cnt=$((err_cnt + 1))
      if [ $err_cnt -gt $max_err_cnt ]; then
        echo "Too many attempts waiting for UGE become ready on $node"
        continue
      fi
      tmp+=($node)
      continue
    fi
#    if [ -z "$(qstat -f -qs u | grep $node)" ]; then
    if ! qstat -f -qs u | grep $node_short ; then
      echo "Adding load sensor and epilog on $node"
      # copy load sensor and epilog
      sudo su - sge -c "scp -o StrictHostKeyChecking=no /tmp/lls.sh /tmp/epilog.sh sge@${node}:${LOAD_SENSOR_DIR}"
      ret=$?
      if [ $ret -ne 0 ]; then
        echo "Error installing load sensor or epilog: scp exit code: $ret"
      fi
      hf=/tmp/$node
      qconf -sconf $node > $hf
      echo "load_sensor $LOAD_SENSOR_DIR/lls.sh" >> $hf
      # temporary change load sensor period to short value
      echo "load_report_time 5" >> $hf
      qconf -Mconf $hf
      # add epilog
      qconf -mattr queue epilog $LOAD_SENSOR_DIR/epilog.sh all.q
    else
      echo "UGE on $node is still in 'u' state"
      tmp+=($node)
    fi
  done
  if [ ${#tmp[@]} -eq 0 ]; then
    echo "All UGE nodes ready"
    break
  fi
  new_nodes_copy=(${tmp[@]})
  if [ $err_cnt -gt $max_err_cnt ]; then
    echo "Too many attempts waiting for UGE become ready on new nodes"
    break
  fi
  sleep 1
}

# wait default load sensor reporting interval
echo "Waiting default load report interval"
sleep 40
# change back to default by removing it
for node in ${new_nodes[@]}; do
  hf=/tmp/$node
  qconf -sconf $node > $hf
  sed -i '/^load_report_time[ \t]*5.*/ d' $hf
  qconf -Mconf $hf
done

