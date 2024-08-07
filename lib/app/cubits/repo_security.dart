import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/auth_mode.dart';
import '../models/local_secret.dart';
import '../utils/local_auth.dart';
import '../utils/log.dart';
import '../utils/master_key.dart';
import '../utils/option.dart';
import '../utils/password_hasher.dart';
import 'repo.dart';

class RepoSecurityState {
  RepoSecurityState({
    required this.oldLocalSecretMode,
    required this.oldLocalSecret,
    SecretKeyOrigin? origin,
    bool? store,
    bool? secureWithBiometrics,
    this.localPassword = const None(),
    this.isBiometricsAvailable = false,
  })  : origin = origin ?? oldLocalSecretMode.origin,
        store = store ?? _initialStore(oldLocalSecretMode),
        secureWithBiometrics = secureWithBiometrics ??
            oldLocalSecretMode.store.isSecuredWithBiometrics;

  final LocalSecretMode oldLocalSecretMode;
  final LocalSecret oldLocalSecret;
  final SecretKeyOrigin origin;
  final bool store;
  final bool secureWithBiometrics;
  final Option<LocalPassword> localPassword;
  final bool isBiometricsAvailable;

  RepoSecurityState copyWith({
    LocalSecretMode? oldLocalSecretMode,
    LocalSecret? oldLocalSecret,
    SecretKeyOrigin? origin,
    bool? store,
    bool? secureWithBiometrics,
    Option<LocalPassword>? localPassword,
    bool? isBiometricsAvailable,
  }) =>
      RepoSecurityState(
        oldLocalSecretMode: oldLocalSecretMode ?? this.oldLocalSecretMode,
        oldLocalSecret: oldLocalSecret ?? this.oldLocalSecret,
        origin: origin ?? this.origin,
        store: store ?? this.store,
        secureWithBiometrics: secureWithBiometrics ?? this.secureWithBiometrics,
        localPassword: localPassword ?? this.localPassword,
        isBiometricsAvailable:
            isBiometricsAvailable ?? this.isBiometricsAvailable,
      );

  // If the secret is already stored and is not random then we can keep using it and only change
  // the other properties. So in those cases putting in a new password is not required.
  bool get isLocalPasswordRequired => switch (oldLocalSecretMode) {
        LocalSecretMode.manual ||
        LocalSecretMode.randomStored ||
        LocalSecretMode.randomSecuredWithBiometrics =>
          true,
        LocalSecretMode.manualStored ||
        LocalSecretMode.manualSecuredWithBiometrics =>
          false,
      };

  bool get isSecureWithBiometricsEnabled =>
      isBiometricsAvailable && (origin == SecretKeyOrigin.random || store);

  bool get isValid => newLocalSecretInput != null;

  bool get hasPendingChanges =>
      origin != oldLocalSecretMode.origin ||
      store != oldLocalSecretMode.store.isStored ||
      secureWithBiometrics !=
          oldLocalSecretMode.store.isSecuredWithBiometrics ||
      localPassword is Some;

  LocalSecretInput? get newLocalSecretInput =>
      switch ((localPassword, origin, store, secureWithBiometrics)) {
        (Some(value: final password), SecretKeyOrigin.manual, false, _) =>
          LocalSecretManual(
            password: password,
            store: SecretKeyStore.notStored,
          ),
        (Some(value: final password), SecretKeyOrigin.manual, true, false) =>
          LocalSecretManual(
            password: password,
            store: SecretKeyStore.stored,
          ),
        (Some(value: final password), SecretKeyOrigin.manual, true, true) =>
          LocalSecretManual(
            password: password,
            store: SecretKeyStore.securedWithBiometrics,
          ),
        (None(), SecretKeyOrigin.manual, _, _) => null,
        (_, SecretKeyOrigin.random, _, false) =>
          LocalSecretRandom(secureWithBiometrics: false),
        (_, SecretKeyOrigin.random, _, true) =>
          LocalSecretRandom(secureWithBiometrics: true),
      };

  LocalPassword? get newLocalPassword => switch ((localPassword, origin)) {
        (Some(value: final value), SecretKeyOrigin.manual) => value,
        (None(), SecretKeyOrigin.manual) || (_, SecretKeyOrigin.random) => null,
      };

  @override
  String toString() => '$runtimeType(origin: $origin, store: $store, ...)';
}

class RepoSecurityCubit extends Cubit<RepoSecurityState> with AppLogger {
  RepoSecurityCubit({
    required LocalSecretMode oldLocalSecretMode,
    LocalSecret? oldLocalSecret,
  }) : super(RepoSecurityState(
          oldLocalSecretMode: oldLocalSecretMode,
          oldLocalSecret: oldLocalSecret ?? LocalSecretKey.random(),
        )) {
    unawaited(_init());
  }

  Future<void> _init() async {
    final canAuthenticate = await LocalAuth.canAuthenticate();
    if (!isClosed) {
      emit(state.copyWith(
        isBiometricsAvailable: canAuthenticate,
      ));
    }
  }

  void setOrigin(SecretKeyOrigin value) {
    emit(state.copyWith(origin: value));
  }

  void setStore(bool value) {
    emit(state.copyWith(store: value));
  }

  void setSecureWithBiometrics(bool value) {
    emit(state.copyWith(secureWithBiometrics: value));
  }

  void setLocalPassword(String? value) {
    emit(state.copyWith(
      localPassword: value != null ? Some(LocalPassword(value)) : None(),
    ));
  }

  Future<bool> apply(
    RepoCubit repoCubit, {
    required PasswordHasher passwordHasher,
    required MasterKey masterKey,
  }) async {
    final newLocalSecretInput = state.newLocalSecretInput;
    if (newLocalSecretInput == null) {
      return false;
    }

    final (newLocalSecret, newAuthMode) = await _computeLocalSecretAndAuthMode(
      repoCubit,
      newLocalSecretInput,
      passwordHasher,
      masterKey,
    );

    // Keep the old auth mode in case we need to revert to it on error.
    final oldAuthMode = repoCubit.state.authMode;

    // Save the new auth mode
    try {
      await repoCubit.setAuthMode(newAuthMode);
      emit(state.copyWith(oldLocalSecretMode: newAuthMode.localSecretMode));
      loggy.debug('Repo auth mode updated: $newAuthMode');
    } catch (e, st) {
      loggy.error(
        'Failed to update repo auth mode:',
        e,
        st,
      );

      return false;
    }

    // Save the new local secret, if it changed
    if (newLocalSecret != null) {
      try {
        await repoCubit.setLocalSecret(
          oldSecret: state.oldLocalSecret,
          newSecret: newLocalSecret,
        );
        emit(state.copyWith(oldLocalSecret: newLocalSecret.toLocalSecret()));
        loggy.debug('Repo local secret updated');
      } catch (e, st) {
        loggy.error(
          'Failed to update repo local secret:',
          e,
          st,
        );

        // Revert to the old auth mode
        await repoCubit.setAuthMode(oldAuthMode);

        return false;
      }
    }

    return true;
  }

  //// DEBUG
  //@override
  //void onChange(Change<RepoSecurityState> change) {
  //  super.onChange(change);
  //  print('${change.currentState} -> ${change.nextState}');
  //}
}

// We want store to be explicitly opt-in so the switch must be initially off even if the
// initial origin is random which is implicitly stored.
bool _initialStore(LocalSecretMode localSecretMode) =>
    switch (localSecretMode) {
      LocalSecretMode.manualStored ||
      LocalSecretMode.manualSecuredWithBiometrics =>
        true,
      LocalSecretMode.manual ||
      LocalSecretMode.randomStored ||
      LocalSecretMode.randomSecuredWithBiometrics =>
        false
    };

Future<(LocalSecretKeyAndSalt?, AuthMode)> _computeLocalSecretAndAuthMode(
  RepoCubit repoCubit,
  LocalSecretInput localSecretInput,
  PasswordHasher passwordHasher,
  MasterKey masterKey,
) async {
  switch (localSecretInput) {
    case LocalSecretManual():
      final localSecretKey =
          await passwordHasher.hashPassword(localSecretInput.password);

      final authMode = switch (localSecretInput.store) {
        SecretKeyStore.notStored => AuthModeBlindOrManual(),
        SecretKeyStore.stored ||
        SecretKeyStore.securedWithBiometrics =>
          await AuthModeKeyStoredOnDevice.encrypt(
            masterKey,
            localSecretKey.key,
            keyOrigin: SecretKeyOrigin.manual,
            secureWithBiometrics:
                localSecretInput.store == SecretKeyStore.securedWithBiometrics,
          ),
      };

      return (localSecretKey, authMode);
    case LocalSecretRandom():
      final oldAuthMode = repoCubit.state.authMode;

      switch (oldAuthMode) {
        case AuthModeKeyStoredOnDevice(keyOrigin: SecretKeyOrigin.random):
          final authMode = oldAuthMode.copyWith(
            secureWithBiometrics: localSecretInput.secureWithBiometrics,
          );

          return (null, authMode);
        case AuthModeKeyStoredOnDevice(keyOrigin: SecretKeyOrigin.manual):
        case AuthModePasswordStoredOnDevice():
        case AuthModeBlindOrManual():
          final localSecretKey = LocalSecretKeyAndSalt.random();
          final authMode = await AuthModeKeyStoredOnDevice.encrypt(
            masterKey,
            localSecretKey.key,
            keyOrigin: SecretKeyOrigin.random,
            secureWithBiometrics: localSecretInput.secureWithBiometrics,
          );

          return (localSecretKey, authMode);
      }
  }
}
