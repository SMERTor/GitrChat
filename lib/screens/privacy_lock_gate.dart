import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Local app lock. The PIN hash is stored in Android Keystore-backed storage.
class PrivacyLockGate extends StatefulWidget {
  const PrivacyLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<PrivacyLockGate> createState() => _PrivacyLockGateState();
}

class _PrivacyLockGateState extends State<PrivacyLockGate>
    with WidgetsBindingObserver {
  static const _pinKey = 'gitrchat_pin_sha256';
  static const _storage = FlutterSecureStorage();
  final _auth = LocalAuthentication();
  final _pin = TextEditingController();
  bool _ready = false;
  bool _setup = false;
  bool _unlocked = false;
  bool _biometricAvailable = false;
  String? _error;

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final saved = await _storage.read(key: _pinKey);
    var biometric = false;
    try {
      biometric = await _auth.canCheckBiometrics &&
          await _auth.isDeviceSupported();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _setup = saved == null;
      _biometricAvailable = biometric;
      _ready = true;
    });
    if (saved != null && biometric) _unlockBiometric();
  }

  Future<void> _submitPin() async {
    final value = _pin.text;
    if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
      setState(() => _error = 'Введите PIN из 4–8 цифр');
      return;
    }
    if (_setup) {
      await _storage.write(key: _pinKey, value: _hash(value));
      if (mounted) setState(() {
        _setup = false;
        _unlocked = true;
        _error = null;
      });
      return;
    }
    final saved = await _storage.read(key: _pinKey);
    if (saved == _hash(value)) {
      setState(() {
        _unlocked = true;
        _error = null;
      });
    } else {
      setState(() => _error = 'Неверный PIN');
    }
    _pin.clear();
  }

  Future<void> _unlockBiometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Разблокируйте GitrChat',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) setState(() => _unlocked = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось выполнить проверку');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_setup && mounted) setState(() => _unlocked = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF071110),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF11F3A6)),
        ),
      );
    }
    if (_unlocked) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xFF071110),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: const BoxDecoration(
                      color: Color(0xFF11F3A6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF04251B),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _setup ? 'Защитите GitrChat' : 'GitrChat заблокирован',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _setup
                        ? 'Создайте личный PIN-код. Он будет храниться защищённо на этом телефоне.'
                        : 'Введите PIN-код для доступа к переписке.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 8,
                    style: const TextStyle(color: Colors.white, letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF14211D),
                      errorText: _error,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _submitPin(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitPin,
                      child: Text(_setup ? 'Создать PIN' : 'Разблокировать'),
                    ),
                  ),
                  if (!_setup && _biometricAvailable) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _unlockBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Отпечаток / биометрия'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF11F3A6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
