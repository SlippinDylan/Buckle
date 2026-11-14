<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>把常用的 Mac 小工具，收進選單列。</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <strong>繁體中文</strong> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>
</div>

Buckle 是原生 macOS 選單列工具，提供系統工具、依語言啟動瀏覽器，以及常用的 Finder 右鍵操作。在背景執行，不顯示 Dock 圖示。

> [!NOTE]
> Buckle 0.1.1 尚無公開安裝檔，請依下方說明從原始碼建置。

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

### 設定

在「設定 → 一般」管理登入時啟動及應用程式語言。預設跟隨系統，也可選擇英文、簡體中文、繁體中文、日文、韓文、德文、法文或西班牙文。變更語言後需重新啟動 Buckle。

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="一般設定">
  <img src="images/readme/permissions-settings.png" width="340" alt="權限狀態">
</p>

截圖統一顯示英文介面。選單會隨已安裝的瀏覽器、已啟用的功能及已拷貝的檔案變化。

## 安裝與首次使用

需要 **macOS 15 或以上版本**，支援 Apple Silicon 與 Intel；CI 建置目標為 Universal 2。

1. 依下方原始碼建置與安裝步驟操作，再從 `/Applications` 開啟已安裝的應用程式。
2. 點擊選單列圖示使用工具或開啟 Finder 功能。四項 Finder 功能首次使用時預設關閉，之後會保留選擇。
3. 開啟「設定 → 權限」啟用 Finder 延伸功能或授予所需權限。狀態自動更新；綠色文字和勾選表示已授權或已啟用。

建置採用 ad-hoc 簽署，未經公證。下載的版本可能需要在系統設定中允許執行；更新後可能需要重新授權。

## 使用前須知

- **記憶體視窗：**手動開啟 macOS LowMemoryPanel，記憶體正常時也可呼叫。視窗內建的「系統已用盡應用程式記憶體」不是 Buckle 的診斷。此功能使用私有系統除錯路徑；Buckle 會檢查目標記憶體警告視窗、還原暫時設定，無法確認視窗時回報失敗。相容性仍需逐個 macOS 版本實測。需要輔助使用與 System Events 自動化授權，不進行背景記憶體監測。
- **重置滑鼠：**在「設定 → 滑鼠重置」中管理應用程式名單，預設包含 Moom、MonitorControl、BetterMouse、iShot Pro。每次操作都會先結束名單中正在執行的應用程式，更新 macOS 共用偏好與系統權限服務，再統一還原這些應用程式。只重新開啟原本正在執行的應用程式。更新服務可能短暫影響其他應用程式，並要求管理者授權。已解除安裝的應用程式會略過，空清單也會重新整理服務。待復原清單會儲存；操作中斷後，下次啟動會詢問是否重新開啟這些應用程式，選擇「稍後」會保留記錄。
- **重新啟動系統選單列：**重新啟動目前使用者的 SystemUIServer，無須 sudo；不保證修復其他應用程式自行管理的圖示。
- **瀏覽器設定檔：**使用瀏覽器原有資料與已儲存的登入狀態，不建立獨立設定檔。多個使用者設定檔的選擇遵循瀏覽器自身行為。切換啟動語言前請先結束瀏覽器；瀏覽器已在執行時，Buckle 只顯示提示。此功能不改變 IP 或時區，也不保證網站使用所選語言。
- **Finder 操作：**拷貝路徑由延伸功能直接完成，其餘操作按需啟動 Buckle。移動時先在 Finder 拷貝檔案，再於目標檔案夾或空白處按右鍵。移動需確認，不取代現有項目，也不整合 Finder 的還原操作；中途失敗時已完成的移動會保留，請檢查來源與目標後再試。選單位置由 Finder 決定。Buckle 自訂的 Finder 選單文字在重新啟動 Buckle 後跟隨應用程式語言，原生 AirDrop 名稱跟隨系統。
- **更新：**已整合 Sparkle，手動檢查在「設定 → 關於」，自動檢查開關在「一般」。開發與 PR 檢查版本停用更新，main 的 CI 發布版本啟用更新；線上更新需先發布安裝檔及簽署的更新清單。

## 從原始碼建置

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

## 開發文件

[開發指南](development.md)（簡體中文）包含建置檢查、CI、打包、更新發布、簽署與實機驗收清單。未來公開安裝檔將發布至 [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases)。
