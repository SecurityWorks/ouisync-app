import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;

import 'package:bloc/bloc.dart';
import 'package:ouisync_plugin/ouisync_plugin.dart' as oui;
import 'package:ouisync_plugin/state_monitor.dart';

import '../../../generated/l10n.dart';
import '../../utils/loggers/ouisync_app_logger.dart';
import '../../utils/utils.dart';
import '../../models/models.dart';
import '../../models/folder_state.dart';
import '../cubits.dart' as cubits;

part "state.dart";

class RepoCubit extends cubits.Watch<RepoState> with OuiSyncAppLogger {
  RepoCubit(RepoState state)
    : super(state);

  oui.Repository get handle => state.handle;
  String get id => state.id;
  String get name => state.name;
  RepoState get repo => state;
  FolderState get currentFolder => state.currentFolder;

  oui.AccessMode get accessMode => state.accessMode;
  bool get canRead => state.accessMode != oui.AccessMode.blind;
  bool get canWrite => state.accessMode == oui.AccessMode.write;

  Future<oui.ShareToken> createShareToken(oui.AccessMode accessMode) async {
    return await handle.createShareToken(accessMode: accessMode, name: name);
  }

  Future<bool> exists(String path) async {
    return await handle.exists(path);
  }

  Future<oui.EntryType?> type(String path) => handle.type(path);

  // Get the state monitor of this particular repository. That is 'root >
  // Repositories > this repository ID'.
  StateMonitor stateMonitor() {
    return handle.stateMonitor()!;
  }

  Future<void> navigateTo(String destination) async {
    update((state) { state.isLoading = true; });
    repo.currentFolder.goTo(destination);
    await _refreshFolder();
    update((state) { state.isLoading = false; });
  }

  Future<void> createFolder(String folderPath) async {
    update((state) { state.isLoading = true; });

    try{
      final result = await repo.createFolder(folderPath);
      if (result.result) {
        repo.currentFolder.goTo(folderPath);
      } else {
        loggy.app('Directory $folderPath creation failed');
      }
    } catch (e, st) {
      loggy.app('Directory $folderPath creation exception', e, st);
    }

    await _refreshFolder();
  }

  Future<void> deleteFolder(String path, bool recursive) async {
    update((state) { state.isLoading = true; });

    try {
      final result = await repo.deleteFolder(path, recursive);
      if (result.errorMessage.isNotEmpty) {
        loggy.app('Delete directory $path failed');
      }
    } catch (e, st) {
      loggy.app('Directory $path deletion exception', e, st);
    }

    await _refreshFolder();
  }

  Future<void> saveFile({
      required String newFilePath,
      required String fileName,
      required int length,
      required Stream<List<int>> fileByteStream,
  }) async {
    if (repo.uploads.containsKey(newFilePath)) {
      showMessage("File is already being uploaded");
      return;
    }

    final file = await _createFile(newFilePath);

    if (file == null) {
      return;
    }

    final job = cubits.Watch(Job(0, length));
    update((repo) { repo.uploads[newFilePath] = job; });

    await _refreshFolder();

    // TODO: We should try to remove the file in case of exception or user cancellation.

    try {
      int offset = 0;
      final stream = fileByteStream.takeWhile((_) => job.state.cancel == false);

      await for (final buffer in stream) {
        await file.write(offset, buffer);
        offset += buffer.length;
        job.update((job) { job.soFar = offset; });
      }
    } catch (e, st) {
      showMessage(S.current.messageWritingFileError(newFilePath));
      return;
    } finally {
      await file.close();
      update((repo) { repo.uploads.remove(newFilePath); });
    }

    if (job.state.cancel) {
      showMessage(S.current.messageWritingFileCanceled(newFilePath));
    } else {
      showMessage(S.current.messageWritingFileDone(newFilePath));
    }
  }

  Future<void> downloadFile({ required String sourcePath, required String destinationPath }) async {
    if (repo.downloads.containsKey(sourcePath)) {
      showMessage("File is already being downloaded");
      return;
    }

    final ouisyncFile = await oui.File.open(handle, sourcePath);
    final length = await ouisyncFile.length;

    final newFile = io.File(destinationPath);
    int offset = 0;

    final job = cubits.Watch(Job(0, length));
    update((repo) { repo.downloads[sourcePath] = job; });

    try {
      while (job.state.cancel == false) {
        final chunk = await ouisyncFile.read(offset, Constants.bufferSize);
        offset += chunk.length;

        await newFile.writeAsBytes(chunk, mode: io.FileMode.writeOnlyAppend);

        if (chunk.length < Constants.bufferSize) {
          update((repo) { repo.downloads.remove(sourcePath); });
          break;
        }

        job.update((job) { job.soFar = offset; });
      }
    } catch (e, st) {
      loggy.app('Download file ${sourcePath} exception', e, st);
      showMessage(S.current.messageDownloadingFileError(sourcePath));
    } finally {
      update((repo) { repo.downloads.remove(sourcePath); });
      await ouisyncFile.close();
    }
  }

  Future<oui.File?> _createFile(String newFilePath) async {
    CreateFileResult? createFileResult;

    try {
      createFileResult = (await repo.createFile(newFilePath)) as CreateFileResult?;
      if (createFileResult!.errorMessage.isNotEmpty) {
        loggy.app('Create file $newFilePath failed:\n${createFileResult.errorMessage}');
        showMessage(S.current.messageNewFileError(newFilePath));
        return null;
      }
    } catch (e, st) {
      loggy.app('Create file $newFilePath exception', e, st);
      showMessage(S.current.messageNewFileError(newFilePath));
      return null;
    }

    return createFileResult.result!;
  }

  Future<void> moveEntry({ required String source, required String destination }) async {
    update((state) { state.isLoading = true; });

    try {
      final moveEntryResult = await repo.moveEntry(source, destination);
      if (moveEntryResult.errorMessage.isNotEmpty) {
        loggy.app('Move entry from ${source} to ${destination} failed:\n${moveEntryResult.errorMessage}');
      }
    } catch (e, st) {
      loggy.app('Move entry from ${source} to ${destination} exception', e, st);
    }

    await _refreshFolder();
  }

  Future<void> deleteFile(String filePath) async {
    update((state) { state.isLoading = true; });

    try{
      final deleteFileResult = await repo.deleteFile(filePath);
      if (deleteFileResult.errorMessage.isNotEmpty)
      {
        loggy.app('Delete file $filePath failed');
      }
    } catch (e, st) {
      loggy.app('Delete file $filePath exception', e, st);
    }

    await _refreshFolder();
  }

  Future<void> getContent() async {
    await _refreshFolder();
  }

  int _next_id = 0;
  Future<void> _refreshFolder() async {
    // TODO: Only increment the id when the content changes.
    int id = _next_id;
    _next_id += 1;

    final path = repo.currentFolder.path;
    bool errorShown = false;

    try {
      while (repo.accessMode != oui.AccessMode.blind) {
        bool success = await repo.currentFolder.refresh();

        if (success) break;
        if (repo.currentFolder.isRoot()) break;

        repo.currentFolder.goUp();

        if (!errorShown) {
          errorShown = true;
          showMessage(S.current.messageErrorCurrentPathMissing(path));
        }
      }
    }
    catch (e) {
      showMessage(e.toString());
    }

    update((state) { state.isLoading = false; });
  }

  void showMessage(String message) {
    update((state) { state.messages.add(message); });
  }
}
