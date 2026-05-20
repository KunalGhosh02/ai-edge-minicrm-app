package com.minicrm.minicrm

import android.os.Build
import android.os.Bundle
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val moveToBackCallback: OnBackInvokedCallback? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            OnBackInvokedCallback { moveTaskToBack(true) }
        } else {
            null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                moveToBackCallback!!,
            )
        }
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            moveToBackCallback != null
        ) {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(moveToBackCallback)
        }
        super.onDestroy()
    }
}
