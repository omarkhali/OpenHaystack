#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIG ----------
DOMAIN="omar-khalid.duckdns.org"
MH_DATA_DIR="/var/lib/docker/volumes/mh_data/_data"
DOCKER_CONTAINER="macless-haystack"
MKCERT_BIN="/usr/local/bin/mkcert"   # سيتم تحميل mkcert هنا إذا لم يكن موجود
EXPORT_ROOT="/root/rootCA.pem"       # ملف root CA النهائي على السيرفر
# --------------------------

echo "ابدأ: إصدار شهادة mkcert للمجال $DOMAIN"

# اكتشاف آركيتيكشر لتحميل النسخة المناسبة (عند الضرورة)
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) MKARCH="linux-amd64" ;;
  aarch64|arm64) MKARCH="linux-arm64" ;;
  armv7l) MKARCH="linux-arm" ;;
  *) echo "معمارية غير معروفة: $ARCH — عدّل السكربت يدوياً" >&2; exit 1 ;;
esac

# 1) تحقق من وجود مجلد mh_data
if [ ! -d "$MH_DATA_DIR" ]; then
  echo "خطأ: المجلد $MH_DATA_DIR غير موجود. تأكد من المسار." >&2
  exit 1
fi

# 2) تثبيت mkcert إن لم يكن موجودًا
if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert غير موجود. سأحمّله إلى $MKCERT_BIN ..."
  TMP="/tmp/mkcert-${MKARCH}.bin"
  DOWNLOAD_URL="https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-${MKARCH}"
  curl -L -sSf -o "$TMP" "$DOWNLOAD_URL"
  chmod +x "$TMP"
  mv "$TMP" "$MKCERT_BIN"
  echo "mkcert نُصِب في $MKCERT_BIN"
else
  MKCERT_BIN="$(command -v mkcert)"
  echo "mkcert مثبت في $MKCERT_BIN"
fi

# 3) إنشاء/تثبيت جذر CA المحلي
echo "تشغيل: mkcert -install (قد يطلب التفاعل)"
"$MKCERT_BIN" -install

# 4) إصدار شهادة للمجال
TMPDIR="$(mktemp -d)"
CERT_OUT="$TMPDIR/certificate.pem"
KEY_OUT="$TMPDIR/privkey.pem"

echo "إصدار شهادة للمجال $DOMAIN ..."
"$MKCERT_BIN" -cert-file "$CERT_OUT" -key-file "$KEY_OUT" "$DOMAIN"

# 5) عمل نسخ احتياطية للملفات القديمة إن وُجدت
for f in certificate.pem privkey.pem; do
  if [ -f "$MH_DATA_DIR/$f" ]; then
    ts=$(date +"%Y%m%d_%H%M%S")
    cp -a "$MH_DATA_DIR/$f" "$MH_DATA_DIR/${f}.bak.$ts"
    echo "نسخة احتياطية: $MH_DATA_DIR/${f}.bak.$ts"
  fi
done

# 6) نقل الشهادة والمفتاح إلى مجلد mh_data
mv -f "$CERT_OUT" "$MH_DATA_DIR/certificate.pem"
mv -f "$KEY_OUT" "$MH_DATA_DIR/privkey.pem"
chown root:root "$MH_DATA_DIR/certificate.pem" "$MH_DATA_DIR/privkey.pem" || true
chmod 644 "$MH_DATA_DIR/certificate.pem" || true
chmod 600 "$MH_DATA_DIR/privkey.pem" || true
echo "نُقِلَت الشهادة و المفتاح إلى $MH_DATA_DIR"

# 7) تصدير Root CA إلى /root/rootCA.pem
# استخدم mkcert -CAROOT لمعرفة مكان root
CAROOT="$("$MKCERT_BIN" -CAROOT 2>/dev/null || echo "/root/.local/share/mkcert")"
ROOT_PEM="$CAROOT/rootCA.pem"
if [ -f "$ROOT_PEM" ]; then
  cp -f "$ROOT_PEM" "$EXPORT_ROOT"
  chmod 644 "$EXPORT_ROOT"
  echo "تم تصدير root CA إلى: $EXPORT_ROOT"
else
  echo "تحذير: لم أجد rootCA.pem في $CAROOT — تحقق يدوياً"
fi

# 8) تنظيف مؤقت
rm -rf "$TMPDIR"

# 9) إعادة تشغيل الحاوية إذا وُجدت
if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
  echo "إعادة تشغيل الحاوية $DOCKER_CONTAINER ..."
  docker restart "${DOCKER_CONTAINER}" && echo "تم إعادة تشغيل ${DOCKER_CONTAINER}"
else
  echo "لم أجد حاوية باسم ${DOCKER_CONTAINER} — شغّلها يدوياً إن كنت تريد"
fi

echo "انتهى. الملفات:"
ls -l "$MH_DATA_DIR/certificate.pem" "$MH_DATA_DIR/privkey.pem" || true
if [ -f "$EXPORT_ROOT" ]; then
  ls -l "$EXPORT_ROOT"
fi
echo ""
echo "الخطوة التالية: انسخ /root/rootCA.pem إلى جهازك (mac/iphone) وثبته لعمل ثقة بالشهادة."

