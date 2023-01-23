# istio-revision-migration

Istio: Upgrading Istio without revision to fully revisioned control plane

## Install

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
