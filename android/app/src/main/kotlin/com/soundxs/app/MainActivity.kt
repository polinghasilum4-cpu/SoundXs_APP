package com.soundxs.app // <- samakan dengan applicationId di android/app/build.gradle

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service WAJIB pakai AudioServiceActivity (bukan FlutterActivity biasa),
// kalau tidak notifikasi/kontrol background tidak jalan.
class MainActivity : AudioServiceActivity()
