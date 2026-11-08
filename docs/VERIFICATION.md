# 検証結果

2026-11-08、Apple M4 Pro / 48 GB、macOS 26、Swift 6.3.3、Command Line Tools環境で実施。

## 自動テスト

`PLAMO_METAL_TEST=1 PLAMO_ACCEPT_MODEL_LICENSE=1 ./scripts/test.sh` — **15件成功**。

- PFML3のコンテキスト・用語集・日本語文体と予約トークン拒否
- リモートURL・認証情報付きURLの拒否
- Content-Rangeの開始位置・終端・総サイズ検証
- Range再開したモデル全体のハッシュ照合
- サーバーがRangeを無視した場合の再取得
- 不正なRange応答で途中ファイルを保持
- SHA-256不一致でモデルを採用せず、途中ファイルを破棄
- 不完全な転送とキャンセル時の途中ファイル保持
- キャンセル済みリクエストの完了・エラーの排除、履歴復元・言語交換
- ローカル保存の再読み込み、壊れたJSONへのフォールバック
- SSEの連結、認証ヘッダー、途中切断・出力上限・コンテキスト上限の拒否
- 実モデルの取得・Metal推論・認証なしアクセスの401応答
- 同時にモデル読み込みを待つ翻訳の一方をキャンセルしても、もう一方が読み込みを完了

統合テストは通常実行ではスキップされます。今回の検証では明示的に有効化し、実行しています。

## 実モデル

`plamo-3-translate-0.8b-Q4_K_M.gguf`（573,123,200 bytes）をHugging Faceの固定revisionから取得。SHA-256:

```
923b2f28a9856de1b8b3b610a7e59ded0b14d007466fd5dd526e6a9ecaadafdd
```

原文「今日はとても良い天気です。」→ **The weather is very nice today.**

llama.cppログで`using device MTL0 (Apple M4 Pro)`および`offloaded 17/17 layers to GPU`を確認。終了後にエンジンのプロセスが残っていないことも確認。

## 配布アプリ

`./scripts/build-app.sh`のReleaseビルドと`codesign --verify --deep --strict`が成功。約33 MBの`.app`にエンジン・dylib・ライセンス・UIリソースを同梱。

`/tmp`を作業ディレクトリとして、配布アプリからUIスモークテストを実行し成功。同梱のllama-serverも`/tmp`から起動して上記の文章を翻訳し、全層のGPUオフロードを確認。開発ディレクトリを作業ディレクトリにする必要はありません。

配布バイナリはローカルのアドホック署名です。外部配布用のDeveloper ID署名・公証は含みません。Intel・macOS 15の実機では未検証です。

## UI

実ウィンドウのNSViewをPNGに保存し、日本語ライト・英語ダークの翻訳画面と、一般設定・モデル一覧・About画面を確認。スモークテスト内でバックグラウンド終了設定によりウィンドウが非表示になることも確認。

画像は固定サンプルを表示しています。通常のユーザー設定・履歴は使っていません。

- [日本語の翻訳画面](translation-ja.png)
- [英語・ダークモード](translation-en-dark.png)
- [一般設定](settings-general.png)
- [モデル管理](settings-models.png)

ログイン項目への登録、他アプリからのグローバルショートカット、Apple翻訳の言語データ取得は、ユーザーのOS設定・許可・ログイン操作に依存します。この検証ではユーザー環境のログイン項目やアクセシビリティ許可を変更していません。これらのOS連携は実装済みですが、対話を伴う実機操作は自動検証の対象外です。
