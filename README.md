# Terragrunt and ArgoCD in Azure k8s
---
First of all, we have to create k8s cluster and install ArgoCD into it.

+ Run on terminal

```
az login
az ad sp create-for-rbac --skip-assignment
cd max/eu-central/prod
export TF_VAR_appId=<paste azure application id>
export TF_VAR_password='<paste azure password>'
export AWS_PROFILE=s3-terraform-state
terragrunt run-all apply --terragrunt-non-interactive
cd aks && az aks get-credentials --resource-group $(terragrunt output -raw resource_group_name) --name $(terragrunt output -raw kubernetes_cluster_name) && cd -
```

+ Check K8S cluster

```
kubectl get nodes -o wide
kubectl get pod --all-namespaces -o wide
kubectl get ns
kubectl run -it --rm pod1 --image=busybox --restart=Never -- sh
```

## Argo CD

### Use Argo CD instractions from [getting_started](https://argoproj.github.io/argo-cd/getting_started/)  

install and configure cli app for manage argocd

```
brew install argocd #for macOS users. For other systems, you can get instructions from the official site.
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
argocd login localhost:8080
```
Create, get, sync and delete application in k8s using argocd cli app.

```
argocd app create guestbook \
    --repo https://github.com/k8s-rs-test/argocd-example-apps.git \
    --path guestbook \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace default \
    --port-forward-namespace argocd

argocd app get guestbook --port-forward-namespace argocd
argocd app sync guestbook --port-forward-namespace argocd

argocd app delete guestbook
```
### ArgoCD create app of the apps.

In this screenshot you can see argo-cd-config module
![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/argocd-config.png)

In this screenshot, you can see the struct of the argoCD application that we have configured in the previous screenshot.
![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/chart-app.png)

As we have done port-forward for service argocd-server we can connect to UI on localhost:8080, use admin as login and password from 'argocd-initial-admin-secret' secret.  

In this screenshot, you can see the guestbook app before the sync run. 
![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/argocd-create-app-from-cli.png)

We can add to k8s different resources by adding files to a specific path in our git repository.

![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/add-yaml-to-dir.png)

We can prioritize the manifests order in which they were applying to the k8s cluster
![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/set-sync-annotation.png)

We can use helm to deploy our application.  
[Here](https://raw.githubusercontent.com/dubass83/learn-terraform-provision-aks-cluster/master/apps/system/templates/helm-loki.yaml) you can see an example of how to deploy helm application in k8s using argoCD.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki-stack
  # You'll usually want to add your resources to the argocd namespace.
  namespace: argocd
  # Add a this finalizer ONLY if you want these to cascade delete.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # The project the application belongs to.
  project: system

  # Source of the application manifests
  source:
    chart: loki-stack
    repoURL: https://grafana.github.io/helm-charts
    targetRevision: 2.3.1
    # helm specific config
    helm:
      # Release name override (defaults to application name)
      releaseName: loki-stack
      # Values file as block file
      values: |
        loki:
          enabled: true

          config:
            auth_enabled: false
            ingester:
              chunk_idle_period: 3m
              chunk_block_size: 262144
              chunk_retain_period: 1m
              max_transfer_retries: 0
              lifecycler:
                ring:
                  kvstore:
                    store: inmemory
                  replication_factor: 1
            limits_config:
              enforce_metric_name: false
              reject_old_samples: true
              reject_old_samples_max_age: 168h
            schema_config:
              configs:
              - from: 2020-10-24
                store: boltdb-shipper
                object_store: filesystem
                schema: v11
                index:
                  prefix: index_
                  period: 24h
            server:
              http_listen_port: 3100
            table_manager:
              retention_deletes_enabled: true
              retention_period: 336h
          persistence:
            enabled: false
            
        promtail:
          enabled: true

        grafana:
          enabled: true
          sidecar:
            datasources:
              enabled: true
          # image:
          #   tag: 6.7.0
          image:
            repository: grafana/grafana
            tag: 7.5.3
            sha: ""
            pullPolicy: IfNotPresent
          securityContext:
            runAsUser: 472
            runAsGroup: 472
            fsGroup: 472
          service:
            type: NodePort
            port: 80
            targetPort: 3000
            nodePort: 30091
            portName: service

          serviceMonitor:
            enabled: false
            labels:
              release: prometheus

          persistence:
            enabled: false
            
          env:
            GF_SESSION_PROVIDER: memory
            GF_SESSION_SESSION_LIFE_TIME: 1800
            GF_USERS_ALLOW_SIGN_UP: false
            
          plugins:
          - camptocamp-prometheus-alertmanager-datasource
          - briangann-datatable-panel
          - vonage-status-panel
          - btplc-peak-report-panel
          - mtanda-heatmap-epoch-panel
          - mtanda-histogram-panel
          - briangann-gauge-panel
          - jdbranham-diagram-panel
          - neocat-cal-heatmap-panel
          - digiapulssi-breadcrumb-panel
          - ryantxu-ajax-panel
          - grafana-piechart-panel
          - grafana-clock-panel
          - grafana-simple-json-datasource
          - cloudflare-app
          - btplc-status-dot-panel
          # App failed to recreate container when try to reinstall this plugin
          #- vertamedia-clickhouse-datasource
          #- alexanderzobnin-zabbix-app

          datasources:
            datasources.yaml:
              apiVersion: 1
              datasources:
              - name: Prometheus
                type: prometheus
                url: http://prometheus-prometheus-oper-prometheus:9090/
                access: proxy
                isDefault: true
              - name: Loki
                type: loki
                url: http://loki:3100/
                access: proxy

  # Destination cluster and namespace to deploy the application
  destination:
    server: https://kubernetes.default.svc
    namespace: plat-system

  # Sync policy
  syncPolicy:
    automated:
      prune: true # Specifies if resources should be pruned during auto-syncing ( false by default ).
      selfHeal: true # Specifies if partial app sync should be executed when resources are changed only in target Kubernetes cluster and no git change detected ( false by default ).
    syncOptions:     # Sync options which modifies sync behavior
    - Validate=false # disables resource validation (equivalent to 'kubectl apply --validate=true')
```


![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/argocd-main-page.png)

When you start using argoCD you get better observability of your k8s cluster.

![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/add-helm-app.png)

![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/grafana-summary.png)

![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/grafana-events.png)

![](https://s3.eu-central-1.amazonaws.com/cdn.dubass83.xyz/imgs/grafana-logs.png)



### Clean

```
killall kubectl
```

```
terragrunt run-all destroy --terragrunt-non-interactive
```