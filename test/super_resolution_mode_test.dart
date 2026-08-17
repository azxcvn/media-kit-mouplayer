import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moumou/models/super_resolution_mode.dart';

/// 超分辨率模型测试：
/// - 模式枚举：7 档（关闭 + A/B/C/A+/B+/C+）、持久化 id 稳定、反查兜底；
/// - 质量枚举：流畅/均衡/高清，index 反查回退均衡；
/// - buildAnime4KChain：mode × quality 生成正确着色器链（纯函数）。
void main() {
  group('SuperResolutionMode', () {
    test('共 7 种模式（关闭 + 6 档超分）', () {
      expect(SuperResolutionMode.values.length, 7);
      expect(SuperResolutionMode.values.first, SuperResolutionMode.off);
      final onModes = SuperResolutionMode.values
          .where((m) => m != SuperResolutionMode.off);
      expect(onModes.length, 6);
    });

    test('id 唯一且稳定，按 id 反查正常', () {
      final ids = SuperResolutionMode.values.map((m) => m.id).toSet();
      expect(ids.length, SuperResolutionMode.values.length);
      for (final m in SuperResolutionMode.values) {
        expect(SuperResolutionMode.byId(m.id), m);
      }
      expect(SuperResolutionMode.byId('不存在'), SuperResolutionMode.off);
      expect(SuperResolutionMode.byId(null), SuperResolutionMode.off);
    });
  });

  group('SuperResolutionQuality', () {
    test('三档：流畅/均衡/高清，默认均衡', () {
      expect(SuperResolutionQuality.values.length, 3);
      expect(SuperResolutionQuality.values.map((q) => q.suffix).toList(),
          ['S', 'M', 'L']);
      expect(SuperResolutionQuality.balanced.label, '均衡');
    });

    test('fromIndex 越界/空回退均衡', () {
      expect(SuperResolutionQuality.fromIndex(0),
          SuperResolutionQuality.fast);
      expect(SuperResolutionQuality.fromIndex(1),
          SuperResolutionQuality.balanced);
      expect(SuperResolutionQuality.fromIndex(2), SuperResolutionQuality.high);
      expect(SuperResolutionQuality.fromIndex(-1),
          SuperResolutionQuality.balanced);
      expect(SuperResolutionQuality.fromIndex(99),
          SuperResolutionQuality.balanced);
      expect(SuperResolutionQuality.fromIndex(null),
          SuperResolutionQuality.balanced);
    });
  });

  group('buildAnime4KChain', () {
    test('关闭模式返回空链', () {
      for (final q in SuperResolutionQuality.values) {
        expect(buildAnime4KChain(SuperResolutionMode.off, q), isEmpty);
      }
    });

    test('始终以 Clamp_Highlights 开头', () {
      for (final m in SuperResolutionMode.values) {
        if (m == SuperResolutionMode.off) continue;
        final chain = buildAnime4KChain(m, SuperResolutionQuality.balanced);
        expect(chain.first, 'Anime4K_Clamp_Highlights.glsl');
      }
    });

    test('质量档决定着色器变体后缀（均衡 = M，后置低一级 = S）', () {
      final chain =
          buildAnime4KChain(SuperResolutionMode.a, SuperResolutionQuality.balanced);
      expect(chain, [
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Upscale_CNN_x2_M.glsl',
        'Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K_AutoDownscalePre_x4.glsl',
        'Anime4K_Upscale_CNN_x2_S.glsl',
      ]);
    });

    test('高清档后置着色器用 M 变体（抵消 4 倍像素量开销）', () {
      final chain =
          buildAnime4KChain(SuperResolutionMode.a, SuperResolutionQuality.high);
      expect(chain, contains('Anime4K_Restore_CNN_L.glsl'));
      expect(chain, contains('Anime4K_Upscale_CNN_x2_L.glsl'));
      expect(chain.last, 'Anime4K_Upscale_CNN_x2_M.glsl');
    });

    test('流畅档全链用 S 变体', () {
      final chain =
          buildAnime4KChain(SuperResolutionMode.a, SuperResolutionQuality.fast);
      expect(chain.where((s) => s.contains('_S.glsl')).length, greaterThan(0));
      expect(chain.any((s) => s.contains('_M.glsl')), isFalse);
      expect(chain.any((s) => s.contains('_L.glsl')), isFalse);
    });

    test('B 模式用 Restore_Soft，C 模式用 Upscale_Denoise', () {
      final b = buildAnime4KChain(
          SuperResolutionMode.b, SuperResolutionQuality.balanced);
      expect(b, contains('Anime4K_Restore_CNN_Soft_M.glsl'));
      final c = buildAnime4KChain(
          SuperResolutionMode.c, SuperResolutionQuality.balanced);
      expect(c, contains('Anime4K_Upscale_Denoise_CNN_x2_M.glsl'));
      expect(c.any((s) => s.contains('Restore_CNN')), isFalse);
    });

    test('PLUS 双段链比单段链更长', () {
      for (final q in SuperResolutionQuality.values) {
        final single = buildAnime4KChain(SuperResolutionMode.a, q).length;
        final plus = buildAnime4KChain(SuperResolutionMode.aPlus, q).length;
        expect(plus, greaterThan(single));
      }
    });

    test('所有模式引用的着色器都已打包进 assets/shaders', () {
      for (final m in SuperResolutionMode.values) {
        for (final q in SuperResolutionQuality.values) {
          for (final shader in buildAnime4KChain(m, q)) {
            expect(
              File('assets/shaders/$shader').existsSync(),
              isTrue,
              reason: '缺少着色器文件：$shader（${m.label} × ${q.label}）',
            );
          }
        }
      }
    });
  });
}
