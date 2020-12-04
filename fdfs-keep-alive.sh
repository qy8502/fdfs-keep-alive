#!/bin/bash
pCount=$(ps -ef | grep $0 | grep -v 'grep' | grep -v ' -c sh' | grep -v $$ | grep -c 'sh')
if [ $pCount -gt 0 ]; then
  exit 0
fi
mkdir -p /data/logs
LOG_PATH="/data/logs/fdfs_keep_alive.log"
declare -A trackers=(["10.0.0.121"]="ACTIVE" ["10.0.0.122"]="ACTIVE" ["10.0.0.123"]="ACTIVE")
declare -A storages=(["10.0.0.114"]="OFFLINE" ["10.0.0.134"]="OFFLINE" ["10.0.0.135"]="OFFLINE" ["10.0.0.137"]="OFFLINE")

echo "" >> $LOG_PATH
echo "" >> $LOG_PATH
echo "====== `date +'%Y-%m-%d %H:%M:%S'` check trackers ${!trackers[@]}  =====" >> $LOG_PATH

for tracker in ${!trackers[@]}
do
  storagesStatus=($(ssh $tracker "timeout 5 fdfs_monitor /etc/fdfs/client.conf 2>/dev/null | grep 'ip_addr' | sed 's/ip_addr = \([0-9|.]*\)  \([A-Z]*\)/\1:\2/g'"))

  if [ -z "${storagesStatus[0]}" ]; then
    echo "ERROR: tracker $tracker monitor timeout！" >> $LOG_PATH
    trackers[$tracker]="OFFLINE"
  else
    for storageStatus in ${storagesStatus[@]}
    do
      storage=`echo ${storageStatus} | awk -F":" '{print $1}'`
  	  status=`echo ${storageStatus} | awk -F":" '{print $2}'`
  	  if [ "$status" != "ACTIVE" ]; then
	    echo "ERROR: tracker $tracker storage $storage is $status!" >> $LOG_PATH
		storages[$storage]="OFFLINE"
	  fi
    done

    for i in {1..10}
    do
      tempfile=($(ssh $tracker "timeout 5 fdfs_test /etc/fdfs/client.conf upload /etc/fdfs/client.conf 2>/dev/null | grep -E 'remote_filename=|ip_addr=' | grep -v -E '_big|server' | sed 's/group_name=\(.*\), remote_filename=\(.*\)/\1 \2/g' | sed 's/group_name=\(.*\), ip_addr=\(.*\), port=\(.*\)/\2/g'"))
      storage="${tempfile[0]}"
      if [ -z "$storage" ]; then
        echo "ERROR: tracker $tracker upload timeout！" >> $LOG_PATH
        trackers[$tracker]="OFFLINE"
      else
        if [ -z "${tempfile[1]}" ]; then
          echo "ERROR: tracker $tracker storage $storage cannot upload！" >> $LOG_PATH
          storages[$storage]="OFFLINE"
        else
          trackers[$tracker]="ACTIVE"
          storages[$storage]="ACTIVE"
          echo "INFO: tracker $tracker storage $storage work fine！" >> $LOG_PATH
          ssh $tracker "fdfs_test /etc/fdfs/client.conf delete ${tempfile[1]} ${tempfile[2]} >/dev/null 2>&1"
        fi
      fi
    done
  fi
done

for storage in ${!storages[@]}
do
  connectCnt=`ssh $storage "netstat -antp | grep fdfs_storaged  | grep ESTABLISHED -c"`
  echo "INFO: storage $storage is ${storages[$storage]}, connected $connectCnt" >> $LOG_PATH
  if [ "${storages[$storage]}" != "ACTIVE" ]; then
    echo "HANDLE: storage $storage record logs and restart it！" >> $LOG_PATH
    ssh $storage "tail -n100 /file/fdfs/logs/storaged.log" >> $LOG_PATH
    ssh $storage "kill -9 $(ps -ef|grep fdfs_storaged|gawk '$0 !~/grep/ {print $2}' |tr -s '\n' ' ') >/dev/null 2>&1" >> $LOG_PATH
    ssh $storage "/usr/local/bin/fdfs_storaged /etc/fdfs/storage.conf >/dev/null 2>&1" >> $LOG_PATH
  fi
done

for tracker in ${!trackers[@]}
do
  connectCnt=`ssh $tracker "netstat -antp | grep fdfs_trackerd | grep ESTABLISHED -c"`
  echo "INFO: tracker $tracker is ${trackers[$tracker]}, connected $connectCnt" >> $LOG_PATH
  if [ "${trackers[$tracker]}" != "ACTIVE" ]; then
    echo "HANDLE: tracker $tracker record logs and restart it！" >> $LOG_PATH
    ssh $tracker "tail -n100 /data/fastdfs/logs/trackerd.log" >> $LOG_PATH
    ssh $tracker "kill -9 $(ps -ef|grep fdfs_trackerd|gawk '$0 !~/grep/ {print $2}' |tr -s '\n' ' ') >/dev/null 2>&1" >> $LOG_PATH
    ssh $tracker "/usr/local/bin/fdfs_trackerd /etc/fdfs/tracker.conf >/dev/null 2>&1" >> $LOG_PATH
  fi
done
