package com.dabok407.hangeoreum

import io.flutter.embedding.android.FlutterActivity

/** Debug-only normal app bootstrap with OS alarm probes after driver cleanup. */
class NativeLifecycleTestActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "nativeLifecycleProbe"
}
