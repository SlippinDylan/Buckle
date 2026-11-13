<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>いつもの Mac ツールを、メニューバーに。</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <strong>日本語</strong> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>
</div>

Buckle は、システムツール、言語を指定したブラウザ起動、Finder の日常操作をまとめた macOS ネイティブのメニューバーアプリです。バックグラウンドで動作し、Dock にアイコンは表示しません。

> [!NOTE]
> Buckle 0.1.0 のインストーラはまだ公開されていません。下記の手順でソースからビルドしてください。

## 主な機能

<table>
  <tr>
    <td width="36%"><strong>メニューバーからシステムツールへ</strong><br><br>システムのメモリウインドウを開く、進行状況を確認しながらマウス関連ツールをリセットする、システムメニューバーを再起動する、といった操作ができます。Finder の各機能は個別に切り替えられ、チェックマークは有効を示します。</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="メニューバーからシステムツールへ"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Finder でそのまま操作</strong><br><br>AirDrop、ターミナルで開く、パスをコピー、ここに項目を移動を Finder のコンテキストメニューに追加します。選択したフォルダや現在のフォルダでターミナルを開き、複数のパスは改行で区切ってコピーできます。</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="Finder でそのまま操作"></td>
  </tr>
  <tr>
    <td width="36%"><strong>8 言語でブラウザを起動</strong><br><br>インストール済みのブラウザを選び、次に言語を選びます。メニューを開くたびに対応ブラウザを検出します。起動はアプリが直接行い、個人用スクリプトは不要です。</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="8 言語でブラウザを起動"></td>
  </tr>
</table>

### 設定

「設定 → 一般」でログイン時の起動とアプリの言語を設定します。既定では macOS に従います。英語、簡体字中国語、繁体字中国語、日本語、韓国語、ドイツ語、フランス語、スペイン語を選択できます。言語の変更後は Buckle を再起動してください。

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="一般設定">
  <img src="images/readme/permissions-settings.png" width="340" alt="権限の状態">
</p>

スクリーンショットは英語のインターフェイスです。メニューは、インストール済みブラウザ、有効な機能、コピーしたファイルによって変わります。

## インストールと初回設定

**macOS 15 以降**の Apple Silicon または Intel Mac が必要です。CI のビルド対象は Universal 2 です。

1. 下記のビルドとインストールの手順に従い、`/Applications` にインストールしたアプリを開きます。
2. メニューバーのアイコンからツールを使うか、Finder の機能を有効にします。4 つの Finder 機能は初回は無効で、以後は選択が保存されます。
3. 「設定 → アクセス権」で Finder 機能拡張を有効にするか、必要な権限を許可します。状態は自動更新され、緑の文字とチェックマークが許可済みまたは有効を示します。

ビルドは ad-hoc 署名で、公証されていません。ダウンロードしたビルドはシステム設定で実行の許可が必要な場合があります。更新後に権限の再許可が必要になる場合もあります。

## 使用前の注意

- **メモリウインドウ：** macOS LowMemoryPanel を手動で開きます。通常のメモリ使用量でも利用できます。内蔵のメモリ不足メッセージは Buckle の診断ではありません。非公開のシステムデバッグ経路を使い、対象のメモリ警告ウインドウを確認して一時設定を復元します。確認できなければエラーを報告します。互換性は macOS の各バージョンで実機確認が必要です。アクセシビリティと System Events のオートメーション権限が必要で、バックグラウンド監視は行いません。
- **マウスのリセット：**「設定 → マウスリセット」でアプリのリストを管理できます。初期リストは Moom、MonitorControl、BetterMouse、iShot Pro です。実行のたびに、リスト内で実行中のアプリを終了し、macOS の共有環境設定サービスとシステム権限サービスを更新してから、アプリを再度開きます。実行中だったアプリのみ再度開きます。サービスの更新は他のアプリに一時的に影響する場合があり、管理者認証が必要です。アンインストール済みのアプリはスキップし、リストが空でもサービスを更新します。復元待ちのリストは保存されます。操作が中断された場合、次回起動時にアプリを再度開くか確認し、「後で」を選ぶと記録を保持します。
- **システムメニューバーの再起動：** 現在のユーザーの SystemUIServer を sudo なしで再起動します。他のアプリが管理するアイコンの問題は直らない場合があります。
- **ブラウザのプロファイル：** ブラウザの既存データと保存済みのログイン状態を使い、別のプロファイルは作成しません。複数のプロファイルの選択はブラウザ自身の動作に従います。起動言語を切り替える前にブラウザを終了してください。すでに起動している場合、Buckle は通知のみを表示します。IP アドレスやタイムゾーンは変わらず、サイトの表示言語も保証しません。
- **Finder：** パスのコピーは機能拡張内で行い、他の操作は必要に応じて Buckle を起動します。移動する場合は Finder でファイルをコピーし、移動先フォルダまたはその背景を右クリックします。確認後に移動し、既存の項目は置き換えず、Finder の「取り消す」には対応しません。途中で失敗しても完了した移動は戻りません。再試行前に両方のフォルダを確認してください。メニュー位置は Finder が決めます。Buckle 独自の Finder メニュー項目は Buckle の再起動後にアプリの言語に従い、ネイティブの AirDrop 名はシステムに従います。
- **更新：** Sparkle を統合しています。手動確認は「設定 → このアプリについて」、自動確認は「一般」にあります。開発・CI テストビルドでは無効です。オンライン更新には、インストーラと署名済みフィードの公開が必要です。

## ソースからビルド

Xcode 26 以降、Node.js、Python 3 が必要です。Debug ビルドに Apple 開発者アカウントは不要です。

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

ビルド後は、用途に応じて以下のどちらかを選んでください。

### 日常利用向けにインストール

実行中の Buckle のメニューバーメニューで「終了」を選び、終了するまで待ちます。Finder で `build/DerivedData/Build/Products/Debug/` 内の `Buckle.app` 全体を `/Applications` に移動します。既存のアプリを置き換える場合も、先に終了してください。`/Applications/Buckle.app` を開き、インストールするコピーは 1 つにしてください。

### 開発用にビルドを実行

実行中の Buckle を「終了」で閉じ、終了を待ってから下記のコマンドを実行してください。または、既存のアプリを終了してから `Buckle.xcodeproj` を開き、`Buckle` scheme を Debug で実行します。Buckle は同時に 1 つだけ実行できます。別のコピーが実行中の場合、新しいプロセスは終了します。開発中はテスト対象のビルドを使い、インストール済みのコピーを同時に開かないでください。

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

## 開発ドキュメント

ビルド検証、CI、パッケージ、更新の公開、署名、実機での検証項目は[開発ガイド](development.md)（簡体字中国語）を参照してください。今後の公開インストーラは [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases) に掲載されます。
