package com.digitalnurse.app

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UsageXlsxWriterTest {
    @Test
    fun buildsFiveReadableWorksheetsWithEscapedTextAndNumericCounts() {
        val sheets = unzip(
            UsageXlsxWriter.build(
                listOf(listOf("统计汇总"), listOf("医院", "医院 & <科室>")),
                listOf(listOf("次数", "说明"), listOf(3, "=1+1")),
                listOf(listOf("床旁宣教汇总")),
                listOf(listOf("理解确认")),
                listOf(listOf("宣教事件明细")),
            ),
        )
        assertEquals(5, sheets.keys.count { it.startsWith("xl/worksheets/") })
        // Every XML part must remain well-formed after user-provided text.
        val parser = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        sheets.values.forEach { parser.parse(ByteArrayInputStream(it.toByteArray())) }
        val summary = sheets.getValue("xl/worksheets/sheet1.xml")
        assertTrue(summary.contains("医院 &amp; &lt;科室&gt;"))
        val details = sheets.getValue("xl/worksheets/sheet2.xml")
        assertTrue(details.contains("<v>3</v>"))
        assertTrue(details.contains("t=\"inlineStr\"><is><t>=1+1</t>"))
        assertFalse(details.contains("<f>"))
        assertTrue(sheets.getValue("xl/workbook.xml").contains("理解确认"))
    }

    @Test
    fun keepsLegacyTwoSheetExportWhenEducationRowsAreAbsent() {
        val sheets = unzip(
            UsageXlsxWriter.build(
                listOf(listOf("统计汇总")), emptyList(), null, null, null,
            ),
        )
        assertEquals(2, sheets.keys.count { it.startsWith("xl/worksheets/") })
        assertFalse(sheets.getValue("xl/workbook.xml").contains("理解确认"))
    }

    private fun unzip(bytes: ByteArray): Map<String, String> {
        val parts = linkedMapOf<String, String>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                parts[entry.name] = zip.readBytes().toString(Charsets.UTF_8)
                zip.closeEntry()
            }
        }
        return parts
    }
}
