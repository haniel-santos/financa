#!/usr/bin/env bash
# Uso: ./setup.sh  (precisa do Flutter instalado)
set -e
flutter create --org com.alphatech --project-name financas --platforms android app
cp -r overlay/* app/
python3 - <<'PY'
p = "app/android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
svc = '''    <service android:name=".BankNotificationService" android:label="Finanças"
        android:exported="true"
        android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
        <intent-filter>
            <action android:name="android.service.notification.NotificationListenerService"/>
        </intent-filter>
    </service>
'''
if "BankNotificationService" not in s:
    s = s.replace("</application>", svc + "</application>")
    open(p, "w", encoding="utf-8").write(s)
PY
cd app && flutter pub get
echo "Pronto. Conecte o celular e rode: cd app && flutter run"
