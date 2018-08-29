#!/bin/bash

if [ $(kubectl get pods -l app=adhoc-zk |grep Running |wc -l) == 0 ]; then
    echo "start create zookeeper cluster"
    kubectl create -f zk/zk-pv.yaml
    kubectl create -f zk/zk-pvc.yaml
    kubectl create -f zk/adhoc-zookeeper.yaml
#    kubectl create -f zookeeper/zookeeper-service.yaml
#    kubectl create -f zookeeper/zookeeper.yaml
    while [ $(kubectl get pods -l app=adhoc-zk |grep Running |wc -l) != 3 ]; do sleep 1; done;
    echo "finish create zookeeper cluster"
fi

product_name=$2
#product_auth="auth"
if [ x"$product_name" = x ]; then
    echo 'Please use below command to start server:'
    echo 'sh start.sh (cleanup|buildup|scale-proxy|scale-server) (PRODUCT_NAME) [REPLICAS]'
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function remove_all() {
    sed "s/PRODUCT_NAME/$product_name/g" codis-service-template.yaml | kubectl delete -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-dashboard-template.yaml | kubectl delete -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-proxy-template.yaml | kubectl delete -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-server-template.yaml | kubectl delete -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-ha-template.yaml | kubectl delete -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-fe-template.yaml | kubectl delete -f -
}

function create_pv() {
    num=$1
    name=datadir-codis-server-$product_name-$num
    if [ $(kubectl get pvc |grep $name |wc -l) == 0 ]; then
        sed "s/PRODUCT_NAME/$product_name/g ; s/NUM/$num/g" glusterfs/glusterfs-pvc-local.yaml | kubectl create -f -
    fi
}

function create_pvc() {
    num=$1
    name=codis-pv-$product_name-$num
    if [ $(kubectl get pv |grep $name |wc -l) == 0 ]; then
        sed "s/PRODUCT_NAME/$product_name/g ; s/NUM/$num/g" glusterfs/glusterfs-pv-local.yaml | kubectl create -f -
    fi
}

case "$1" in

### 清理原来codis遗留数据
cleanup)
    # kubectl delete -f .
    remove_all
    # 如果zookeeper不是在kurbernetes上，需要登陆上zk机器 执行 zkCli.sh -server {zk-addr}:2181 rmr /codis3/$product_name
    kubectl exec -it adhoc-zk-0 -- zkCli.sh -server adhoc-zk-0:2181 rmr /codis3/$product_name
    ;;

### 创建新的codis集群
buildup)
    # kubectl delete -f .
    remove_all
    # 如果zookeeper不是在kurbernetes上，需要登陆上zk机器 执行 zkCli.sh -server {zk-addr}:2181 rmr /codis3/$product_name
    kubectl exec -it adhoc-zk-0 -- zkCli.sh -server adhoc-zk-0:2181 rmr /codis3/$product_name
    sed "s/PRODUCT_NAME/$product_name/g" codis-service-template.yaml | kubectl create -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-dashboard-template.yaml | kubectl create -f -
    while [ $(kubectl get pods -l app=codis-dashboard-$product_name |grep Running |wc -l) != 1 ]; do sleep 1; done;
    sed "s/PRODUCT_NAME/$product_name/g" codis-proxy-template.yaml | kubectl create -f -
    for (( i=0; i<2; i++)); do create_pv $i; create_pvc $i; done;
    sed "s/PRODUCT_NAME/$product_name/g" codis-server-template.yaml | kubectl create -f -
    servers=$(grep "replicas" codis-server-template.yaml |awk  '{print $2}')
    while [ $(kubectl get pods -l app=codis-server-$product_name |grep Running |wc -l) != $servers ]; do sleep 1; done;
    kubectl exec -it codis-server-$product_name-0 -- codis-admin  --dashboard=codis-dashboard-$product_name:18080 --rebalance --confirm
    sed "s/PRODUCT_NAME/$product_name/g" codis-ha-template.yaml | kubectl create -f -
    sed "s/PRODUCT_NAME/$product_name/g" codis-fe-template.yaml | kubectl create -f -
    sleep 60
    kubectl exec -it codis-dashboard-$product_name-0 -- redis-cli -h codis-proxy-$product_name -p 19000 PING
    if [ $? != 0 ]; then
        echo "buildup codis cluster with problems, plz check it!!"
    fi
    ;;

### 扩容／缩容 codis proxy
scale-proxy)
    kubectl scale rc codis-proxy-$product_name --replicas=$3
    ;;

### 扩容／[缩容] codis server
scale-server)
    cur=$(kubectl get statefulset codis-server-$product_name |tail -n 1 |awk '{print $3}')
    des=$3
    echo $cur
    echo $des
    if [ $cur == $des ]; then
        echo "current server == desired server, return"
    elif [ $cur -lt $des ]; then
        for (( i=$des-$cur+1; i<$des; i++)); do create_pv $i; create_pvc $i; done;
        kubectl scale statefulsets codis-server-$product_name --replicas=$des
        while [ $(kubectl get pods -l app=codis-server-$product_name |grep Running |wc -l) != $3 ]; do sleep 1; done;
        kubectl exec -it codis-server-$product_name-0 -- codis-admin  --dashboard=codis-dashboard-$product_name:18080 --rebalance --confirm
    else
        echo "reduce the number of codis-server-$product_name, does not support, please wait"
        # while [ $cur > $des ]
        # do
        #    cur=`expr $cur - 2`
        #    gid=$(expr $cur / 2 + 1)
        #    kubectl exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --slot-action --create-some --gid-from=$gid --gid-to=1 --num-slots=1024
        #    while [ $(kubectl exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080  --slots-status |grep "\"backend_addr_group_id\": $gid" |wc -l) != 0 ]; do echo "waiting slot migrating..."; sleep 1; done;
        #    kubectl scale statefulsets codis-server --replicas=$cur
        #    kubectl exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --remove-group --gid=$gid
        # done
        # kubectl scale statefulsets codis-server --replicas=$des
        # kubectl exec -it codis-server-0 -- codis-admin  --dashboard=codis-dashboard:18080 --rebalance --confirm
    fi
    ;;

*)
    echo "wrong argument(s)"
    ;;

esac
