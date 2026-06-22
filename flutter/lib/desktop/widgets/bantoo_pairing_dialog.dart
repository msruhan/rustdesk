import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<bool> isBantooPaired() async {
  final token = await bind.mainGetLocalOption(key: 'bantoo-device-token');
  return token.isNotEmpty;
}

Future<void> showBantooPairingDialog(BuildContext context) async {
  final codeController = TextEditingController();
  final err = await showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(translate('Hubungkan akun Bantoo')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Masukkan kode 6 digit dari web Bantoo (menu Remote / IndoDesk).'),
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: translate('Kode pairing'),
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(translate('Cancel')),
        ),
        TextButton(
          onPressed: () async {
            final code = codeController.text.trim();
            if (code.length != 6) {
              Navigator.pop(ctx, translate('Kode harus 6 digit'));
              return;
            }
            final api = await bind.mainGetApiServer();
            if (api.isEmpty) {
              Navigator.pop(ctx, translate('API server belum dikonfigurasi'));
              return;
            }
            final id = await bind.mainGetMyId();
            final uuid = await bind.mainGetUuid();
            final platform = isWindows
                ? 'windows'
                : isMacOS
                    ? 'macos'
                    : 'desktop';
            try {
              final resp = await http.post(
                Uri.parse('$api/api/indodesk/pair/confirm'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'code': code,
                  'rustdeskId': id.replaceAll(' ', ''),
                  'deviceUuid': uuid,
                  'platform': platform,
                }),
              );
              final json = jsonDecode(resp.body) as Map<String, dynamic>;
              if (json['success'] == true &&
                  json['data']?['deviceToken'] != null) {
                await bind.mainSetLocalOption(
                  key: 'bantoo-device-token',
                  value: json['data']['deviceToken'] as String,
                );
                Navigator.pop(ctx);
              } else {
                Navigator.pop(
                    ctx, json['error']?.toString() ?? translate('Failed'));
              }
            } catch (e) {
              Navigator.pop(ctx, translate('Failed'));
            }
          },
          child: Text(translate('OK')),
        ),
      ],
    ),
  );
  if (err != null && err.isNotEmpty) {
    showToast(err);
  } else if (err == null) {
    showToast(translate('Successful'));
  }
}
