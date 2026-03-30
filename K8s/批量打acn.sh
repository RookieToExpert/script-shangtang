# 执行如下脚本
for node in (cat "dataops-(date +%Y%m%d)-change.node"); do

echo "处理节点：$node"
kubectl label node "$node" node-role.sensecore.cn/dataops-data-plane-
kubectl taint node "$node" node-role.sensecore.cn/dataops-data-plane-

echo "添加新的 label 和 taint..."
##根据kubectl describe看节点的规格大小，找到对应的规格替换
kubectl label node $node node-role.compute.sensecore.cn/prod=ecp-private resource.compute.sensecore.cn/machine-type=acn.c1a.60xlarge --overwrite
kubectl taint node $node node-role.compute.sensecore.cn/prod=ecp:NoExecute --overwrite

echo "完成：$node"
done