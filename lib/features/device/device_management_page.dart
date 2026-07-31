import 'package:fitness_snack_lock/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:pull_down_button/pull_down_button.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Padlocks'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(left: 20, right: 8),
            onTap: () {},
            title: const Text("Felix's Padlocks"),
            subtitle: Row(
              children: [
                const Text('Connected'),
                Icon(
                  PhosphorIconsBold.dot,
                  color: Colors.grey.shade800,
                ),
                const PhosphorIcon(
                  PhosphorIconsDuotone.batteryFull,
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    '75%',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 8),
                  child: Icon(
                    size: 24,
                    PhosphorIconsBold.cellSignalFull,
                    color: Colors.black54,
                  ),
                ),
                const Text(
                  '100%',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            leading: const CircleAvatar(
              child: PhosphorIcon(
                PhosphorIconsBold.lockKey,
                color: AppColors.kPrimaryColor,
              ),
            ),
            trailing: PullDownButton(
              itemBuilder: (context) => [
                PullDownMenuItem(
                  title: 'Delegate Permission',
                  onTap: () {},
                ),
                PullDownMenuItem(
                  title: 'Disconnect',
                  onTap: () {},
                ),
                PullDownMenuItem(
                  title: 'Forget',
                  onTap: () {},
                ),
              ],
              buttonBuilder: (context, showMenu) => IconButton(
                onPressed: showMenu,
                padding: EdgeInsets.zero,
                icon: const Icon(PhosphorIconsBold.dotsThree),
              ),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 20, right: 8),
            onTap: () {},
            title: const Text("Kitchen's Padlocks"),
            subtitle: Row(
              children: [
                const Text('Not connected'),
                Icon(
                  PhosphorIconsBold.dot,
                  color: Colors.grey.shade800,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Icon(
                    size: 24,
                    PhosphorIconsBold.cellSignalFull,
                    color: Colors.black54,
                  ),
                ),
                const Text(
                  '100%',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            leading: const CircleAvatar(
              child: PhosphorIcon(PhosphorIconsRegular.lockKey),
            ),
            trailing: PullDownButton(
              itemBuilder: (context) => [
                PullDownMenuItem(
                  title: 'Connect',
                  onTap: () {},
                ),
                PullDownMenuItem(
                  title: 'Forget',
                  onTap: () {},
                ),
              ],
              buttonBuilder: (context, showMenu) => IconButton(
                onPressed: showMenu,
                padding: EdgeInsets.zero,
                icon: const Icon(PhosphorIconsBold.dotsThree),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
