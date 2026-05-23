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

リリース用の単一ファイルexeは自己完結形式で作成するため、利用者側に .NET 9 のインストールは不要です。

## 実行

```powershell
dotnet run --project .\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj
```

## リリースビルド

Windows x64向けの単一ファイルexeを作成する場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Publish-Release.ps1
```

または直接 `dotnet publish` を実行します。

```powershell
dotnet publish .\src\FunctionsAnalyzer.Gui\FunctionsAnalyzer.Gui.csproj -p:PublishProfile=win-x64-single-file
```

作成されるexe:

```text
src\FunctionsAnalyzer.Gui\bin\Release\net9.0-windows\win-x64\publish\FunctionsAnalyzer.exe
```

## 導入手順

利用者には `FunctionsAnalyzer.exe` を任意のフォルダに配置してもらい、ダブルクリックで起動します。自己完結形式の単一ファイルexeとして出力しているため、別途 .NET ランタイムを入れる必要はありません。

このリリースexeはWindows x64向けです。Windows ARM64など別Runtime向けに配布する場合は、publish profileを追加して対象Runtimeでpublishしてください。

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
