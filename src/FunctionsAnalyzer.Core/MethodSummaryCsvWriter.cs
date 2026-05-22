using System.Text;

namespace FunctionsAnalyzer.Core;

public static class MethodSummaryCsvWriter
{
    public static string ToCsv(IEnumerable<MethodSummary> methods)
    {
        ArgumentNullException.ThrowIfNull(methods);

        var builder = new StringBuilder();
        builder.AppendLine("関数名,Summaryコメント");

        foreach (var method in methods)
        {
            builder
                .Append(Escape(method.FunctionName))
                .Append(',')
                .Append(Escape(method.SummaryComment))
                .AppendLine();
        }

        return builder.ToString();
    }

    public static void WriteToFile(string filePath, IEnumerable<MethodSummary> methods)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        var directory = Path.GetDirectoryName(Path.GetFullPath(filePath));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(filePath, ToCsv(methods), new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
    }

    private static string Escape(string value)
    {
        if (value.Contains('"') || value.Contains(',') || value.Contains('\r') || value.Contains('\n'))
        {
            return $"\"{value.Replace("\"", "\"\"")}\"";
        }

        return value;
    }
}
