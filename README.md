# C# Functions Analyzer

WinFormsで操作するC#ソース解析ツールです。選択した `.cs` ファイル内の通常のメソッド定義をRoslyn ASTで解析し、メソッド名、XMLドキュメントコメントの `<summary>`、仮引数名をExcelブックに出力します。

## 機能

- 通常のメソッド定義のみを解析します。
- コメントアウトされたメソッド定義はRoslyn AST上でコメント扱いになるため、出力対象外です。
- `<summary>` がないメソッドはSummary列を空欄にします。
- 複数行のSummaryは空白を正規化し、半角スペース1つで一行にします。
- 画面上では `Summary` と `Parameters` をタブで分けて表示します。
- 各タブでは列ごとの複数行テキストとして表示し、それぞれコピーできます。
- Excelは2シート構成で出力します。
  - `Summary`: A列 `関数名`、B列 `Summaryコメント`
  - `Parameters`: A列 `関数名`、B列 `仮引数名`

## 必要環境

- .NET 9 SDK
- Windows

## 実行

```powershell
dotnet run --project .\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj
```

## テスト

```powershell
dotnet test .\FunctionsAnalyzer.sln
```

## Bootstrap

リポジトリをダウンロードできないユーザー向けに、`bootstrap\Bootstrap-FunctionsAnalyzer.ps1` を配布できます。このスクリプトはテストコードを含まない実行用ソースを展開し、既定では展開後にGUIを起動します。

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap\Bootstrap-FunctionsAnalyzer.ps1
```

展開だけ行う場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap\Bootstrap-FunctionsAnalyzer.ps1 -NoRun
```
