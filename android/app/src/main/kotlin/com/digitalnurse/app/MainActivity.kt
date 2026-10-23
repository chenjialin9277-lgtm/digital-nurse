package com.digitalnurse.app

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioAttributes
import android.media.ExifInterface
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val logoPickerRequestCode = 4102
    private val legacyExcelSaveRequestCode = 4103
    private val nurseAvatarPickerRequestCode = 4104
    private val educationVideoPickerRequestCode = 4105
    private val educationVideoPlaybackRequestCode = 4106
    private val systemChannel = "digital_nurse/system"
    private val networkChannel = "digital_nurse/network_status"
    private val localTtsChannel = "digital_nurse/local_tts_status"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var networkSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var localTtsSink: EventChannel.EventSink? = null
    private var textToSpeech: TextToSpeech? = null
    private var textToSpeechReady = false
    private var textToSpeechInitializing = false
    private var pendingSpeechText: String? = null
    private var pendingLogoResult: MethodChannel.Result? = null
    private var pendingNurseAvatarResult: MethodChannel.Result? = null
    private var pendingExcelResult: MethodChannel.Result? = null
    private var pendingEducationVideoResult: MethodChannel.Result? = null
    private var pendingVideoPlaybackResult: MethodChannel.Result? = null
    private var pendingExcelBytes: ByteArray? = null
    private var educationDatabaseChannel: EducationDatabaseChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        initializeTextToSpeech()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        educationDatabaseChannel = EducationDatabaseChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "网址为空", null)
                        } else {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        }
                    }
                    "speakText" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrBlank()) {
                            result.error("EMPTY_TEXT", "播报内容为空", null)
                        } else {
                            requestLocalSpeech(text)
                            result.success(null)
                        }
                    }
                    "stopLocalSpeech" -> {
                        pendingSpeechText = null
                        textToSpeech?.stop()
                        result.success(null)
                    }
                    "pickDepartmentLogo" -> openDepartmentLogoPicker(result)
                    "pickNurseAvatar" -> openNurseAvatarPicker(result)
                    "pickEducationVideo" -> openEducationVideoPicker(result)
                    "playEducationVideo" -> {
                        val path = call.argument<String>("path")
                        val title = call.argument<String>("title") ?: "宣教示范视频"
                        playEducationVideo(path, title, result)
                    }
                    "deleteEducationVideo" -> {
                        val path = call.argument<String>("path")
                        try {
                            deleteEducationVideo(path)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("VIDEO_DELETE_FAILED", error.message, null)
                        }
                    }
                    "saveUsageXlsx" -> {
                        val fileName = call.argument<String>("fileName")
                        val summaryRows = call.argument<List<List<Any?>>>("summaryRows")
                        val detailRows = call.argument<List<List<Any?>>>("detailRows")
                        val educationSummaryRows =
                            call.argument<List<List<Any?>>>("educationSummaryRows")
                        val comprehensionRows =
                            call.argument<List<List<Any?>>>("comprehensionRows")
                        val educationEventRows =
                            call.argument<List<List<Any?>>>("educationEventRows")
                        if (fileName.isNullOrBlank() || summaryRows == null || detailRows == null) {
                            result.error("EMPTY_REPORT", "表格内容为空", null)
                        } else {
                            try {
                                val bytes = UsageXlsxWriter.build(
                                    summaryRows,
                                    detailRows,
                                    educationSummaryRows,
                                    comprehensionRows,
                                    educationEventRows,
                                )
                                saveUsageXlsx(fileName, bytes, result)
                            } catch (error: Exception) {
                                result.error("EXPORT_FAILED", error.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    networkSink = events
                    registerNetworkMonitor()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterNetworkMonitor()
                    networkSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, localTtsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    localTtsSink = events
                }

                override fun onCancel(arguments: Any?) {
                    localTtsSink = null
                }
            })
    }

    private fun openDepartmentLogoPicker(result: MethodChannel.Result) {
        if (pendingLogoResult != null) {
            result.error("PICKER_BUSY", "已有图片选择窗口正在打开", null)
            return
        }
        pendingLogoResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, logoPickerRequestCode)
        } catch (error: Exception) {
            pendingLogoResult = null
            result.error("PICKER_UNAVAILABLE", error.message, null)
        }
    }

    private fun openNurseAvatarPicker(result: MethodChannel.Result) {
        if (pendingNurseAvatarResult != null) {
            result.error("PICKER_BUSY", "已有形象选择窗口正在打开", null)
            return
        }
        pendingNurseAvatarResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, nurseAvatarPickerRequestCode)
        } catch (error: Exception) {
            pendingNurseAvatarResult = null
            result.error("PICKER_UNAVAILABLE", error.message, null)
        }
    }

    private fun openEducationVideoPicker(result: MethodChannel.Result) {
        if (pendingEducationVideoResult != null) {
            result.error("PICKER_BUSY", "已有视频选择窗口正在打开", null)
            return
        }
        pendingEducationVideoResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, educationVideoPickerRequestCode)
        } catch (error: Exception) {
            pendingEducationVideoResult = null
            result.error("PICKER_UNAVAILABLE", error.message, null)
        }
    }

    private fun playEducationVideo(
        path: String?,
        title: String,
        result: MethodChannel.Result,
    ) {
        if (pendingVideoPlaybackResult != null) {
            result.error("VIDEO_BUSY", "已有视频正在播放", null)
            return
        }
        if (path.isNullOrBlank()) {
            result.error("VIDEO_MISSING", "未配置示范视频", null)
            return
        }
        try {
            val videoRoot = File(filesDir, "education_videos").canonicalFile
            val video = File(path).canonicalFile
            if (!video.path.startsWith(videoRoot.path + File.separator) || !video.isFile) {
                result.error("VIDEO_MISSING", "视频文件已丢失，请在宣教管理中重新导入", null)
                return
            }
            pendingVideoPlaybackResult = result
            val intent = Intent(this, EducationVideoActivity::class.java).apply {
                putExtra(EducationVideoActivity.EXTRA_VIDEO_PATH, video.absolutePath)
                putExtra(EducationVideoActivity.EXTRA_VIDEO_TITLE, title)
            }
            startActivityForResult(intent, educationVideoPlaybackRequestCode)
        } catch (error: Exception) {
            pendingVideoPlaybackResult = null
            result.error("VIDEO_OPEN_FAILED", error.message, null)
        }
    }

    private fun deleteEducationVideo(path: String?) {
        if (path.isNullOrBlank()) return
        val videoRoot = File(filesDir, "education_videos").canonicalFile
        val video = File(path).canonicalFile
        if (!video.path.startsWith(videoRoot.path + File.separator)) {
            throw IllegalArgumentException("不能删除APP视频目录以外的文件")
        }
        if (video.exists() && !video.delete()) {
            throw IllegalStateException("视频文件删除失败")
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            logoPickerRequestCode -> {
                val result = pendingLogoResult
                pendingLogoResult = null
                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result?.success(null)
                    return
                }
                try {
                    result?.success(copyDepartmentLogo(data.data!!))
                } catch (error: Exception) {
                    result?.error("LOGO_COPY_FAILED", error.message, null)
                }
            }
            nurseAvatarPickerRequestCode -> {
                val result = pendingNurseAvatarResult
                pendingNurseAvatarResult = null
                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result?.success(null)
                    return
                }
                try {
                    result?.success(copyStandardNurseAvatar(data.data!!))
                } catch (error: Exception) {
                    result?.error("AVATAR_STANDARD_FAILED", error.message, null)
                }
            }
            educationVideoPickerRequestCode -> {
                val result = pendingEducationVideoResult
                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    pendingEducationVideoResult = null
                    result?.success(null)
                    return
                }
                val uri = data.data!!
                Thread {
                    try {
                        val path = copyEducationVideo(uri)
                        mainHandler.post {
                            pendingEducationVideoResult = null
                            result?.success(path)
                        }
                    } catch (error: Exception) {
                        mainHandler.post {
                            pendingEducationVideoResult = null
                            result?.error("VIDEO_COPY_FAILED", error.message, null)
                        }
                    }
                }.start()
            }
            educationVideoPlaybackRequestCode -> {
                val result = pendingVideoPlaybackResult
                pendingVideoPlaybackResult = null
                if (resultCode == EducationVideoActivity.RESULT_PLAYBACK_ERROR) {
                    result?.error(
                        "VIDEO_PLAYBACK_FAILED",
                        data?.getStringExtra(EducationVideoActivity.EXTRA_ERROR_MESSAGE)
                            ?: "视频无法播放，请确认为H.264 + AAC编码的MP4文件",
                        null,
                    )
                } else {
                    result?.success(
                        data?.getBooleanExtra(
                            EducationVideoActivity.EXTRA_PLAYBACK_COMPLETED,
                            false,
                        ) ?: false,
                    )
                }
            }
            legacyExcelSaveRequestCode -> {
                val result = pendingExcelResult
                val bytes = pendingExcelBytes
                pendingExcelResult = null
                pendingExcelBytes = null
                if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) {
                    result?.success(null)
                    return
                }
                try {
                    contentResolver.openOutputStream(data.data!!)?.use { output ->
                        output.write(bytes)
                    } ?: throw IllegalStateException("无法写入Excel文件")
                    result?.success("已保存到您选择的位置")
                } catch (error: Exception) {
                    result?.error("EXPORT_FAILED", error.message, null)
                }
            }
        }
    }

    private fun copyDepartmentLogo(uri: Uri): String {
        val bitmap = contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input)
        } ?: throw IllegalArgumentException("无法识别所选图片")
        val longestSide = maxOf(bitmap.width, bitmap.height)
        val processed =
            if (longestSide > 1200) {
                val scale = 1200f / longestSide.toFloat()
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                bitmap
            }
        val directory = File(filesDir, "department_logos").apply { mkdirs() }
        val destination = File(directory, "department_logo_${System.currentTimeMillis()}.png")
        FileOutputStream(destination).use { output ->
            if (!processed.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw IllegalStateException("科室Logo保存失败")
            }
        }
        if (processed !== bitmap) processed.recycle()
        bitmap.recycle()
        return destination.absolutePath
    }

    private fun copyEducationVideo(uri: Uri): String {
        val displayName = queryOpenableValue(uri, OpenableColumns.DISPLAY_NAME) ?: ""
        val mime = contentResolver.getType(uri)?.lowercase(Locale.ROOT) ?: ""
        if (mime != "video/mp4" && !displayName.lowercase(Locale.ROOT).endsWith(".mp4")) {
            throw IllegalArgumentException("为保证平板兼容性，请选择MP4视频（H.264 + AAC）")
        }
        val declaredSize = queryOpenableValue(uri, OpenableColumns.SIZE)?.toLongOrNull()
        val maximumBytes = 1024L * 1024L * 1024L
        if (declaredSize != null && declaredSize > maximumBytes) {
            throw IllegalArgumentException("视频不能超过1GB，建议压缩到500MB以内")
        }
        val directory = File(filesDir, "education_videos").apply { mkdirs() }
        if (declaredSize != null && directory.usableSpace < declaredSize + 100L * 1024L * 1024L) {
            throw IllegalStateException("平板剩余存储空间不足，请先清理空间")
        }
        val destination = File(directory, "education_video_${System.currentTimeMillis()}.mp4")
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > maximumBytes) {
                            throw IllegalArgumentException("视频不能超过1GB")
                        }
                        output.write(buffer, 0, read)
                    }
                    output.fd.sync()
                }
            } ?: throw IllegalArgumentException("无法读取所选视频")
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
        if (destination.length() == 0L) {
            destination.delete()
            throw IllegalArgumentException("所选视频为空文件")
        }
        return destination.absolutePath
    }

    private fun queryOpenableValue(uri: Uri, column: String): String? {
        return contentResolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val index = cursor.getColumnIndex(column)
            if (index < 0 || cursor.isNull(index)) null else cursor.getString(index)
        }
    }

    private fun copyStandardNurseAvatar(uri: Uri): String {
        val orientation = try {
            contentResolver.openInputStream(uri)?.use { input ->
                ExifInterface(input).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val bitmap = contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input)
        } ?: throw IllegalArgumentException("无法识别所选形象图片")
        val rotation = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        var working =
            if (rotation == 0f) {
                bitmap
            } else {
                Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    bitmap.width,
                    bitmap.height,
                    Matrix().apply { postRotate(rotation) },
                    true,
                ).also { bitmap.recycle() }
            }
        if (working.width < 1080 || working.height < 1440) {
            working.recycle()
            throw IllegalArgumentException(
                "清晰度不足：图片至少需要1080×1440像素",
            )
        }
        val ratio = working.width.toDouble() / working.height.toDouble()
        if (ratio < 0.65 || ratio > 0.85) {
            working.recycle()
            throw IllegalArgumentException("图片比例不符合要求：请选择接近3:4的竖版人物图")
        }

        val targetRatio = 0.75
        val cropWidth: Int
        val cropHeight: Int
        if (ratio > targetRatio) {
            cropHeight = working.height
            cropWidth = (cropHeight * targetRatio).toInt()
        } else {
            cropWidth = working.width
            cropHeight = (cropWidth / targetRatio).toInt()
        }
        val cropX = ((working.width - cropWidth) / 2).coerceAtLeast(0)
        val cropY = ((working.height - cropHeight) / 2).coerceAtLeast(0)
        val cropped = Bitmap.createBitmap(working, cropX, cropY, cropWidth, cropHeight)
        if (cropped !== working) working.recycle()
        val standardized = Bitmap.createScaledBitmap(cropped, 1080, 1440, true)
        if (standardized !== cropped) cropped.recycle()

        val directory = File(filesDir, "nurse_avatars").apply { mkdirs() }
        val destination = File(directory, "nurse_avatar_${System.currentTimeMillis()}.png")
        FileOutputStream(destination).use { output ->
            if (!standardized.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                standardized.recycle()
                throw IllegalStateException("数字护士形象保存失败")
            }
        }
        standardized.recycle()
        return destination.absolutePath
    }

    private fun registerNetworkMonitor() {
        unregisterNetworkMonitor()
        val manager = getSystemService(ConnectivityManager::class.java)
        networkSink?.success(hasUsableNetwork(manager))
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emitNetworkState(manager)
            override fun onLost(network: Network) = emitNetworkState(manager, 700)
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                emitNetworkState(manager)
        }
        networkCallback = callback
        manager.registerDefaultNetworkCallback(callback)
    }

    private fun unregisterNetworkMonitor() {
        val callback = networkCallback ?: return
        try {
            getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // The callback may already have been removed during activity teardown.
        }
        networkCallback = null
    }

    private fun emitNetworkState(manager: ConnectivityManager, delayMs: Long = 0) {
        mainHandler.postDelayed({ networkSink?.success(hasUsableNetwork(manager)) }, delayMs)
    }

    private fun hasUsableNetwork(manager: ConnectivityManager): Boolean {
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun emitTtsStatus(status: String) {
        mainHandler.post { localTtsSink?.success(status) }
    }

    private fun initializeTextToSpeech() {
        if (textToSpeechInitializing) return
        textToSpeechInitializing = true
        textToSpeechReady = false
        textToSpeech?.shutdown()
        textToSpeech = TextToSpeech(this) { status ->
            // Some Android engines invoke the callback before the field
            // assignment is visible. Posting to the main queue avoids that race.
            mainHandler.post { finishTextToSpeechInitialization(status) }
        }
    }

    private fun finishTextToSpeechInitialization(status: Int) {
        textToSpeechInitializing = false
        val engine = textToSpeech
        if (status != TextToSpeech.SUCCESS || engine == null) {
            textToSpeechReady = false
            pendingSpeechText = null
            emitTtsStatus("error")
            return
        }

        val candidateLocales = listOf(
            Locale.SIMPLIFIED_CHINESE,
            Locale.CHINA,
            Locale.CHINESE,
            Locale.getDefault(),
        )
        for (locale in candidateLocales) {
            val result = engine.setLanguage(locale)
            if (result != TextToSpeech.LANG_MISSING_DATA &&
                result != TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                break
            }
        }
        engine.setSpeechRate(0.92f)
        engine.setPitch(1.0f)
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                // Use the tablet's normal media route/volume. Accessibility
                // audio can be independently muted on some Xiaomi builds.
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = emitTtsStatus("start")
            override fun onDone(utteranceId: String?) = emitTtsStatus("done")
            @Deprecated("Deprecated in Android")
            override fun onError(utteranceId: String?) = emitTtsStatus("error")
        })
        textToSpeechReady = true
        pendingSpeechText?.let {
            pendingSpeechText = null
            speakNow(it)
        }
    }

    private fun requestLocalSpeech(text: String) {
        if (textToSpeechReady) {
            speakNow(text)
        } else {
            pendingSpeechText = text
            initializeTextToSpeech()
        }
    }

    private fun speakNow(text: String) {
        val engine = textToSpeech ?: run {
            emitTtsStatus("error")
            return
        }
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        val utteranceId = "fixed-answer-${System.currentTimeMillis()}"
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId) !=
            TextToSpeech.SUCCESS
        ) {
            emitTtsStatus("error")
        }
    }

    private fun saveUsageXlsx(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (pendingExcelResult != null) {
                result.error("EXPORT_BUSY", "已有Excel保存窗口正在打开", null)
                return
            }
            pendingExcelResult = result
            pendingExcelBytes = bytes
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            try {
                startActivityForResult(intent, legacyExcelSaveRequestCode)
            } catch (error: Exception) {
                pendingExcelResult = null
                pendingExcelBytes = null
                result.error("EXPORT_UNAVAILABLE", error.message, null)
            }
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(
                MediaStore.Downloads.MIME_TYPE,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            )
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/数字护士使用记录",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("无法创建下载文件")
        try {
            contentResolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: throw IllegalStateException("无法写入下载文件")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            result.success("下载/数字护士使用记录/$fileName")
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            result.error("EXPORT_FAILED", error.message, null)
        }
    }

    override fun onDestroy() {
        unregisterNetworkMonitor()
        educationDatabaseChannel?.close()
        educationDatabaseChannel = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        pendingSpeechText = null
        pendingLogoResult?.error("ACTIVITY_CLOSED", "页面已关闭", null)
        pendingLogoResult = null
        pendingNurseAvatarResult?.error("ACTIVITY_CLOSED", "页面已关闭", null)
        pendingNurseAvatarResult = null
        pendingExcelResult?.error("ACTIVITY_CLOSED", "页面已关闭", null)
        pendingExcelResult = null
        pendingExcelBytes = null
        pendingEducationVideoResult?.error("ACTIVITY_CLOSED", "页面已关闭", null)
        pendingEducationVideoResult = null
        pendingVideoPlaybackResult?.error("ACTIVITY_CLOSED", "页面已关闭", null)
        pendingVideoPlaybackResult = null
        super.onDestroy()
    }
}
