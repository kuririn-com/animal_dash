import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const privacyPolicyText = '''Animal Dash プライバシーポリシー
更新日：2026年10月8日

Animal Dashは、ゲームの最高距離と最高コイン数を端末内に保存します。アカウントの作成は不要で、運営者がこれらの記録をサーバーに送信する機能はありません。

広告の配信にはGoogle AdMobを利用します。広告SDKは、広告配信、不正利用防止、広告効果の測定等のため、端末やアプリの識別情報、IPアドレスから推定されるおおよその位置、広告の表示・操作情報、診断・パフォーマンス情報等を取り扱う場合があります。広告の詳細はGoogleのプライバシーポリシー（https://policies.google.com/privacy）をご確認ください。

本アプリはパーソナライズされていない広告をリクエストし、Googleの同意判定に従って広告を読み込みます。同意が必要な地域等ではGoogleの画面が表示される場合があります。同意の変更が必要な場合は、アプリ内の「プライバシー」から「広告の設定」を開けます。

広告削除はAppleのアプリ内課金で購入できる買い切り商品です。購入・復元・返金に伴う利用権の確認にはStoreKitを利用し、Appleが確認した購入情報を端末で読み取ります。支払情報はAppleが管理し、運営者はカード番号等を取得しません。広告削除の購入済み状態を確認できた場合は、バナー広告・全画面広告を表示せず、広告のリクエストを停止します。

カメラ、マイク、連絡先、写真ライブラリ、正確な位置情報を利用する機能はありません。端末内のゲーム記録はアプリの削除により削除されます。

Instagramのお問い合わせでいただいた連絡情報や内容は、お問い合わせへの対応に利用します。個人情報を含める場合は、必要な範囲にとどめてください。

運営・お問い合わせ（Instagram）：https://www.instagram.com/r.ever_official/
本ポリシーは、機能や利用サービスの変更等に応じて更新する場合があります。''';

Future<void> showGamePrivacy(BuildContext context, {
  required bool optionsRequired,
  required VoidCallback onConsentChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('プライバシー'),
      content: const SizedBox(
        width: 520,
        child: SingleChildScrollView(child: SelectableText(privacyPolicyText)),
      ),
      actions: [
        if (optionsRequired)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ConsentForm.showPrivacyOptionsForm((error) {
                if (error != null) debugPrint('Privacy options: $error');
                onConsentChanged();
              });
            },
            child: const Text('広告の設定'),
          ),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('閉じる')),
      ],
    ),
  );
}
