# 1. 节点亲和性扫描 (Advanced JSONPath)
# 场景： 某些 Pod 被固定调度到了特定节点，你需要找出这些 Pod 强制要求的 nodeSelector。
# 题目： 请输出所有 Pod 的名字及其 nodeSelector 的内容。

# 挑战点： nodeSelector 并不总是存在（很多 Pod 没有这个字段）。

# 要求： 如果 Pod 没有 nodeSelector，该行留空或显示空对象，不要让命令报错。

# 提示： 路径是 .spec.nodeSelector。
k get pod -o custom-columns="NAME:.metadata.name,NODESELECTOR:.spec.nodeSelector"
NAME                                                         NODESELECTOR
ccy-npu-dev-2qf29-worker-0                                   map[host-arch:huawei-arm]
ccy-vllm-dev-hjsxc-worker-0                                  map[host-arch:huawei-arm]
deploy-api-shanjifei-14-a3-0-w95bd-worker-0                  map[host-arch:huawei-arm]
deploy-api-shanjifei-14-a3-1-8jjmd-copy-copy-worker-0        map[accelerator-type:module-910c-8 host-arch:huawei-arm]
deploy-api-shanjifei-14-a3-1-8jjmd-copy-worker-0             map[accelerator-type:module-910c-8 host-arch:huawei-arm]


# 2. 多容器重启识别 (Custom Columns + Multi-Field)
# 场景： 在多容器 Pod 中，只看 RESTARTS 总数是不够的，你可能想知道具体是哪个镜像在崩。
# 题目： 展示一张表，包含：

# POD_NAME

# CONTAINER_NAMES (显示该 Pod 内所有容器的名字，逗号隔开)

# RESTART_COUNTS (显示该 Pod 内所有容器对应的重启次数，逗号隔开)

# 提示： 路径分别是 .spec.containers[*].name 和 .status.containerStatuses[*].restartCount。
k get pod grafana-6b67974595-dmgvb -n infra \
-o jsonpath='{"POD\t\t\t\tCONTAINER\t\tRESTART\n"}{range .status.containerStatuses[*]}{"grafana-6b67974595-dmgvb"}{"\t"}{.name}{"\t"}{.restartCount}{"\n"}{end}'
POD				CONTAINER		RESTART
grafana-6b67974595-dmgvb	grafana	0
grafana-6b67974595-dmgvb	grafana-sc-alerts	0
grafana-6b67974595-dmgvb	grafana-sc-dashboard	0
grafana-6b67974595-dmgvb	grafana-sc-datasources	0


# 3. 寻找“孤儿”或“特定控制器” Pod (Field Selector)
# 场景： 你想找那些不是由 Deployment（实际上是 ReplicaSet）管理的“裸” Pod，或者是特定控制器创建的 Pod。
# 题目： 筛选出所有 metadata.ownerReferences 为空的 Pod（即没有父级控制器的 Pod）。

# 注意： --field-selector 不支持 ownerReferences。

# 题目要求： 请写出一段命令（可以配合 jq 或 jsonpath 过滤），找出那些没有控制器的“手动创建”的 Pod。
k get pod -A -o jsonpath='{range .items[?(!@.metadata.ownerReferences)]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
k get pod -A -o go-template='{{range .items}}{{if not .metadata.ownerReferences}}{{.metadata.namespace}}{{"/"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'
k get pod -A -o json | jq -r '.items[] | select(.metadata.ownerReferences == null) | "\(.metadata.namespace)/\(.metadata.name)"'



# 4. 镜像拉取策略审计 (Bulk Inspection)
# 场景： 安全审计要求所有镜像必须设置 imagePullPolicy: Always。
# 题目： 请找出当前命名空间下，所有镜像拉取策略 不是 Always 的容器镜像名称。

# 要求： 只输出镜像名，且去重（如果有多个 Pod 用同一个镜像）。

# 提示： 路径是 .spec.containers[?(@.imagePullPolicy!="Always")].image。注意：这是 JSONPath 的过滤语法 [?(...)]。
k get pod -A -o jsonpath='{range .items[*].spec.containers[?(@.imagePullPolicy!="Always")]}{.image}{"\n"}{end}' | sort | uniq
kubectl get pod -A -o go-template='{{range .items}}\
{{range .spec.containers}}\
{{if ne .imagePullPolicy "Always"}}{{.image}}{{"\n"}}{{end}}{{end}}{{end}}' | sort | uniq
registry.sensetime.com/sensecore/infra/coredns/coredns:v1.11.3
registry2.d.pjlab.org.cn/ccr-deeplink/lmdeploy_dlinfer:0.12.3rc
registry2.d.pjlab.org.cn/ccr-deeplink/lmdeploy_dlinfer:a3-v0.11.1
registry2.d.pjlab.org.cn/ccr-hw/910c:83RC3_PTA271_official


# 5. 服务类型与端口映射 (Custom Columns)
# 场景： 你需要快速导出一张 Service 清单给网络组。
# 题目： 展示所有 Service，包含：

# SVC_NAME

# TYPE (ClusterIP, NodePort 等)

# CLUSTER_IP

# EXTERNAL_IP

# PORT_MAP (显示格式如 80:30008/TCP)

# 提示： 端口映射比较复杂，路径涉及 .spec.ports[*].port, .spec.ports[*].nodePort, .spec.ports[*].protocol。
k get svc -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,IP:.spec.clusterIP,PORT_MAP:.spec.ports[*].port"

kubectl get svc -o go-template='{{printf "%-25s %-10s %-15s %-20s\n" "NAME" "TYPE" "CLUSTER-IP" "PORTS"}} \
{{range .items}}{{printf "%-25s %-10s %-15s" .metadata.name .spec.type .spec.clusterIP}} \
{{range .spec.ports}}{{.port}}/{{.protocol}} {{end}}{{"\n"}}{{end}}'
NAME                                      TYPE        IP             PORT_MAP
ccy-vllm-dev-hjsxc                        ClusterIP   None           <none>
deploy-api-1464-xujun-a3-0-4sg4j          ClusterIP   None           <none>
dyh-npu-dev-lg8vf                         ClusterIP   None           <none>
jmx-0111                                  ClusterIP   None           <none>
jmx-hw-xtuner                             ClusterIP   None           <none>
kubernetes                                ClusterIP   10.108.34.80   443,9200,9201