#!/bin/bash
# axonhub/version.sh
# 使用公共函数库，但自己决定过滤规则

set -euo pipefail

# 加载公共函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.functions/github.sh"
source "${SCRIPT_DIR}/../.functions/version.sh"

# 镜像特定配置
LAST_VERSION=v1.0.0-beta10-96bf086
OWNER="looplj"
REPO="axonhub"
DAYS_BEFORE=1

# 计算补丁指纹：对 series 清单 + 所有引用的 patch 内容取 sha256 前 7 位。
# 相同补丁集 → 相同指纹；任何改动 → 指纹变化。无补丁时返回 "none"。
patches_hash() {
    local patches_dir="${SCRIPT_DIR}/patches"
    local series_file="${patches_dir}/series"

    if [[ ! -f "$series_file" ]]; then
        echo "none"
        return 0
    fi

    # 拼接 series 内容与所有 patch 文件内容，统一哈希
    {
        cat "$series_file"
        while IFS= read -r line; do
            case "$line" in \#*|"") continue ;; esac
            cat "${patches_dir}/${line}" 2>/dev/null || echo "MISSING:${line}"
        done < "$series_file"
    } | sha256sum | cut -c1-7
}

# axonhub特定的tag过滤函数
# 跟踪所有语义化版本（含预发布版本，如v1.0.0-beta7）
filter_axonhub_tags() {
    local tags_json="$1"

    echo "$tags_json" | jq '
      map(select(
        .name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z]+[0-9]*)?$")
      ))
    '
}

main() {
    log_info "检测 $OWNER/$REPO 的新版本"

    local all_tags
    all_tags=$(query_github_tags "$OWNER" "$REPO") || {
        log_error "查询GitHub tags失败"
        echo "current_version="
        echo "last_version=${LAST_VERSION}"
        echo "upstream_version="
        return 1
    }

    local filtered_tags
    filtered_tags=$(filter_axonhub_tags "$all_tags")

    local cutoff_timestamp
    cutoff_timestamp=$(days_ago_timestamp "$DAYS_BEFORE") || {
        log_error "计算截止时间失败"
        echo "current_version="
        echo "last_version=${LAST_VERSION}"
        echo "upstream_version="
        return 1
    }

    local stable_tags
    stable_tags=$(filter_tags_before_date "$filtered_tags" "$cutoff_timestamp")

    local upstream_version
    upstream_version=$(get_latest_tag "$stable_tags")

    if [[ -z "$upstream_version" ]]; then
        log_warning "未找到符合条件的稳定版本（${DAYS_BEFORE}天前）"
        echo "current_version="
        echo "last_version=${LAST_VERSION}"
        echo "upstream_version="
        return 0
    fi

    # 组合版本：上游 tag + 补丁指纹
    # 例: v1.0.0-beta7-a1b2c3d
    local phash
    phash=$(patches_hash)

    local current_version="${upstream_version}-${phash}"

    echo "current_version=${current_version}"
    echo "last_version=${LAST_VERSION}"
    echo "upstream_version=${upstream_version}"
}

# 运行主函数
main "$@"
