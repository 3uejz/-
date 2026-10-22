#!/bin/sh
set -eu

: "${MINIO_ROOT_USER:?缺少 MINIO_ROOT_USER}"
: "${MINIO_ROOT_PASSWORD:?缺少 MINIO_ROOT_PASSWORD}"
: "${OBJECT_BUCKET:?缺少 OBJECT_BUCKET}"
: "${OBJECT_ACCESS_KEY:?缺少 OBJECT_ACCESS_KEY}"
: "${OBJECT_SECRET_KEY:?缺少 OBJECT_SECRET_KEY}"
: "${CI_ACCESS_KEY:?缺少 CI_ACCESS_KEY}"
: "${CI_SECRET_KEY:?缺少 CI_SECRET_KEY}"

ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
POLICY_DIR="${POLICY_DIR:-/policies}"
MC_CONFIG_DIR="${MC_CONFIG_DIR:-/tmp/mc}"
export MC_CONFIG_DIR

attempt=0
until mc alias set local "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "MinIO 在 120 秒内未就绪" >&2
    exit 1
  fi
  sleep 2
done

mc mb --ignore-existing "local/$OBJECT_BUCKET"
mc version enable "local/$OBJECT_BUCKET" >/dev/null 2>&1 || true
mc anonymous set none "local/$OBJECT_BUCKET" >/dev/null 2>&1 || true

sed "s/__BUCKET__/$OBJECT_BUCKET/g" "$POLICY_DIR"/server-rw.json > /tmp/server-rw.json
sed "s/__BUCKET__/$OBJECT_BUCKET/g" "$POLICY_DIR"/ci-rw.json > /tmp/ci-rw.json

mc admin user add local "$OBJECT_ACCESS_KEY" "$OBJECT_SECRET_KEY" >/dev/null 2>&1 || true
mc admin user add local "$CI_ACCESS_KEY" "$CI_SECRET_KEY" >/dev/null 2>&1 || true

mc admin policy create local lifetext-server-rw /tmp/server-rw.json >/dev/null 2>&1 || true
mc admin policy create local lifetext-ci-rw /tmp/ci-rw.json >/dev/null 2>&1 || true

mc admin policy attach local lifetext-server-rw --user "$OBJECT_ACCESS_KEY" >/dev/null 2>&1 || true
mc admin policy attach local lifetext-ci-rw --user "$CI_ACCESS_KEY" >/dev/null 2>&1 || true

echo "MinIO 初始化完成: bucket=$OBJECT_BUCKET server=$OBJECT_ACCESS_KEY ci=$CI_ACCESS_KEY"
