# nginx

一个独立、可部署到任意 Kubernetes 集群的 **nginx 软件样例**：基于 `nginx:perl` 官方镜像，
仅替换默认首页 `index.html`，对外提供一张静态页面。它不依赖任何特定平台，普通 k8s 即可部署。

## 软件结构

```
nginx/
├── Makefile                       # 构建入口（package / clean）
├── build/nginx/
│   ├── build.sh                   # 打包脚本：构建镜像 + chart -> 版本包 tar.gz
│   ├── images/
│   │   ├── Dockerfile             # FROM nginx:perl + COPY index.html
│   │   └── index.html             # 自定义首页（改这里即可换页面内容）
│   └── charts/nginx/              # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml        # NodePort（节点 / port-forward 访问）
│           └── nginx-httproute.yaml# 可选：挂 Gateway API 网关的路由（默认关闭）
└── output/                        # 构建产物（gitignore，clean 可清）
    └── nginx-v0.0.1.tar.gz         # 版本包（charts + images）
```

版本包（`make package` 产出）内部只含两样东西：

```
nginx-v0.0.1.tar.gz
├── charts/nginx-v0.0.1.tgz     # helm chart（Deployment + Service，可选 HTTPRoute）
└── images/nginx-v0.0.1.tar     # docker save 导出的镜像
```

## 构建

```bash
cd software-distribution-platform-example/nginx
make package            # 默认 v0.0.1，产出 output/nginx-v0.0.1.tar.gz
make clean              # 清 output/
```

## 部署

chart 通过 Helm 安装，命名空间使用 release 所在的命名空间（不指定 `-n` 即 **`default`**）：

```bash
helm install nginx ./build/nginx/charts/nginx            # 装到 default
# 或指定命名空间： helm install nginx ./build/nginx/charts/nginx -n my-ns
```

镜像默认打在 `localhost:5000/nginx:<version>`；若目标集群无法直连该仓库，先
`docker push` 到你的镜像仓库，再用 `--set image.imageAddr=<repo>/nginx:<version>` 覆盖。

## 部署后是什么模样

部署后，集群里有一个 nginx Pod（容器端口 **80**，首页已被替换为自定义静态页）
和一个名为 `nginx` 的 Service（端口 80，类型 NodePort）。页面访问方式：

1. **port-forward（最通用，任意 k8s 适用，推荐调试用）**
   ```bash
   kubectl -n default port-forward svc/nginx 8080:80
   # 浏览器打开 http://localhost:8080/
   ```

2. **NodePort（从集群节点访问）**
   ```bash
   kubectl -n default get svc nginx   # 查看自动分配的 NODE_PORT
   # 浏览器打开 http://<节点IP>:<NODE_PORT>/
   ```

3. **网关 / Ingress（对外域名访问，可选）**
   - 若集群已部署 Gateway API 网关，可开启 chart 自带 HTTPRoute：`--set gatewayRoute.enabled=true`
     （默认 host `test.com`、路径 `/`，网关名可按 `--set gatewayRoute.name=` 覆盖）。
   - 也可自行创建 Ingress，把域名（如 `test.com`）指向 `svc/nginx:80`。

> 默认 `gatewayRoute.enabled=false`：普通 k8s 不装网关也能完整运行，仅上面的方式 1 / 2 即可访问。
