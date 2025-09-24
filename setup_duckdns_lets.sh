#!/usr/bin/env bash
# setup_duckdns_lets.sh
# سكربت واحد لإصدار شهادة Let's Encrypt عبر DuckDNS وتثبيتها لمجلد macless-haystack

set -euo pipefail
IFS=$'\n\t'

# ------------ اضبط المتغيرات هنا قبل التشغيل -------------
DOMAIN="omar-khalid.duckdns.org"        # غيّر إن لزم
DUCKDNS_TOKEN="c3758fc2-751c-4e19-aa14-b1727eddf1a7"   # توكن DuckDNS (آمن لو على جهازك)
EMAIL="omar.com1992@gmail.com"          # بريدك لتسجيل حساب ACME
DATA_PATH="/var/lib/docker/volumes/mh_data/_data"  # مكان mh_data على نظامك
ACME_HOME="${HOME}/.acme.sh"
ACME_BIN="${ACME_HOME}/acme.sh"
# ---------------------------------------------------------

echo "بدء السكربت: إصدار شهادة Let's Encrypt للنطاق ${DOMAIN}"
echo

# تأكد من وجود مجلد البيانات
if [ ! -d "${DATA_PATH}" ]; then
  echo "مجلد البيانات ${DATA_PATH} غير موجود. سأقوم بإنشائه."
  mkdir -p "${DATA_PATH}"
  chown root:root "${DATA_PATH}" || true
fi

# 1) تثبيت acme.sh إن لم يكن موجوداً
if [ ! -x "${ACME_BIN}" ]; then
  echo "acme.sh غير مُثبّت. أقوم بالتثبيت الآن..."
  curl -sSfL https://get.acme.sh | SHELL=/bin/bash /bin/bash
  # source لإتاحة الأمر في الجلسة الحالية
  if [ -f "${ACME_HOME}/acme.sh" ]; then
    ACME_BIN="${ACME_HOME}/acme.sh"
  fi
fi

if [ ! -x "${ACME_BIN}" ]; then
  echo "خطأ: لم أتمكن من إيجاد acme.sh بعد التثبيت. افحص التثبيت يدوياً."
  exit 1
fi

echo "استخدام acme.sh الموجود في: ${ACME_BIN}"
echo

# 2) ضبط متغير بيئة DuckDNS (يحتاجه dnsapi)
export DuckDNS_Token="${DUCKDNS_TOKEN}"

# 3) تسجيل حساب لدى Let's Encrypt إن لم يُسجَّل
echo "تسجيل/تحديث حساب لدى Let's Encrypt بالإيميل ${EMAIL} (إن لزم)..."
"${ACME_BIN}" --register-account -m "${EMAIL}" --server letsencrypt || true
echo

# 4) إصدار الشهادة عبر DNS - duckdns
echo "طلب شهادة عبر DNS (duckdns) ل ${DOMAIN} ..."
# --force/--debug/--log يمكن إضافتها إن أردت تفاصيل. هنا نستخدم --log لملف لوق محلي.
LOGFILE="/tmp/acme_${DOMAIN}_$(date +%s).log"
"${ACME_BIN}" --issue --dns dns_duckdns -d "${DOMAIN}" --server letsencrypt --log > "${LOGFILE}" 2>&1 || {
  echo "فشل إصدار الشهادة — راجع اللوق: ${LOGFILE}"
  tail -n 80 "${LOGFILE}"
  exit 2
}

echo "صدرت الشهادة بنجاح (راجع اللوق: ${LOGFILE})."
echo

# 5) تثبيت الشهادة في مجلد mh_data (privkey.pem و certificate.pem)
echo "تثبيت الشهادة في ${DATA_PATH} ..."
"${ACME_BIN}" --install-cert -d "${DOMAIN}" \
  --key-file       "${DATA_PATH}/privkey.pem" \
  --fullchain-file "${DATA_PATH}/certificate.pem" \
  --reloadcmd "docker restart macless-haystack" \
  > /tmp/acme_install_${DOMAIN}.log 2>&1 || {
    echo "خطأ أثناء تثبيت الشهادة. راجع /tmp/acme_install_${DOMAIN}.log"
    tail -n 80 /tmp/acme_install_${DOMAIN}.log
    exit 3
  }

echo "الشهادة و المفتاح تم تثبيتها."
ls -l "${DATA_PATH}/privkey.pem" "${DATA_PATH}/certificate.pem" || true

# 6) ضبط الصلاحيات المناسبة
echo "ضبط صلاحيات الملفات (root:root، 600 للمفتاح، 644 للشهادة)..."
chown root:root "${DATA_PATH}/privkey.pem" "${DATA_PATH}/certificate.pem" || true
chmod 600 "${DATA_PATH}/privkey.pem" || true
chmod 644 "${DATA_PATH}/certificate.pem" || true

# 7) أعد تشغيل الحاوية (إن لم يتم عبر reloadcmd)
echo "إعادة تشغيل الحاوية macless-haystack..."
if docker ps -a --format '{{.Names}}' | grep -q '^macless-haystack$'; then
  docker restart macless-haystack || echo "تحذير: فشل إعادة تشغيل الحاوية"
else
  echo "لم أعثر على حاوية مسماة macless-haystack على هذا النود؛ تأكد أن الحاوية موجودة."
fi

# 8) تحقق سريع من الوصول إلى المنفذ مع curl
echo
echo "تحقق سريع: جلب رأس HTTPS من https://${DOMAIN}:6176 (سيظهر تفاصيل الشهادة إن نجح)"
if command -v curl >/dev/null 2>&1; then
  curl -vk --max-time 10 "https://${DOMAIN}:6176/" || echo "تحذير: تحقّق الاتصال فشل أو المنفذ ليس مفتوحاً."
else
  echo "curl غير مثبت، لا يمكن إجراء تحقق تلقائي."
fi

echo
echo "تم الانتهاء. الشهادة مثبتة في ${DATA_PATH} ، والتجديد التلقائي مُعتمد عبر acme.sh (cron مُضاف تلقائياً)."
echo "ملاحظات: إذا أردت تشغيل السكربت بدون إظهار التوكن في التاريخ أو اللوجات، ضع التوكن في متغير بيئة مؤمن قبل تشغيل."

