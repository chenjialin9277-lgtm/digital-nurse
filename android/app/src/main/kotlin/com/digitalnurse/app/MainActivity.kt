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
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private val logoPickerRequestCode = 4102
    private val legacyExcelSaveRequestCode = 4103
    private val nurseAvatarPickerRequestCode = 4104
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
                    "saveUsageXlsx" -> {
                        val fileName = call.argument<String>("fileName")
                        val summaryRows = call.argument<List<List<Any?>>>("summaryRows")
                        val detailRows = call.argument<List<List<Any?>>>("detailRows")
                        if (fileName.isNullOrBlank() || summaryRows == null || detailRows == null) {
                            result.error("EMPTY_REPORT", "表格内容为空", null)
                        } else {
                            try {
                                val bytes = buildXlsx(summaryRows, detailRows)
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

    private fun buildXlsx(
        summaryRows: List<List<Any?>>,
        detailRows: List<List<Any?>>,
    ): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            addZipEntry(zip, "[Content_Types].xml", contentTypesXml())
            addZipEntry(zip, "_rels/.rels", rootRelationshipsXml())
            addZipEntry(zip, "xl/workbook.xml", workbookXml())
            addZipEntry(zip, "xl/_rels/workbook.xml.rels", workbookRelationshipsXml())
            addZipEntry(zip, "xl/styles.xml", stylesXml())
            addZipEntry(
                zip,
                "xl/worksheets/sheet1.xml",
                worksheetXml(summaryRows, summarySheet = true),
            )
            addZipEntry(
                zip,
                "xl/worksheets/sheet2.xml",
                worksheetXml(detailRows, summarySheet = false),
            )
        }
        return output.toByteArray()
    }

    private fun addZipEntry(zip: ZipOutputStream, path: String, content: String) {
        zip.putNextEntry(ZipEntry(path))
        zip.write(content.toByteArray(Charsets.UTF_8))
        zip.closeEntry()
    }

    private fun contentTypesXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>""".trimIndent()

    private fun rootRelationshipsXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>""".trimIndent()

    private fun workbookXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="统计汇总" sheetId="1" r:id="rId1"/>
            <sheet name="使用明细" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>""".trimIndent()

    private fun workbookRelationshipsXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>""".trimIndent()

    private fun stylesXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="3">
            <font><sz val="11"/><name val="等线"/></font>
            <font><b/><sz val="15"/><color rgb="FF0B5870"/><name val="等线"/></font>
            <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="等线"/></font>
          </fonts>
          <fills count="3">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FF087F8C"/><bgColor indexed="64"/></patternFill></fill>
          </fills>
          <borders count="2">
            <border><left/><right/><top/><bottom/><diagonal/></border>
            <border><left style="thin"><color rgb="FFD4E3E6"/></left><right style="thin"><color rgb="FFD4E3E6"/></right><top style="thin"><color rgb="FFD4E3E6"/></top><bottom style="thin"><color rgb="FFD4E3E6"/></bottom><diagonal/></border>
          </borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="4">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"><alignment horizontal="center" vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf>
            <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0"><alignment horizontal="center" vertical="center"/></xf>
          </cellXfs>
          <cellStyles count="1"><cellStyle name="常规" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>""".trimIndent()

    private fun worksheetXml(rows: List<List<Any?>>, summarySheet: Boolean): String {
        val xml = StringBuilder()
        xml.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>")
        xml.append("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">")
        if (!summarySheet) {
            xml.append("<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>")
        }
        xml.append(
            if (summarySheet) {
                "<cols><col min=\"1\" max=\"1\" width=\"24\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"44\" customWidth=\"1\"/></cols>"
            } else {
                "<cols><col min=\"1\" max=\"1\" width=\"9\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"16\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"14\" customWidth=\"1\"/><col min=\"4\" max=\"4\" width=\"20\" customWidth=\"1\"/></cols>"
            },
        )
        xml.append("<sheetData>")
        rows.forEachIndexed { rowIndex, row ->
            val excelRow = rowIndex + 1
            val isTitle = summarySheet && rowIndex == 0
            val isHeader =
                (!summarySheet && rowIndex == 0) ||
                    (summarySheet && row.firstOrNull()?.toString() == "统计项目")
            xml.append("<row r=\"$excelRow\"${if (isTitle) " ht=\"25\" customHeight=\"1\"" else ""}>")
            row.forEachIndexed { columnIndex, value ->
                val reference = "${columnName(columnIndex)}$excelRow"
                val style = if (isTitle) 1 else if (isHeader) 2 else if (!summarySheet) 3 else 0
                if (value is Number) {
                    xml.append("<c r=\"$reference\" s=\"$style\"><v>$value</v></c>")
                } else {
                    xml.append("<c r=\"$reference\" s=\"$style\" t=\"inlineStr\"><is><t>${escapeXml(value?.toString() ?: "")}</t></is></c>")
                }
            }
            xml.append("</row>")
        }
        xml.append("</sheetData>")
        if (summarySheet) xml.append("<mergeCells count=\"1\"><mergeCell ref=\"A1:B1\"/></mergeCells>")
        xml.append("</worksheet>")
        return xml.toString()
    }

    private fun columnName(index: Int): String {
        var value = index + 1
        val name = StringBuilder()
        while (value > 0) {
            val remainder = (value - 1) % 26
            name.insert(0, ('A'.code + remainder).toChar())
            value = (value - 1) / 26
        }
        return name.toString()
    }

    private fun escapeXml(value: String): String =
        value.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")

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
        super.onDestroy()
    }
}
