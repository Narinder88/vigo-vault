import 'package:fitness_snack_lock/services/data_service.dart';
import 'package:fitness_snack_lock/services/paired_lock_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataRequestPattern credential rotation frames', () {
    const token = 'aabbccdd';
    const aesKey = '00112233445566778899aabbccddeeff';

    test('password verify frame is 05 03 06 OLDPWD TOKEN FILL[3]', () {
      expect(
        DataRequestPattern.getPasswordVerifyHex(token),
        '050306303030303030aabbccdd000000',
      );
    });

    test('password set frame is 05 04 06 NEWPWD TOKEN FILL[3]', () {
      expect(
        DataRequestPattern.getPasswordSetHex(
          token,
          const [0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
        ),
        '050406112233445566aabbccdd000000',
      );
    });

    test('factory AES key splits into documented KEYL/KEYH', () {
      expect(
        DataRequestPattern.defaultEncryptKey,
        '3A60432A5C01211F291E0F4E0C132825',
      );
      expect(
        DataRequestPattern.getAesKeyLowHex(
          token,
          DataRequestPattern.defaultEncryptKey,
        ),
        '0701083a60432a5c01211faabbccdd00',
      );
      expect(
        DataRequestPattern.getAesKeyHighHex(
          token,
          DataRequestPattern.defaultEncryptKey,
        ),
        '070208291e0f4e0c132825aabbccdd00',
      );
    });

    test('AES key frames split KEYL/KEYH with TOKEN and FILL[1]', () {
      expect(
        DataRequestPattern.getAesKeyLowHex(token, aesKey),
        '0701080011223344556677aabbccdd00',
      );
      expect(
        DataRequestPattern.getAesKeyHighHex(token, aesKey),
        '0702088899aabbccddeeffaabbccdd00',
      );
    });

    test('rotation success parsers require RET 00', () {
      expect(
        DataRequestPattern.isPasswordRotationSuccess(
          const [0x05, 0x05, 0x01, 0x00],
        ),
        isTrue,
      );
      expect(
        DataRequestPattern.isPasswordRotationSuccess(
          const [0x05, 0x05, 0x01, 0x01],
        ),
        isFalse,
      );
      expect(
        DataRequestPattern.isAesKeyRotationSuccess(
          const [0x07, 0x03, 0x01, 0x00],
        ),
        isTrue,
      );
      expect(
        DataRequestPattern.isAesKeyRotationSuccess(
          const [0x07, 0x03, 0x01, 0x01],
        ),
        isFalse,
      );
    });

    test('factory password hex is ASCII 000000', () {
      expect(DataRequestPattern.defaultPasswordHex, '303030303030');
      expect(
        DataRequestPattern.passwordBytesToHex(
          DataRequestPattern.defaultPasswordBytes,
        ),
        '303030303030',
      );
    });

    test('generated AES key and password have protocol lengths', () {
      final aesKeyHex = DataRequestPattern.generateAesKeyHex();
      final password = DataRequestPattern.generatePasswordBytes();
      expect(aesKeyHex, hasLength(32));
      expect(PairedLockStorage.isValidAesKeyHex(aesKeyHex), isTrue);
      expect(PairedLockStorage.isFactoryAesKey(aesKeyHex), isFalse);
      expect(password, hasLength(6));
      expect(
        PairedLockStorage.isValidPasswordHex(
          DataRequestPattern.passwordBytesToHex(password),
        ),
        isTrue,
      );
    });

    test('unlock frame uses the provided password bytes', () {
      expect(
        DataRequestPattern.getUnlockHex(
          token,
          passwordBytes: const [0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
        ),
        '050106112233445566aabbccdd000001',
      );
    });

  });
}
