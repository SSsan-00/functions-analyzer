using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Core.Tests;

[TestClass]
public sealed class MethodSummaryCsvWriterTests
{
    [TestMethod]
    public void ToCsv_WritesHeaderAndRowsInFunctionNameSummaryOrder()
    {
        var csv = MethodSummaryCsvWriter.ToCsv(
            new[]
            {
                new MethodSummary("First", "First summary."),
                new MethodSummary("Second", string.Empty)
            });

        Assert.AreEqual(
            "関数名,Summaryコメント" + Environment.NewLine
            + "First,First summary." + Environment.NewLine
            + "Second," + Environment.NewLine,
            csv);
    }

    [TestMethod]
    public void ToCsv_EscapesCsvSpecialCharacters()
    {
        var csv = MethodSummaryCsvWriter.ToCsv(
            new[]
            {
                new MethodSummary("Execute", "Uses \"quoted\", comma text.")
            });

        Assert.AreEqual(
            "関数名,Summaryコメント" + Environment.NewLine
            + "Execute,\"Uses \"\"quoted\"\", comma text.\"" + Environment.NewLine,
            csv);
    }
}
