using System.Text;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace FunctionsAnalyzer.Core;

public static class CSharpMethodSummaryExtractor
{
    public static IReadOnlyList<MethodSummary> ExtractFromFile(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        return AnalyzeFile(filePath).Summaries;
    }

    public static IReadOnlyList<MethodSummary> ExtractFromSource(string source)
    {
        return AnalyzeSource(source).Summaries;
    }

    public static MethodAnalysisResult AnalyzeFile(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        return AnalyzeSource(File.ReadAllText(filePath, Encoding.UTF8));
    }

    public static MethodAnalysisResult AnalyzeSource(string source)
    {
        ArgumentNullException.ThrowIfNull(source);

        var tree = CSharpSyntaxTree.ParseText(source);
        var root = tree.GetCompilationUnitRoot();
        var methods = root
            .DescendantNodes()
            .OfType<MethodDeclarationSyntax>()
            .ToList();

        var summaries = methods
            .Select(method => new MethodSummary(
                method.Identifier.ValueText,
                ExtractSummaryComment(method)))
            .ToList();

        var details = methods
            .SelectMany(ExtractDetails)
            .ToList();

        return new MethodAnalysisResult(summaries, details);
    }

    private static IEnumerable<MethodDetail> ExtractDetails(MethodDeclarationSyntax method)
    {
        var functionName = method.Identifier.ValueText;
        foreach (var parameter in method.ParameterList.Parameters)
        {
            yield return new MethodDetail(functionName, "引数", parameter.Identifier.ValueText);
        }

        yield return new MethodDetail(functionName, "戻り値", method.ReturnType.ToString());
    }

    private static string ExtractSummaryComment(MethodDeclarationSyntax method)
    {
        var documentationComment = method
            .GetLeadingTrivia()
            .Select(trivia => trivia.GetStructure())
            .OfType<DocumentationCommentTriviaSyntax>()
            .FirstOrDefault();

        if (documentationComment is null)
        {
            return string.Empty;
        }

        var summaryElement = documentationComment
            .Content
            .OfType<XmlElementSyntax>()
            .FirstOrDefault(element => string.Equals(
                element.StartTag.Name.LocalName.ValueText,
                "summary",
                StringComparison.OrdinalIgnoreCase));

        if (summaryElement is null)
        {
            return string.Empty;
        }

        return NormalizeWhitespace(ReadXmlText(summaryElement.Content));
    }

    private static string ReadXmlText(SyntaxList<XmlNodeSyntax> nodes)
    {
        var builder = new StringBuilder();

        foreach (var node in nodes)
        {
            AppendXmlText(node, builder);
        }

        return builder.ToString();
    }

    private static void AppendXmlText(XmlNodeSyntax node, StringBuilder builder)
    {
        switch (node)
        {
            case XmlTextSyntax text:
                foreach (var token in text.TextTokens)
                {
                    builder.Append(token.ValueText);
                }

                break;
            case XmlElementSyntax element:
                foreach (var childNode in element.Content)
                {
                    AppendXmlText(childNode, builder);
                }

                break;
        }
    }

    private static string NormalizeWhitespace(string value)
    {
        return Regex.Replace(value, @"\s+", " ").Trim();
    }
}
