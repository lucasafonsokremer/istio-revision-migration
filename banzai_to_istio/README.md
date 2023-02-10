# Migrar do Banzaioperator para istio operator

## Instalando e configurando o ambiente com Banzaioperator

### Instalar Banzaioperator de exemplo

- Instalando Helm

```
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null 
sudo apt-get install apt-transport-https --yes 
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list 
sudo apt-get update 
sudo apt-get install helm
```

- Instalar banzaioperator (versão 1.7.8 do Istio)

```
helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
helm install --create-namespace --namespace=istio-system istio-operator banzaicloud-stable/istio-operator --version 0.0.69
```

### Configurando o Operator

```
cat <<EOF | kubectl apply -n istio-system -f - 
apiVersion: istio.banzaicloud.io/v1beta1 
kind: Istio 
metadata: 
  labels: 
    controller-tools.k8s.io: "1.0" 
  name: istio-operator 
spec: 
  mtls: false 
  version: "1.7.8" 
  includeIPRanges: "*" 
  excludeIPRanges: "" 
  autoInjectionNamespaces: 
  - "default" 
  outboundTrafficPolicy: 
    mode: ALLOW_ANY 
  gateways: 
    enabled: true 
    ingress: 
      enabled: true 
    egress: 
      enabled: false 
  telemetry: 
    enabled: false 
  tracing: 
    enabled: false 
  localityLB: 
    enabled: false 
  policy: 
    enabled: false 
EOF
```

### Criando um app de teste

```
kubectl create namespace demoapp ; kubectl label namespace demoapp istio-injection=enabled
```

```
kubectl -n demoapp apply -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/platform/kube/bookinfo.yaml
```

### Instalando o MetalLB para criar um serviço do tipo LoadBalancer

- Destinado à ambientes onpremise

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml
```

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml
```

```
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```

```
cat <<EOF | kubectl apply -f -
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
      - 192.168.10.5-192.168.10.9
EOF
```

### Criar entradas para expor à aplicação no gateway

```
kubectl create -n demoapp -f https://raw.githubusercontent.com/istio/istio/master/samples/bookinfo/networking/bookinfo-gateway.yaml
```

### Testando o Acesso

```
IP=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I $IP/productpage
```

### Output
