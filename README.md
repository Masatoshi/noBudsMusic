# noBudsMusic

macOSでBluetoothイヤホン／ヘッドセットのタップ操作が `Play`
コマンドとして処理され、再生対象がない場合にApple
Musicが自動起動する挙動を防ぐ常駐アプリ。

## 背景

macOS
26系では、Bluetoothイヤホンのタップ操作により次の経路でMusic.appが起動することがある。

``` text
Bluetooth headset
  → bluetoothd
  → mediaremoted
  → LaunchServices
  → Music.app
```

確認済みログ例:

``` text
SenderBundleIdentifier = <com.apple.bluetoothd>
command = Play
Destination app com.apple.Music not available for command
command requested a launch
```

`com.apple.rcd` を無効化しても発生する。

noTunesのような「起動後にMusicを終了する」方式ではなく、Play/Pause入力をMusic起動前に遮断する。

## 対象環境

- macOS 26.x
- Apple Silicon
- Swift / SwiftUI / Xcodeプロジェクト

動作確認対象:

- Redmi Buds 6 Lite
- Pixel Buds A-Series

## アプリ形態

Swift製のバックグラウンド常駐アプリ。メニューバー項目の表示は任意設定で、非表示にしてもバックグラウンド常駐を継続する。

## 動作仕様

グローバルStatusと、デバイスごとの遮断設定の2段階で判定する。

``` text
Status OFF
  → すべてのPlay/Pauseをそのまま通す

Status ON
  → 遮断対象として登録されたBluetoothデバイス由来のPlay/Pauseだけを遮断
  → 未登録デバイス、キーボード、USBデバイスなどは変更しない
```

Bluetooth以外のデバイスは遮断対象に選択できない。送信元を確実に判定できない場合は、誤遮断を避けてイベントを通す。

## デバイス識別

デバイス名だけを永続識別子に使わない。IOHIDから取得できる範囲でTransport、Product
Name、Manufacturer、Vendor ID、Product ID、Serial Number、Location
ID、Primary Usage Page、Primary Usageを収集し、次の優先順位で安定識別子を生成する。

1. Serial Numberを含む識別子
2. Vendor ID + Product ID + Product Name
3. その他のIOHIDプロパティを加えたフォールバック

Location IDは再接続のたびに変わるため識別子には含めない。2と3では同一モデルを複数所持している場合に区別できないので、その可能性をログとDevices画面に明示する。

## メニューバー

``` text
noBudsMusic

Status                  ON/OFF
Devices...
Show in Menu Bar        ON/OFF
Launch at Login         ON/OFF
Diagnostics...
Quit
```

メニューバーを非表示にしても常駐は続く。復帰する手段は次の3つ。

- FinderまたはSpotlightからアプリを再度起動する（二重起動はしない）
- `open nobudsmusic://settings`
- `just settings`

## 成功条件

実機で以下を満たすこと。

1. Status ONかつPixel Buds A-Seriesの個別設定ONで、タップしてもMusic.appが起動しない
2. Status ONかつRedmi Buds 6 Liteの個別設定ONで、タップしてもMusic.appが起動しない
3. 個別設定OFFでは通常どおりPlay/Pauseが動作する
4. グローバルStatus OFFではすべて通常どおり動作する
5. キーボードのPlay/Pauseは影響を受けない
6. USBデバイスのPlay/Pauseは影響を受けない
7. 音量キーは影響を受けない
8. イヤホンの音声出力とマイクは影響を受けない
9. AirPlayは影響を受けない
10. Control CenterのNow Playingを不要に壊さない
11. メニューバー非表示でも常駐する
12. アプリ再起動後も設定が保持される
13. macOS再起動後もログイン時起動する
14. 同じアプリが二重起動しない

## 現在の実装状況

**Phase 2（観測）完了。遮断の見込みは立っていない。**

計測の結果、**Bluetoothイヤホンのタップはユーザー空間で遮断できない**ことが判明した。
タップはHIDデバイスもHIDレポートも `NX_SYSDEFINED` イベントも生成せず、`bluetoothd`
が直接MediaRemoteコマンドを発行している。

```text
bluetoothd  --(MediaRemote command: Play)-->  mediaremoted  -->  Now Playing宛先
```

このため当初の候補（IOHIDManager / CGEventTap / IOHID seize / DriverKit）は
**4つとも成立しない**。詳細は `TECH_RESEARCH.md` のM11、判断は
`docs/adr/0001-event-interception-approach.md`（Rejected）。

残る公開APIの案は「遮断」ではなく「宛先を用意する」方向だが、
**デバイス個別設定が原理的に不可能**になり、キーボードやControl Centerの操作まで
吸ってしまうリスクがある。仕様レベルの判断が必要な段階。

動作するもの: 判定ロジック、デバイス識別、設定保存、Devices／Diagnostics画面、
HID観測（`HIDDeviceMonitor`）、常駐と復帰導線。

## 開発

必要なもの: Xcode 26系、[just](https://github.com/casey/just)、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

`project.yml` がプロジェクト定義のSSOTで、`noBudsMusic.xcodeproj`
は生成物（コミットしない）。

``` bash
just check
```

lint、build、testを実行する。

``` bash
just run
```

ビルドして起動する。

初回起動時にInput MonitoringとAccessibilityの権限を求められる。権限の状態はDiagnostics画面でも確認できる。

### 署名と権限の維持

TCCは権限を**署名IDに紐づける**。既定のアドホック署名はリビルドのたびに変わるため、
そのままだと毎回権限が失効し、計測のたびに再許可が必要になる。

実際の証明書で署名すればリビルドしても維持される。`.env`（gitignore対象）に設定する。

``` bash
security find-identity -v -p codesigning
```

``` bash
# .env
NOBUDS_CODE_SIGN_IDENTITY="<証明書のSHA-1>"
NOBUDS_DEVELOPMENT_TEAM="<チームID>"
```

未設定ならアドホック署名にフォールバックする（追加設定なしでビルドは通る）。
現在の設定は `just signing` で確認できる。

署名IDを変更したときは一度だけ再許可が必要。

``` bash
just reset-permissions
just run
```

観測ログ:

``` bash
just logs
```

Music.app起動そのものの追跡（`bluetoothd` / `mediaremoted`）:

``` bash
just logs-system
```

その他のレシピは `just --list` を参照。

## 配布

**先に実装、配布形態は後で決める。**

App Storeはサンドボックス必須で、想定機構（`CGEventTap` + `IOHIDManager`）が
サンドボックス下で成立するかは未検証。ただしそもそも遮断できるかが未計測なので、
存在するか分からない機構に合わせて配布形態を先に決めることはしない。
実装が動いてから評価し、App Storeが不可ならGitHubでOSSとして公開する。

実装側にサンドボックス由来の制約は一切かけない。`docs/adr/0002-distribution-channel.md` を参照。

バンドルID: `jp.kaizudenki.noBudsMusic`

## ライセンス

MIT
