package com.digitalnurse.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

class EducationDatabaseHelper(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE education_items (
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
            CREATE TABLE education_meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun loadActive(): List<String> {
        val encodedItems = mutableListOf<String>()
        readableDatabase.query(
            EDUCATION_TABLE,
            arrayOf("contents_json"),
            "enabled = 1 AND deleted = 0",
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

    companion object {
        private const val DATABASE_NAME = "digital_nurse.db"
        private const val DATABASE_VERSION = 1
        private const val EDUCATION_TABLE = "education_items"
        private const val META_TABLE = "education_meta"
        private const val LEGACY_MIGRATION_KEY = "legacy_migration_completed"
    }
}
