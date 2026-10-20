# Makefile — software-distribution-platform-example/nginx-canary 本地构建
# 本组件自包含：只依赖仓内脚本（build/nginx-canary/build.sh），不依赖仓库外任何脚本。

APP := nginx-canary

# canary 场景需要同一软件的两个版本来做灰度对照：
# 先后执行 make package VERSION=v0.0.1 与 make package VERSION=v0.0.2 产出两份版本包。
VERSION ?= v0.0.1

.PHONY: help package clean

help:
	@echo "targets:"
	@echo "  package  组件打包：构建镜像 + chart，输出 <component>-<version>.tar.gz (build/$(APP)/build.sh)"
	@echo "  clean    删除本组件生成物(output/)"

package:
	bash build/$(APP)/build.sh $(VERSION)

clean:
	rm -rf $(CURDIR)/output
	@echo "[clean:$(APP)] done."
