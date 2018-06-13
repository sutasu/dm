#!/bin/bash
# usage: job_ids job_slots queue_available_slots queue_total_slots queue_reserved_slots queue_names

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
QUEUE=all.q
TORTUGA_ROOT=/opt/tortuga
HARDWARE_PROFILE=aws
SOFTWARE_PROFILE=execd
SLOTS_ON_EXECD=2
LOCAL_PATH_COMPLEX=path
SYNC_BACK_PATH_COMPLEX=sync_back
SGE_LOCAL_STORAGE_ROOT=/tmp/sge_data
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

free_slots_array=(${3//,/ })
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
#hashes=()
for job_id in ${job_ids[@]}; do
  hard_list=$(qstat -j $job_id | awk '/hard resource_list/ {print $3}')
  hard_list_arr=(${hard_list//,/ })
  for hl in ${hard_list_arr[@]}; do
    if [[ $hl = "$LOCAL_PATH_COMPLEX"* ]]; then
      path="${hl##*=}"
      paths_from+=($path)
      path_to="${path//\//_}"
      paths_to+=($path_to)
      job_ids_with_data+=($job_id)
    fi
    if [[ $hl = "$SYNC_BACK_PATH_COMPLEX"* ]]; then
      echo "sync_back"
    fi
  done  
done

echo "job_ids_with_data=${job_ids_with_data[@]}"
echo "paths_from=${paths_from[@]}"
echo "paths_to=${paths_to[@]}"

# calculate data hashes
#for path in ${paths_from[@]}; do
#  hash=$(find $SGE_DATA_IN -type f -exec md5sum {} \; | sort | md5sum | awk '{print $1}')
#  hashes+=(hash)
#done
  
while get-node-requests -r $request_id | fgrep pending ; do
  echo "Waiting for nodes to boot"
  sleep 1
done


data_total=${#paths_from[@]}
new_nodes=($(get-node-requests -r $request_id | tail -n +2))

sleep 60

#new_nodes_copy=(${new_nodes[@]})
# transfer data
#max_cnt=10
#for((cnt=0;cnt<max_cnt;++cnt)) { 
#  tmp=()

new_nodes_total=${#new_nodes[@]}
node_cnt=0
#initial_check=1

for ((data_cnt=0; data_cnt<data_total; data_cnt++)) {
  if [ $node_cnt -ge $new_nodes_total ]; then
    node_cnt=0
#    initial_check=0
  fi
#  if [ $initial_check -eq 1 ]; then
#    echo "Checking if ssh is available for $node"
#    ssh -q -o "BatchMode=yes" sge@$node "echo 2>&1"
#    if [ $? -ne 0 ]; then
#      echo "ssh not available on $node yet"
#      sleep 1
#    else
#      echo "ssh available on $node"
#    fi
#  fi 
  data_path=${paths_from[$data_cnt]}
  node=${new_nodes[$node_cnt]}
  #hash=${hashes[$data_cnt]}
  path_to=${paths_to[$data_cnt]}
  if [ $ASYNC -eq 1 ]; then
    rsync -avzhe "ssh -o StrictHostKeyChecking=no" \
      --rsync-path="mkdir -p $SGE_LOCAL_STORAGE_ROOT/$path_to && rsync" \
      $data_path sge@$node:$path_to/ &
    RSYNC_PIDS+=($!)
  else
    echo "Transferring data from $data_path to sge@$node:$path_to/"
    sudo su - sge -c "rsync -avzhe \"ssh -o StrictHostKeyChecking=no\" \
      --rsync-path=\"mkdir -p $SGE_LOCAL_STORAGE_ROOT/$path_to && rsync\" \
      $data_path sge@$node:$SGE_LOCAL_STORAGE_ROOT/$path_to/"
    ret=$?
    if [ $ret -ne 0 ]; then
      echo "error code from rsync: $ret"
    fi
  fi
  node_cnt=$((node_cnt + 1))
}

# prepare load sensor
sed "s|%%SGE_STORAGE_ROOT%%|$SGE_LOCAL_STORAGE_ROOT|; s|%%SGE_COMPLEX_NAME%%|$LOCAL_PATH_COMPLEX|" $SCRIPT_DIR/load-sensor.sh > /tmp/lls.sh

# wait for UGE become available on compute nodes
# install load sensor
max_cnt=10
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
      echo "Adding load sensor on $node"
      # install load sensor
      scp -o StrictHostKeyChecking=no /tmp/lls.sh sge@${node}:${SGE_ROOT}/${SGE_CELL}
      ret=$?
      if [ $ret -ne 0 ]; then
        echo "Error installing load sensor: scp exit code: $ret"
      fi
      hf=/tmp/$node
      qconf -sconf $node > $hf
      echo "load_sensor $SGE_ROOT/$SGE_CELL/lls.sh" >> $hf
      qconf -Mconf $hf
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

