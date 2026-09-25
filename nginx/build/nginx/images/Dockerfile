# nginx 运行时镜像。
# 构建上下文只含本文件与 index.html：nginx:perl 基座 + 替换默认首页，产出一张静态页。
FROM nginx:perl
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
