package com.digitalnurse.app

import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.MediaController
import android.widget.TextView
import android.widget.Toast
import android.widget.VideoView

class EducationVideoActivity : Activity() {
    private lateinit var videoView: VideoView
    private var playbackFailed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        val path = intent.getStringExtra(EXTRA_VIDEO_PATH)
        if (path.isNullOrBlank()) {
            finishWithError("视频文件不存在")
            return
        }

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        videoView = VideoView(this)
        root.addView(
            videoView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER,
            ),
        )

        val titleBar = TextView(this).apply {
            text = intent.getStringExtra(EXTRA_VIDEO_TITLE) ?: "宣教示范视频"
            setTextColor(Color.WHITE)
            textSize = 18f
            setPadding(72, 18, 72, 18)
            setBackgroundColor(0x66000000)
            gravity = Gravity.CENTER
        }
        root.addView(
            titleBar,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )

        val close = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            contentDescription = "关闭视频"
            setColorFilter(Color.WHITE)
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { finishNormally(completed = false) }
        }
        root.addView(
            close,
            FrameLayout.LayoutParams(64, 64, Gravity.TOP or Gravity.END),
        )
        setContentView(root)

        val controls = MediaController(this).apply { setAnchorView(videoView) }
        videoView.setMediaController(controls)
        videoView.setVideoPath(path)
        videoView.setOnPreparedListener { player ->
            player.isLooping = false
            videoView.start()
        }
        videoView.setOnCompletionListener { finishNormally(completed = true) }
        videoView.setOnErrorListener { _, _, _ ->
            if (!playbackFailed) {
                playbackFailed = true
                finishWithError("视频无法播放，请转换为H.264 + AAC编码的MP4文件")
            }
            true
        }
        videoView.requestFocus()
    }

    override fun onBackPressed() = finishNormally(completed = false)

    private fun finishNormally(completed: Boolean) {
        if (::videoView.isInitialized) videoView.stopPlayback()
        setResult(
            RESULT_OK,
            Intent().putExtra(EXTRA_PLAYBACK_COMPLETED, completed),
        )
        finish()
    }

    private fun finishWithError(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        setResult(
            RESULT_PLAYBACK_ERROR,
            Intent().putExtra(EXTRA_ERROR_MESSAGE, message),
        )
        finish()
    }

    companion object {
        const val EXTRA_VIDEO_PATH = "education_video_path"
        const val EXTRA_VIDEO_TITLE = "education_video_title"
        const val EXTRA_ERROR_MESSAGE = "education_video_error"
        const val EXTRA_PLAYBACK_COMPLETED = "education_video_completed"
        const val RESULT_PLAYBACK_ERROR = Activity.RESULT_FIRST_USER + 41
    }
}
