import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/config/frontface_chat_config.dart';
import 'src/config/frontface_chat_strings.dart';
import 'src/config/frontface_chat_theme.dart';
import 'src/provider/frontface_chat_provider.dart';
import 'src/ui/frontface_chat_screen.dart';

export 'src/config/frontface_chat_config.dart';
export 'src/config/frontface_chat_strings.dart';
export 'src/config/frontface_chat_theme.dart';
export 'src/models/frontface_models.dart';
export 'src/provider/frontface_chat_provider.dart';
export 'src/ui/frontface_chat_screen.dart';
export 'src/ui/widgets/frontface_lead_form.dart';
export 'src/ui/widgets/frontface_message_bubble.dart';

/// Entry point for opening FrontFace chat in your Flutter app.
class FrontFaceChat {
  FrontFaceChat._();

  /// Opens the chat screen as a full-screen route.
  ///
  /// Creates a scoped [FrontFaceChatProvider] for the route and disposes it
  /// when the user closes the screen.
  ///
  /// ```dart
  /// await FrontFaceChat.open(
  ///   context,
  ///   config: FrontFaceChatConfig(
  ///     projectId: 'your-project-uuid',
  ///     publishableKey: 'pk_...',
  ///   ),
  /// );
  /// ```
  static Future<void> open(
    BuildContext context, {
    required FrontFaceChatConfig config,
    FrontFaceChatTheme theme = const FrontFaceChatTheme(),
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => ChangeNotifierProvider(
          create: (_) => FrontFaceChatProvider(
            config: config,
            strings: strings,
          ),
          child: FrontFaceChatScreen(theme: theme),
        ),
      ),
    );
  }

  /// Returns a [FrontFaceChatProvider] you can register in your app's
  /// global provider tree (e.g. with `MultiProvider`).
  ///
  /// Use this when you want to navigate with your own route or keep chat
  /// state alive across screens.
  static FrontFaceChatProvider createProvider({
    required FrontFaceChatConfig config,
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
  }) {
    return FrontFaceChatProvider(config: config, strings: strings);
  }

  /// A floating action button that opens the chat screen.
  ///
  /// ```dart
  /// floatingActionButton: FrontFaceChat.fab(
  ///   context,
  ///   config: config,
  ///   backgroundColor: Colors.black,
  /// ),
  /// ```
  static Widget fab(
    BuildContext context, {
    required FrontFaceChatConfig config,
    FrontFaceChatTheme theme = const FrontFaceChatTheme(),
    FrontFaceChatStrings strings = const FrontFaceChatStrings(),
    Color? backgroundColor,
    Color? foregroundColor,
    IconData icon = Icons.chat_bubble_outline,
  }) {
    return FloatingActionButton(
      backgroundColor: backgroundColor ?? theme.primaryColor,
      foregroundColor: foregroundColor ?? theme.onPrimaryColor,
      onPressed: () => open(
        context,
        config: config,
        theme: theme,
        strings: strings,
      ),
      child: Icon(icon),
    );
  }
}
