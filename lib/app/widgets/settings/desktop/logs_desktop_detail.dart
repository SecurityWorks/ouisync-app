import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../generated/l10n.dart';
import '../../../cubits/cubits.dart';
import '../../../pages/pages.dart';
import '../../../utils/utils.dart';
import 'desktop_settings.dart';

class LogsDesktopDetail extends StatelessWidget {
  const LogsDesktopDetail(
      {required this.item,
      required this.settings,
      required this.reposCubit,
      required this.panicCounter,
      required this.natDetection});

  final SettingItem item;
  final Settings settings;
  final ReposCubit reposCubit;
  final StateMonitorIntValue panicCounter;
  final Future<NatDetection> natDetection;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildDeleteTile(context),
      Divider(height: 30.0),
      _buildShareTile(context),
      Divider(height: 30.0),
      _buildViewTile(context),
      Divider(height: 30.0)
    ]);
  }

  Widget _buildDeleteTile(BuildContext context) => Column(children: [
        Row(children: [Text('Save', textAlign: TextAlign.start)]),
        ListTile(
            leading: const Icon(Icons.save),
            title: Row(children: [
              TextButton(
                  onPressed: () {},
                  child: Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: 15.0, horizontal: 20.0),
                      child: Text('Save log file')),
                  style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white))
            ]))
      ]);

  Widget _buildShareTile(BuildContext context) => ListTile(
      title: Text(S.current.actionShare),
      leading: Icon(Icons.share),
      onTap: () => _shareLogs);

  Widget _buildViewTile(BuildContext context) => ListTile(
      title: Text(S.current.messageView),
      leading: Icon(Icons.visibility),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LogViewPage(settings: settings),
          )));

  Future<void> _shareLogs(BuildContext context) async {
    final tempPath = await _dumpInfo(context);
    await Share.shareXFiles([XFile(tempPath, mimeType: 'text/plain')]);
  }

  Future<String> _dumpInfo(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final info = await PackageInfo.fromPlatform();
    final name = info.appName.toLowerCase();

    final connType = context.read<PowerControl>().state.connectivityType;
    final connInfo = context.read<ConnectivityInfo>().state;

    // TODO: Add time zone, at time of this writing, time zones have not yet
    // been implemented by DateFormat.
    final formatter = DateFormat('yyyy-MM-dd--HH-mm-ss');
    final timestamp = formatter.format(DateTime.now());
    final path = buildDestinationPath(dir.path, '$name--$timestamp.log');
    final outFile = File(path);

    final sink = outFile.openWrite();

    final natType = (await natDetection).state.message();

    try {
      sink.writeln("appName: ${info.appName}");
      sink.writeln("packageName: ${info.packageName}");
      sink.writeln("version: ${info.version}");
      sink.writeln("buildNumber: ${info.buildNumber}");

      sink.writeln("connectionType: $connType");
      sink.writeln("externalIP: ${connInfo.externalIP}");
      sink.writeln("localIPv4: ${connInfo.localIPv4}");
      sink.writeln("localIPv6: ${connInfo.localIPv6}");
      sink.writeln("NAT type: $natType");
      sink.writeln("tcpListenerV4:  ${connInfo.tcpListenerV4}");
      sink.writeln("tcpListenerV6:  ${connInfo.tcpListenerV6}");
      sink.writeln("quicListenerV4: ${connInfo.quicListenerV4}");
      sink.writeln("quicListenerV6: ${connInfo.quicListenerV6}");
      sink.writeln("\n");

      await dumpAll(sink, reposCubit.session.getRootStateMonitor());
    } finally {
      await sink.close();
    }

    return path;
  }
}