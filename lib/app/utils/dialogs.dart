import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ouisync_app/app/models/models.dart';
import 'package:ouisync_plugin/ouisync_plugin.dart';

import '../bloc/blocs.dart';
import '../controls/controls.dart';
import '../pages/pages.dart';
import 'utils.dart';

abstract class Dialogs {
  static Widget floatingActionsButtonMenu(
    Bloc bloc,
    Session session,
    BuildContext context,
    AnimationController controller,
    String parentPath,
    Map<String, IconData> actions,
    String actionsDialog,
    Color backgroundColor,
    Color foregroundColor,
  ) { 
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: new List.generate(actions.length, (int index) {
        String actionName = actions.keys.elementAt(index);

        Widget child = new Container(
          height: 70.0,
          width: 156.0,
          alignment: FractionalOffset.topCenter,
          child: new ScaleTransition(
            scale: new CurvedAnimation(
              parent: controller,
              curve: new Interval(
                0.0,
                1.0 - index / actions.length / 2.0,
                curve: Curves.easeOut
              ),
            ),
            child: new FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              label: Text(actionName),
              icon: Icon(actions[actionName]),
              onPressed: () async { 
                late Future<dynamic> dialog;
                switch (actionsDialog) {
                  case flagRepoActionsDialog:
                  /// Only one repository allowed for the MVP
                    // dialog = repoActionsDialog(context, bloc as RepositoryBloc, session, actionName);
                    break;

                  case flagFolderActionsDialog:
                    dialog = folderActionsDialog(context, bloc as DirectoryBloc, session, parentPath, actionName);
                    break;

                  case flagReceiveShareActionsDialog:
                    dialog = receiveShareActionsDialog(context, bloc as DirectoryBloc, session, parentPath, actionName);
                    break;

                  default:
                    return;
                }

                bool resultOk = await dialog;
                if (resultOk) {
                  controller.reset(); 
                }
              },
            ),
          ),
        );
        return child;
      }).toList()..add(
        new FloatingActionButton.extended(
          heroTag: null,
          label: Text('Actions'),
          icon: new AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? child) {
              return new Transform(
                transform: new Matrix4.rotationZ(controller.value * 0.5 * math.pi),
                alignment: FractionalOffset.center,
                child: new Icon(controller.isDismissed ? Icons.pending : Icons.close),
              );
            },
          ),
          onPressed: () {
            controller.isDismissed
            ? controller.forward()
            : controller.reverse();
          },
        ),
      ),
    );
  }

  static Future<dynamic> repoActionsDialog(BuildContext context, RepositoryBloc repositoryBloc, Session session, String action) {
    String dialogTitle = '';
    Widget? actionBody;

    switch (action) {
      case actionNewRepo:
        dialogTitle = 'New Repository';
        actionBody = AddRepoPage(
          session: session,
          title: 'New Repository',
        );
        break;
    }

    return _actionDialog(
      context,
      dialogTitle,
      actionBody
    );
  }

  static Future<dynamic> folderActionsDialog(BuildContext context, DirectoryBloc directoryBloc, Session session, String parentPath, String action) {
    String dialogTitle = '';
    Widget? actionBody;

    switch (action) {
      case actionNewFolder:
        dialogTitle = 'New Folder';
        actionBody = AddFolderPage(
          session: session,
          path: parentPath,
          bloc: directoryBloc,
          title: 'New Folder',
        );
        break;
      
      case actionNewFile:
        dialogTitle = 'Add File';
        actionBody = AddFilePage(
          session: session,
          parentPath: parentPath,
          bloc: directoryBloc,
          title: 'Add File',
        );
        break;
        
    }

    return _actionDialog(
      context,
      dialogTitle,
      actionBody
    );
  }

  static Future<dynamic> receiveShareActionsDialog(BuildContext context, DirectoryBloc directoryBloc, Session session, String parentPath, String action) {
    String dialogTitle = '';
    Widget? actionBody;

    switch (action) {
      case actionNewFile:
        dialogTitle = 'Add File';
        actionBody = AddFilePage(
          session: session,
          parentPath: parentPath,
          bloc: directoryBloc,
          title: 'Add File',
        );
        break;
      case actionNewFolder:
        dialogTitle = 'New Folder';
        actionBody = AddFolderPage(
          session: session,
          path: parentPath,
          bloc: directoryBloc,
          title: 'New Folder',
        );
        break;
    }

    return _actionDialog(
      context,
      dialogTitle,
      actionBody
    );
  }

  static _actionDialog(BuildContext context, String dialogTitle, Widget? actionBody) => showDialog(
    context: context,
    builder: (BuildContext context) {
      return ActionsDialog(
        title: dialogTitle,
        body: actionBody,
      );
    }
  );

  static filePopupMenu(Session session, Bloc bloc, Map<String, BaseItem> fileMenuOptions) {
    return PopupMenuButton(
      itemBuilder: (context) {
        return fileMenuOptions.entries.map((e) => 
          PopupMenuItem(
              child: Text(e.key),
              value: e,
          ) 
        ).toList();
      },
      onSelected: (value) {
        final data = (value as MapEntry<String, BaseItem>).value;
        bloc.add(
          DeleteFile(
            session: session,
            parentPath: extractParentFromPath(data.path),
            filePath: data.path
          )
        );
      }
    );
  }

  static Future<void> showRequestStoragePermissionDialog(BuildContext context) async {
    Text title = Text('OuiSync - Storage permission needed');
    Text message = Text('Ouisync need access to the phone storage to operate properly.\n\nPlease accept the permissions request');
    
    await _permissionDialog(context, title, message);
  }

  static Future<void> showStoragePermissionNotGrantedDialog(BuildContext context) async {
    Text title = Text('OuiSync - Storage permission not granted');
    Text message = Text('Ouisync need access to the phone storage to operate properly.\n\nWithout this permission the app won\'t work.');
    
    await _permissionDialog(context, title, message);
  }

  static Future<void> _permissionDialog(BuildContext context, Widget title, Widget message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: title,
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget> [
               message, 
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }
    );
  }
}