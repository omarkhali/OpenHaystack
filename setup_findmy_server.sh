#!/usr/bin/env bash
set -euo pipefail

# تعديل: غيّر REPO_URL أو PROJECT_DIR إذا أردت
REPO_URL="https://github.com/biemster/FindMy.git"
PROJECT_DIR="$HOME/FindMy"

# يجب تشغيله بصلاحيات sudo / root أو سيطلب sudo داخلياً
if ! command -v apt >/dev/null 2>&1; then
  echo "هذا السكربت مخصص لتوزيعات Debian/Ubuntu/Armbian (apt)."
  exit 1
fi

echo "1) تحديث النظام وتثبيت الحزم الأساسية..."
sudo apt update
sudo apt install -y git curl ca-certificates build-essential \
    python3 python3-venv python3-pip libssl-dev libffi-dev

echo "2) استنساخ المشروع إلى $PROJECT_DIR (أو تحديث إن موجود)..."
if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR"
  git pull || true
else
  git clone "$REPO_URL" "$PROJECT_DIR"
  cd "$PROJECT_DIR"
fi

echo "3) إنشاء وتفعيل virtualenv..."
python3 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate

echo "4) تحديث pip وتثبيت باقات بايثون المطلوبة..."
pip install --upgrade pip setuptools wheel
pip install pbkdf2 srp requests cryptography pycryptodome

echo
echo "التهيئة اكتملت. لتشغيل سكربت التقارير تفعيل venv ثم:"
echo "  cd $PROJECT_DIR"
echo "  source venv/bin/activate"
echo "  python3 request_reports.py --regen --trusteddevice"
echo
echo "ملاحظة: سكربت request_reports.py سيطلب Apple ID / Password / 2FA تفاعلياً."

