import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ouisync/ouisync.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../generated/l10n.dart';
import '../models/auth_mode.dart';
import '../models/access_mode.dart';
import '../cubits/cubits.dart' show RepoCubit, RepoState;
import '../utils/utils.dart'
    show
        AppThemeExtension,
        Constants,
        Dimensions,
        Fields,
        LocalAuth,
        Settings,
        ThemeGetter;
import '../widgets/widgets.dart'
    show ActionsDialog, DirectionalAppBar, PositiveButton, NegativeButton;

class RepoResetAccessPage extends StatefulWidget {
  final RepoCubit repo;
  final Access startAccess;
  final Settings settings;
  final _Jobs _jobs;

  // Returns `null` if nothing changes (e.g. the user presses the back button
  // before submitting any changes).
  static Future<Access> show(Access startAccess, BuildContext context,
      RepoCubit repo, Settings settings) async {
    final route = MaterialPageRoute<Access>(
        builder: (context) =>
            RepoResetAccessPage._(repo, startAccess, settings));

    Navigator.push(context, route);

    return (await route.popped)!;
  }

  RepoResetAccessPage._(
    this.repo,
    this.startAccess,
    this.settings,
  ) : _jobs = _Jobs();

  @override
  State<RepoResetAccessPage> createState() =>
      RepoResetAccessPageState(startAccess);
}

class RepoResetAccessPageState extends State<RepoResetAccessPage> {
  _TokenStatus tokenStatus;
  Access currentAccess;

  RepoResetAccessPageState(this.currentAccess)
      : tokenStatus = _InvalidTokenStatus(_InvalidTokenType.empty);

  bool get hasPendingChanges => tokenStatus is _SubmitableTokenStatus;

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, currentAccess);
      },
      child: Scaffold(
        appBar: DirectionalAppBar(title: Text("Reset repository access")),
        body: BlocBuilder<RepoCubit, RepoState>(
          bloc: widget.repo,
          builder: (context, repoState) {
            return Column(
              children: [
                Expanded(
                    child: ListView(children: [
                  _buildRepoNameInfo(),
                  _buildCurrentAccessModeInfo(),
                  _buildAuthMethodInfo(),
                  _buildTokenInputWidget(),
                  _buildTokenInfo(),
                  _buildActionInfo(),
                ])),
                Container(
                  // TODO: Constants should be defined globally.
                  padding: EdgeInsetsDirectional.symmetric(vertical: 18.0),
                  child: _buildSubmitButton(),
                ),
              ],
            );
          },
        ),
      ));

  // -----------------------------------------------------------------

  Widget _buildInfoWidget(
      {required String title, required String subtitle, String? warning}) {
    final dangerStyle = context.theme.appTextStyle.bodySmall
        .copyWith(color: Constants.dangerColor);

    return ListTile(
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(subtitle),
          if (warning != null)
            SelectableText("⚠️ $warning", style: dangerStyle),
        ],
      ),
    );
  }

  Widget _buildRepoNameInfo() {
    return ListTile(
      title: Text(S.current.repoResetRepoNameLabel),
      subtitle: Text(widget.repo.name),
    );
  }

  Widget _buildCurrentAccessModeInfo() {
    String subtitle;

    switch (currentAccess) {
      case BlindAccess():
        subtitle = "Blind or locked";
      case ReadAccess():
        subtitle = "Read";
      case WriteAccess():
        subtitle = "Write";
    }

    return _buildInfoWidget(
      title: S.current.repoResetAccessTypeLabel,
      subtitle: subtitle,
    );
  }

  Widget _buildAuthMethodInfo() {
    String subtitle;
    String? warning;

    switch (widget.repo.state.authMode) {
      case AuthModeBlindOrManual():
        subtitle = "Blind or locked behind a local password";
        warning = "The application cannot tell the difference";
      case AuthModePasswordStoredOnDevice():
        subtitle = "Password stored on device";
        warning = null;
      case AuthModeKeyStoredOnDevice authMode:
        subtitle = switch (authMode.secureWithBiometrics) {
          false => "Key is stored on this device.",
          true =>
            "Key is stored on this device and additional verification is needed to open the repository.",
        };
        warning = null;
    }

    return _buildInfoWidget(
      title: S.current.repoResetAuthInfoLabel,
      subtitle: subtitle,
      warning: warning,
    );
  }

  Widget _buildTokenInfo() {
    final info = switch (tokenStatus) {
      _SubmitableTokenStatus status =>
        _capitalized(status.inputToken.accessMode.localized),
      _SubmittedTokenStatus status =>
        _capitalized(status.inputToken.accessMode.localized),
      _NonMatchingTokenStatus status =>
        _capitalized(status.inputToken.accessMode.localized),
      _InvalidTokenStatus status => switch (status.type) {
          _InvalidTokenType.empty => "",
          _InvalidTokenType.malformed => "Invalid",
        },
    };

    return _buildInfoWidget(
      title: S.current.repoResetTokenTypeLabel,
      subtitle: info,
    );
  }

  // Capitalize first letter of a string
  String _capitalized(String str) {
    return str.length > 0
        ? '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}'
        : str;
  }

  Widget _buildActionInfo() {
    final (action, warning) = switch (tokenStatus) {
      _SubmitableTokenStatus status => _buildTokenStatusSubmitable(status),
      _SubmittedTokenStatus status => _buildTokenStatusSubmitted(status),
      _InvalidTokenStatus status => _buildTokenStatusInvalid(status),
      _NonMatchingTokenStatus status => _buildTokenStatusNonMatching(status),
    };

    return _buildInfoWidget(
      title: S.current.repoResetActionInfoLabel,
      subtitle: action,
      warning: warning,
    );
  }

  // -----------------------------------------------------------------

  (String, String?) _buildTokenStatusSubmitable(_SubmitableTokenStatus status) {
    final repoAccessMode = widget.repo.state.accessMode;
    final tokenAccessMode = status.inputToken.accessMode;

    final String info;
    String? warning;

    switch ((repoAccessMode, tokenAccessMode)) {
      case (AccessMode.blind, AccessMode.blind):
        info = "The repository will become blind.";
        warning =
            "This repository may have read or write access locked behind a local password. If so, unlocking will not be possible after this action is executed.";
      case (AccessMode.read, AccessMode.read):
      case (AccessMode.write, AccessMode.write):
        info =
            "No action will be performed because the token and repository access are the same.";
      case (AccessMode.blind, AccessMode.read):
        info = "The repository will become read only.";
        warning =
            "This repository may have write access locked behind a local password. If so, unlocking for writing will not be possible after this action is executed.";
      case (AccessMode.blind, AccessMode.write):
      case (AccessMode.read, AccessMode.write):
        info = "The repository will gain write access.";
      case (AccessMode.read, AccessMode.blind):
        info = "The repository will lose its read access.";
        warning =
            "This action is irreversible without a read or write token link.";
      case (AccessMode.write, AccessMode.read):
        info = "The repository will lose its write access.";
        warning = "This action is irreversible without a write token link.";
      case (AccessMode.write, AccessMode.blind):
        info = "The repository will lose its read and write access.";
        warning = "This action is irreversible without a write token link.";
    }

    return (info, warning);
  }

  (String, String?) _buildTokenStatusInvalid(_InvalidTokenStatus status) {
    final String info;
    switch (status.type) {
      case _InvalidTokenType.empty:
        info = "Please provide a valid token link to determine the action.";
      case _InvalidTokenType.malformed:
        info = "The token link is invalid.";
    }
    return (info, null);
  }

  (String, String?) _buildTokenStatusNonMatching(
      _NonMatchingTokenStatus status) {
    return (
      "No action can be performed because the token does not correspond to this repository.",
      null
    );
  }

  (String, String?) _buildTokenStatusSubmitted(_SubmittedTokenStatus status) {
    return (
      "No action will be performed because the token has already been submitted.",
      null
    );
  }

  // -----------------------------------------------------------------

  Widget _buildTokenInputWidget() => ListTile(
          title: Fields.formTextField(
        key: Key('token-input'), // Used in tests
        context: context,
        labelText: S.current.labelRepositoryLink,
        hintText: S.current.messageRepositoryToken,
        suffixIcon: const Icon(Icons.key_rounded),
        onChanged: (input) {
          widget._jobs.addJob(() async {
            final inputToken = await parseTokenInput(input);
            _updateTokenStatusOnTokenInputChange(inputToken);
          });
        },
      ));

  // -----------------------------------------------------------------

  Widget _buildSubmitButton() {
    Future<void> Function()? onPressed;

    switch (tokenStatus) {
      case _SubmitableTokenStatus valid:
        onPressed = () async {
          if (await _confirmUpdateDialog()) {
            await _submit(valid.inputToken);
          }
        };
      default:
    }

    return Fields.inPageAsyncButton(
        key: Key('repo-reset-submit'),
        text: S.current.actionUpdate,
        onPressed: onPressed);
  }

  Future<bool> _confirmUpdateDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => ActionsDialog(
        title: S.current.repoResetConfirmUpdateTitle,
        body: ListBody(
          children: <Widget>[
            const SizedBox(height: 20.0),
            Text(
              S.current.repoResetConfirmUpdateMessage,
              style: context.theme.appTextStyle.bodyMedium
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20.0),
            Fields.dialogActions(
              buttons: [
                NegativeButton(
                  text: S.current.actionCancel,
                  onPressed: () async =>
                      await Navigator.of(context).maybePop(false),
                ),
                PositiveButton(
                  text: S.current.actionYes,
                  isDangerButton: true,
                  onPressed: () async =>
                      await Navigator.of(context).maybePop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _submit(_ValidInputToken input) async {
    final repo = widget.repo;

    // This unlocks or locks the repository in the `AccessMode` of to the token.
    await repo.resetCredentials(input.token);

    // Generate new local secret which will unlock the repo in the future.
    final newLocalSecret = LocalSecretKeyAndSalt.random();
    AccessChange readAccessChange;
    AccessChange writeAccessChange;

    switch (input.accessMode) {
      case AccessMode.blind:
        readAccessChange = DisableAccess();
        writeAccessChange = DisableAccess();
      case AccessMode.read:
        readAccessChange = EnableAccess(newLocalSecret);
        writeAccessChange = DisableAccess();
      case AccessMode.write:
        readAccessChange = DisableAccess();
        writeAccessChange = EnableAccess(newLocalSecret);
    }

    // Encrypt the global secret from the token using the `newLocalSecret` and
    // store it (the encrypted global secret) in the repo.
    await repo.setAccess(read: readAccessChange, write: writeAccessChange);

    final AuthMode newAuthMode;
    final Access currentAccess;

    if (readAccessChange is EnableAccess || writeAccessChange is EnableAccess) {
      // Use a reasonably secure and convenient auth mode, the user can go to
      // the security screen to change it later.
      newAuthMode = await AuthModeKeyStoredOnDevice.encrypt(
        widget.settings.masterKey,
        newLocalSecret.key,
        keyOrigin: SecretKeyOrigin.random,
        // TODO: This isn't really correct, biometric (or other, e.g. pin) should be
        // available whenever the OS supports it **and** when the repository DB files
        // are stored inside a FS directory that the system protects from other app
        // access.
        secureWithBiometrics: await LocalAuth.canAuthenticate(),
      );

      if (writeAccessChange is EnableAccess) {
        currentAccess = WriteAccess(newLocalSecret.key);
      } else {
        currentAccess = ReadAccess(newLocalSecret.key);
      }
    } else {
      newAuthMode = AuthModeBlindOrManual();
      currentAccess = BlindAccess();
    }

    // Store the auth mode inside the repository so it can be the next time
    // after it's locked (e.g. after the app restart).
    await repo.setAuthMode(newAuthMode);

    setState(() {
      tokenStatus = _SubmittedTokenStatus(input);
      this.currentAccess = currentAccess;
    });
  }

  // -----------------------------------------------------------------

  void _updateTokenStatusOnTokenInputChange(_InputToken token) {
    final repoState = widget.repo.state;
    final _TokenStatus newStatus;

    switch (token) {
      case _InvalidInputToken token:
        newStatus = _InvalidTokenStatus(token.type);
      case _ValidInputToken token:
        if (repoState.infoHash != token.infoHash) {
          newStatus = _NonMatchingTokenStatus(token);
        } else {
          newStatus = _SubmitableTokenStatus(token);
        }
    }

    if (mounted) {
      setState(() {
        tokenStatus = newStatus;
      });
    }
  }

  // -----------------------------------------------------------------

  Future<_InputToken> parseTokenInput(String input) async {
    if (input.isEmpty) {
      return _InvalidInputToken.empty();
    }

    ShareToken token;

    try {
      token = await ShareToken.fromString(widget.repo.session, input);
    } catch (e) {
      return _InvalidInputToken.malformed();
    }

    final accessMode = await token.mode;
    final infoHash = await token.infoHash;

    return _ValidInputToken(token, accessMode, infoHash);
  }
}

//--------------------------------------------------------------------

enum _InvalidTokenType { empty, malformed }

//--------------------------------------------------------------------

sealed class _TokenStatus {}

class _SubmitableTokenStatus implements _TokenStatus {
  final _ValidInputToken inputToken;
  _SubmitableTokenStatus(this.inputToken);
}

class _SubmittedTokenStatus implements _TokenStatus {
  final _ValidInputToken inputToken;
  _SubmittedTokenStatus(this.inputToken);
}

class _NonMatchingTokenStatus implements _TokenStatus {
  final _ValidInputToken inputToken;
  _NonMatchingTokenStatus(this.inputToken);
}

class _InvalidTokenStatus implements _TokenStatus {
  final _InvalidTokenType type;
  _InvalidTokenStatus(this.type);
}

//--------------------------------------------------------------------

sealed class _InputToken {}

class _ValidInputToken implements _InputToken {
  final ShareToken token;
  final AccessMode accessMode;
  final String infoHash;

  _ValidInputToken(this.token, this.accessMode, this.infoHash);
}

class _InvalidInputToken implements _InputToken {
  final _InvalidTokenType type;

  _InvalidInputToken(this.type);

  factory _InvalidInputToken.empty() =>
      _InvalidInputToken(_InvalidTokenType.empty);
  factory _InvalidInputToken.malformed() =>
      _InvalidInputToken(_InvalidTokenType.malformed);
}

//--------------------------------------------------------------------

// Job queue with the maximum size of two: One running and one pending.
class _Jobs {
  Future<void>? runningJob;
  Future<void> Function()? pendingJob;

  _Jobs();

  void addJob(Future<void> Function() job) {
    if (runningJob == null) {
      runningJob = () async {
        await job();

        runningJob = null;

        final pj = pendingJob;
        pendingJob = null;

        if (pj != null) {
          addJob(pj);
        }
      }();
    } else {
      pendingJob = job;
    }
  }
}
