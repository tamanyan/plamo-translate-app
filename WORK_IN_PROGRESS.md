# 実装・検証状況

2026-11-08、停止時の作業メモから実装を再開。ネイティブアプリの実装、実モデル検証、配布用.appの作成とPR作成を完了。

PR: https://github.com/tamanyan/plamo-translate-app/pull/1

## 目的

macOS向けのPLaMo翻訳アプリ。DeepLに近い左右の翻訳ペインと、ChatGPT風のモダンなUI。日本語UIを基本に英語へ切り替え可能。参考の設定画面にある表示言語、終了時動作、ログイン時起動、選択テキストの翻訳ショートカットを実装。モデル管理は `tanakh/plamo-translate-desktop` を参考にする。完成後に `tamanyan/plamo-translate-app` へPRを作成する。

Swift採用・必要な依存取得・PR作成は許可済み。サブエージェントは利用していない。

## 完了した作業

1. Swift Packageをレビュー・ビルドし、`@main`、SwiftUI画面、ネイティブメニューを追加。
2. モデル14種の選択・ライセンス全文表示と同意・取得進捗・停止・再開・削除・サイズとSHA-256検証を実装。
3. 同梱llama-serverを127.0.0.1の一時ポートで起動。起動ごとのランダム認証トークン、ヘルスチェック、MTL0への全層オフロード、停止処理を実装。
4. 左右の翻訳ペイン、履歴の検索・お気に入り・削除、日英UI、外観、設定、ログイン項目連携、バックグラウンド動作、⌘Cを2回押す翻訳ショートカットを実装。
5. ユーザー入力のBindingからのみ自動翻訳を起動。履歴の復元・言語の交換は自動翻訳を誤発火しない。古いリクエストの結果を排除。
6. 実0.8Bモデルの取得・SHA検証・Metal翻訳を実施。実ウィンドウのスクリーンショットを確認。キャンセル、Range異常、SSEの異常終了などを含む15テストが成功。
7. 配布用.app作成・アイコン生成スクリプト、README、第三者帰属表示、macOS CIを追加。Releaseビルドと署名検証が成功。開発ディレクトリ外から同梱エンジンで翻訳できることを確認。
8. 空のoriginへ最小のmainベースコミット（.gitignoreのみ）を作成。`feat/native-plamo-translate`ブランチに実装をまとめ、PR #1を作成。マージはしていない。

## 実行方法

```sh
./scripts/fetch-engine.sh
swift run PlamoTranslate
```

配布用は `./scripts/build-app.sh`。生成物: `dist/PLaMo Translate.app`。

通常テスト: `./scripts/test.sh`。統合テストの実行方法と確認結果は [docs/VERIFICATION.md](docs/VERIFICATION.md)、利用方法は [README.md](README.md)。

## 環境依存の確認事項

- 実機検証はApple Silicon / macOS 26。Intel・macOS 15の実機では未検証。
- ログイン項目登録とグローバルショートカットは、OSの許可とユーザー操作が必要。自動検証ではユーザーのOS設定を変更していない。
- Apple翻訳はmacOSの対応言語・言語データに依存する。
- 配布アプリはローカルのアドホック署名。Developer ID署名・公証による一般配布は対象外。

## 参照元

- https://github.com/tanakh/plamo-translate-desktop
- https://github.com/ggml-org/llama.cpp/releases/tag/b12110
- https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF

モデルはPLaMo Community License。アプリ内に全文を同梱し、ダウンロード前に同意を取得する。カタログ・PFML形式の帰属とllama.cppのMITライセンスは [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) に記載。
