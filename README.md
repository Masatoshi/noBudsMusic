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

**このアプリは何も遮断しない。** Now Playing の宛先を占有するだけ。

`mediaremoted` は Play コマンドを Now Playing 宛先へ送り、**宛先が空のときに
プレイヤーを起動する**。これが Music.app 自動起動の直接原因なので、席を埋めて
おけば起動する理由が消える。

受け取ったコマンドは `.noSuchContent` で返す。これにより:

``` text
再生中のアプリがある  → mediaremoted がそちらへ転送する（操作は普通に効く）
どこにも送り先がない  → 何も起きない。起動も要求されない
```

`.success`（消費する）でも起動は防げるが、コマンドがどこにも届かなくなり、
再生中のアプリを操作できなくなる。この戻り値ひとつが設計の要。

**デバイスごとの設定は持たない。** MediaRemoteコマンドには送信元デバイスの
識別情報が無く、すべて `com.apple.bluetoothd` として届くため、機器を区別する
ことが原理的にできない。

**権限を一切必要としない。** アクセシビリティも入力監視も不要。

**App Sandbox 内で動作する。** サンドボックス下でも機構は一切劣化しない（M26）。

**常駐コストはほぼゼロ。** タイマーも監視ループも無く、コマンドが来たときだけ
起きる。

## メニューバー

``` text
noBudsMusic

Status                  ON/OFF
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

1. Status ONでイヤホンをタップしてもMusic.appが起動しない
2. Status OFFでは通常どおり動作する
3. キーボードのPlay / Pauseは影響を受けない
4. USBデバイスのPlay / Pauseは影響を受けない
5. 音量キーは影響を受けない
6. イヤホンの音声出力とマイクは影響を受けない
7. AirPlayは影響を受けない
8. 再生中のアプリの操作を妨げない
9. Control CenterのNow Playingを不要に壊さない
   - 再生中はそのアプリが表示される。何も再生していないときは本アプリが
     「Music.app の自動起動を防止中」と表示される。Now Playing の席を占有する
     機構である以上これは避けられず、実際その時点の宛先は本アプリなので表示は
     正確。タイトルを外してもアプリ名にフォールバックするだけだった
10. メニューバー非表示でも常駐する
11. アプリ再起動後も設定が保持される
12. macOS再起動後もログイン時起動する
13. 同じアプリが二重起動しない

## 現在の実装状況

**動作する。** 実機（Pixel Buds A-Series）で確認済み。

- イヤホンをタップしてもMusic.appが起動しない
- YouTube / Amazon Music は、一度再生していればイヤホンから操作できる
- 再生中のアプリが宛先を取り返し、その間このアプリは関与しない

そこに至るまでに4つの案を計測で潰している。詳細は `TECH_RESEARCH.md`（M1〜M24）、
判断は `docs/adr/`。当初の候補（IOHIDManager / CGEventTap / IOHID seize /
DriverKit）は**すべて成立しない** — イヤホンのタップはHID経路に一切現れず、
`bluetoothd` が直接MediaRemoteコマンドを発行しているため。

未検証: キーボードの専用メディアキー（転送されるはずだが未確認）。

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
