using FunctionsAnalyzer.Core;

namespace FunctionsAnalyzer.Gui;

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

    private MethodAnalysisResult _currentResult = new(
        Array.Empty<MethodSummary>(),
        Array.Empty<MethodDetail>());

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
        root.Controls.Add(CreatePreviewTabs(), 0, 1);
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

        var excelLabel = CreatePathLabel("Excel出力先");
        _excelFileTextBox.Dock = DockStyle.Top;
        _excelFileTextBox.Margin = new Padding(0, 0, 8, 8);

        var browseExcelButton = CreateBrowseButton();
        browseExcelButton.Click += BrowseExcelButton_Click;

        panel.Controls.Add(sourceLabel, 0, 0);
        panel.Controls.Add(_sourceFileTextBox, 1, 0);
        panel.Controls.Add(browseSourceButton, 2, 0);
        panel.Controls.Add(excelLabel, 0, 1);
        panel.Controls.Add(_excelFileTextBox, 1, 1);
        panel.Controls.Add(browseExcelButton, 2, 1);

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

    private Control CreatePreviewTabs()
    {
        var tabs = new TabControl
        {
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 8, 0, 8)
        };

        var summaryTab = new TabPage("Summary");
        summaryTab.Controls.Add(CreateColumnPreviewPanel(
            "関数名",
            _summaryFunctionNamesTextBox,
            _copySummaryFunctionNamesButton,
            CopySummaryFunctionNamesButton_Click,
            "Summaryコメント",
            _summaryCommentsTextBox,
            _copySummaryCommentsButton,
            CopySummaryCommentsButton_Click));

        var parametersTab = new TabPage("Parameters");
        parametersTab.Controls.Add(CreateThreeColumnPreviewPanel(
            "関数名",
            _parameterFunctionNamesTextBox,
            _copyParameterFunctionNamesButton,
            CopyParameterFunctionNamesButton_Click,
            "区分",
            _parameterCategoriesTextBox,
            _copyParameterCategoriesButton,
            CopyParameterCategoriesButton_Click,
            "詳細",
            _parameterDetailsTextBox,
            _copyParameterDetailsButton,
            CopyParameterDetailsButton_Click));

        tabs.TabPages.Add(summaryTab);
        tabs.TabPages.Add(parametersTab);
        return tabs;
    }

    private static Control CreateColumnPreviewPanel(
        string leftLabel,
        TextBox leftTextBox,
        Button leftCopyButton,
        EventHandler leftCopyHandler,
        string rightLabel,
        TextBox rightTextBox,
        Button rightCopyButton,
        EventHandler rightCopyHandler)
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 2,
            Padding = new Padding(8)
        };
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

    private static Control CreateThreeColumnPreviewPanel(
        string leftLabel,
        TextBox leftTextBox,
        Button leftCopyButton,
        EventHandler leftCopyHandler,
        string centerLabel,
        TextBox centerTextBox,
        Button centerCopyButton,
        EventHandler centerCopyHandler,
        string rightLabel,
        TextBox rightTextBox,
        Button rightCopyButton,
        EventHandler rightCopyHandler)
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 2,
            Padding = new Padding(8)
        };
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
            Text = "Excel出力",
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
            FileName = string.IsNullOrWhiteSpace(_excelFileTextBox.Text)
                ? "functions.xlsx"
                : Path.GetFileName(_excelFileTextBox.Text),
            InitialDirectory = GetInitialExcelDirectory()
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _excelFileTextBox.Text = dialog.FileName;
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

            var excelPath = EnsureExcelPath();
            MethodAnalysisExcelWriter.WriteToFile(excelPath, _currentResult);
            SetStatus($"{_currentResult.Summaries.Count} 件のメソッド、{_currentResult.Details.Count} 件のParameters行をExcel出力しました。");
        }
        catch (Exception ex)
        {
            ShowError("Excel出力に失敗しました。", ex);
        }
    }

    private void CopySummaryFunctionNamesButton_Click(object? sender, EventArgs e)
    {
        CopyText(_summaryFunctionNamesTextBox.Text, "Summaryシートの関数名をコピーしました。");
    }

    private void CopySummaryCommentsButton_Click(object? sender, EventArgs e)
    {
        CopyText(_summaryCommentsTextBox.Text, "Summaryコメントをコピーしました。");
    }

    private void CopyParameterFunctionNamesButton_Click(object? sender, EventArgs e)
    {
        CopyText(_parameterFunctionNamesTextBox.Text, "Parametersシートの関数名をコピーしました。");
    }

    private void CopyParameterCategoriesButton_Click(object? sender, EventArgs e)
    {
        CopyText(_parameterCategoriesTextBox.Text, "区分をコピーしました。");
    }

    private void CopyParameterDetailsButton_Click(object? sender, EventArgs e)
    {
        CopyText(_parameterDetailsTextBox.Text, "詳細をコピーしました。");
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

        var hasSummaries = result.Summaries.Count > 0;
        _copySummaryFunctionNamesButton.Enabled = hasSummaries;
        _copySummaryCommentsButton.Enabled = hasSummaries;

        var hasParameters = result.Details.Count > 0;
        _copyParameterFunctionNamesButton.Enabled = hasParameters;
        _copyParameterCategoriesButton.Enabled = hasParameters;
        _copyParameterDetailsButton.Enabled = hasParameters;
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

        var sourcePath = _sourceFileTextBox.Text.Trim();
        var sourceDirectory = Path.GetDirectoryName(sourcePath);
        return !string.IsNullOrWhiteSpace(sourceDirectory) && Directory.Exists(sourceDirectory)
            ? sourceDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    }

    private static string CreateDefaultExcelPath(string sourcePath)
    {
        var directory = Path.GetDirectoryName(sourcePath);
        var fileName = Path.GetFileNameWithoutExtension(sourcePath);
        var excelFileName = string.IsNullOrWhiteSpace(fileName) ? "functions.xlsx" : $"{fileName}_functions.xlsx";

        return string.IsNullOrWhiteSpace(directory)
            ? excelFileName
            : Path.Combine(directory, excelFileName);
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
