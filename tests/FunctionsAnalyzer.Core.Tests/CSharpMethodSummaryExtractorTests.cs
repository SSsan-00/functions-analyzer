using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Core.Tests;

[TestClass]
public sealed class CSharpMethodSummaryExtractorTests
{
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
