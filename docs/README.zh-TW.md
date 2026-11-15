<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>把常用的 Mac 小工具，收進選單列。</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <strong>繁體中文</strong> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>
</div>

Buckle 是原生 macOS 選單列工具，提供系統工具、依語言啟動瀏覽器，以及常用的 Finder 右鍵操作。在背景執行，不顯示 Dock 圖示。

**[下載 macOS 版本](https://github.com/SlippinDylan/Buckle/releases/latest)** · [開發指南](development.md)

> [!NOTE]
> 本文介紹目前原始碼中的功能。下載版本的具體變更與使用限制，請以對應版本的發行說明為準。

## 安裝與首次使用

需要 **macOS 15 或以上版本**，支援 Apple Silicon 與 Intel；CI 建置目標為 Universal 2。

1. 前往 [GitHub 最新版本](https://github.com/SlippinDylan/Buckle/releases/latest)，在 **Assets** 中下載 `Buckle-<版本>.dmg`。原始碼壓縮檔供開發使用，不是安裝檔。
2. 更新前，先在執行中的 Buckle 選單選擇「結束」，等待應用程式結束。開啟 DMG，將 `Buckle.app` 拖入「應用程式」，視需要取代舊版本。
3. 開啟 `/Applications/Buckle.app`。Buckle 會顯示於選單列，不顯示 Dock 圖示；保留一份已安裝的應用程式。
4. 透過選單列使用工具或開啟 Finder 右鍵功能。四項 Finder 功能首次使用時預設關閉，之後會保留選擇。
5. 在「設定 → 權限」中啟用 Finder 擴充功能或授予所需權限。狀態自動更新；綠色文字和勾選表示已授權或已啟用。

尚未關閉或完成過引導的使用者，會在正常啟動時看到一次使用引導；現有使用者也會看到，原設定保留。引導介紹選單列入口，可選擇 Finder 右鍵功能、按需授權，並設定登入時啟動和自動檢查更新。變更立即儲存，四項 Finder 功能在主動選擇前仍預設關閉。不授權也能繼續；關閉視窗後，重新啟動和升級都不會自動重開。需要時可從「設定 → 一般 → 顯示使用引導…」重新開啟。新使用者略過更新選擇時，自動檢查保持關閉；既有更新偏好保留，支援更新的版本仍可手動檢查。 最後在視窗內顯示設定完成頁，點擊「開始使用 Buckle」即可開啟選單。 權限獨立放在功能開關之前的一頁，可按需授權或直接繼續。

> [!IMPORTANT]
> 建置採用 ad-hoc 簽署，未經公證。下載的版本可能需要在系統設定中允許執行；更新後可能需要重新授權。

目前尚無法透過 Homebrew 安裝。Buckle Cask 在[共用 Tap](https://github.com/SlippinDylan/homebrew-tap)發佈之前，請使用 DMG。

## 功能一覽

<table>
  <tr>
    <td width="36%"><strong>系統工具，點擊即用</strong><br><br>手動開啟系統記憶體視窗、查看滑鼠重置的進度與結果，或重新啟動系統選單列。Finder 功能可分別開啟與關閉，勾選表示已開啟。</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="系統工具，點擊即用"></td>
  </tr>
  <tr>
    <td width="36%"><strong>直接在 Finder 操作</strong><br><br>將 AirDrop、在終端機中打開、拷貝路徑、搬移項目至此加入 Finder 快顯選單。在選取的檔案夾或目前目錄開啟終端機；多個路徑分行拷貝。</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="直接在 Finder 操作"></td>
  </tr>
  <tr>
    <td width="36%"><strong>依八種語言啟動瀏覽器</strong><br><br>先選本機瀏覽器，再選語言。每次開啟選單都會重新偵測支援的瀏覽器，由應用程式直接啟動，無須設定個人腳本。</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="依八種語言啟動瀏覽器"></td>
  </tr>
</table>

## 設定

在「設定 → 一般」管理登入時啟動及應用程式語言。預設跟隨系統，也可選擇英文、簡體中文、繁體中文、日文、韓文、德文、法文或西班牙文。變更語言後需重新啟動 Buckle。

在「設定 → 滑鼠重置」中新增、移除應用程式，並設定重新開啟前的等待時間：0–60 秒，預設 3 秒。變更自動儲存，重設期間暫時禁止編輯。

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="一般設定">
  <img src="images/readme/permissions-settings.png" width="340" alt="權限狀態">
</p>

截圖展示英文介面，可能與已安裝版本有所差異。選單會隨已安裝的瀏覽器、已啟用功能及已拷貝檔案變化。

## 使用前須知

- **記憶體視窗：**手動開啟 macOS LowMemoryPanel，記憶體正常時也可呼叫。視窗內建的「系統已用盡應用程式記憶體」不是 Buckle 的診斷。此功能使用私有系統除錯路徑；Buckle 會檢查目標記憶體警告視窗、還原暫時設定，無法確認視窗時回報失敗。相容性仍需逐個 macOS 版本實測。需要輔助使用與 System Events 自動化授權，不進行背景記憶體監測。
- **重置滑鼠：**在「設定 → 滑鼠重置」中管理應用程式名單，預設包含 Moom、MonitorControl、BetterMouse、iShot Pro。每次操作都會先結束名單中正在執行的應用程式，更新 macOS 共用偏好與系統權限服務，再統一還原這些應用程式。只重新開啟原本正在執行的應用程式。更新服務可能短暫影響其他應用程式，並要求管理者授權。已解除安裝的應用程式會略過，空清單也會重新整理服務。待復原清單會儲存；操作中斷後，下次啟動會詢問是否重新開啟這些應用程式，選擇「稍後」會保留記錄。
- **重新啟動系統選單列：**重新啟動目前使用者的 SystemUIServer，無須 sudo；不保證修復其他應用程式自行管理的圖示。
- **瀏覽器設定檔：**使用瀏覽器原有資料與已儲存的登入狀態，不建立獨立設定檔。多個使用者設定檔的選擇遵循瀏覽器自身行為。切換啟動語言前請先結束瀏覽器；瀏覽器已在執行時，Buckle 只顯示提示。日語啟動時按照原腳本為瀏覽器程序指定東京時區；其他語言保留系統時區。不修改 macOS 設定或 IP，也不保證網站語言或地區格式。時區行為僅在 Chrome Beta 上完成實測。
- **Finder 操作：**拷貝路徑由延伸功能直接寫入純文字，多條路徑分行顯示；其餘操作按需啟動 Buckle。搬移時先在 Finder 拷貝檔案，再於目標檔案夾或空白處按右鍵。Buckle 在 Finder 開啟目標檔案夾並觸發原生搬移，需要輔助使用權限以及控制 Finder、System Events 的自動化權限。進度、同名衝突和還原由 Finder 處理，操作結果以系統對話框為準；Buckle 不等待傳輸結束。選單位置由 Finder 決定。Buckle 自訂的 Finder 選單文字在重新啟動 Buckle 後跟隨應用程式語言，原生 AirDrop 名稱跟隨系統。 權限頁分別顯示 Finder 與 System Events 的自動化授權狀態。 為避免執行被重新指派的命令，存在自訂 Finder 或全域選單快速鍵時，Buckle 會停止自動搬移，請直接在 Finder 中操作。
- **AirDrop：**開啟系統分享介面，不等待傳輸結束。同一時間只允許一個 AirDrop 工作階段，其他 Finder 操作仍可使用。Buckle 不會為 AirDrop 延後結束，使用分享視窗時請保持 Buckle 執行。
- **更新：**已整合 Sparkle，手動檢查在「設定 → 關於」，自動檢查開關在「一般」。開發、CI 驗證與測試包停用更新，正式 Release 建置啟用更新。打包開關開啟時，main 的完整 CI 建置成功後自動打包、發佈尚未發行的版本，再同步簽署的更新清單與 Homebrew Cask；僅文件或輔助檔案變更不發佈。線上更新需要已發佈的安裝檔與簽署的更新清單。

## 從原始碼建置

<details>
<summary>展開原始碼建置與開發步驟</summary>

需要 Xcode 26 或以上版本、Node.js、Python 3。Debug 建置無須 Apple 開發者帳號。

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

建置完成後，依用途選擇以下其中一種方式。

### 安裝日常使用的版本

先在執行中 Buckle 的選單列選單選擇「結束」，等待應用程式結束。在 Finder 中，將 `build/DerivedData/Build/Products/Debug/` 下的整個 `Buckle.app` 移入 `/Applications`；若要取代現有版本，也先結束再取代。開啟 `/Applications/Buckle.app`，保留一份已安裝的應用程式。

### 開發時執行建置結果

先透過「結束」關閉現有 Buckle，等待應用程式結束，再執行下方指令。也可在結束現有應用程式後，開啟 `Buckle.xcodeproj`，執行 `Buckle` scheme 的 Debug 設定。Buckle 只允許一個執行個體：現有執行個體未結束時，新啟動的程序會結束。開發時使用正在測試的建置，不要同時開啟安裝目錄中的副本。

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

</details>

## 開發文件

[開發指南](development.md)包含架構、檢查、CI 打包、更新發佈、簽署與實機驗收說明。已發佈的安裝檔見 [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases)；[版本變更說明](../CHANGELOG.md)統一使用英文。
