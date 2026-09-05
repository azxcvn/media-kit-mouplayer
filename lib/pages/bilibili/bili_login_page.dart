import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:moumou/services/bilibili/bili_account.dart';
import 'package:moumou/services/bilibili/bili_auth_service.dart';
import 'package:moumou/services/bilibili/bili_constants.dart';
import 'package:moumou/services/device_services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saver_gallery/saver_gallery.dart';

/// 哔哩哔哩登录页（工作.md 阶段一）：
/// - 「扫码登录」：二维码 + 等待扫码/已扫码/失效三态 + 刷新/保存相册/打开哔哩哔哩；
/// - 「Cookie 登录」：粘贴浏览器 Cookie 兜底（风控异常时逃生门）。
///
/// 登录成功后 pop(true)，「我的」页监听 [BiliAccount] 自动刷新账号卡片。
class BiliLoginPage extends StatefulWidget {
  const BiliLoginPage({super.key});

  @override
  State<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends State<BiliLoginPage> {
  static const _qrValidSeconds = 180;

  final GlobalKey _qrBoundaryKey = GlobalKey();
  final TextEditingController _cookieController = TextEditingController();

  BiliAccount get account => BiliAccount.instance;

  String? _qrUrl;
  String? _authCode;
  String _statusText = '正在获取二维码...';
  int _remaining = 0;
  bool _busy = false;
  bool _ticking = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    _pollTimer?.cancel();
    setState(() {
      _qrUrl = null;
      _statusText = '正在获取二维码...';
    });
    try {
      final qr = await account.startQrLogin();
      if (!mounted) return;
      setState(() {
        _qrUrl = qr.url;
        _authCode = qr.authCode;
        _statusText = '请使用哔哩哔哩客户端扫码';
        _remaining = _qrValidSeconds;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = '获取二维码失败，请重试');
    }
  }

  Future<void> _tick() async {
    if (_ticking || _authCode == null) return;
    // 倒计时到 0 主动刷新（与服务端 86038 兜底双保险）
    if (_remaining > 0) {
      setState(() => _remaining--);
      if (_remaining == 0) {
        setState(() => _statusText = '二维码已失效，正在刷新...');
        await _generate();
        return;
      }
    }
    _ticking = true;
    try {
      final poll = await account.pollQr(_authCode!);
      if (!mounted) return;
      switch (poll.code) {
        case BiliConstants.qrScanned:
          setState(() => _statusText = '已扫码，请在手机上确认');
          break;
        case BiliConstants.qrExpired:
          _pollTimer?.cancel();
          setState(() => _statusText = '二维码已失效，正在刷新...');
          await _generate();
          break;
        case BiliConstants.qrSuccess:
          _pollTimer?.cancel();
          if (poll.data != null) {
            await _onLoginSuccess(poll.data!);
          } else {
            // 服务端已确认登录但凭证未解析出来（cookie_info 缺失）：
            // 不能静默取消轮询冻结页面，给提示并刷新重试。
            debugPrint('[BILI-LOGIN] poll 成功但 data 为空，刷新重试');
            _toast('登录凭证获取失败，请重试');
            await _generate();
          }
          break;
        default:
          break; // qrNotScanned 或其它：保持等待扫码
      }
    } catch (_) {
      // 网络抖动：静默，下个 tick 重试
    } finally {
      _ticking = false;
    }
  }

  Future<void> _onLoginSuccess(BiliTvLoginData data) async {
    setState(() => _busy = true);
    try {
      final user = await account.completeQrLogin(data);
      if (!mounted) return;
      _toast('登录成功：${user.nickname}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('登录失败，请重试');
      await _generate();
    }
  }

  Future<void> _saveQr() async {
    if (_qrUrl == null) return;
    try {
      final boundary =
          _qrBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        _toast('保存失败');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      image.dispose();
      if (bytes == null || bytes.isEmpty) {
        _toast('保存失败');
        return;
      }
      final name = 'moumou_bili_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await SaverGallery.saveImage(
        bytes,
        fileName: name,
        skipIfExists: false,
      );
      _toast(result.isSuccess ? '二维码已保存到相册' : '保存失败：${result.errorMessage}');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _openBilibili() async {
    final url = _qrUrl;
    if (url == null) return;
    final ok = await DeviceServices.openBilibiliScan(url);
    if (!mounted) return;
    if (!ok) _toast('未检测到哔哩哔哩客户端');
  }

  Future<void> _importCookie() async {
    final raw = _cookieController.text.trim();
    if (raw.isEmpty) {
      _toast('请先粘贴 Cookie');
      return;
    }
    setState(() => _busy = true);
    try {
      final user = await account.importCookie(raw);
      if (!mounted) return;
      _toast('登录成功：${user.nickname}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('登录失败：Cookie 无效或已过期');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('哔哩哔哩登录'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code_2), text: '扫码登录'),
              Tab(icon: Icon(Icons.cookie_outlined), text: 'Cookie 登录'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildQrTab(context),
            _buildCookieTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildQrTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          RepaintBoundary(
            key: _qrBoundaryKey,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _qrUrl == null
                  ? const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : QrImageView(
                      data: _qrUrl!,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _statusText,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          if (_qrUrl != null && _remaining > 0) ...[
            const SizedBox(height: 6),
            Text(
              '剩余有效时间：$_remaining 秒',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _qrUrl == null ? null : _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
              ),
              TextButton.icon(
                onPressed: _qrUrl == null ? null : _saveQr,
                icon: const Icon(Icons.save_alt),
                label: const Text('保存到相册'),
              ),
              TextButton.icon(
                onPressed: _qrUrl == null ? null : _openBilibili,
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开哔哩哔哩'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '「打开哔哩哔哩」会在已安装的哔哩哔哩客户端中自动唤起扫码确认。',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCookieTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '从浏览器复制 Cookie 粘贴登录（扫码异常时的备用方式）',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cookieController,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Cookie',
              hintText: 'SESSDATA=...; bili_jct=...; DedeUserID=...',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _importCookie,
            icon: const Icon(Icons.login),
            label: Text(_busy ? '登录中...' : '登录'),
          ),
          const SizedBox(height: 16),
          Text(
            'Cookie 仅本地加密保存，不会上传或记录日志。',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
