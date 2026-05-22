using System.IO.Compression;
using System.Xml.Linq;
using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Core.Tests;

[TestClass]
public sealed class MethodAnalysisExcelWriterTests
{
    [TestMethod]
    public void Write_CreatesWorkbookWithSummaryAndParametersSheets()
    {
        var result = new MethodAnalysisResult(
            new[]
            {
                new MethodSummary("Foo", "Foo summary."),
                new MethodSummary("Bar", string.Empty)
            },
            new[]
            {
                new MethodParameter("Foo", "arg1"),
                new MethodParameter("Foo", "arg2")
            });

        using var stream = new MemoryStream();
        MethodAnalysisExcelWriter.Write(stream, result);
        stream.Position = 0;

        using var archive = new ZipArchive(stream, ZipArchiveMode.Read);
        var workbookXml = ReadEntry(archive, "xl/workbook.xml");
        var summarySheetXml = ReadEntry(archive, "xl/worksheets/sheet1.xml");
        var parametersSheetXml = ReadEntry(archive, "xl/worksheets/sheet2.xml");

        StringAssert.Contains(workbookXml, """<sheet name="Summary" sheetId="1" r:id="rId1"/>""");
        StringAssert.Contains(workbookXml, """<sheet name="Parameters" sheetId="2" r:id="rId2"/>""");

        CollectionAssert.AreEqual(
            new[] { "関数名", "Summaryコメント", "Foo", "Foo summary.", "Bar", string.Empty },
            ReadInlineStrings(summarySheetXml).ToArray());
        CollectionAssert.AreEqual(
            new[] { "関数名", "仮引数名", "Foo", "arg1", "Foo", "arg2" },
            ReadInlineStrings(parametersSheetXml).ToArray());
    }

    private static string ReadEntry(ZipArchive archive, string path)
    {
        var entry = archive.GetEntry(path);
        Assert.IsNotNull(entry, $"{path} was not found.");

        using var reader = new StreamReader(entry.Open());
        return reader.ReadToEnd();
    }

    private static IEnumerable<string> ReadInlineStrings(string worksheetXml)
    {
        XNamespace spreadsheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        var document = XDocument.Parse(worksheetXml);

        return document
            .Descendants(spreadsheet + "t")
            .Select(element => element.Value);
    }
}
