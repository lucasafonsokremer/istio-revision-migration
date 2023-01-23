# istio-revision-migration

Istio: Upgrading Istio without revision to fully revisioned control plane

## Istio Direct Upgrades and Revision

- [Direct upgrades](https://istio.io/latest/blog/2021/direct-upgrade/)
- [Revision](https://istio.io/latest/blog/2021/revision-tags/)


## Install (Lab Only)

- Download istio

```
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.7.8 TARGET_ARCH=x86_64 sh -

curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.14.6 TARGET_ARCH=x86_64 sh -
```

- Export do ctl

```
cd istio-1.7.8/
export PATH=$PWD/bin:$PATH
```

- Install helm (Debian)

```
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null 
sudo apt-get install apt-transport-https --yes 
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list 
sudo apt-get update 
sudo apt-get install helm
```

- Install Istio (1.7.8)

```
# Create namespace
kubectl create namespace istio-operator

# Install without revision
helm upgrade --install istio-operator manifests/charts/istio-operator --set watchedNamespaces=istio-system

# Enable istio-injection
kubectl label namespace default istio-injection=enabled

# Create istio-system namespace
kubectl create namespace istio-system
```

- Enable istiod and istio gateway

```
kubectl apply -f - <<EOF 
apiVersion: install.istio.io/v1alpha1  
kind: IstioOperator  
metadata:  
  name: istio-control-plane 
  namespace: istio-system  
spec:  
  profile: default  
  components:  
    egressGateways:  
      - namespace: istio-system  
        name: istio-ingressgateway  
        enabled: false 
EOF
```

- Create httpbin

```
kubectl apply -f samples/httpbin/httpbin.yaml
```

```
kubectl apply -f - <<EOF  
apiVersion: networking.istio.io/v1alpha3  
kind: Gateway  
metadata:  
  name: httpbin-gateway  
spec:  
  selector:  
    istio: ingressgateway # use Istio default gateway implementation  
  servers:  
  - port:  
      number: 80  
      name: http  
      protocol: HTTP  
    hosts:  
    - "httpbin.example.com"  
EOF
```

```
kubectl apply -f - <<EOF  
apiVersion: networking.istio.io/v1alpha3  
kind: VirtualService  
metadata:  
  name: httpbin  
spec:  
  hosts:  
  - "httpbin.example.com"  
  gateways:  
  - httpbin-gateway  
  http:  
  - match:  
    - uri:  
        prefix: /status  
    - uri:  
        prefix: /delay  
    route:  
    - destination:  
        port:  
          number: 8000  
        host: httpbin  
EOF
```

- Install MetalLB (for cloud environment is not required)

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml

kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```

```
kubectl apply -f - <<EOF
apiVersion: v1 
kind: ConfigMap 
metadata: 
  namespace: metallb-system 
  name: config 
data: 
  config: | 
    address-pools: 
    - name: default 
      protocol: layer2 
      addresses: 
      - 192.168.10.20-192.168.10.30
EOF
```

- Check istio

```
export INGRESS_NAME=istio-ingressgateway 
export INGRESS_NS=istio-system

export INGRESS_HOST=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}') 
export INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="http2")].port}') 
export SECURE_INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="https")].port}') 
export TCP_INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="tcp")].port}') 
curl -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST:$INGRESS_PORT/status/200"
```

```
./show-istio-logs.sh
```

## Migrate to fully revisioned control plane (no downtime required for upgrades)

- [Github Issue](https://github.com/istio/istio/issues/40702)

## Install new release

```
cd ~/istio-1.14.6
```

```
helm upgrade --install istio-operator manifests/charts/istio-operator -n istio-operator --set revision=1-14-6 --set watchedNamespaces=istio-system
```

```
kubectl get deployment -n istio-operator
```

```
kubectl apply -f - <<EOF
apiVersion: install.istio.io/v1alpha1  
kind: IstioOperator  
metadata:  
  name: istio-control-plane-1-14-6   
  namespace: istio-system  
spec:  
  profile: default  
  revision: "1-14-6"  
#  components:  
#    egressGateways:   
#      - namespace: istio-system  
#        name: istio-ingressgateway  
#        enabled: false
EOF
```

```
kubectl label namespace default istio-injection-
```

- Check envoy

```
istioctl proxy-status
kubectl exec -it -n default httpbin-74d94f6c6c-jfc9s -c istio-proxy -- pilot-agent request GET server_info | head -n 5
```

- Set new label with rev

```
kubectl label namespace default istio.io/rev=1-14-6 --overwrite=true
```

```
kubectl rollout restart deployment httpbin
```

```
istioctl proxy-status
kubectl exec -it -n default httpbin-74d94f6c6c-jfc9s -c istio-proxy -- pilot-agent request GET server_info | head -n 5
```

- Logs

```
*********************************
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
istio-operator          1/1     1            1           2d19h
istio-operator-1-14-6   1/1     1            1           2d19h
    Image:      gcr.io/istio-testing/operator:latest
    Image:      docker.io/istio/operator:1.14.6
*********************************
NAME                         REVISION   STATUS    AGE
istio-control-plane                     HEALTHY   2d19h
istio-control-plane-1-14-6   1-14-6     HEALTHY   2d19h
*********************************
NAME                            WEBHOOKS   AGE
istio-sidecar-injector          4          2d19h
istio-sidecar-injector-1-14-6   2          2d19h
*********************************
NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
istio-ingressgateway   1/1     1            1           2d19h
                        operator.istio.io/version=1.14.6
    Image:       docker.io/istio/proxyv2:1.14.6
*********************************
NAME              STATUS   AGE     REV
default           Active   2d20h   1-14-6
istio-operator    Active   2d19h   
istio-system      Active   2d19h   
kube-node-lease   Active   2d20h   
kube-public       Active   2d20h   
kube-system       Active   2d20h   
metallb-system    Active   2d19h   
*********************************
NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                                      AGE
istio-ingressgateway   LoadBalancer   10.104.30.7      192.168.10.20   15021:30749/TCP,80:32322/TCP,443:32601/TCP   2d19h
istiod                 ClusterIP      10.98.198.201    <none>          15010/TCP,15012/TCP,443/TCP,15014/TCP        2d19h
istiod-1-14-6          ClusterIP      10.106.243.120   <none>          15010/TCP,15012/TCP,443/TCP,15014/TCP        2d19h
*********************************
No resources found in default namespace.
```
