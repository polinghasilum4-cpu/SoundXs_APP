package com.soundxs.app // <- samakan dengan applicationId di android/app/build.gradle

import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service WAJIB pakai AudioServiceActivity (bukan FlutterActivity biasa),
// kalau tidak notifikasi/kontrol background tidak jalan.
class MainActivity : AudioServiceActivity() {

    private var reverb: PresetReverb? = null
    private var virtualizer: Virtualizer? = null
    private var session: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "soundxs/fx")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "attach" -> {
                            val id = call.argument<Int>("session") ?: -1
                            result.success(attach(id))
                        }
                        "reverb" -> result.success(setReverb(call.argument<Int>("preset") ?: 0))
                        "virtualizer" -> result.success(setVirtualizer(call.argument<Int>("strength") ?: 0))
                        "release" -> {
                            releaseFx()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    // Efek audio tidak boleh membuat aplikasi crash.
                    result.success(false)
                }
            }
    }

    private fun attach(id: Int): Boolean {
        if (id <= 0) return false
        if (id == session && (reverb != null || virtualizer != null)) return true
        releaseFx()
        session = id
        return true
    }

    private fun setReverb(preset: Int): Boolean {
        if (session <= 0) return false
        return try {
            if (preset <= 0) {
                reverb?.setEnabled(false)
                true
            } else {
                val r = reverb ?: PresetReverb(0, session).also { reverb = it }
                r.preset = preset.toShort()
                r.setEnabled(true)
                true
            }
        } catch (e: Throwable) {
            reverb = null
            false
        }
    }

    private fun setVirtualizer(strength: Int): Boolean {
        if (session <= 0) return false
        return try {
            if (strength <= 0) {
                virtualizer?.setEnabled(false)
                true
            } else {
                val v = virtualizer ?: Virtualizer(0, session).also { virtualizer = it }
                if (!v.strengthSupported) {
                    false
                } else {
                    v.setStrength(strength.coerceIn(0, 1000).toShort())
                    v.setEnabled(true)
                    true
                }
            }
        } catch (e: Throwable) {
            virtualizer = null
            false
        }
    }

    private fun releaseFx() {
        try { reverb?.release() } catch (_: Throwable) {}
        try { virtualizer?.release() } catch (_: Throwable) {}
        reverb = null
        virtualizer = null
        session = -1
    }

    override fun onDestroy() {
        releaseFx()
        super.onDestroy()
    }
}
