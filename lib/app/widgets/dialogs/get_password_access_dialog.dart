import 'package:flutter/material.dart';
import 'package:ouisync/ouisync.dart';

import '../../../generated/l10n.dart';
import '../../pages/repo_reset_access.dart';
import '../../widgets/dialogs/actions_dialog.dart';
import '../../utils/utils.dart'
    show
        AccessModeLocalizedExtension,
        AppLogger,
        Constants,
        Dialogs,
        Dimensions,
        Fields,
        LocalAuth,
        MasterKey,
        Settings,
        validateNoEmptyMaybeRegExpr;
import '../../models/models.dart'
    show AuthModeKeyStoredOnDevice, RepoLocation, SecretKeyOrigin;
import '../../models/access_mode.dart';
import '../../cubits/cubits.dart' show RepoCubit;
import '../widgets.dart'
    show NegativeButton, PositiveButton, LinkStyleAsyncButton;

class GetPasswordAccessDialog extends StatefulWidget {
  GetPasswordAccessDialog({
    required this.repoCubit,
    required this.settings,
  });

  final RepoCubit repoCubit;
  final Settings settings;

  static Future<Access?> show(
    BuildContext topContext,
    RepoCubit repoCubit,
    Settings settings,
  ) async {
    return await showDialog<Access>(
      context: topContext,
      builder: (BuildContext dialogContext) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ActionsDialog(
            title: S.current.messageUnlockRepository(repoCubit.name),
            body: GetPasswordAccessDialog(
              repoCubit: repoCubit,
              settings: settings,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<GetPasswordAccessDialog> createState() => _State();
}

class _State extends State<GetPasswordAccessDialog> with AppLogger {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool passwordInvalid = false;

  @override
  Widget build(BuildContext context) => Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPasswordField(context),
          _buildIDontHaveLocalPasswordButton(context),
          Fields.dialogActions(buttons: _buildActions(context)),
        ],
      ));

  Widget _buildIDontHaveLocalPasswordButton(BuildContext context) {
    return LinkStyleAsyncButton(
        key: Key('enter-repo-reset-screen'),
        text: "\n${S.current.actionIDontHaveALocalPassword}\n",
        onTap: () async {
          if (!await LocalAuth.authenticateIfPossible(
              context, S.current.messagePleaseAuthenticate)) {
            return;
          }

          final access = await RepoResetAccessPage.show(
              BlindAccess(), context, widget.repoCubit, widget.settings);

          Navigator.of(context).pop(access);
        });
  }

  Widget _buildPasswordField(BuildContext context) => Fields.formTextField(
        context: context,
        controller: passwordController,
        obscureText: obscurePassword,
        labelText: S.current.labelTypePassword,
        hintText: S.current.messageRepositoryPassword,
        errorText: passwordInvalid ? S.current.messageUnlockRepoFailed : null,
        suffixIcon: Fields.actionIcon(
          Icon(
            obscurePassword
                ? Constants.iconVisibilityOn
                : Constants.iconVisibilityOff,
            size: Dimensions.sizeIconSmall,
          ),
          color: Colors.black,
          onPressed: () => setState(() {
            obscurePassword = !obscurePassword;
          }),
        ),
        validator: validateNoEmptyMaybeRegExpr(
          emptyError: S.current.messageErrorRepositoryPasswordValidation,
        ),
        autofocus: true,
      );

  List<Widget> _buildActions(context) => [
        NegativeButton(
          text: S.current.actionCancel,
          onPressed: () async => await Navigator.of(context).maybePop(null),
        ),
        PositiveButton(
          text: S.current.actionUnlock,
          onPressed: () => _onSubmit(context),
        )
      ];

  Future<void> _onSubmit(BuildContext context) async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    if (passwordController.text.isEmpty) {
      return;
    }

    final password = LocalPassword(passwordController.text);

    final AccessMode accessMode;

    if (false) {
      // TODO: Find out why if we use `executefutureWithLoadingDialog` this
      // dialog alwayrs returns `null`. Seems to also be related to the dialog
      // using a `Form`.
      accessMode = await Dialogs.executeFutureWithLoadingDialog(
        context,
        widget.repoCubit.getSecretAccessMode(password),
      );
    } else {
      accessMode = await widget.repoCubit.getSecretAccessMode(password);
    }

    Access access;

    switch (accessMode) {
      case AccessMode.blind:
        setState(() {
          passwordInvalid = true;
        });
        return;
      case AccessMode.read:
        access = ReadAccess(password);
      case AccessMode.write:
        access = WriteAccess(password);
    }

    setState(() {
      passwordInvalid = false;
    });

    Navigator.of(context).pop(access);
  }
}
