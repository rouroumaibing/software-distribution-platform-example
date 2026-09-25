# Makefile — software-distribution-platform-example/nginx 本地构建
# 本组件自包含：只依赖仓内脚本（build/nginx/build.sh），不依赖仓库外任何脚本。

APP := nginx

# 交付产物统一落在 nginx/output/ 下（charts/ + images/ + <component>-<version>.tar.gz），
# clean 一条 rm -rf 即可清空。
.PHONY: help package clean

help:
	@echo "targets:"
	@echo "  package  组件打包：构建镜像 + chart，输出 <component>-<version>.tar.gz (build/$(APP)/build.sh)"
	@echo "  clean    删除本组件生成物(output/)"

package:
	bash build/$(APP)/build.sh

clean:
	rm -rf $(CURDIR)/output
	@echo "[clean:$(APP)] done."
