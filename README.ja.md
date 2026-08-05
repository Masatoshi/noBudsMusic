# noBudsMusic

Bluetoothイヤホンをタップしたときに、意図しない Music.app の起動を防ぐ常駐アプリです。

[English](README.md)

## 問題

macOS 26系では、何も再生していない状態でBluetoothイヤホンをタップすると、意図して
いない Music.app の起動が発生することがあります。

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = com.apple.bluetoothd>,
              and command requested a launch.
```

`com.apple.rcd` を無効化しても発生します。

## 仕組み

**このアプリは何も遮断しません。**

タップは `bluetoothd` から MediaRemote コマンドとして `mediaremoted` に届き、Now
Playing の参照先へルーティングされます。**参照先が存在しないとき、macOS はプレイヤーを
起動します。** これが Music.app の自動起動を招く要因です。

このアプリは Now Playing の参照先になるだけで、他には何も触れません。受け取ったコマンドは
すべて `.noSuchContent` で返します。

```text
再生中のアプリがある  → mediaremoted がそちらへ転送する（普通に操作できる）
何も再生していない    → コマンドはどこにも行かず、起動も要求されない
```

`.success`（消費する）でも起動は防げますが、コマンドがどこにも届かなくなり、一時停止中の
YouTube をイヤホンから再開できなくなります。**この戻り値ひとつが設計の要点**で、ここに
辿り着くまでに8つの案を実測で退けています。

その結果:

- **追加の権限は不要です。** アクセシビリティも入力監視もイベントタップも使いません
- **ポーリングをしません。** タイマーも監視ループもなく、コマンドが来たときだけ動きます
- **App Sandbox 内で完結します。**
- **メディアキーも音量キーも影響を受けません。** すべて転送するためです
- **デバイスごとの設定は持てません。** MediaRemote コマンドに送信元の識別情報がなく、
  すべて `com.apple.bluetoothd` として届くため原理的に不可能です

## インストール

macOS 14以降で動作する可能性がありますが、検証は macOS 26 / Apple Silicon のみです。

署名済みのリリースはまだないので、動かすにはビルドが必要です。Xcode 26系と
ビルドツール2つを使います。

```bash
brew install just xcodegen
just run
```

メニューバーに常駐します。ウィンドウも Dock アイコンもありません。

ダウンロード配布がない理由と、それが変わる条件は
[ADR 0002](docs/adr/0002-distribution-channel.md) にあります。

## 使い方

メニューバー項目だけで、ウィンドウはありません。

```text
Music.app の自動起動を防ぐ    [x]
メニューバーに表示            [x]
ログイン時に起動              [ ]
終了
```

メニューバーを非表示にしても常駐は続きます。戻すには Finder か Spotlight からアプリを
再度開くか、`just show` を実行してください。

このアプリが Now Playing の参照先になっていて、他に何も再生していない間、Control Center には
「Music.app の自動起動を防止中」と表示されます。Now Playing の参照先になる仕組みである
以上これは避けられず、その時点の参照先は実際にこのアプリなので表示としては正確です。
何かが再生されていれば、そちらが表示されます。

## 確認済みの動作

Redmi Buds 6 Lite と Pixel Buds A-Series、実機2台で確認しました。

- イヤホンをタップしても Music.app が起動しない
- YouTube と Amazon Music は、一度再生していればイヤホンから操作できる
- 再生中のアプリが参照先を取り返し、その間このアプリは関与しない
- キーボードのメディアキー（F8）と音量キー（F11/F12）は影響を受けない
- 音声出力、マイク、AirPlay は影響を受けない
- メニューバー非表示でも常駐し、再起動後も設定が残り、二重起動しない

## noTunes との関係

[noTunes](https://github.com/tombonez/noTunes) はもっと広い問題を解いています。
アイコンのクリック、リンク、イヤホンのタップ、**何がきっかけでも** Music.app を
開かせません。

このアプリが対処するのは原因のひとつだけです。`mediaremoted` がプレイヤーを起動する
条件を消すだけで、それ以外の経路には何もしません。

つまり代替関係ではありません。Music.app を一切開かせたくないなら noTunes のほうが
守備範囲がずっと広くなります。このアプリが解決するのは、Bluetoothイヤホンのタップ
だけです。

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [`docs/macos-notes.md`](docs/macos-notes.md) | 開発中に判明したmacOSの挙動。このプロジェクト外でも通用する |
| [`TECH_RESEARCH.md`](TECH_RESEARCH.md) | 実測ログ M1〜M27。否定的な結果を含む |
| [`docs/adr/`](docs/adr/) | 設計判断3件（遮断機構、配布形態、Now Playing方式） |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 構成と設計上の制約 |

**試して動かなかった手法も記録しています。** IOHIDManager、CGEventTap、
`kIOHIDOptionsTypeSeizeDevice`、DriverKit はすべて実測で否定されました。イヤホンの
タップは HID 経路に一切現れないためです。デバイス個別設定も、Now Playing 方式の他の
3形態も同様です。根拠は `TECH_RESEARCH.md` にあります。

## 開発

プロジェクト定義の正本は `project.yml` です。`noBudsMusic.xcodeproj` はそこから
生成されるため、リポジトリには含めていません。ビルド系のコマンドが毎回生成します。

```bash
just check   # lint, build, test
just logs    # アプリの動作ログ
just --list  # その他
```

ビルドはアドホック署名になります。開発中はそれで問題ありません。追加の権限を要求しない
ので、署名が変わっても失効するものがありません。

## ライセンス

MIT
