#!/bin/bash
# 构建 software-distribution-platform-example/nginx：
#   构建镜像（FROM nginx:perl + 自定义 index.html）-> docker save 镜像 tar
#   charts/ chart 源目录 -> 渲染版本后打 tgz；最终 pack 成 <component>-<version>.tar.gz
#   （charts + images 一起交付）
#
# 用法: ./build.sh [version]    默认 v0.0.1
#       ./build.sh clean        清理 output/
#
set -e

BUILD_DIR=$(cd "$(dirname "$0")"; pwd)
OUTPUTDIR="${BUILD_DIR}/../../output"
component=nginx
version=${1:-"v0.0.1"}

buildDate=$(TZ=Asia/Shanghai date +%FT%T%z)

function clean(){
    rm -rf "${OUTPUTDIR}"
    echo "${component} output cleaned."
}

if [ "${1:-}" = "clean" ]; then
    clean
    exit 0
fi

function prepare_build_file(){
    mkdir -p "${OUTPUTDIR}"
    cp -rf "${BUILD_DIR}/charts" "${OUTPUTDIR}/"
    cp -rf "${BUILD_DIR}/images" "${OUTPUTDIR}/"
}

# 版本渲染：打包前把 version 渲染进 output/charts 副本
# （不动仓内源文件），避免交付包镜像 tag 与 chart 版本脱节。
function sed_inplace(){
    # 不用 sed -i：BSD 与 GNU 的 -i 语义不同、本机可能混装，统一走临时文件覆盖。
    local expr="$1" file="$2"
    sed "${expr}" "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
}

function render_chart_version(){
    local chartdir="${OUTPUTDIR}/charts/${component}"
    local vf="${chartdir}/values.yaml"
    local cf="${chartdir}/Chart.yaml"
    local repo
    repo=$(sed -nE 's/^[[:space:]]*imageAddr:[[:space:]]*(.*):[^:]*[[:space:]]*$/\1/p' "${vf}" | head -1)
    if [ -z "${repo}" ]; then
        echo "ERROR: 未能在 ${vf} 解析 imageAddr 的仓库地址" >&2
        exit 1
    fi
    sed_inplace "s#^\([[:space:]]*imageAddr:[[:space:]]*\).*#\1${repo}:${version}#" "${vf}"
    sed_inplace "s#^version: .*#version: ${version#v}#" "${cf}"
    echo "chart rendered: imageAddr=${repo}:${version} chartVersion=${version#v}"
}

function build_nginx_image(){
    pushd "${OUTPUTDIR}/images" > /dev/null
    echo "== docker build ${component}:${version} =="
    # 镜像名与 chart values.imageAddr 保持一致（默认 localhost:5000 为本地构建约定）。
    # 不用 --network host：macOS Docker Desktop 不支持 host 网络；nginx 构建仅需 COPY，无需容器内联网。
    docker build . -t "localhost:5000/${component}:${version}"
    docker save -o "${OUTPUTDIR}/images/${component}-${version}.tar" "localhost:5000/${component}:${version}"
    if [ -f "${OUTPUTDIR}/images/${component}-${version}.tar" ]; then
        echo "${component} build image successfully."
    else
        echo "${component} build image failed."
        exit 1
    fi
    popd > /dev/null
}

# 可选: 有本地 registry（如 kind 环境 localhost:5000）时打 tag 推送，失败不阻断。
function push_to_local_registry(){
    if docker push "localhost:5000/${component}:${version}" 2>/dev/null; then
        echo "${component} pushed to localhost:5000."
    else
        echo "WARN: push to localhost:5000 failed (no local registry?), skip."
    fi
}

function charts_pack(){
    pushd "${OUTPUTDIR}/charts" > /dev/null
    tar -zcvf "${component}-${version}.tgz" "${component}"
    if [ -f "${component}-${version}.tgz" ]; then
        echo "${component} charts pack successfully."
    else
        echo "${component} charts pack failed."
        exit 1
    fi
    popd > /dev/null
}

function pack(){
    pushd "${OUTPUTDIR}" > /dev/null
    # 交付包仅含 chart tgz + 镜像 tar（去除 charts/<component> 源目录、images 源文件等冗余副本）：
    #   charts/<component>-<version>.tgz
    #   images/<component>-<version>.tar
    tar -zcvf "${component}-${version}.tar.gz" \
        "charts/${component}-${version}.tgz" \
        "images/${component}-${version}.tar"
    if [ -f "${component}-${version}.tar.gz" ]; then
        echo "${component} pack successfully."
        echo "== 交付包: ${OUTPUTDIR}/${component}-${version}.tar.gz =="
        echo "== 交付包内容 =="
        tar -tzvf "${component}-${version}.tar.gz"
    else
        echo "${component} pack failed."
        exit 1
    fi
    popd > /dev/null
}

prepare_build_file
render_chart_version
build_nginx_image
push_to_local_registry
charts_pack
pack
