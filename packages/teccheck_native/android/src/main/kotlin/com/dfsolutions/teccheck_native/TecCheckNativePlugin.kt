package com.dfsolutions.teccheck_native

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.Executors

class TecCheckNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingPerm: MethodChannel.Result? = null
    private val pool = Executors.newFixedThreadPool(64)
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        ctx = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "teccheck_native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ---------- ActivityAware ----------
    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        activity = b.activity; binding = b; b.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)
    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        activity = null; binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "netInfo" -> background(result) { netInfo() }
            "wifiScan" -> background(result) { wifiScan() }
            "icmpEcho" -> {
                val host = call.argument<String>("host")!!
                val ttl = call.argument<Int>("ttl") ?: 64
                val timeout = call.argument<Int>("timeoutMs") ?: 2000
                val size = call.argument<Int>("size") ?: 56
                val df = call.argument<Boolean>("df") ?: false
                background(result) { icmpEcho(host, ttl, timeout, size, df) }
            }
            "reachable" -> {
                val ip = call.argument<String>("ip")!!
                val timeout = call.argument<Int>("timeoutMs") ?: 400
                background(result) {
                    runCatching { InetAddress.getByName(ip).isReachable(timeout) }.getOrDefault(false)
                }
            }
            "openOokla" -> {
                val i = ctx.packageManager.getLaunchIntentForPackage("org.zwanoo.android.speedtest")
                if (i != null) {
                    i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    ctx.startActivity(i); result.success(true)
                } else result.success(false)
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        pool.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("ERR", e.message, null) }
            }
        }
    }

    // ---------- Permissões ----------
    private fun requestPermissions(result: MethodChannel.Result) {
        val act = activity
        if (act == null || Build.VERSION.SDK_INT < 23) {
            result.success(true); return
        }
        val perms = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (Build.VERSION.SDK_INT >= 33) perms += Manifest.permission.NEARBY_WIFI_DEVICES
        val missing = perms.filter { act.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) {
            result.success(true); return
        }
        pendingPerm = result
        act.requestPermissions(missing.toTypedArray(), REQ)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, grants: IntArray): Boolean {
        if (code != REQ) return false
        pendingPerm?.success(grants.all { it == PackageManager.PERMISSION_GRANTED })
        pendingPerm = null
        return true
    }

    // ---------- Conexão atual ----------
    @Suppress("DEPRECATION")
    private fun netInfo(): Map<String, Any?> {
        val cm = ctx.getSystemService(ConnectivityManager::class.java)
        val net = cm?.activeNetwork ?: return mapOf("connected" to false)
        val caps = cm.getNetworkCapabilities(net)
        val lp = cm.getLinkProperties(net)
        val transport = when {
            caps == null -> "—"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Dados móveis"
            else -> "Outro"
        }
        val v4 = lp?.linkAddresses?.firstOrNull { it.address is Inet4Address }
        val v6 = lp?.linkAddresses
            ?.filter { it.address is Inet6Address && !it.address.isLinkLocalAddress }
            ?.mapNotNull { it.address.hostAddress }.orEmpty()
        var gateway = lp?.routes?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress

        val m = mutableMapOf<String, Any?>(
            "connected" to true,
            "transport" to transport,
            "ip" to v4?.address?.hostAddress,
            "prefix" to (v4?.prefixLength ?: 24),
            "dns" to lp?.dnsServers?.mapNotNull { it.hostAddress }.orEmpty(),
            "ipv6" to v6,
        )
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
            val wm = ctx.getSystemService(WifiManager::class.java)
            val wi = wm?.connectionInfo
            if (wi != null) {
                if (gateway == null) {
                    val g = wm?.dhcpInfo?.gateway ?: 0
                    if (g != 0) gateway = "${g and 255}.${(g shr 8) and 255}.${(g shr 16) and 255}.${(g shr 24) and 255}"
                }
                m["ssid"] = wi.ssid?.removeSurrounding("\"")?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
                m["bssid"] = wi.bssid?.takeIf { it != "02:00:00:00:00:00" }?.uppercase()
                m["rssi"] = wi.rssi.takeIf { it in -127..0 }
                m["linkSpeed"] = wi.linkSpeed.takeIf { it > 0 }
                m["frequency"] = wi.frequency.takeIf { it > 0 }
                if (Build.VERSION.SDK_INT >= 29) {
                    m["txSpeed"] = wi.txLinkSpeedMbps.takeIf { it > 0 }
                    m["rxSpeed"] = wi.rxLinkSpeedMbps.takeIf { it > 0 }
                }
                if (Build.VERSION.SDK_INT >= 30) m["wifiStandard"] = wi.wifiStandard
            }
        }
        m["gateway"] = gateway
        return m
    }

    // ---------- Varredura Wi-Fi ----------
    @Suppress("DEPRECATION")
    private fun wifiScan(): Map<String, Any?> {
        val wm = ctx.getSystemService(WifiManager::class.java) ?: return mapOf("fresh" to false, "nets" to emptyList<Any>())
        val started = runCatching { wm.startScan() }.getOrDefault(false)
        if (started) Thread.sleep(4000)
        val nets = runCatching { wm.scanResults }.getOrDefault(emptyList()).map { r ->
            val width = when (r.channelWidth) {
                ScanResult.CHANNEL_WIDTH_20MHZ -> 20
                ScanResult.CHANNEL_WIDTH_40MHZ -> 40
                ScanResult.CHANNEL_WIDTH_80MHZ -> 80
                ScanResult.CHANNEL_WIDTH_160MHZ, ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 160
                5 -> 320
                else -> 20
            }
            mapOf(
                "ssid" to (r.SSID?.takeIf { it.isNotBlank() } ?: "(rede oculta)"),
                "bssid" to r.BSSID?.uppercase().orEmpty(),
                "rssi" to r.level,
                "freq" to r.frequency,
                "width" to width,
                "caps" to r.capabilities.orEmpty(),
                "standard" to if (Build.VERSION.SDK_INT >= 30) r.wifiStandard else 0,
            )
        }
        return mapOf("fresh" to started, "nets" to nets)
    }

    // ---------- ICMP via /system/bin/ping ----------
    private fun icmpEcho(host: String, ttl: Int, timeoutMs: Int, size: Int, df: Boolean): Map<String, Any?> {
        val w = ((timeoutMs + 999) / 1000).coerceAtLeast(1)
        val cmd = mutableListOf("/system/bin/ping", "-c", "1", "-W", "$w", "-t", "$ttl", "-s", "$size")
        if (df) cmd += listOf("-M", "do")
        cmd += host
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val out = try {
            p.inputStream.bufferedReader().readText().also { p.waitFor() }
        } finally {
            p.destroy()
        }
        val time = Regex("""time[=<]([\d.]+)""").find(out)?.groupValues?.get(1)?.toDoubleOrNull()
        val from = Regex("""[Ff]rom ([0-9a-fA-F:.]+)""").find(out)?.groupValues?.get(1)?.trimEnd(':')
        return when {
            "bytes from" in out -> mapOf("status" to "reply", "from" to from, "rttMs" to time)
            "Time to live exceeded" in out || "Time exceeded" in out -> mapOf("status" to "ttl", "from" to from)
            "Frag needed" in out || "message too long" in out.lowercase() -> mapOf("status" to "fragneeded", "from" to from)
            "Unreachable" in out -> mapOf("status" to "unreachable", "from" to from)
            "unknown host" in out.lowercase() -> mapOf("status" to "error", "message" to "Host desconhecido")
            else -> mapOf("status" to "timeout")
        }
    }

    companion object {
        private const val REQ = 4721
    }
}
