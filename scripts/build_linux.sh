#!/usr/bin/env bash
# AudioShelf Linux 构建脚本（Ubuntu）
set -euo pipefail

cd "$(dirname "$0")/.."

# 中国镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build linux --release"
flutter build linux --release

echo ""
echo "✅ 构建完成：build/linux/x64/release/bundle/audioshelf"
