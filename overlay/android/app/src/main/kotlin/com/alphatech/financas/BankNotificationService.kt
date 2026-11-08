package com.alphatech.financas

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

// Captura notificações dos apps de banco e guarda numa fila; o Flutter lê e limpa a fila.
class BankNotificationService : NotificationListenerService() {
    private val banks = setOf(
        "com.nu.production",          // Nubank
        "br.com.intermedium",         // Inter
        "com.itau",                   // Itaú
        "com.bradesco",               // Bradesco
        "br.com.bb.android",          // Banco do Brasil
        "com.c6bank.app",             // C6
        "br.com.santander.way",       // Santander
        "com.picpay",                 // PicPay
        "com.mercadopago.wallet",     // Mercado Pago
        "br.com.gabba.Caixa"          // Caixa
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in banks) return
        val ex = sbn.notification.extras
        val title = ex.getCharSequence("android.title")?.toString() ?: ""
        val text = (ex.getCharSequence("android.bigText") ?: ex.getCharSequence("android.text"))?.toString() ?: ""
        val prefs = getSharedPreferences("fin_queue", MODE_PRIVATE)
        synchronized(BankNotificationService::class.java) {
            val q = JSONArray(prefs.getString("q", "[]"))
            q.put(JSONObject().put("pkg", sbn.packageName).put("title", title)
                .put("text", text).put("ts", sbn.postTime))
            prefs.edit().putString("q", q.toString()).apply()
        }
    }
}
