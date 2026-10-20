# nginx-canary

[`nginx`](../nginx) 案例的 **canary 变体**：同一个 nginx 软件，独立、可部署到任意
Kubernetes 集群。与 nginx 案例并排对照，差异点即知识点——把一个普通软件改造成
**可灰度发布**的软件，最小改动只需要两处。

## 与 nginx 案例的差异（全部差异，仅此 2 处）

| # | 差异 | 作用 |
| --- | --- | --- |
| 1 | `images/index.html` 带 `__APP_VERSION__` 占位符，构建时由 build.sh 渲染为版本号 | 每个版本的首页自带版本标识，`curl` 即可区分 v0.0.1 / v0.0.2 |
| 2 | Deployment / Service 的 `selector` 只含 `app` 标签（nginx 案例多一个 `version: v1`） | 同一 Service 能同时选中**不同镜像版本**的 pod——多版本并存（灰度/滚动发布）时，流量按副本比例自然分布，无需改动 selector |

其余部分（Makefile / build.sh / chart 结构 / NodePort Service）与 nginx 案例完全同型。

## 软件结构

```
nginx-canary/
├── Makefile                       # 构建入口（package / clean）
├── build/nginx-canary/
│   ├── build.sh                   # 打包脚本：构建镜像 + chart -> 版本包 tar.gz
│   ├── images/
│   │   ├── Dockerfile             # FROM nginx:perl + COPY index.html
│   │   └── index.html             # 自定义首页（带 __APP_VERSION__ 占位符）
│   └── charts/nginx-canary/       # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml        # NodePort
│           └── nginx-httproute.yaml# 可选：挂 Gateway API 网关的路由（默认关闭）
└── output/                        # 构建产物（gitignore，clean 可清）
```

## 构建

灰度对照需要**同一软件的两个版本**，先后构建两份版本包：

```bash
cd software-distribution-platform-example/nginx-canary
make package                  # 默认 v0.0.1，产出 output/nginx-canary-v0.0.1.tar.gz
make package VERSION=v0.0.2   # 产出 output/nginx-canary-v0.0.2.tar.gz
make clean
```

## 部署

chart 通过 Helm 安装，命名空间使用 release 所在的命名空间（不指定 `-n` 即 **`default`**）：

```bash
helm install nginx-canary ./build/nginx-canary/charts/nginx-canary            # 装到 default
# 或指定命名空间： helm install nginx-canary ./build/nginx-canary/charts/nginx-canary -n my-ns
```

镜像默认打在 `localhost:5000/nginx-canary:<version>`；若目标集群无法直连该仓库，先
push 到你的镜像仓库，再用 `--set image.imageAddr=<repo>/nginx-canary:<version>` 覆盖。

## 部署后是什么模样

部署后，集群里有一个 nginx-canary Pod（容器端口 **80**，首页带版本号标识）
和一个名为 `nginx-canary` 的 Service（端口 80，类型 NodePort）。页面访问方式：

1. **port-forward（最通用，任意 k8s 适用，推荐调试用）**
   ```bash
   kubectl -n default port-forward svc/nginx-canary 8080:80
   # 浏览器打开 http://localhost:8080/，页面显示 version: v0.0.1
   ```

2. **NodePort（从集群节点访问）**
   ```bash
   kubectl -n default get svc nginx-canary   # 查看自动分配的 NODE_PORT
   curl http://<节点IP>:<NODE_PORT>/
   ```

3. **网关 / Ingress（对外域名访问，可选）**
   - 若集群已部署 Gateway API 网关，可开启 chart 自带 HTTPRoute：`--set gatewayRoute.enabled=true`
     （默认 host `test.com`、路径 `/`，网关名可按 `--set gatewayRoute.name=` 覆盖）。
   - 也可自行创建 Ingress，把域名指向 `svc/nginx-canary:80`。

> 默认 `gatewayRoute.enabled=false`：普通 k8s 不装网关也能完整运行，仅上面的方式 1 / 2 即可访问。

## 多版本并存

把 v0.0.1 与 v0.0.2 两个版本装进同一集群（不同 release 名或不同命名空间），各自页面
显示各自的版本号；若把两个版本的 pod 挂到同一个 Service 下（标签同为 `app: nginx-canary`），
Service 会按 pod 副本比例分发流量——这正是灰度发布的基础形态。
