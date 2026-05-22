namespace FunctionsAnalyzer.Core;

public sealed record MethodAnalysisResult(
    IReadOnlyList<MethodSummary> Summaries,
    IReadOnlyList<MethodParameter> Parameters);
