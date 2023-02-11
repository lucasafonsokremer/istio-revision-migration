# Migrar do Banzaioperator para istio operator com Zero Downtime

## Links Importantes

- [Advanced canary Upgrade](https://istio.io/latest/docs/setup/additional-setup/gateway/#canary-upgrade-advanced)
- [Gateway Operator Upgrade](https://istio.io/v1.11/docs/setup/upgrade/gateways/#upgrade-with-operator)
- [Habilitar Jaeger de testes](https://istio.io/latest/docs/ops/integrations/jaeger/)
- [Habilitar Prometheus de testes](https://istio.io/latest/docs/ops/integrations/prometheus/)

## Possíveis Debugs

- Validar configurações do control plane

```
kubectl get configmap -n istio-system istio-1-14-6 -o yaml
```

- Validar PILOT TRACE

```
kubectl -n istio-system get  deployment  istiod-1-14-6 -o yaml | grep  -A 2 'name: PILOT_TRACE_SAMPLING'
```

- Port Forward do Jaeger

```
kubectl port-forward svc/tracing 80:80 -n istio-system --address=0.0.0.0 &
```



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

```
root@k8s-master01:~/istio-1.14.6# IP=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
root@k8s-master01:~/istio-1.14.6# curl -I $IP/productpage
HTTP/1.1 200 OK
content-type: text/html; charset=utf-8
content-length: 5290
server: istio-envoy
date: Fri, 10 Feb 2023 13:44:31 GMT
x-envoy-upstream-service-time: 418

root@k8s-master01:~/istio-1.14.6# kubectl get services -n istio-system
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                                                      AGE
istio-ingressgateway       LoadBalancer   10.98.199.220   192.168.10.5   15021:31655/TCP,80:30714/TCP,443:30577/TCP,15443:31782/TCP   4m52s
istio-operator             ClusterIP      10.106.45.167   <none>         443/TCP                                                      5m31s
istio-operator-authproxy   ClusterIP      10.111.223.83   <none>         8443/TCP                                                     5m31s
istiod                     ClusterIP      10.103.213.70   <none>         15010/TCP,15012/TCP,443/TCP,15014/TCP,853/TCP                5m4s
root@k8s-master01:~/istio-1.14.6# istioctl proxy-status
NAME                                                   CLUSTER     CDS        LDS        EDS        RDS        ECDS         ISTIOD                      VERSION
details-v1-6758dd9d8d-nlhjg.demoapp                                SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
istio-ingressgateway-5b8cbc6d49-4nkb6.istio-system                 SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
productpage-v1-775bf8d9f-8jlnz.demoapp                             SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
ratings-v1-f849dc6d-99fdl.demoapp                                  SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
reviews-v1-74fb8fdbd8-n5sw4.demoapp                                SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
reviews-v2-58d564d4db-chxcr.demoapp                                SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
reviews-v3-55545c459b-wgq4k.demoapp                                SYNCED     SYNCED     SYNCED     SYNCED     NOT SENT     istiod-5c8f745fbf-gf2b8     1.7.4
```

## Instalando o Istio Operator

### Baixando o fonte

```
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.14.6 TARGET_ARCH=x86_64 sh -
```

```
cd istio-1.14.6/
export PATH=$PWD/bin:$PATH
```

### Instalando o Istio Operator

```
kubectl create namespace istio-operator
```

- Importante: Como o gateway já está no namespace do control plane o watchedNamespaces aqui só contem um namespace, caso o gateway estivesse em outro precisaríamos incrementar esta lista

```
helm upgrade --install istio-operator manifests/charts/istio-operator -n istio-operator --set revision=1-14-6 --set watchedNamespaces=istio-system
```

### Configurando o control plane

- Primeiramente vamos parar o BanzaiOperator, já que ele atua diferente do Istio Operator e gera conflito em alguns momentos

```
kubectl scale statefulset -n istio-system istio-operator --replicas=0
```

- Exemplo de config do control plane

```
kubectl apply -f - <<EOF
########################################################################################### 
# This is an Istio custom configuration file for PRODUCTION-LEVEL installations           # 
# https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/                      # 
# https://istio.io/latest/docs/reference/config/istio.operator.v1alpha1/                  # 
# https://istio.io/latest/docs/setup/upgrade/canary/                                      # 
#                                                                                         # 
###########################################################################################
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-control-plane-1-14-6
  namespace: istio-system
spec:
  # Only the control plane components are installed (https://istio.io/latest/docs/setup/additional-setup/config-profiles/)
  profile: minimal
  # root registry url
  #hub: "your-registry-url/istio"
  # Version for docker image
  tag: 1.14.6
  # Revision is set as 'version' label and part of the resource names when installing multiple control planes.
  # When using revision-based upgrades jumping across two minor versions is supported (e.g. upgrading directly from version 1.8 to 1.10)
  # This is in contrast to in-place upgrades where it is required to upgrade to each intermediate minor release.
  # You must replace . characters in the revision name, for example, revision=1-6-8 for Istio 1.6.8, because . is not a valid revision name character.
  revision: 1-14-6

  # meshConfig defines runtime configuration of components, including istiod and istio-agent behavior
  meshConfig:
    # File address for the proxy access log
    accessLogFile: "/dev/stdout"
    # Flag to control generation of trace spans and request IDs
    enableTracing: true
    defaultConfig:
      # The amount of time allowed for connections to complete on proxy shutdown
      terminationDrainDuration: "15s"
      # Tracing section
      # sampling = The percentage of requests (0.0 - 100.0) that will be randomly selected for trace generation
      # Reporting trace data in zipkin format to jaeger collector
      # https://www.jaegertracing.io/docs/1.6/getting-started/
      # This settings are move to meshConfig since istio 1.6.0
      # https://istio.io/latest/docs/tasks/observability/distributed-tracing/mesh-and-proxy-config/#customizing-trace-sampling
      tracing:
        sampling: "100.0"
        zipkin:
          address: "zipkin.istio-system:9411"

    # Set the default behavior of the sidecar for handling outbound traffic from the application
    outboundTrafficPolicy:
      mode: ALLOW_ANY

  # Specify global behavior
  # https://istio.io/v1.5/docs/reference/config/installation-options/#global-options
  values:
    global:
      imagePullPolicy: "IfNotPresent"
      # Sidecar resource settings
      proxy:
        # The Istio load tests mesh consists of 1000 services and 2000 sidecars with 70,000 mesh-wide requests
        # per second and istio-proxy used 0.35 vCPU and 40 MB memory per 1000 requests per second.
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 2000m
            memory: 1024Mi
        logLevel: warning

  # Traffic management feature
  components:
    pilot:
      enabled: true
      k8s:
        # Recommended to be >1 in production
        replicaCount: 2
        # The Istio load tests mesh consists of 1000 services and 2000 sidecars with 70,000 mesh-wide
        # requests per second and Istiod used 1 vCPU and 1.5 GB of memory.
        resources:
          requests:
            cpu: 200m
            memory: 200Mi
          limits:
            memory: 3072Mi
        strategy:
          rollingUpdate:
            maxSurge: 100%
            maxUnavailable: 25%                
        # Recommended to scale istiod under load
        hpaSpec:
          maxReplicas: 5
          minReplicas: 2
          scaleTargetRef:
            apiVersion: apps/v1
            kind: Deployment
            # matches the format istiod-<revision_label>
            name: istiod-1-14-6
          metrics:
            - resource:
                name: cpu
                targetAverageUtilization: 60
              type: Resource

        # Schedule pods on separate nodes if possible
        overlays:
          - apiVersion: apps/v1
            kind: Deployment
            # matches the format istiod-<revision_label>
            name: istiod-1-14-6
            patches:
              - path: spec.template.spec.affinity
                value:
                  podAntiAffinity:
                    preferredDuringSchedulingIgnoredDuringExecution:
                    - podAffinityTerm:
                        labelSelector:
                          matchExpressions:
                          - key: app
                            operator: In
                            values:
                            - istiod
                        topologyKey: kubernetes.io/hostname
                      weight: 100

        # Scale pods on specific node group
        #tolerations:
        #  - key: "istio"
        #    operator: "Equal"
        #    value: "istio-ingress"
        #    effect: "NoSchedule"

    # Istio Gateway feature
    # Disable gateways deployments, which are deployed in separate IstioOperator configurations
    ingressGateways:
    - name: istio-ingressgateway
      enabled: false
    - name: istio-eastwestgateway
      enabled: false
    egressGateways:
    - name: istio-egressgateway
      enabled: false

    # Istio CNI feature
    cni:
      enabled: false
EOF
```

- Exemplo de config do Gateway

```
########################################################################################### 
# This is an Istio custom configuration file for PRODUCTION-LEVEL installations           # 
# https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/                      # 
# https://istio.io/latest/docs/reference/config/istio.operator.v1alpha1/                  # 
# https://istio.io/latest/docs/setup/upgrade/canary/                                      # 
#                                                                                         # 
###########################################################################################
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-ingressgateway-1-14-6
  namespace: istio-system
spec:
  # Only the control plane components are installed (https://istio.io/latest/docs/setup/additional-setup/config-profiles/)
  profile: empty
  # root registry url
  #hub: "your-registry-url/istio"
  # Version for docker image
  tag: 1.14.6
  # Revision is set as 'version' label and part of the resource names when installing multiple control planes.
  # When using revision-based upgrades jumping across two minor versions is supported (e.g. upgrading directly from version 1.8 to 1.10)
  # This is in contrast to in-place upgrades where it is required to upgrade to each intermediate minor release.
  # You must replace . characters in the revision name, for example, revision=1-6-8 for Istio 1.6.8, because . is not a valid revision name character.
  revision: 1-14-6

  # Ingress Gateway section
  components:
    ingressGateways:
      - name: istio-ingressgateway-1-14-6
        namespace: istio-system
        enabled: true
        label:
          istio: ingressgateway-1-14-6
          version: 1-14-6
        k8s:
          overlays:
          - apiVersion: v1
            kind: Service
            name: istio-ingressgateway-1-14-6
            patches:
            - path: spec.selector
              value:
                app: istio-ingressgateway
                istio: ingressgateway
                service.istio.io/canonical-name: ingressgateway-1-14-6  
          - apiVersion: apps/v1
            kind: Deployment
            name: istio-ingressgateway-1-14-6
            patches:
              # Schedule pods on separate nodes if possible
              - path: spec.template.spec.affinity
                value:
                  podAntiAffinity:
                    preferredDuringSchedulingIgnoredDuringExecution:
                    - podAffinityTerm:
                        labelSelector:
                          matchExpressions:
                          - key: app
                            operator: In
                            values:
                              - istio-ingressgateway
                        topologyKey: kubernetes.io/hostname
                      weight: 100
              - path: spec.template.metadata.labels  
                value: 
                  app: istio-ingressgateway
                  gateway-name: istio-ingressgateway
                  gateway-type: ingress
                  istio: ingressgateway
                  istio.io/rev: 1-14-6
              - path: spec.selector.matchLabels
                value:
                  app: istio-ingressgateway
                  gateway-name: istio-ingressgateway
                  gateway-type: ingress
                  istio: ingressgateway
                  istio.io/rev: 1-14-6

          service:  
            # Since we created our own LoadBalanced service, tell istio to create a ClusterIP service for this gateway  
            type: ClusterIP  
            # match the LoadBalanced Service  
            ports:  
              - name: status-port  
                port: 15021  
                targetPort: 15021  
              - name: http2  
                port: 80  
                targetPort: 8080  
              - name: https  
                port: 443  
                targetPort: 8443  
              - name: tcp  
                port: 31400  
                targetPort: 31400  
              - name: tls  
                port: 15443  
                targetPort: 15443
```
