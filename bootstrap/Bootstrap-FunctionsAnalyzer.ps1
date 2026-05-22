[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Get-Location) "FunctionsAnalyzer.Source"),
    [switch]$NoRun
)

$ErrorActionPreference = "Stop"
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

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

WinFormsで操作するC#ソース解析ツールです。選択した `.cs` ファイル内の通常のメソッド定義をRoslyn ASTで解析し、メソッド名とXMLドキュメントコメントの `<summary>` をCSVに出力します。

## 必要環境

- .NET 9 SDK
- Windows

## 実行

```powershell
dotnet run --project .\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj
```
'@

Write-SourceFile "FunctionsAnalyzer.sln" @'

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{827E0CD3-B72D-47B6-A68D-7590B98EB39B}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "FunctionsAnalyzer.Core", "src\FunctionsAnalyzer.Core\FunctionsAnalyzer.Core.csproj", "{B6069699-A711-4195-8BC4-D382438AB187}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "FunctionsAnalyzer.Gui", "src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj", "{B43A9A00-FF65-42BB-A815-12AB51A80503}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{B6069699-A711-4195-8BC4-D382438AB187}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{B6069699-A711-4195-8BC4-D382438AB187}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{B6069699-A711-4195-8BC4-D382438AB187}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{B6069699-A711-4195-8BC4-D382438AB187}.Release|Any CPU.Build.0 = Release|Any CPU
		{B43A9A00-FF65-42BB-A815-12AB51A80503}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{B43A9A00-FF65-42BB-A815-12AB51A80503}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{B43A9A00-FF65-42BB-A815-12AB51A80503}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{B43A9A00-FF65-42BB-A815-12AB51A80503}.Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(NestedProjects) = preSolution
		{B6069699-A711-4195-8BC4-D382438AB187} = {827E0CD3-B72D-47B6-A68D-7590B98EB39B}
		{B43A9A00-FF65-42BB-A815-12AB51A80503} = {827E0CD3-B72D-47B6-A68D-7590B98EB39B}
	EndGlobalSection
EndGlobal
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

Write-SourceFile "src\FunctionsAnalyzer.Core\MethodSummary.cs" @'
namespace FunctionsAnalyzer.Core;

public sealed record MethodSummary(string FunctionName, string SummaryComment);
'@

Write-SourceFile "src\FunctionsAnalyzer.Core\CSharpMethodSummaryExtractor.cs" @'
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

        return ExtractFromSource(File.ReadAllText(filePath, Encoding.UTF8));
    }

    public static IReadOnlyList<MethodSummary> ExtractFromSource(string source)
    {
        ArgumentNullException.ThrowIfNull(source);

        var tree = CSharpSyntaxTree.ParseText(source);
        var root = tree.GetCompilationUnitRoot();

        return root
            .DescendantNodes()
            .OfType<MethodDeclarationSyntax>()
            .Select(method => new MethodSummary(
                method.Identifier.ValueText,
                ExtractSummaryComment(method)))
            .ToList();
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
'@

Write-SourceFile "src\FunctionsAnalyzer.Core\MethodSummaryCsvWriter.cs" @'
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
'@

Write-SourceFile "src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj" @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
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

Write-SourceFile "src\FunctionsAnalyzer.Gui\Program.cs" @'
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
'@

Write-SourceFile "src\FunctionsAnalyzer.Gui\MainForm.cs" @'
using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Gui;

public sealed class MainForm : Form
{
    private readonly TextBox _sourceFileTextBox = new();
    private readonly TextBox _csvFileTextBox = new();
    private readonly TextBox _functionNamesTextBox = new();
    private readonly TextBox _summaryCommentsTextBox = new();
    private readonly Label _statusLabel = new();
    private readonly Button _copyFunctionNamesButton = new();
    private readonly Button _copySummaryCommentsButton = new();

    private IReadOnlyList<MethodSummary> _currentResults = Array.Empty<MethodSummary>();

    public MainForm()
    {
        Text = "C# Functions Analyzer";
        MinimumSize = new Size(860, 560);
        StartPosition = FormStartPosition.CenterScreen;

        InitializeLayout();
        UpdatePreview(Array.Empty<MethodSummary>());
        SetStatus("解析対象の C# ファイルを選択してください。");
    }

    private void InitializeLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        root.Controls.Add(CreatePathPanel(), 0, 0);
        root.Controls.Add(CreatePreviewPanel(), 0, 1);
        root.Controls.Add(CreateActionPanel(), 0, 2);
        root.Controls.Add(_statusLabel, 0, 3);

        _statusLabel.AutoSize = true;
        _statusLabel.Padding = new Padding(0, 8, 0, 0);

        Controls.Add(root);
    }

    private Control CreatePathPanel()
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 3,
            RowCount = 2,
            AutoSize = true
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var sourceLabel = CreatePathLabel("C#ファイル");
        _sourceFileTextBox.Dock = DockStyle.Top;
        _sourceFileTextBox.Margin = new Padding(0, 0, 8, 8);

        var browseSourceButton = CreateBrowseButton();
        browseSourceButton.Click += BrowseSourceButton_Click;

        var csvLabel = CreatePathLabel("CSV出力先");
        _csvFileTextBox.Dock = DockStyle.Top;
        _csvFileTextBox.Margin = new Padding(0, 0, 8, 8);

        var browseCsvButton = CreateBrowseButton();
        browseCsvButton.Click += BrowseCsvButton_Click;

        panel.Controls.Add(sourceLabel, 0, 0);
        panel.Controls.Add(_sourceFileTextBox, 1, 0);
        panel.Controls.Add(browseSourceButton, 2, 0);
        panel.Controls.Add(csvLabel, 0, 1);
        panel.Controls.Add(_csvFileTextBox, 1, 1);
        panel.Controls.Add(browseCsvButton, 2, 1);

        return panel;
    }

    private static Label CreatePathLabel(string text)
    {
        return new Label
        {
            Text = text,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 0, 8, 8)
        };
    }

    private static Button CreateBrowseButton()
    {
        return new Button
        {
            Text = "参照...",
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 8)
        };
    }

    private Control CreatePreviewPanel()
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 2,
            Margin = new Padding(0, 8, 0, 8)
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 35));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 65));
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        panel.Controls.Add(CreatePreviewHeader("関数名", _copyFunctionNamesButton, CopyFunctionNamesButton_Click), 0, 0);
        panel.Controls.Add(CreatePreviewHeader("Summaryコメント", _copySummaryCommentsButton, CopySummaryCommentsButton_Click), 1, 0);

        ConfigurePreviewTextBox(_functionNamesTextBox);
        ConfigurePreviewTextBox(_summaryCommentsTextBox);

        panel.Controls.Add(_functionNamesTextBox, 0, 1);
        panel.Controls.Add(_summaryCommentsTextBox, 1, 1);

        return panel;
    }

    private static Control CreatePreviewHeader(string labelText, Button copyButton, EventHandler clickHandler)
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            AutoSize = true,
            Margin = new Padding(0, 0, 8, 4)
        };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var label = new Label
        {
            Text = labelText,
            AutoSize = true,
            Anchor = AnchorStyles.Left
        };

        copyButton.Text = "コピー";
        copyButton.AutoSize = true;
        copyButton.Anchor = AnchorStyles.Right;
        copyButton.Click += clickHandler;

        panel.Controls.Add(label, 0, 0);
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
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false
        };

        var analyzeButton = new Button
        {
            Text = "解析",
            AutoSize = true
        };
        analyzeButton.Click += AnalyzeButton_Click;

        var exportButton = new Button
        {
            Text = "CSV出力",
            AutoSize = true
        };
        exportButton.Click += ExportButton_Click;

        panel.Controls.Add(analyzeButton);
        panel.Controls.Add(exportButton);

        return panel;
    }

    private void BrowseSourceButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "C# files (*.cs)|*.cs|All files (*.*)|*.*",
            Title = "解析対象の C# ファイルを選択"
        };

        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        _sourceFileTextBox.Text = dialog.FileName;
        if (string.IsNullOrWhiteSpace(_csvFileTextBox.Text))
        {
            _csvFileTextBox.Text = CreateDefaultCsvPath(dialog.FileName);
        }
    }

    private void BrowseCsvButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new SaveFileDialog
        {
            Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
            Title = "CSV出力先を選択",
            FileName = string.IsNullOrWhiteSpace(_csvFileTextBox.Text)
                ? "functions.csv"
                : Path.GetFileName(_csvFileTextBox.Text),
            InitialDirectory = GetInitialCsvDirectory()
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _csvFileTextBox.Text = dialog.FileName;
        }
    }

    private void AnalyzeButton_Click(object? sender, EventArgs e)
    {
        AnalyzeCurrentFile();
    }

    private void ExportButton_Click(object? sender, EventArgs e)
    {
        try
        {
            if (!AnalyzeCurrentFile())
            {
                return;
            }

            var csvPath = EnsureCsvPath();
            MethodSummaryCsvWriter.WriteToFile(csvPath, _currentResults);
            SetStatus($"{_currentResults.Count} 件のメソッドをCSV出力しました。");
        }
        catch (Exception ex)
        {
            ShowError("CSV出力に失敗しました。", ex);
        }
    }

    private void CopyFunctionNamesButton_Click(object? sender, EventArgs e)
    {
        CopyText(_functionNamesTextBox.Text, "関数名をコピーしました。");
    }

    private void CopySummaryCommentsButton_Click(object? sender, EventArgs e)
    {
        CopyText(_summaryCommentsTextBox.Text, "Summaryコメントをコピーしました。");
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

            var results = CSharpMethodSummaryExtractor.ExtractFromFile(sourcePath);
            UpdatePreview(results);

            if (string.IsNullOrWhiteSpace(_csvFileTextBox.Text))
            {
                _csvFileTextBox.Text = CreateDefaultCsvPath(sourcePath);
            }

            SetStatus($"{results.Count} 件のメソッドを解析しました。");
            return true;
        }
        catch (Exception ex)
        {
            ShowError("解析に失敗しました。", ex);
            return false;
        }
    }

    private void UpdatePreview(IReadOnlyList<MethodSummary> results)
    {
        _currentResults = results;
        _functionNamesTextBox.Text = string.Join(Environment.NewLine, results.Select(result => result.FunctionName));
        _summaryCommentsTextBox.Text = string.Join(Environment.NewLine, results.Select(result => result.SummaryComment));

        var hasResults = results.Count > 0;
        _copyFunctionNamesButton.Enabled = hasResults;
        _copySummaryCommentsButton.Enabled = hasResults;
    }

    private string EnsureCsvPath()
    {
        var csvPath = _csvFileTextBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(csvPath))
        {
            return csvPath;
        }

        csvPath = CreateDefaultCsvPath(_sourceFileTextBox.Text.Trim());
        _csvFileTextBox.Text = csvPath;
        return csvPath;
    }

    private string GetInitialCsvDirectory()
    {
        var csvPath = _csvFileTextBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(csvPath))
        {
            var csvDirectory = Path.GetDirectoryName(csvPath);
            if (!string.IsNullOrWhiteSpace(csvDirectory) && Directory.Exists(csvDirectory))
            {
                return csvDirectory;
            }
        }

        var sourcePath = _sourceFileTextBox.Text.Trim();
        var sourceDirectory = Path.GetDirectoryName(sourcePath);
        return !string.IsNullOrWhiteSpace(sourceDirectory) && Directory.Exists(sourceDirectory)
            ? sourceDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    }

    private static string CreateDefaultCsvPath(string sourcePath)
    {
        var directory = Path.GetDirectoryName(sourcePath);
        var fileName = Path.GetFileNameWithoutExtension(sourcePath);
        var csvFileName = string.IsNullOrWhiteSpace(fileName) ? "functions.csv" : $"{fileName}_functions.csv";

        return string.IsNullOrWhiteSpace(directory)
            ? csvFileName
            : Path.Combine(directory, csvFileName);
    }

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
        MessageBox.Show(
            this,
            $"{message}{Environment.NewLine}{exception.Message}",
            "C# Functions Analyzer",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }

    private void SetStatus(string message)
    {
        _statusLabel.Text = $"ステータス: {message}";
    }
}
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
