# noBudsMusic

Bluetoothイヤホンをタップしたときに Music.app が勝手に起動するのを防ぐ常駐アプリ。

[English](README.md)

## 問題

macOS 26系では、何も再生していない状態でBluetoothイヤホンをタップすると、頼んでも
いない Music.app が起動することがある。

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = com.apple.bluetoothd>,
              and command requested a launch.
```

`com.apple.rcd` を無効化しても発生する。

## 仕組み

**このアプリは何も遮断しない。**

タップは `bluetoothd` から MediaRemote コマンドとして `mediaremoted` に届き、Now
Playing の宛先へルーティングされる。**宛先が空のとき、macOS はプレイヤーを起動する。**
この空席がバグの正体。

そこでアプリが席を占有し、あとは道を空ける。受け取ったコマンドはすべて
`.noSuchContent` で返す。

```text
再生中のアプリがある  → mediaremoted がそちらへ転送する（普通に操作できる）
何も再生していない    → コマンドはどこにも行かず、起動も要求されない
```

`.success`（消費する）でも起動は防げるが、コマンドがどこにも届かなくなり、一時停止中の
YouTube をイヤホンから再開できなくなる。**この戻り値ひとつが設計の全部**で、ここに
辿り着くまでに8つの案を計測で潰した。

その結果:

- **権限が一切不要。** アクセシビリティも入力監視もイベントタップも使わない
- **ポーリングなし。** タイマーも監視ループも無く、コマンドが来たときだけ起きる
- **App Sandbox 内で動作**し、何も劣化しない
- **メディアキーも音量キーも影響を受けない。** すべて転送するため
- **デバイスごとの設定は持てない。** MediaRemote コマンドに送信元の識別情報が無く、
  すべて `com.apple.bluetoothd` として届くため原理的に不可能

## インストール

macOS 14以降で動くはずだが、検証は macOS 26 / Apple Silicon のみ。

```bash
just run
```

必要なもの: Xcode 26系、[just](https://github.com/casey/just)、
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

署名済みのリリースはまだ無いので、動かすにはビルドするしかない。理由と、それが
変わる条件は [ADR 0002](docs/adr/0002-distribution-channel.md) にある。

## 使い方

メニューバー項目だけ。ウィンドウは持たない。

```text
Music.app の自動起動を防ぐ    [x]
メニューバーに表示            [x]
ログイン時に起動              [ ]
終了
```

メニューバーを非表示にしても常駐は続く。戻すには Finder か Spotlight からアプリを
再度開くか、`just show` を実行する。

席を占有していて他に何も再生していない間、Control Center には
「Music.app の自動起動を防止中」と表示される。Now Playing の席を占有する機構である
以上これは避けられず、その時点の宛先は実際にこのアプリなので表示としては正確。何かが
再生されていれば、そちらが表示される。

## 確認済みの動作

Redmi Buds 6 Lite と Pixel Buds A-Series、実機2台で確認。

- イヤホンをタップしても Music.app が起動しない
- YouTube と Amazon Music は、一度再生していればイヤホンから操作できる
- 再生中のアプリが宛先を取り返し、その間このアプリは関与しない
- キーボードのメディアキー（F8）と音量キー（F11/F12）は影響を受けない
- 音声出力、マイク、AirPlay は影響を受けない
- メニューバー非表示でも常駐し、再起動後も設定が残り、二重起動しない

## noTunes との関係

[noTunes](https://github.com/tombonez/noTunes) はもっと広い問題を解いている。
アイコンのクリック、リンク、イヤホンのタップ、**何が引き金でも** Music.app を
開かせない。

このアプリが対処するのは原因のひとつだけ。`mediaremoted` がプレイヤーを起動する
条件を消すだけで、それ以外の経路には何もしない。

つまり代替関係ではない。Music.app を一切開かせたくないなら noTunes のほうが
守備範囲がずっと広い。イヤホンのタップのときだけ困っているなら、こちらは権限も
常駐コストも要らない狭い解になる。

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [`docs/macos-notes.md`](docs/macos-notes.md) | 開発中に判明したmacOSの挙動。このプロジェクト外でも通用する |
| [`TECH_RESEARCH.md`](TECH_RESEARCH.md) | 計測ログ M1〜M27。否定的な結果を含む |
| [`docs/adr/`](docs/adr/) | 設計判断3件（遮断機構、配布形態、Now Playing方式） |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 構成と設計上の制約 |

**面白いのは動かなかった方**かもしれない。IOHIDManager、CGEventTap、
`kIOHIDOptionsTypeSeizeDevice`、DriverKit はすべて計測で否定された — イヤホンのタップは
HID経路に一切現れないため。デバイス個別設定も、Now Playing 方式の他の3形態も同様。
根拠は `TECH_RESEARCH.md` に全部ある。

## 開発

`project.yml` がSSOTで、`noBudsMusic.xcodeproj` は生成物（コミットしない）。

```bash
just check   # lint, build, test
just logs    # アプリの動作ログ
just --list  # その他
```

アドホックではなく実際の証明書で署名するには `.env`（gitignore対象）に設定する。

```bash
NOBUDS_CODE_SIGN_IDENTITY="<証明書のSHA-1>"   # security find-identity -v -p codesigning
NOBUDS_DEVELOPMENT_TEAM="<チームID>"
```

未設定ならアドホック署名になるが、それで問題ない。**権限を使わないので、署名が変わっても
失効するTCC権限が存在しない。**

## ライセンス

MIT
