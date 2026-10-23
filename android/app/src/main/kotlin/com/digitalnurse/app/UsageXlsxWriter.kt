package com.digitalnurse.app

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Pure XLSX serialization, independent of Activity and Android file storage. */
object UsageXlsxWriter {
    fun build(
        summaryRows: List<List<Any?>>,
        detailRows: List<List<Any?>>,
        educationSummaryRows: List<List<Any?>>?,
        comprehensionRows: List<List<Any?>>?,
        educationEventRows: List<List<Any?>>?,
    ): ByteArray {
        val sheets = mutableListOf(
            XlsxSheet("统计汇总", summaryRows, true),
            XlsxSheet("使用明细", detailRows, false),
        )
        if (educationSummaryRows != null &&
            comprehensionRows != null &&
            educationEventRows != null
        ) {
            sheets += XlsxSheet("床旁宣教汇总", educationSummaryRows, true)
            sheets += XlsxSheet("理解确认", comprehensionRows, false)
            sheets += XlsxSheet("宣教事件明细", educationEventRows, false)
        }
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            addZipEntry(zip, "[Content_Types].xml", contentTypesXml(sheets.size))
            addZipEntry(zip, "_rels/.rels", rootRelationshipsXml())
            addZipEntry(zip, "xl/workbook.xml", workbookXml(sheets))
            addZipEntry(
                zip,
                "xl/_rels/workbook.xml.rels",
                workbookRelationshipsXml(sheets.size),
            )
            addZipEntry(zip, "xl/styles.xml", stylesXml())
            sheets.forEachIndexed { index, sheet ->
                addZipEntry(
                    zip,
                    "xl/worksheets/sheet${index + 1}.xml",
                    worksheetXml(sheet.rows, summarySheet = sheet.summary),
                )
            }
        }
        return output.toByteArray()
    }

    private data class XlsxSheet(
        val name: String,
        val rows: List<List<Any?>>,
        val summary: Boolean,
    )

    private fun addZipEntry(zip: ZipOutputStream, path: String, content: String) {
        zip.putNextEntry(ZipEntry(path))
        zip.write(content.toByteArray(Charsets.UTF_8))
        zip.closeEntry()
    }

    private fun contentTypesXml(sheetCount: Int): String {
        val worksheets = (1..sheetCount).joinToString("") { index ->
            "<Override PartName=\"/xl/worksheets/sheet$index.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          $worksheets
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>""".trimIndent()
    }

    private fun rootRelationshipsXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>""".trimIndent()

    private fun workbookXml(sheets: List<XlsxSheet>): String {
        val sheetNodes = sheets.mapIndexed { index, sheet ->
            "<sheet name=\"${escapeXml(sheet.name)}\" sheetId=\"${index + 1}\" r:id=\"rId${index + 1}\"/>"
        }.joinToString("")
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            $sheetNodes
          </sheets>
        </workbook>""".trimIndent()
    }

    private fun workbookRelationshipsXml(sheetCount: Int): String {
        val worksheetRelationships = (1..sheetCount).joinToString("") { index ->
            "<Relationship Id=\"rId$index\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$index.xml\"/>"
        }
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          $worksheetRelationships
          <Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>""".trimIndent()
    }

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

}
