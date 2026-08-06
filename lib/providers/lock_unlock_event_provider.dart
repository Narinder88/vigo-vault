import 'package:flutter_riverpod/legacy.dart';

/// Incremented when the vault unlocks (phone or Apple Watch) so UI layers can reset.
final lockUnlockEventProvider = StateProvider<int>((ref) => 0);

void notifyLockUnlockSuccess(Ref ref) {
  ref.read(lockUnlockEventProvider.notifier).state++;
}
