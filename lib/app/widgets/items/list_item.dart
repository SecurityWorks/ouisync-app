import 'package:flutter/material.dart';

import '../../cubits/cubits.dart';
import '../../models/models.dart';
import '../../utils/utils.dart';
import '../widgets.dart';

class ListItem extends StatelessWidget with AppLogger {
  const ListItem({
    super.key,
    required this.reposCubit,
    required this.repoCubit,
    required this.itemData,
    required this.mainAction,
    required this.verticalDotsAction,
  });

  final ReposCubit? reposCubit;
  final RepoCubit? repoCubit;
  final BaseItem itemData;
  final Function mainAction;
  final Function verticalDotsAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
          onTap: () => mainAction.call(),
          splashColor: Colors.blue,
          child: Container(
            padding: Dimensions.paddingListItem,
            child: _buildItem(),
          )),
      color: Colors.white,
    );
  }

  Widget _buildItem() {
    final data = itemData;

    if (data is RepoItem) {
      return _buildRepoItem(data);
    }

    if (data is FileItem) {
      return _buildFileItem(data);
    }

    if (data is FolderItem) {
      return _buildFolderItem(data);
    }

    if (data is RepoMissingItem) {
      return _buildRepoMissingItem(data);
    }

    assert(false,
        "Item must be either RepoItem, FileItem, FolderItem, or RepoMissingItem");
    return SizedBox.shrink();
  }

  Widget _buildRepoItem(RepoItem repoItem) {
    assert(reposCubit != null, "Repository cubit object for RepoItem is null");

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
            flex: 1,
            child: IconButton(
              icon: Icon(Fields.accessModeIcon(repoItem.accessMode),
                  size: Dimensions.sizeIconAverage),
              color: Constants.folderIconColor,
              padding: EdgeInsets.all(0.0),
              onPressed: () =>
                  reposCubit?.get(repoItem.location)?.cubit?.lock(),
            )),
        Expanded(
            flex: 9,
            child: Padding(
                padding: Dimensions.paddingItem,
                child: RepoDescription(repoData: repoItem))),
        _getVerticalMenuAction(false)
      ],
    );
  }

  Widget _buildFileItem(FileItem fileData) {
    assert(repoCubit != null, "Repository object for FileItem is null");

    if (repoCubit == null) {
      return SizedBox.shrink();
    }

    final uploadJob = repoCubit!.state.uploads[fileData.path];
    final downloadJob = repoCubit!.state.downloads[fileData.path];

    final isUploading = uploadJob != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(flex: 1, child: FileIconAnimated(downloadJob)),
        Expanded(
            flex: 9,
            child: Padding(
                padding: Dimensions.paddingItem,
                child: FileDescription(repoCubit!, fileData, uploadJob))),
        _getVerticalMenuAction(isUploading)
      ],
    );
  }

  Widget _buildFolderItem(FolderItem folderItem) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const Expanded(
            flex: 1,
            child: Icon(Icons.folder_rounded,
                size: Dimensions.sizeIconAverage,
                color: Constants.folderIconColor)),
        Expanded(
            flex: 9,
            child: Padding(
                padding: Dimensions.paddingItem,
                child: FolderDescription(folderData: itemData))),
        _getVerticalMenuAction(false)
      ],
    );
  }

  Widget _buildRepoMissingItem(RepoMissingItem repoMissingItem) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
            flex: 1,
            child: Icon(Icons.error_outline_rounded,
                size: Dimensions.sizeIconAverage,
                color: Constants.folderIconColor)),
        Expanded(
            flex: 9,
            child: Padding(
                padding: Dimensions.paddingItem,
                child: RepoMissing(repoData: repoMissingItem))),
        _getDeleteMissingRepoAction()
      ],
    );
  }

  Widget _getVerticalMenuAction(bool isUploading) {
    return IconButton(
        icon:
            const Icon(Icons.more_vert_rounded, size: Dimensions.sizeIconSmall),
        onPressed: isUploading ? null : () async => await verticalDotsAction());
  }

  Widget _getDeleteMissingRepoAction() {
    return IconButton(
        icon: const Icon(Icons.delete,
            size: Dimensions.sizeIconMicro, color: Constants.dangerColor),
        onPressed: () async => await verticalDotsAction());
  }
}
