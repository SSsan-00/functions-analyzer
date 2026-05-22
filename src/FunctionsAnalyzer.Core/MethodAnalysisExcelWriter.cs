using System.IO.Compression;
using System.Security;
using System.Text;

namespace FunctionsAnalyzer.Core;

public static class MethodAnalysisExcelWriter
{
    public static void WriteToFile(string filePath, MethodAnalysisResult result)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        ArgumentNullException.ThrowIfNull(result);

        var directory = Path.GetDirectoryName(Path.GetFullPath(filePath));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        using var stream = File.Create(filePath);
        Write(stream, result);
    }

    public static void Write(Stream stream, MethodAnalysisResult result)
    {
        ArgumentNullException.ThrowIfNull(stream);
        ArgumentNullException.ThrowIfNull(result);

        using var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true);

        WriteEntry(archive, "[Content_Types].xml", CreateContentTypesXml());
        WriteEntry(archive, "_rels/.rels", CreatePackageRelationshipsXml());
        WriteEntry(archive, "xl/workbook.xml", CreateWorkbookXml());
        WriteEntry(archive, "xl/_rels/workbook.xml.rels", CreateWorkbookRelationshipsXml());
        WriteEntry(archive, "xl/styles.xml", CreateStylesXml());
        WriteEntry(archive, "xl/worksheets/sheet1.xml", CreateWorksheetXml(
            new[] { "関数名", "Summaryコメント" },
            result.Summaries.Select(summary => new[] { summary.FunctionName, summary.SummaryComment }),
            secondColumnWidth: 80));
        WriteEntry(archive, "xl/worksheets/sheet2.xml", CreateWorksheetXml(
            new[] { "関数名", "仮引数名" },
            result.Parameters.Select(parameter => new[] { parameter.FunctionName, parameter.ParameterName }),
            secondColumnWidth: 28));
    }

    private static void WriteEntry(ZipArchive archive, string path, string content)
    {
        var entry = archive.CreateEntry(path, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        writer.Write(content);
    }

    private static string CreateContentTypesXml()
    {
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
              <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
              <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
              <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            </Types>
            """;
    }

    private static string CreatePackageRelationshipsXml()
    {
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """;
    }

    private static string CreateWorkbookXml()
    {
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets>
                <sheet name="Summary" sheetId="1" r:id="rId1"/>
                <sheet name="Parameters" sheetId="2" r:id="rId2"/>
              </sheets>
            </workbook>
            """;
    }

    private static string CreateWorkbookRelationshipsXml()
    {
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """;
    }

    private static string CreateStylesXml()
    {
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <fonts count="2">
                <font><sz val="11"/><name val="Calibri"/></font>
                <font><b/><sz val="11"/><name val="Calibri"/></font>
              </fonts>
              <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
              <borders count="1"><border/></borders>
              <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
              <cellXfs count="2">
                <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
                <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
              </cellXfs>
              <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
            </styleSheet>
            """;
    }

    private static string CreateWorksheetXml(
        IReadOnlyList<string> headers,
        IEnumerable<IReadOnlyList<string>> rows,
        double secondColumnWidth)
    {
        var builder = new StringBuilder();
        builder.AppendLine("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>""");
        builder.AppendLine("""<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">""");
        builder.AppendLine($"""  <cols><col min="1" max="1" width="28" customWidth="1"/><col min="2" max="2" width="{secondColumnWidth}" customWidth="1"/></cols>""");
        builder.AppendLine("""  <sheetData>""");

        WriteRow(builder, 1, headers, styleIndex: 1);

        var rowIndex = 2;
        foreach (var row in rows)
        {
            WriteRow(builder, rowIndex, row, styleIndex: 0);
            rowIndex++;
        }

        builder.AppendLine("""  </sheetData>""");
        builder.AppendLine("""</worksheet>""");
        return builder.ToString();
    }

    private static void WriteRow(StringBuilder builder, int rowIndex, IReadOnlyList<string> values, int styleIndex)
    {
        builder.AppendLine($"""    <row r="{rowIndex}">""");
        for (var columnIndex = 0; columnIndex < values.Count; columnIndex++)
        {
            var cellReference = $"{ToColumnName(columnIndex + 1)}{rowIndex}";
            builder.AppendLine($"""      <c r="{cellReference}" s="{styleIndex}" t="inlineStr"><is><t xml:space="preserve">{EscapeXml(values[columnIndex])}</t></is></c>""");
        }

        builder.AppendLine("""    </row>""");
    }

    private static string ToColumnName(int columnNumber)
    {
        var name = string.Empty;
        while (columnNumber > 0)
        {
            columnNumber--;
            name = (char)('A' + columnNumber % 26) + name;
            columnNumber /= 26;
        }

        return name;
    }

    private static string EscapeXml(string value)
    {
        return SecurityElement.Escape(value) ?? string.Empty;
    }
}
