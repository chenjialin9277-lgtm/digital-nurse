package com.digitalnurse.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

class EducationDatabaseHelper(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(database: SQLiteDatabase) {
        createEducationTables(database)
        createEventTable(database)
    }

    override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createEventTable(database)
    }

    private fun createEducationTables(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS education_items (
              id TEXT PRIMARY KEY,
              category TEXT NOT NULL,
              contents_json TEXT NOT NULL,
              estimated_minutes INTEGER NOT NULL,
              sort_order INTEGER NOT NULL,
              favorite INTEGER NOT NULL,
              enabled INTEGER NOT NULL,
              version INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS education_meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    private fun createEventTable(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS education_events (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              department_id TEXT NOT NULL,
              item_id TEXT,
              item_version INTEGER,
              language TEXT,
              event_type TEXT NOT NULL,
              attempt INTEGER,
              value INTEGER,
              occurred_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    fun loadActive(): List<String> {
        return loadItems("enabled = 1 AND deleted = 0")
    }

    fun loadAll(): List<String> {
        return loadItems("deleted = 0")
    }

    private fun loadItems(selection: String): List<String> {
        val encodedItems = mutableListOf<String>()
        readableDatabase.query(
            EDUCATION_TABLE,
            arrayOf("contents_json"),
            selection,
            null,
            null,
            null,
            "sort_order ASC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                encodedItems.add(cursor.getString(0))
            }
        }
        return encodedItems
    }

    fun replaceAll(encodedItems: List<String>) {
        replaceAllInternal(encodedItems, markLegacyMigrated = false)
    }

    fun replaceAllAndMarkLegacyMigrated(encodedItems: List<String>) {
        replaceAllInternal(encodedItems, markLegacyMigrated = true)
    }

    private fun replaceAllInternal(
        encodedItems: List<String>,
        markLegacyMigrated: Boolean,
    ) {
        val database = writableDatabase
        database.beginTransaction()
        try {
            database.delete(EDUCATION_TABLE, null, null)
            encodedItems.forEach { encoded ->
                database.insertOrThrow(
                    EDUCATION_TABLE,
                    null,
                    valuesFor(encoded),
                )
            }
            if (markLegacyMigrated) {
                writeMeta(database, LEGACY_MIGRATION_KEY, "1")
            }
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
    }

    fun save(encodedItem: String) {
        writableDatabase.insertWithOnConflict(
            EDUCATION_TABLE,
            null,
            valuesFor(encodedItem),
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun softDelete(id: String) {
        require(id.isNotBlank()) { "宣教项目ID不能为空" }
        writableDatabase.update(
            EDUCATION_TABLE,
            ContentValues().apply { put("deleted", 1) },
            "id = ?",
            arrayOf(id),
        )
    }

    fun reorder(orderedIds: List<String>) {
        val database = writableDatabase
        database.beginTransaction()
        try {
            orderedIds.forEachIndexed { index, id ->
                val encoded = database.query(
                    EDUCATION_TABLE,
                    arrayOf("contents_json"),
                    "id = ?",
                    arrayOf(id),
                    null,
                    null,
                    null,
                ).use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                } ?: return@forEachIndexed
                val item = JSONObject(encoded).apply { put("sortOrder", index) }
                database.update(
                    EDUCATION_TABLE,
                    ContentValues().apply {
                        put("sort_order", index)
                        put("contents_json", item.toString())
                    },
                    "id = ?",
                    arrayOf(id),
                )
            }
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
    }

    fun isLegacyMigrationCompleted(): Boolean =
        readableDatabase.query(
            META_TABLE,
            arrayOf("value"),
            "key = ?",
            arrayOf(LEGACY_MIGRATION_KEY),
            null,
            null,
            null,
        ).use { cursor -> cursor.moveToFirst() && cursor.getString(0) == "1" }

    fun markLegacyMigrationCompleted() {
        writeMeta(writableDatabase, LEGACY_MIGRATION_KEY, "1")
    }

    fun saveEducationEvent(encodedEvent: String) {
        val event = JSONObject(encodedEvent)
        val id = event.optString("id").trim()
        val sessionId = event.optString("sessionId").trim()
        val departmentId = event.optString("departmentId").trim()
        val eventType = event.optString("type").trim()
        val occurredAt = event.optString("occurredAt").trim()
        require(id.isNotEmpty()) { "宣教事件ID不能为空" }
        require(sessionId.isNotEmpty()) { "宣教会话ID不能为空" }
        require(departmentId.isNotEmpty()) { "科室标识不能为空" }
        require(eventType.isNotEmpty()) { "宣教事件类型不能为空" }
        require(occurredAt.isNotEmpty()) { "宣教事件时间不能为空" }
        writableDatabase.insertOrThrow(
            EVENT_TABLE,
            null,
            ContentValues().apply {
                put("id", id)
                put("session_id", sessionId)
                put("department_id", departmentId)
                putNullableString("item_id", event, "itemId")
                putNullableInt("item_version", event, "itemVersion")
                putNullableString("language", event, "language")
                put("event_type", eventType)
                putNullableInt("attempt", event, "attempt")
                putNullableInt("value", event, "value")
                put("occurred_at", occurredAt)
            },
        )
    }

    fun loadEducationEvents(start: String, end: String): List<String> {
        require(start.isNotBlank() && end.isNotBlank()) { "查询日期不能为空" }
        val events = mutableListOf<String>()
        readableDatabase.query(
            EVENT_TABLE,
            arrayOf(
                "id",
                "session_id",
                "department_id",
                "item_id",
                "item_version",
                "language",
                "event_type",
                "attempt",
                "value",
                "occurred_at",
            ),
            "occurred_at >= ? AND occurred_at < ?",
            arrayOf(start, end),
            null,
            null,
            "occurred_at ASC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val event = JSONObject()
                    .put("id", cursor.getString(0))
                    .put("sessionId", cursor.getString(1))
                    .put("departmentId", cursor.getString(2))
                    .put("type", cursor.getString(6))
                    .put("occurredAt", cursor.getString(9))
                if (!cursor.isNull(3)) event.put("itemId", cursor.getString(3))
                if (!cursor.isNull(4)) event.put("itemVersion", cursor.getInt(4))
                if (!cursor.isNull(5)) event.put("language", cursor.getString(5))
                if (!cursor.isNull(7)) event.put("attempt", cursor.getInt(7))
                if (!cursor.isNull(8)) event.put("value", cursor.getInt(8))
                events.add(event.toString())
            }
        }
        return events
    }

    private fun valuesFor(encodedItem: String): ContentValues {
        val item = JSONObject(encodedItem)
        val id = item.optString("id").trim()
        require(id.isNotEmpty()) { "宣教项目ID不能为空" }
        return ContentValues().apply {
            put("id", id)
            put("category", item.optString("category", "未分类"))
            put("contents_json", item.toString())
            put("estimated_minutes", item.optInt("estimatedManualMinutes", 1))
            put("sort_order", item.optInt("sortOrder", 0))
            put("favorite", if (item.optBoolean("favorite", false)) 1 else 0)
            put("enabled", if (item.optBoolean("enabled", true)) 1 else 0)
            put("version", item.optInt("version", 1))
            put("deleted", 0)
            put("created_at", item.optString("createdAt"))
            put("updated_at", item.optString("updatedAt"))
        }
    }

    private fun writeMeta(database: SQLiteDatabase, key: String, value: String) {
        database.insertWithOnConflict(
            META_TABLE,
            null,
            ContentValues().apply {
                put("key", key)
                put("value", value)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    private fun ContentValues.putNullableString(
        column: String,
        json: JSONObject,
        key: String,
    ) {
        if (json.has(key) && !json.isNull(key)) put(column, json.getString(key))
        else putNull(column)
    }

    private fun ContentValues.putNullableInt(
        column: String,
        json: JSONObject,
        key: String,
    ) {
        if (json.has(key) && !json.isNull(key)) put(column, json.getInt(key))
        else putNull(column)
    }

    companion object {
        private const val DATABASE_NAME = "digital_nurse.db"
        private const val DATABASE_VERSION = 2
        private const val EDUCATION_TABLE = "education_items"
        private const val META_TABLE = "education_meta"
        private const val EVENT_TABLE = "education_events"
        private const val LEGACY_MIGRATION_KEY = "legacy_migration_completed"
    }
}
