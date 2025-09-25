#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$HOME/FindMy"
DOCKER_VOL="/var/lib/docker/volumes/mh_data/_data"

# 1) تثبيت Docker
echo "1) تثبيت Docker..."
apt update
apt install -y ca-certificates curl gnupg lsb-release apt-transport-https
apt install -y docker.io docker-compose-plugin
systemctl enable --now docker

# 2) إنشاء شبكة و Volumes
echo "2) إنشاء الشبكة و Volumes..."
docker network create mh-network >/dev/null 2>&1 || true
docker volume create mh_data >/dev/null 2>&1 || true
docker volume create anisette-v3_data >/dev/null 2>&1 || true

# 3) تشغيل anisette
echo "3) تشغيل Anisette..."
docker run -d --restart always --name anisette \
  -p 6969:6969 \
  --volume anisette-v3_data:/home/Alcoholic/.config/anisette-v3 \
  --network mh-network \
  dadoum/anisette-v3-server:latest

# 4) تشغيل macless-haystack
echo "4) تشغيل Macless-Haystack..."
docker run -d --restart unless-stopped --name macless-haystack \
  -p 6176:6176 \
  -v mh_data:/app/endpoint/data \
  --network mh-network \
  christld/macless-haystack:latest

# 5) تجهيز بيئة FindMy
echo "5) تثبيت FindMy وبيئة Python..."
apt install -y git python3 python3-venv python3-pip libssl-dev libffi-dev build-essential
if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR" && git pull || true
else
  git clone https://github.com/biemster/FindMy.git "$PROJECT_DIR"
  cd "$PROJECT_DIR"
fi

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install pbkdf2 srp requests cryptography pycryptodome

# 6) تشغيل request_reports.py للتسجيل
echo
echo "⚠️ أدخل بيانات Apple ID / Password / 2FA عند الطلب..."
cd "$PROJECT_DIR"
source venv/bin/activate
python3 request_reports.py --regen --trusteddevice &

# 7) انتظار توليد auth.json
echo "⌛ في انتظار إنشاء auth.json..."
while [ ! -f "$PROJECT_DIR/auth.json" ]; do
  sleep 5
done

# 8) نقل auth.json بعد توليده
echo "📂 نقل auth.json إلى $DOCKER_VOL..."
cp "$PROJECT_DIR/auth.json" "$DOCKER_VOL/auth.json"
chmod 600 "$DOCKER_VOL/auth.json"
echo "✅ تم النقل. إعادة تشغيل macless-haystack..."
docker restart macless-haystack

echo
echo "✅ انتهى التثبيت والإعداد بالكامل!"

