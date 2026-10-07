using System.Text;
using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Core.Tests;

[TestClass]
public sealed class CSharpMethodSummaryExtractorTests
{
    [TestMethod]
    [DataRow(65001, false)]
    [DataRow(65001, true)]
    [DataRow(932, false)]
    [DataRow(1200, true)]
    [DataRow(1201, true)]
    [DataRow(12000, true)]
    [DataRow(12001, true)]
    public void AnalyzeFile_AutoDetectsEncodingAndPreservesJapanese(int codePage, bool withBom)
    {
        const string source = """
            public class Sample
            {
                /// <summary>日本語の説明。① 髙橋</summary>
                public string 取得(string 名前) => 名前;
            }
            """;
        var encoding = codePage == 932
            ? CodePagesEncodingProvider.Instance.GetEncoding(932)!
            : Encoding.GetEncoding(codePage);
        var bytes = (withBom ? encoding.GetPreamble() : Array.Empty<byte>())
            .Concat(encoding.GetBytes(source)).ToArray();
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllBytes(path, bytes);
            var result = CSharpMethodSummaryExtractor.AnalyzeFile(path);
            Assert.AreEqual(new MethodSummary("取得", "日本語の説明。① 髙橋"), result.Summaries.Single());
            CollectionAssert.AreEqual(
                new[] { new MethodDetail("取得", "引数", "名前"), new MethodDetail("取得", "戻り値", "string") },
                result.Details.ToArray());
            CollectionAssert.AreEqual(result.Summaries.ToArray(), CSharpMethodSummaryExtractor.ExtractFromFile(path).ToArray());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [TestMethod]
    [DataRow("")]
    [DataRow("public class Sample { public void Run() {} }")]
    public void AnalyzeFile_AcceptsEmptyAndAsciiFiles(string source)
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllBytes(path, Encoding.ASCII.GetBytes(source));
            CollectionAssert.AreEqual(
                CSharpMethodSummaryExtractor.AnalyzeSource(source).Summaries.ToArray(),
                CSharpMethodSummaryExtractor.AnalyzeFile(path).Summaries.ToArray());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public void AnalyzeFile_RejectsInvalidBytesWithoutReplacingCharacters(bool withUtf8Bom)
    {
        var path = Path.GetTempFileName();
        try
        {
            // 0x81 alone is invalid in both UTF-8 and CP932. A BOM must also be respected.
            File.WriteAllBytes(path, withUtf8Bom ? new byte[] { 0xEF, 0xBB, 0xBF, 0x81 } : new byte[] { 0x81 });
            Assert.ThrowsExactly<DecoderFallbackException>(() => CSharpMethodSummaryExtractor.AnalyzeFile(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [TestMethod]
    public void ExtractFromSource_ReturnsNormalMethodsWithSummaryComments()
    {
        const string source = """
            public sealed class Sample
            {
                /// <summary>
                /// First summary.
                /// </summary>
                public void First()
                {
                }

                /// <summary>Second summary.</summary>
                private static int Second() => 1;
            }
            """;

        var results = CSharpMethodSummaryExtractor.ExtractFromSource(source);

        CollectionAssert.AreEqual(
            new[]
            {
                new MethodSummary("First", "First summary."),
                new MethodSummary("Second", "Second summary.")
            },
            results.ToArray());
    }

    [TestMethod]
    public void ExtractFromSource_FlattensMultiLineSummaryWithSingleSpaces()
    {
        const string source = """
            public sealed class Sample
            {
                /// <summary>
                /// First line.
                /// Second    line.
                ///
                /// Third line.
                /// </summary>
                public void Execute()
                {
                }
            }
            """;

        var result = CSharpMethodSummaryExtractor.ExtractFromSource(source).Single();

        Assert.AreEqual("First line. Second line. Third line.", result.SummaryComment);
    }

    [TestMethod]
    public void ExtractFromSource_UsesEmptySummaryWhenSummaryCommentIsMissing()
    {
        const string source = """
            public sealed class Sample
            {
                public void Execute()
                {
                }
            }
            """;

        var result = CSharpMethodSummaryExtractor.ExtractFromSource(source).Single();

        Assert.AreEqual("Execute", result.FunctionName);
        Assert.AreEqual(string.Empty, result.SummaryComment);
    }

    [TestMethod]
    public void ExtractFromSource_IgnoresCommentedOutMethodDefinitions()
    {
        const string source = """
            public sealed class Sample
            {
                // /// <summary>Ignored summary.</summary>
                // public void Ignored()
                // {
                // }

                /// <summary>Included summary.</summary>
                public void Included()
                {
                }
            }
            """;

        var result = CSharpMethodSummaryExtractor.ExtractFromSource(source).Single();

        Assert.AreEqual("Included", result.FunctionName);
        Assert.AreEqual("Included summary.", result.SummaryComment);
    }

    [TestMethod]
    public void ExtractFromSource_DoesNotReturnConstructorsPropertiesOrLocalFunctions()
    {
        const string source = """
            public sealed class Sample
            {
                public Sample()
                {
                }

                public int Value { get; set; }

                /// <summary>Outer summary.</summary>
                public void Outer()
                {
                    void Local()
                    {
                    }
                }
            }
            """;

        var result = CSharpMethodSummaryExtractor.ExtractFromSource(source).Single();

        Assert.AreEqual("Outer", result.FunctionName);
        Assert.AreEqual("Outer summary.", result.SummaryComment);
    }

    [TestMethod]
    public void AnalyzeSource_ReturnsParameterAndReturnValueRowsForEachMethod()
    {
        const string source = """
            public sealed class Sample
            {
                public void Foo(string arg1, int arg2)
                {
                }

                public int Bar()
                {
                    return 0;
                }
            }
            """;

        var result = CSharpMethodSummaryExtractor.AnalyzeSource(source);

        CollectionAssert.AreEqual(
            new[]
            {
                new MethodDetail("Foo", "引数", "arg1"),
                new MethodDetail("Foo", "引数", "arg2"),
                new MethodDetail("Foo", "戻り値", "void"),
                new MethodDetail("Bar", "戻り値", "int")
            },
            result.Details.ToArray());
    }
}
