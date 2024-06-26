import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ouisync_plugin/ouisync_plugin.dart';

import '../../generated/l10n.dart';
import '../cubits/cubits.dart';
import '../cubits/launch_at_startup.dart';
import '../widgets/widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage(
    this.session,
    this.cubits,
    this.checkForDokan,
  );

  final Session session;
  final Cubits cubits;
  final void Function() checkForDokan;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final connectivityInfo = ConnectivityInfo(widget.session);
  late final PeerSetCubit peerSet = PeerSetCubit(widget.session);
  late final NatDetection natDetection = NatDetection(widget.session);
  final launchAtStartup = LaunchAtStartupCubit();

  @override
  void initState() {
    super.initState();

    peerSet.init();
    unawaited(_updateConnectivityInfo());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.titleSettings),
          elevation: 0.0,
        ),
        body: AppSettingsContainer(
          widget.session,
          widget.cubits,
          connectivityInfo: connectivityInfo,
          natDetection: natDetection,
          peerSet: peerSet,
          checkForDokan: widget.checkForDokan,
          launchAtStartup: launchAtStartup,
        ),
      );

  Future<void> _updateConnectivityInfo() async {
    await connectivityInfo.update();

    await for (final _ in widget.cubits.powerControl.stream) {
      await connectivityInfo.update();
    }
  }
}
