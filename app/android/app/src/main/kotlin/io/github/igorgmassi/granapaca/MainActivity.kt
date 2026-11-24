package io.github.igorgmassi.granapaca

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // RF-04: hide app content from Android recents thumbnails and block screenshots.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
