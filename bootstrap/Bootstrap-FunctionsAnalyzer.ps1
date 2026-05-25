[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Get-Location) "FunctionsAnalyzer.Source"),
    [switch]$NoRun
)

$ErrorActionPreference = "Stop"
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

# NOTE:
# Run this script as a .ps1 file saved on disk (do not paste line-by-line into the console).
# Here-string terminators ('@) must be at column 1; if indentation is added during copy/paste,
# parse errors such as "< は今後のために予約されています" can occur.

function Write-SourceFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $path = Join-Path $OutputPath $RelativePath
    $directory = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET 9 SDK が見つかりません。https://dotnet.microsoft.com/download/dotnet/9.0 からインストールしてください。"
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-SourceFile "Directory.Build.props" @'
<Project>
  <PropertyGroup Condition="'$(Configuration)' == 'Release'">
    <DebugType>none</DebugType>
    <DebugSymbols>false</DebugSymbols>
  </PropertyGroup>
</Project>
'@

Write-SourceFile ".gitignore" @'
bin/
obj/
.vs/
.vscode/
*.user
*.suo
'@

Write-SourceFile "README.md" @'
# C# Functions Analyzer

WinFormsで操作するC#ソース解析ツールです。選択した `.cs` ファイル内の通常のメソッド定義をRoslyn ASTで解析し、メソッド名、Summaryコメント、仮引数名、戻り値の型をExcelブックに出力します。

## 必要環境

- .NET 9 SDK
- Windows

リリース用の単一ファイルexeは自己完結形式で作成するため、利用者側に .NET 9 のインストールは不要です。

## 実行

```powershell
dotnet run --project .\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj
```

## リリースビルド

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-Release.ps1
```

作成されるexe:

```text
src\FunctionsAnalyzer.Gui\bin\Release\net9.0-windows\win-x64\publish\FunctionsAnalyzer.exe
```

## 導入手順

利用者には `FunctionsAnalyzer.exe` を任意のフォルダに配置してもらい、ダブルクリックで起動します。
'@

Write-SourceFile "src\FunctionsAnalyzer.Core\FunctionsAnalyzer.Core.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.1.0" />
  </ItemGroup>

</Project>
'@

Write-SourceFile "src\FunctionsAnalyzer.Core\Analysis.cs" @'
using System.IO.Compression;
using System.Security;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace FunctionsAnalyzer.Core;

public sealed record MethodSummary(string FunctionName, string SummaryComment);

public sealed record MethodDetail(string FunctionName, string Category, string Detail);

public sealed record MethodAnalysisResult(
    IReadOnlyList<MethodSummary> Summaries,
    IReadOnlyList<MethodDetail> Details);

public static class CSharpMethodSummaryExtractor
{
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
        var methods = root.DescendantNodes().OfType<MethodDeclarationSyntax>().ToList();

        var summaries = methods
            .Select(method => new MethodSummary(method.Identifier.ValueText, ExtractSummaryComment(method)))
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

        return summaryElement is null
            ? string.Empty
            : Regex.Replace(ReadXmlText(summaryElement.Content), @"\s+", " ").Trim();
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
}

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
            new[] { "関数名", "区分", "詳細" },
            result.Details.Select(detail => new[] { detail.FunctionName, detail.Category, detail.Detail }),
            secondColumnWidth: 18,
            thirdColumnWidth: 36));
    }

    private static void WriteEntry(ZipArchive archive, string path, string content)
    {
        var entry = archive.CreateEntry(path, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        writer.Write(content);
    }

    private static string CreateContentTypesXml() => """
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

    private static string CreatePackageRelationshipsXml() => """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """;

    private static string CreateWorkbookXml() => """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Summary" sheetId="1" r:id="rId1"/>
            <sheet name="Parameters" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>
        """;

    private static string CreateWorkbookRelationshipsXml() => """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """;

    private static string CreateStylesXml() => """
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

    private static string CreateWorksheetXml(IReadOnlyList<string> headers, IEnumerable<IReadOnlyList<string>> rows, double secondColumnWidth, double? thirdColumnWidth = null)
    {
        var builder = new StringBuilder();
        builder.AppendLine("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>""");
        builder.AppendLine("""<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">""");
        builder.Append($"""  <cols><col min="1" max="1" width="28" customWidth="1"/><col min="2" max="2" width="{secondColumnWidth}" customWidth="1"/>""");
        if (thirdColumnWidth is not null)
        {
            builder.Append($"""<col min="3" max="3" width="{thirdColumnWidth.Value}" customWidth="1"/>""");
        }

        builder.AppendLine("""</cols>""");
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
            builder.AppendLine($"""      <c r="{cellReference}" s="{styleIndex}" t="inlineStr"><is><t xml:space="preserve">{SecurityElement.Escape(values[columnIndex])}</t></is></c>""");
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
}
'@

Write-SourceFile "src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
    <AssemblyName>FunctionsAnalyzer</AssemblyName>
    <Nullable>enable</Nullable>
    <UseWindowsForms>true</UseWindowsForms>
    <EnableWindowsTargeting>true</EnableWindowsTargeting>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\FunctionsAnalyzer.Core\FunctionsAnalyzer.Core.csproj" />
  </ItemGroup>

</Project>
'@

Write-SourceFile "src\FunctionsAnalyzer.Gui\Properties\PublishProfiles\win-x64-single-file.pubxml" @'
<Project>
  <PropertyGroup>
    <Configuration>Release</Configuration>
    <TargetFramework>net9.0-windows</TargetFramework>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <SelfContained>true</SelfContained>
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
    <PublishTrimmed>false</PublishTrimmed>
    <PublishReadyToRun>false</PublishReadyToRun>
    <DebugType>none</DebugType>
    <DebugSymbols>false</DebugSymbols>
    <CopyOutputSymbolsToPublishDirectory>false</CopyOutputSymbolsToPublishDirectory>
    <PublishDir>bin\Release\net9.0-windows\win-x64\publish\</PublishDir>
  </PropertyGroup>
</Project>
'@

Write-SourceFile "src\FunctionsAnalyzer.Gui\Program.cs" @'
using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Gui;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

public sealed class MainForm : Form
{
    private readonly TextBox _sourceFileTextBox = new();
    private readonly TextBox _excelFileTextBox = new();
    private readonly TextBox _summaryFunctionNamesTextBox = new();
    private readonly TextBox _summaryCommentsTextBox = new();
    private readonly TextBox _parameterFunctionNamesTextBox = new();
    private readonly TextBox _parameterCategoriesTextBox = new();
    private readonly TextBox _parameterDetailsTextBox = new();
    private readonly Label _statusLabel = new();
    private readonly Button _copySummaryFunctionNamesButton = new();
    private readonly Button _copySummaryCommentsButton = new();
    private readonly Button _copyParameterFunctionNamesButton = new();
    private readonly Button _copyParameterCategoriesButton = new();
    private readonly Button _copyParameterDetailsButton = new();
    private MethodAnalysisResult _currentResult = new(Array.Empty<MethodSummary>(), Array.Empty<MethodDetail>());

    public MainForm()
    {
        Text = "C# Functions Analyzer";
        MinimumSize = new Size(900, 600);
        StartPosition = FormStartPosition.CenterScreen;
        InitializeLayout();
        UpdatePreview(new MethodAnalysisResult(Array.Empty<MethodSummary>(), Array.Empty<MethodDetail>()));
        SetStatus("解析対象の C# ファイルを選択してください。");
    }

    private void InitializeLayout()
    {
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new Padding(12) };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(CreatePathPanel(), 0, 0);
        root.Controls.Add(CreatePreviewTabs(), 0, 1);
        root.Controls.Add(CreateActionPanel(), 0, 2);
        root.Controls.Add(_statusLabel, 0, 3);
        _statusLabel.AutoSize = true;
        _statusLabel.Padding = new Padding(0, 8, 0, 0);
        Controls.Add(root);
    }

    private Control CreatePathPanel()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Top, ColumnCount = 3, RowCount = 2, AutoSize = true };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var browseSourceButton = CreateBrowseButton();
        browseSourceButton.Click += BrowseSourceButton_Click;
        var browseExcelButton = CreateBrowseButton();
        browseExcelButton.Click += BrowseExcelButton_Click;

        _sourceFileTextBox.Dock = DockStyle.Top;
        _sourceFileTextBox.Margin = new Padding(0, 0, 8, 8);
        _excelFileTextBox.Dock = DockStyle.Top;
        _excelFileTextBox.Margin = new Padding(0, 0, 8, 8);

        panel.Controls.Add(CreatePathLabel("C#ファイル"), 0, 0);
        panel.Controls.Add(_sourceFileTextBox, 1, 0);
        panel.Controls.Add(browseSourceButton, 2, 0);
        panel.Controls.Add(CreatePathLabel("Excel出力先"), 0, 1);
        panel.Controls.Add(_excelFileTextBox, 1, 1);
        panel.Controls.Add(browseExcelButton, 2, 1);
        return panel;
    }

    private static Label CreatePathLabel(string text) => new() { Text = text, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 0, 8, 8) };

    private static Button CreateBrowseButton() => new() { Text = "参照...", AutoSize = true, Margin = new Padding(0, 0, 0, 8) };

    private Control CreatePreviewTabs()
    {
        var tabs = new TabControl { Dock = DockStyle.Fill, Margin = new Padding(0, 8, 0, 8) };
        var summaryTab = new TabPage("Summary");
        summaryTab.Controls.Add(CreateColumnPreviewPanel("関数名", _summaryFunctionNamesTextBox, _copySummaryFunctionNamesButton, CopySummaryFunctionNamesButton_Click, "Summaryコメント", _summaryCommentsTextBox, _copySummaryCommentsButton, CopySummaryCommentsButton_Click));
        var parametersTab = new TabPage("Parameters");
        parametersTab.Controls.Add(CreateThreeColumnPreviewPanel("関数名", _parameterFunctionNamesTextBox, _copyParameterFunctionNamesButton, CopyParameterFunctionNamesButton_Click, "区分", _parameterCategoriesTextBox, _copyParameterCategoriesButton, CopyParameterCategoriesButton_Click, "詳細", _parameterDetailsTextBox, _copyParameterDetailsButton, CopyParameterDetailsButton_Click));
        tabs.TabPages.Add(summaryTab);
        tabs.TabPages.Add(parametersTab);
        return tabs;
    }

    private static Control CreateColumnPreviewPanel(string leftLabel, TextBox leftTextBox, Button leftCopyButton, EventHandler leftCopyHandler, string rightLabel, TextBox rightTextBox, Button rightCopyButton, EventHandler rightCopyHandler)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2, Padding = new Padding(8) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 35));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 65));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(CreatePreviewHeader(leftLabel, leftCopyButton, leftCopyHandler), 0, 0);
        panel.Controls.Add(CreatePreviewHeader(rightLabel, rightCopyButton, rightCopyHandler), 1, 0);
        ConfigurePreviewTextBox(leftTextBox);
        ConfigurePreviewTextBox(rightTextBox);
        panel.Controls.Add(leftTextBox, 0, 1);
        panel.Controls.Add(rightTextBox, 1, 1);
        return panel;
    }

    private static Control CreateThreeColumnPreviewPanel(string leftLabel, TextBox leftTextBox, Button leftCopyButton, EventHandler leftCopyHandler, string centerLabel, TextBox centerTextBox, Button centerCopyButton, EventHandler centerCopyHandler, string rightLabel, TextBox rightTextBox, Button rightCopyButton, EventHandler rightCopyHandler)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 2, Padding = new Padding(8) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 34));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 22));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 44));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(CreatePreviewHeader(leftLabel, leftCopyButton, leftCopyHandler), 0, 0);
        panel.Controls.Add(CreatePreviewHeader(centerLabel, centerCopyButton, centerCopyHandler), 1, 0);
        panel.Controls.Add(CreatePreviewHeader(rightLabel, rightCopyButton, rightCopyHandler), 2, 0);
        ConfigurePreviewTextBox(leftTextBox);
        ConfigurePreviewTextBox(centerTextBox);
        ConfigurePreviewTextBox(rightTextBox);
        panel.Controls.Add(leftTextBox, 0, 1);
        panel.Controls.Add(centerTextBox, 1, 1);
        panel.Controls.Add(rightTextBox, 2, 1);
        return panel;
    }

    private static Control CreatePreviewHeader(string labelText, Button copyButton, EventHandler clickHandler)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, AutoSize = true, Margin = new Padding(0, 0, 8, 4) };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        copyButton.Text = "コピー";
        copyButton.AutoSize = true;
        copyButton.Anchor = AnchorStyles.Right;
        copyButton.Click += clickHandler;
        panel.Controls.Add(new Label { Text = labelText, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        panel.Controls.Add(copyButton, 1, 0);
        return panel;
    }

    private static void ConfigurePreviewTextBox(TextBox textBox)
    {
        textBox.Dock = DockStyle.Fill;
        textBox.Multiline = true;
        textBox.ReadOnly = true;
        textBox.ScrollBars = ScrollBars.Both;
        textBox.WordWrap = false;
        textBox.Font = new Font(FontFamily.GenericMonospace, 9F);
        textBox.Margin = new Padding(0, 0, 8, 0);
    }

    private Control CreateActionPanel()
    {
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        var analyzeButton = new Button { Text = "解析", AutoSize = true };
        analyzeButton.Click += (_, _) => AnalyzeCurrentFile();
        var exportButton = new Button { Text = "Excel出力", AutoSize = true };
        exportButton.Click += ExportButton_Click;
        panel.Controls.Add(analyzeButton);
        panel.Controls.Add(exportButton);
        return panel;
    }

    private void BrowseSourceButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog { Filter = "C# files (*.cs)|*.cs|All files (*.*)|*.*", Title = "解析対象の C# ファイルを選択" };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        _sourceFileTextBox.Text = dialog.FileName;
        if (string.IsNullOrWhiteSpace(_excelFileTextBox.Text))
        {
            _excelFileTextBox.Text = CreateDefaultExcelPath(dialog.FileName);
        }
    }

    private void BrowseExcelButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new SaveFileDialog
        {
            Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*",
            Title = "Excel出力先を選択",
            FileName = string.IsNullOrWhiteSpace(_excelFileTextBox.Text) ? "functions.xlsx" : Path.GetFileName(_excelFileTextBox.Text),
            InitialDirectory = GetInitialExcelDirectory()
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _excelFileTextBox.Text = dialog.FileName;
        }
    }

    private void ExportButton_Click(object? sender, EventArgs e)
    {
        try
        {
            if (!AnalyzeCurrentFile())
            {
                return;
            }

            var excelPath = EnsureExcelPath();
            MethodAnalysisExcelWriter.WriteToFile(excelPath, _currentResult);
            SetStatus($"{_currentResult.Summaries.Count} 件のメソッド、{_currentResult.Details.Count} 件のParameters行をExcel出力しました。");
        }
        catch (Exception ex)
        {
            ShowError("Excel出力に失敗しました。", ex);
        }
    }

    private bool AnalyzeCurrentFile()
    {
        try
        {
            var sourcePath = _sourceFileTextBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(sourcePath))
            {
                throw new InvalidOperationException("解析対象の C# ファイルを選択してください。");
            }

            if (!File.Exists(sourcePath))
            {
                throw new FileNotFoundException("解析対象の C# ファイルが見つかりません。", sourcePath);
            }

            var result = CSharpMethodSummaryExtractor.AnalyzeFile(sourcePath);
            UpdatePreview(result);
            if (string.IsNullOrWhiteSpace(_excelFileTextBox.Text))
            {
                _excelFileTextBox.Text = CreateDefaultExcelPath(sourcePath);
            }

            SetStatus($"{result.Summaries.Count} 件のメソッド、{result.Details.Count} 件のParameters行を解析しました。");
            return true;
        }
        catch (Exception ex)
        {
            ShowError("解析に失敗しました。", ex);
            return false;
        }
    }

    private void UpdatePreview(MethodAnalysisResult result)
    {
        _currentResult = result;
        _summaryFunctionNamesTextBox.Text = string.Join(Environment.NewLine, result.Summaries.Select(summary => summary.FunctionName));
        _summaryCommentsTextBox.Text = string.Join(Environment.NewLine, result.Summaries.Select(summary => summary.SummaryComment));
        _parameterFunctionNamesTextBox.Text = string.Join(Environment.NewLine, result.Details.Select(detail => detail.FunctionName));
        _parameterCategoriesTextBox.Text = string.Join(Environment.NewLine, result.Details.Select(detail => detail.Category));
        _parameterDetailsTextBox.Text = string.Join(Environment.NewLine, result.Details.Select(detail => detail.Detail));
        _copySummaryFunctionNamesButton.Enabled = result.Summaries.Count > 0;
        _copySummaryCommentsButton.Enabled = result.Summaries.Count > 0;
        _copyParameterFunctionNamesButton.Enabled = result.Details.Count > 0;
        _copyParameterCategoriesButton.Enabled = result.Details.Count > 0;
        _copyParameterDetailsButton.Enabled = result.Details.Count > 0;
    }

    private string EnsureExcelPath()
    {
        var excelPath = _excelFileTextBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(excelPath))
        {
            return excelPath;
        }

        excelPath = CreateDefaultExcelPath(_sourceFileTextBox.Text.Trim());
        _excelFileTextBox.Text = excelPath;
        return excelPath;
    }

    private string GetInitialExcelDirectory()
    {
        var excelPath = _excelFileTextBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(excelPath))
        {
            var excelDirectory = Path.GetDirectoryName(excelPath);
            if (!string.IsNullOrWhiteSpace(excelDirectory) && Directory.Exists(excelDirectory))
            {
                return excelDirectory;
            }
        }

        var sourceDirectory = Path.GetDirectoryName(_sourceFileTextBox.Text.Trim());
        return !string.IsNullOrWhiteSpace(sourceDirectory) && Directory.Exists(sourceDirectory)
            ? sourceDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    }

    private static string CreateDefaultExcelPath(string sourcePath)
    {
        var directory = Path.GetDirectoryName(sourcePath);
        var fileName = Path.GetFileNameWithoutExtension(sourcePath);
        var excelFileName = string.IsNullOrWhiteSpace(fileName) ? "functions.xlsx" : $"{fileName}_functions.xlsx";
        return string.IsNullOrWhiteSpace(directory) ? excelFileName : Path.Combine(directory, excelFileName);
    }

    private void CopySummaryFunctionNamesButton_Click(object? sender, EventArgs e) => CopyText(_summaryFunctionNamesTextBox.Text, "Summaryシートの関数名をコピーしました。");

    private void CopySummaryCommentsButton_Click(object? sender, EventArgs e) => CopyText(_summaryCommentsTextBox.Text, "Summaryコメントをコピーしました。");

    private void CopyParameterFunctionNamesButton_Click(object? sender, EventArgs e) => CopyText(_parameterFunctionNamesTextBox.Text, "Parametersシートの関数名をコピーしました。");

    private void CopyParameterCategoriesButton_Click(object? sender, EventArgs e) => CopyText(_parameterCategoriesTextBox.Text, "区分をコピーしました。");

    private void CopyParameterDetailsButton_Click(object? sender, EventArgs e) => CopyText(_parameterDetailsTextBox.Text, "詳細をコピーしました。");

    private void CopyText(string text, string successMessage)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        Clipboard.SetText(text);
        SetStatus(successMessage);
    }

    private void ShowError(string message, Exception exception)
    {
        SetStatus(message);
        MessageBox.Show(this, $"{message}{Environment.NewLine}{exception.Message}", "C# Functions Analyzer", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private void SetStatus(string message)
    {
        _statusLabel.Text = $"ステータス: {message}";
    }
}
'@

Write-SourceFile "scripts\Publish-Release.ps1" @'
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $repoRoot "src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj"
$publishProfile = "win-x64-single-file"
$publishDirectory = Join-Path $repoRoot "src\FunctionsAnalyzer.Gui\bin\Release\net9.0-windows\win-x64\publish"
$exePath = Join-Path $publishDirectory "FunctionsAnalyzer.exe"

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}

dotnet publish $projectPath -p:PublishProfile=$publishProfile
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Publish completed, but the expected exe was not found: $exePath"
}

Write-Host "Release exe created:"
Write-Host $exePath
'@

Write-Host "Source expanded to: $OutputPath"

if ($NoRun) {
    Write-Host "Run with: dotnet run --project `"$OutputPath\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj`""
    return
}

$isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
if (-not $isWindows) {
    Write-Warning "このツールはWinFormsアプリのため、実行はWindowsで行ってください。ソース展開は完了しています。"
    return
}

dotnet run --project "$OutputPath\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
