import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/bantoo_pairing_dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

const _kGrantKey = 'bantoo-session-grant';
const _kOtpKey = 'bantoo-session-otp';
const _kUnlockedKey = 'bantoo-session-unlocked';
const _kSessionLogoutEvent = 'indodesk_session_logout';
const _kSessionLogoutHandler = 'bantoo_gate';

Future<void> clearBantooSessionUnlock() async {
  await bind.mainSetLocalOption(key: _kGrantKey, value: '');
  await bind.mainSetLocalOption(key: _kOtpKey, value: '');
  await bind.mainSetLocalOption(key: _kUnlockedKey, value: '');
}

Future<void> applyBantooSessionUnlock({
  required String grant,
  required String otp,
}) async {
  await bind.mainSetLocalOption(key: _kGrantKey, value: grant);
  await bind.mainSetLocalOption(key: _kOtpKey, value: otp);
  await bind.mainSetLocalOption(key: _kUnlockedKey, value: 'Y');
  if (bind.isIncomingOnly()) {
    bind.mainSetTemporaryPassword(password: otp);
  }
}

class _BantooApiResult {
  const _BantooApiResult({
    this.data,
    this.error,
    this.statusCode = 0,
  });

  final Map<String, dynamic>? data;
  final String? error;
  final int statusCode;

  bool get ok => data != null;
}

Future<_BantooApiResult> _bantooJsonRequest(
  String method,
  String path, {
  Map<String, dynamic>? body,
}) async {
  final api = (await bind.mainGetApiServer()).replaceAll(RegExp(r'/+$'), '');
  if (api.isEmpty) {
    return const _BantooApiResult(error: 'Server Bantoo belum dikonfigurasi');
  }
  final token = await bind.mainGetLocalOption(key: 'bantoo-device-token');
  if (token.isEmpty) {
    return const _BantooApiResult(error: 'Perangkat belum terhubung ke Bantoo');
  }
  final uri = Uri.parse('$api$path');
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
  final resp = method == 'GET'
      ? await http.get(uri, headers: headers)
      : await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
  Map<String, dynamic> json;
  try {
    json = jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return _BantooApiResult(
      statusCode: resp.statusCode,
      error: translate('Gagal menghubungi server Bantoo'),
    );
  }
  if (resp.statusCode >= 400 || json['success'] != true) {
    return _BantooApiResult(
      statusCode: resp.statusCode,
      error: (json['error'] as String?) ??
          translate('Gagal menghubungi server Bantoo'),
    );
  }
  return _BantooApiResult(
    statusCode: resp.statusCode,
    data: json['data'] as Map<String, dynamic>?,
  );
}

class BantooSessionGate extends StatefulWidget {
  const BantooSessionGate({super.key});

  @override
  State<BantooSessionGate> createState() => _BantooSessionGateState();
}

class _BantooSessionGateState extends State<BantooSessionGate> with WindowListener {
  _GatePhase _phase = _GatePhase.loading;
  String? _message;
  String? _confirmDeadlineAt;
  final _otpController = TextEditingController();
  Timer? _heartbeatTimer;
  bool _endingSession = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);
    platformFFI.registerEventHandler(
      _kSessionLogoutEvent,
      _kSessionLogoutHandler,
      (_) async => _onSessionEnded(),
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    rustDeskWinManager.unregisterActiveWindowListener(onActiveWindowChanged);
    platformFFI.unregisterEventHandler(
      _kSessionLogoutEvent,
      _kSessionLogoutHandler,
    );
    _heartbeatTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (rustDeskWinManager.getActiveWindows().contains(kMainWindowId)) {
      await rustDeskWinManager.unregisterActiveWindow(kMainWindowId);
    }
    if (isMacOS && await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    await windowManager.hide();
    super.onWindowClose();
  }

  Future<void> _onSessionEnded({String? message}) async {
    if (_endingSession) return;
    _endingSession = true;
    try {
      _heartbeatTimer?.cancel();
      await clearBantooSessionUnlock();
      if (bind.isIncomingOnly()) {
        bind.mainUpdateTemporaryPassword();
      }
      if (isDesktop) {
        await rustDeskWinManager.closeAllSubWindows();
      }
      if (!mounted) return;
      setState(() {
        _phase = _GatePhase.locked;
        _message = message ?? translate('Sesi konsultasi telah berakhir');
      });
    } finally {
      _endingSession = false;
    }
  }

  Future<void> _bootstrap() async {
    await clearBantooSessionUnlock();
    if (!await isBantooPaired()) {
      setState(() {
        _phase = _GatePhase.needPairing;
        _message = null;
      });
      return;
    }
    await _refreshPreflight();
  }

  Future<void> _refreshPreflight() async {
    final wasUnlocked = _phase == _GatePhase.unlocked;
    setState(() {
      _phase = _GatePhase.loading;
      _message = null;
    });
    final result = await _bantooJsonRequest('GET', '/api/indodesk/session/preflight');
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _phase = _GatePhase.error;
        _message = result.error ?? translate('Gagal menghubungi server Bantoo');
      });
      return;
    }
    final data = result.data!;
    if (wasUnlocked && data['canUnlock'] != true) {
      await _onSessionEnded(
        message: (data['reason'] as String?) ??
            translate('Belum ada sesi konsultasi remote yang aktif'),
      );
      return;
    }
    if (data['canUnlock'] == true) {
      setState(() {
        _phase = _GatePhase.otpEntry;
        _confirmDeadlineAt = data['confirmDeadlineAt'] as String?;
        _message = data['status'] == 'AWAITING_CONFIRMATION'
            ? translate('Masa garansi remote — masukkan OTP sesi')
            : null;
      });
      return;
    }
    setState(() {
      _phase = _GatePhase.locked;
      _message = (data['reason'] as String?) ??
          translate('Belum ada sesi konsultasi remote yang aktif');
    });
    if (isDesktop) {
      unawaited(rustDeskWinManager.closeAllSubWindows());
    }
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      setState(() => _message = translate('OTP tidak valid'));
      return;
    }
    setState(() {
      _phase = _GatePhase.loading;
      _message = null;
    });
    final result = await _bantooJsonRequest(
      'POST',
      '/api/indodesk/session/unlock',
      body: {'otp': otp},
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _phase = _GatePhase.otpEntry;
        _message = result.error ??
            translate('OTP tidak valid atau sesi tidak aktif');
      });
      return;
    }
    final data = result.data!;
    final grant = data['grant'] as String? ?? '';
    await applyBantooSessionUnlock(grant: grant, otp: otp);
    if (bind.isIncomingOnly()) {
      await gFFI.serverModel.updatePasswordModel();
    }
    if (!mounted) return;
    setState(() => _phase = _GatePhase.unlocked);
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final result =
          await _bantooJsonRequest('POST', '/api/indodesk/heartbeat', body: {});
      if (!mounted) return;
      if (result.ok && result.data?['shouldLogout'] == true) {
        await _onSessionEnded();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.unlocked:
        return const DesktopTabPage();
      case _GatePhase.loading:
        return _shell(
          child: const Center(child: CircularProgressIndicator()),
        );
      case _GatePhase.needPairing:
        return _shell(
          child: _card(
            title: translate('Hubungkan akun Bantoo'),
            body: translate(
              'Pairing diperlukan sebelum membuka sesi IndoDesk.',
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  await showBantooPairingDialog(context);
                  await _bootstrap();
                },
                child: Text(translate('Hubungkan akun Bantoo')),
              ),
            ],
          ),
        );
      case _GatePhase.locked:
        return _shell(
          child: _card(
            title: translate('IndoDesk terkunci'),
            body: _message ??
                translate('Belum ada sesi konsultasi remote yang aktif'),
            actions: [
              OutlinedButton(
                onPressed: _refreshPreflight,
                child: Text(translate('Refresh')),
              ),
            ],
          ),
        );
      case _GatePhase.otpEntry:
        return _shell(
          child: _card(
            title: translate('Masukkan OTP sesi'),
            body: _message ??
                translate('OTP 6 digit dari halaman konsultasi di web Bantoo.'),
            extra: Column(
              children: [
                if (_confirmDeadlineAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      translate('Batas konfirmasi: ') + _confirmDeadlineAt!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: translate('OTP sesi'),
                    counterText: '',
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: _refreshPreflight,
                child: Text(translate('Refresh')),
              ),
              FilledButton(
                onPressed: _submitOtp,
                child: Text(translate('Buka IndoDesk')),
              ),
            ],
          ),
        );
      case _GatePhase.error:
        return _shell(
          child: _card(
            title: translate('Error'),
            body: _message ?? translate('Terjadi kesalahan'),
            actions: [
              FilledButton(
                onPressed: _bootstrap,
                child: Text(translate('Coba lagi')),
              ),
            ],
          ),
        );
    }
  }

  Widget _shell({required Widget child}) {
    return Scaffold(body: SafeArea(child: Center(child: child)));
  }

  Widget _card({
    required String title,
    required String body,
    required List<Widget> actions,
    Widget? extra,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                body,
                style: _message != null && _phase == _GatePhase.otpEntry
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              if (extra != null) ...[
                const SizedBox(height: 16),
                extra,
              ],
              const SizedBox(height: 20),
              ...actions.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: w,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GatePhase {
  loading,
  needPairing,
  locked,
  otpEntry,
  unlocked,
  error,
}
