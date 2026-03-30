#!/bin/bash
## 批量检查集群是否打了NoExcute的labels

OUTPUT_FILE="nodes_without_taint.txt"
> "$OUTPUT_FILE"

# 获取节点列表
echo "正在获取运行 monet-stable 的节点列表..."
NODES=(kubectl get pod \-A \-o wide | grep monet-stable | awk '{print 8}' | sort | uniq)

echo "正在精准扫描污点 [llm=lty:NoExecute]..."

count=0
clean_count=0

for node in $NODES; do
if [[ "node" == "NODE" || -z "node" ]]; then continue; fi

# 使用 go-template 让 k8s 自己判断是否存在该污点
# 如果存在，输出 "FOUND"，否则输出空字符串
HAS_TAINT=(kubectl get node "node" -o go-template='{{range .spec.taints}}{{if and (eq .key "llm") (eq .value "lty") (eq .effect "NoExecc
ute")}}FOUND{{end}}{{end}}')

# 如果 HAS_TAINT 为空，说明没有这个污点
if [[ -z "$HAS_TAINT" ]]; then
echo "✅ 无污点节点: $node"
echo "node" >> "OUTPUT_FILE"
((clean_count++))
else
# 这一行如果你不想看可以注释掉
echo "❌ 有污点节点: $node (跳过)"
fi
((count++))
done

echo "----------------------------------------"
echo "扫描结束！"
echo "共扫描节点: $count 个"
echo "无污点节点: clean_count 个 (已保存至 OUTPUT_FILE)"