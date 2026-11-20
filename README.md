# PitaLoc(ピタロケ)

iPhone の位置情報を、地図で選んだ場所に**固定**するアプリです。
地図をタップ →「ここに固定」→ 終わったら「固定を解除」。お気に入り地点はワンタップで固定できます。

- 対象:iOS 17.4 以降(iOS 26 で使う前提)
- Mac 不要(**Windows PC は最初のセットアップでだけ使います**)
- iPhone を再起動すると必ず本当の位置に戻ります

> ⚠️ 位置ゲーム・出退勤/出席アプリ・マッチングアプリなどで使うと利用規約違反になることがあります。

---

## 全体の流れ

| いつ | どこで | やること |
|---|---|---|
| 1回だけ | GitHub(ブラウザ) | このフォルダをリポジトリに上げて、IPA を自動ビルド |
| 1回だけ | Windows | iTunes・iloader・idevice_pair を入れて、SideStore とペアリングファイルを用意 |
| 1回だけ | iPhone | PitaLoc を入れて、ペアリングファイルを読み込む |
| 毎回 | iPhone | LocalDevVPN を ON → PitaLoc で固定 |

2台の iPhone それぞれで「Windows」「iPhone」の手順が必要です(ペアリングファイルは端末ごとに違います)。**まず1台で動作を確認してから2台目へ。**

---

## ① GitHub で IPA を作る(Mac 不要)

1. GitHub に新しいリポジトリを作る(Private で OK)
2. このフォルダの中身をすべてアップロード(`.github` フォルダも含める)
   - ブラウザの「Add file → Upload files」でドラッグ&ドロップでも可
   - ※ `.github` のような「.」で始まるフォルダは Windows のエクスプローラーで隠れていることがあります。GitHub Desktop を使うと確実です
3. リポジトリの **Actions** タブ → **Build IPA** → **Run workflow**
4. 15〜30 分ほどで完了(初回は Rust のビルドで時間がかかります)
5. 完了した実行を開き、下の **Artifacts** から `PitaLoc-ipa` をダウンロード → 中の `PitaLoc.ipa` を取り出す

失敗したときは、Artifacts の `xcodebuild-log` かログ画面の赤いエラーを Claude に貼ってください。

## ② Windows の準備(1回だけ)

1. **iTunes** を Apple の公式サイトから入れる(**Microsoft Store 版ではないもの**)。iCloud も同様。
   iPhone を USB でつないで iTunes で認識されることを確認し、iPhone 側で「このコンピュータを信頼」。
2. **iPhone でデベロッパモードをオン**:設定 → プライバシーとセキュリティ → デベロッパモード → オン → 再起動
   (メニューに出てこない場合は、先に③の SideStore を入れると出てきます)
3. **iloader**(https://github.com/nab138/iloader/releases)を入れて起動
   - Apple ID でサインイン(普段の Apple ID でも可。気になる場合はサブの Apple ID)
   - 「Install SideStore」を実行 → SideStore と、そのためのペアリングファイルが自動で入ります
4. **idevice_pair**(https://github.com/jkcoxson/idevice_pair/releases の `idevice_pair--windows-x86_64.exe`)を起動
   - iPhone をロック解除してホーム画面にしておく
   - デバイスを選ぶ → **Remote pairing(RPPairing)** を選ぶ → Create → **Save to file…**
   - ※ Lockdown 形式ではなく **RPPairing** を選んでください
5. 保存したファイルを iPhone に送る(メールで自分宛て、iCloud Drive、Google Drive など)

## ③ iPhone の準備(1回だけ)

1. App Store から **LocalDevVPN**(無料)を入れて、一度「接続」する
2. 設定 → 一般 → VPNとデバイス管理 → 自分の Apple ID の開発者アプリを「信頼」
3. **SideStore** を開き、My Apps の「+」から `PitaLoc.ipa` を選んでインストール
4. **PitaLoc** を開くと準備画面が出るので、上から順に
   - ペアリングファイル:「ファイルを選ぶ」で②-5のファイルを選ぶ
   - VPN:「VPNを接続」
   - 位置情報:「許可する」→「Appの使用中は許可」
   - 「はじめる」

## ④ 普段の使い方

1. LocalDevVPN が ON になっているか確認(PitaLoc 画面に警告が出ていなければ OK)
2. 地図をタップ、または上の検索欄で場所・住所・`35.68, 139.76` のような座標を入力
3. 「**ここに固定**」
4. 終わったら「**固定を解除**」

- ★ ボタンからお気に入りを選ぶと、その場所にすぐ固定されます
- 固定中は PitaLoc をスワイプで終了しないでください(接続が切れると位置が戻ることがあります)
- 最初の固定は Wi‑Fi につながった状態で行うのがおすすめです

---

## 定期的なメンテナンス

- **無料 Apple ID の場合、アプリは7日で期限切れ**になります。SideStore を開いて「Refresh All」を押せば延長できます(LocalDevVPN が ON のとき、iPhone だけで可能)。
- **iOS をアップデートしたら**、②-4 の RPPairing ファイルを作り直して、PitaLoc の設定から読み込み直してください。

## うまくいかないとき

| 症状 | 対処 |
|---|---|
| 「iPhone内部への接続に失敗」 | LocalDevVPN を一度 OFF → ON。Wi‑Fi に接続。 |
| 「ペアリングファイルを読み込めません」 | idevice_pair で **RPPairing** 形式を作り直す |
| 「開発者サービスとのやり取りに失敗」 | デベロッパモードがオンか確認、iPhone を再起動 |
| 解除しても位置が戻らない | iPhone を再起動すると必ず戻ります |
| 他のアプリが位置をすぐ戻してしまう | そのアプリ側が独自に位置を検査している可能性があり、この方法では対処できません |

## 構成

```
PitaLoc/
  App/PitaLocApp.swift          起動・画面の切り替え
  Engine/LocationEngine.swift   idevice FFI で位置シミュレーションを呼ぶ部分
  Engine/SpoofController.swift  固定/解除・自動再接続・お気に入り
  Engine/PairingStore.swift     ペアリングファイルの保存
  Engine/VPNStatus.swift        LocalDevVPN の接続確認
  Engine/KeepAlive.swift        固定中にアプリが止まらないようにする
  Views/                        画面(準備・地図・検索・お気に入り・設定)
project.yml                     XcodeGen のプロジェクト定義
.github/workflows/build.yml     GitHub Actions(idevice のビルド → IPA 作成)
```

ライセンス表記は `THIRD_PARTY_LICENSES.md` を参照(idevice / Locus ともに MIT)。
