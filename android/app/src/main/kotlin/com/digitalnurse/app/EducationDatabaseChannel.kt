package com.digitalnurse.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class EducationDatabaseChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val database = EducationDatabaseHelper(context.applicationContext)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in SUPPORTED_METHODS) {
            result.notImplemented()
            return
        }
        executor.execute {
            try {
                val value: Any? = when (call.method) {
                    "loadActive" -> database.loadActive()
                    "loadAll" -> database.loadAll()
                    "replaceAll" -> {
                        database.replaceAll(call.stringListArgument("items"))
                        null
                    }
                    "replaceAllAndMarkLegacyMigrated" -> {
                        database.replaceAllAndMarkLegacyMigrated(
                            call.stringListArgument("items"),
                        )
                        null
                    }
                    "save" -> {
                        database.save(call.requiredStringArgument("item"))
                        null
                    }
                    "softDelete" -> {
                        database.softDelete(call.requiredStringArgument("id"))
                        null
                    }
                    "reorder" -> {
                        database.reorder(call.stringListArgument("orderedIds"))
                        null
                    }
                    "isLegacyMigrationCompleted" ->
                        database.isLegacyMigrationCompleted()
                    "markLegacyMigrationCompleted" -> {
                        database.markLegacyMigrationCompleted()
                        null
                    }
                    "saveEducationEvent" -> {
                        database.saveEducationEvent(call.requiredStringArgument("event"))
                        null
                    }
                    "loadEducationEvents" -> database.loadEducationEvents(
                        call.requiredStringArgument("start"),
                        call.requiredStringArgument("end"),
                    )
                    else -> null
                }
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "EDUCATION_DATABASE_ERROR",
                        error.message ?: "本地宣教数据库操作失败",
                        null,
                    )
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
        database.close()
    }

    private fun MethodCall.argumentsMap(): Map<*, *> =
        arguments as? Map<*, *> ?: emptyMap<Any, Any>()

    private fun MethodCall.requiredStringArgument(key: String): String =
        (argumentsMap()[key] as? String)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("缺少参数：$key")

    private fun MethodCall.stringListArgument(key: String): List<String> {
        val raw = argumentsMap()[key] as? List<*>
            ?: throw IllegalArgumentException("缺少参数：$key")
        return raw.map { value ->
            value as? String
                ?: throw IllegalArgumentException("参数格式错误：$key")
        }
    }

    companion object {
        private const val CHANNEL_NAME = "digital_nurse/education_database"
        private val SUPPORTED_METHODS = setOf(
            "loadActive",
            "loadAll",
            "replaceAll",
            "replaceAllAndMarkLegacyMigrated",
            "save",
            "softDelete",
            "reorder",
            "isLegacyMigrationCompleted",
            "markLegacyMigrationCompleted",
            "saveEducationEvent",
            "loadEducationEvents",
        )
    }
}
