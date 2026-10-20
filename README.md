# software-distribution-platform-example

SDP（软件发布平台）**案例库** —— 收录可被 SDP 构建、分发、安装到环境的第三方软件范例。

## 案例

| 案例 | 说明 |
| --- | --- |
| [`nginx/`](./nginx) | 以 `nginx:perl` 为基础镜像、仅替换 `index.html` 的静态页面样例。 |
| [`nginx-canary/`](./nginx-canary) | nginx 案例的 canary 变体：版本占位首页 + app-only selector，独立可部署、天然支持多版本副本比例分流；与 nginx 案例并排对照，差异点见其 README。 |

## 如何使用一个案例

每个案例都自带独立构建入口，产出可被 SDP 发布的版本包（含镜像 tar + chart tgz）：

```bash
cd nginx
make package        # 产出 output/nginx-v0.0.1.tar.gz
make clean          # 清 output/
```

把版本包交给 SDP 软件发布（底层会加载镜像 tar + helm 安装 chart）即可。发布后的访问方式见各案例 `README.md`。
