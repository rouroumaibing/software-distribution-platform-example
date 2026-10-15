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

# ---------- 容器运行时自感知分派（docker / containerd-nerdctl 双支持）----------
# k8s 1.24+ 默认 containerd、节点无 docker：构建与镜像操作按本地可用运行时分派。
# 默认 nerdctl（containerd 工具）；若环境存在 docker 命令则重赋为 docker；
# 否则保持 nerdctl；nerdctl 须已在环境中就绪，缺失直接报失败（不做自动安装）。
SDP_RUNTIME="${SDP_RUNTIME:-nerdctl}"

ensure_nerdctl() {
    # nerdctl 硬判断：环境中必须已安装 nerdctl + buildkitd，否则直接报失败。
    # （nerdctl build 依赖 buildkitd，nerdctl 不自带也不自动启动；离线节点请提前装好。）
    command -v nerdctl >/dev/null 2>&1 || {
        echo "ERROR: 当前环境无 docker，且未检测到 nerdctl，无法构建镜像。请先安装 nerdctl + buildkitd。" >&2
        exit 1
    }
    command -v buildkitd >/dev/null 2>&1 || {
        echo "ERROR: 检测到 nerdctl 但缺少 buildkitd（nerdctl build 必需），请先安装 buildkitd。" >&2
        exit 1
    }
    pgrep -x buildkitd >/dev/null 2>&1 || nohup buildkitd --containerd-worker --addr tcp://127.0.0.1:1234 >/var/log/buildkitd.log 2>&1 &
    export BUILDKIT_HOST=tcp://127.0.0.1:1234
}

resolve_runtime() {
    case "${SDP_RUNTIME}" in docker|nerdctl) ;; *) echo "ERROR: SDP_RUNTIME 仅支持 docker|nerdctl" >&2; exit 1 ;; esac
    if command -v docker >/dev/null 2>&1; then SDP_RUNTIME=docker; return 0; fi
    ensure_nerdctl
    nerdctl info >/dev/null 2>&1 || { echo "ERROR: containerd/nerdctl 不可达" >&2; exit 1; }
}

sdp_build() { local ctx="$1" img="$2"; shift 2
    case "${SDP_RUNTIME}" in
        docker)  docker  build  "$@" -t "$img" "$ctx" ;;
        nerdctl) nerdctl build  "$@" -t "$img" "$ctx" ;;
    esac; }
sdp_save() {
    if [ -n "${2:-}" ]; then
        case "${SDP_RUNTIME}" in
            docker)  docker  save -o "$2" "$1" ;;
            nerdctl) nerdctl save --format docker -o "$2" "$1" ;;
        esac
    else
        case "${SDP_RUNTIME}" in
            docker)  docker  save "$1" ;;
            nerdctl) nerdctl save --format docker "$1" ;;
        esac
    fi; }
sdp_inspect() { case "${SDP_RUNTIME}" in docker) docker image inspect "$1" ;; nerdctl) nerdctl image inspect "$1" ;; esac; }
sdp_pull() { case "${SDP_RUNTIME}" in docker) docker pull "$1" ;; nerdctl) nerdctl pull "$1" ;; esac; }
sdp_tag() { case "${SDP_RUNTIME}" in docker) docker tag "$1" "$2" ;; nerdctl) nerdctl tag "$1" "$2" ;; esac; }
sdp_push() { case "${SDP_RUNTIME}" in docker) docker push "$1" ;; nerdctl) nerdctl push "$1" ;; esac; }
sdp_login() { case "${SDP_RUNTIME}" in docker) docker login "$@" ;; nerdctl) nerdctl login "$@" ;; esac; }

resolve_runtime; echo "== container runtime: ${SDP_RUNTIME} =="

function build_nginx_image(){
    pushd "${OUTPUTDIR}/images" > /dev/null
    echo "== build ${component}:${version} (runtime=${SDP_RUNTIME}) =="
    sdp_build . "localhost:5000/${component}:${version}"
    sdp_save "localhost:5000/${component}:${version}" "${OUTPUTDIR}/images/${component}-${version}.tar"
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
    if sdp_push "localhost:5000/${component}:${version}" 2>/dev/null; then
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
