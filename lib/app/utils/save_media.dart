import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:ouisync/ouisync.dart';
import 'package:path/path.dart' as p;

import '../cubits/cubits.dart';
import '../widgets/widgets.dart';
import 'utils.dart';

class SaveMedia with EntryOps, AppLogger {
  SaveMedia(
    BuildContext context, {
    required RepoCubit repoCubit,
    required this.sourcePath,
    required this.type,
  })  : _context = context,
        _repoCubit = repoCubit;

  final BuildContext _context;
  final RepoCubit _repoCubit;
  final String sourcePath;
  final EntryType type;

  Future<void> save() async {
    final newFileName = p.basename(sourcePath);
    final newFilePath = p.join(
      _repoCubit.state.currentFolder.path,
      newFileName,
    );

    final exist = await _repoCubit.exists(newFilePath);
    if (!exist) {
      await _saveFile(
        devicePath: sourcePath,
        toPath: newFilePath,
        fileName: newFileName,
      );

      return;
    }

    final fileAction = await getFileActionType(
      _context,
      newFileName,
      newFilePath,
      EntryType.file,
    );

    if (fileAction == null) return;

    if (fileAction == FileAction.replace) {
      await _replaceFile(devicePath: sourcePath, toPath: newFilePath);
    }

    if (fileAction == FileAction.keep) {
      await _renameAndSaveFile(
        devicePath: sourcePath,
        toPath: newFilePath,
        fileName: newFileName,
      );
    }
  }

  Future<void> _saveFile({
    required String devicePath,
    required String toPath,
    required String fileName,
  }) async {
    final file = io.File(devicePath);
    final length = (await file.stat()).size;
    final fileByteStream = file.openRead();

    await _repoCubit.saveFile(
      filePath: toPath,
      length: length,
      fileByteStream: fileByteStream,
    );
  }

  Future<void> _replaceFile({
    required String devicePath,
    required String toPath,
  }) async {
    try {
      final file = io.File(devicePath);
      final fileLength = (await file.stat()).size;
      final fileByteStream = file.openRead();

      await _repoCubit.replaceFile(
        filePath: toPath,
        length: fileLength,
        fileByteStream: fileByteStream,
      );
    } catch (e, st) {
      loggy.debug(e, st);
    }
  }

  Future<void> _renameAndSaveFile({
    required String devicePath,
    required String toPath,
    required String fileName,
  }) async {
    final newPath = await disambiguateEntryName(
      repoCubit: _repoCubit,
      path: toPath,
    );

    await _saveFile(
      devicePath: devicePath,
      toPath: newPath,
      fileName: fileName,
    );
  }
}
