#!/bin/bash
# Populate metrics and logs by creating some ephimeral objects
# 


clear

trap ctrl_c INT

function ctrl_c() {
        echo -e "\033[1;34m"CTRL+C Pressed..."\033[0m"
        echo
        echo -e "\033[1;34m"Cleaning temporary objects, ACNPs, ANPs, Deployments, Services and Pods"\033[0m"
        cat /tmp/uuid | grep -e "-clusternetworkpolicy-" | xargs -n1 -I{arg} kubectl delete acnp {arg} 2>&1 >> /dev/null && echo -ne "."
        cat /tmp/uuid | grep -e "-networkpolicy-" | xargs -n1 -I{arg} kubectl delete anp {arg} 2>&1 >> /dev/null && echo -ne "."
        kubectl delete deployment www 2>&1 >> /dev/null && echo -ne "."
        kubectl delete svc www 2>&1 >> /dev/null && echo -ne "."
        kubectl delete pod curl --force --grace-period=0 >/dev/null 2>&1 && echo -ne "."
        kubectl delete pod ddos --force --grace-period=0 >/dev/null 2>&1 && echo -ne "."
        echo
        echo -e "\033[1;34m"Cleaning done! Thanks for using it!"\033[0m"
        echo
        echo
        exit 1
}
echo -e "\033[0;33m"   This simulator will create some activity in your cluster using current context"\033[0m"
echo -e "\033[0;33m"   It will spin up some client and a deployment-backed ClusterIP service based on apache application"\033[0m"
echo -e "\033[0;33m"   After that it will create random AntreaNetworkPolicies and AntreaClusterNetworkPolicies and it will generate some traffic with random patterns"\033[0m"
echo -e "\033[0;33m"   It will also randomly scale in and out the deployment during execution. This is useful for demo to see all metrics and logs showing up in the visualization tool"\033[0m"
echo

echo

# Create a service with Apache deployment
kubectl create deployment www --image=httpd --replicas=1 --port=80>/dev/null 2>&1
kubectl expose deployment/www --port=80 >/dev/null 2>&1

# Create pod with curl
kubectl run curl --image=curlimages/curl --command -- /bin/sh -c "sleep infinity" >/dev/null 2>&1

# Create pod with hping3 traffic simulation
kubectl run ddos --image=sflow/hping3 --command -- /bin/sh -c "sleep infinity" >/dev/null 2>&1

# Waiting for pods to be created
kubectl wait pods --for=jsonpath='{.status.phase}'=Running -l run=curl --timeout=1m >/dev/null 2>&1
kubectl wait pods --for=jsonpath='{.status.phase}'=Running -l app=www --timeout=1m >/dev/null 2>&1
kubectl wait pods --for=jsonpath='{.status.phase}'=Running -l run=ddos --timeout=1m >/dev/null 2>&1

echo -e "\033[5;41;1;37m   *** Starting activity simulation. Press CTRL+C to stop job ***   \033[0m"

actions=("Allow" "Drop" "Reject")
kinds=("ClusterNetworkPolicy" "NetworkPolicy")

:> /tmp/uuid
while true 
do 

for action in "${actions[@]}"
do
for kind in "${kinds[@]}"
do
echo -ne "."
kubectl scale deployment www --replicas=$[($RANDOM % 20) + 1] >/dev/null 2>&1
uuid=$(uuidgen)
name=$action-$kind-ingress-$uuid
name=$(echo "$name" | awk '{print tolower($0)}')
echo $name >> /tmp/uuid
cat << EOF | kubectl apply -f 2>&1 >> /dev/null -
apiVersion: crd.antrea.io/v1alpha1
kind: $kind
metadata:
  name: $name
spec:
  priority: 5
  tier: application
  appliedTo:
    - podSelector:
        matchLabels:
          app: www
  ingress:
    - action: $action
      from:
        - podSelector:
            matchLabels:
               run: curl
               run: ddos
      ports:
        - protocol: TCP
          port: 80
      name: ingress-$action-from-traficgens
      enableLogging: true
EOF
# Curl www application a random times
rnd=$(echo $[ $RANDOM % 15 + 2 ])
for ((run=1; run <= rnd; run++))
   do 
     kubectl exec curl -- curl -s www -m 1 >/dev/null 2>&1
   done
# Send random count of TCP SYN to www
kubectl exec ddos -- hping3 -c $[($RANDOM % 2000) + 1] --faster -S -p 80 www >/dev/null 2>&1
sleep .$[ ( $RANDOM % 20 ) + 1 ]s
done
done
# Egress Rules
for action in "${actions[@]}"
do
for kind in "${kinds[@]}"
do
echo -ne "."
kubectl scale deployment www --replicas=$[($RANDOM % 20) + 1] >/dev/null 2>&1
uuid=$(uuidgen)
name=$action-$kind-egress-$uuid
name=$(echo "$name" | awk '{print tolower($0)}')
echo $name >> /tmp/uuid
cat << EOF | kubectl apply -f 2>&1 >> /dev/null -
apiVersion: crd.antrea.io/v1alpha1
kind: $kind
metadata:
  name: $name
spec:
  priority: 5
  tier: application
  appliedTo:
    - podSelector:
        matchLabels:
          run: curl
          run: ddos
  egress:
    - action: $action
      to:
        - podSelector:
            matchLabels:
               app: www
      ports:
        - protocol: TCP
          port: 80
      name: egress-$action-to-www
      enableLogging: true
EOF
# Curl www application a random times
rnd=$(echo $[ $RANDOM % 15 + 2 ])
for ((run=1; run <= rnd; run++))
   do 
     kubectl exec curl -- curl -s www -m 1 >/dev/null 2>&1
   done
# Send random count of TCP SYN to www
kubectl exec ddos -- hping3 -c $[($RANDOM % 2000) + 1] --faster -S -p 80 www >/dev/null 2>&1
sleep .$[ ( $RANDOM % 20 ) + 1 ]s
done
done
# Recycling objects for new IPS
kubectl delete pod curl --force --grace-period=0 >/dev/null 2>&1 &&
kubectl delete pod ddos --force --grace-period=0 >/dev/null 2>&1 &&
kubectl delete svc www >/dev/null 2>&1 &&
kubectl run curl --image=curlimages/curl --command -- /bin/sh -c "sleep infinity" >/dev/null 2>&1
kubectl run ddos --image=sflow/hping3 --command -- /bin/sh -c "sleep infinity" >/dev/null 2>&1
kubectl expose deployment/www --port=80 >/dev/null 2>&1
# Waiting for pods to be created
kubectl wait pods --for=jsonpath='{.status.phase}'=Running -l run=curl --timeout=1m >/dev/null 2>&1
kubectl wait pods --for=jsonpath='{.status.phase}'=Running -l run=ddos --timeout=1m >/dev/null 2>&1
done
