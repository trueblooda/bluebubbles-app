import 'dart:async';
import 'package:bluebubbles/layouts/setup/splash_screen.dart';
import 'package:collection/collection.dart';
import 'package:bluebubbles/repository/models/platform_file.dart';
import 'package:dynamic_cached_fonts/dynamic_cached_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:universal_io/io.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:isolate';
import 'dart:ui';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles/helpers/attachment_downloader.dart';
import 'package:bluebubbles/helpers/constants.dart';
import 'package:bluebubbles/helpers/logger.dart';
import 'package:bluebubbles/helpers/navigator.dart';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/layouts/conversation_list/conversation_list.dart';
import 'package:bluebubbles/layouts/conversation_view/conversation_view.dart';
import 'package:bluebubbles/layouts/setup/failure_to_start.dart';
import 'package:bluebubbles/layouts/setup/setup_view.dart';
import 'package:bluebubbles/layouts/testing_mode.dart';
import 'package:bluebubbles/managers/background_isolate.dart';
import 'package:bluebubbles/managers/incoming_queue.dart';
import 'package:bluebubbles/managers/life_cycle_manager.dart';
import 'package:bluebubbles/managers/method_channel_interface.dart';
import 'package:bluebubbles/managers/navigator_manager.dart';
import 'package:bluebubbles/managers/notification_manager.dart';
import 'package:bluebubbles/managers/queue_manager.dart';
import 'package:bluebubbles/managers/settings_manager.dart';
import 'package:bluebubbles/repository/database.dart';
import 'package:bluebubbles/repository/models/theme_object.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:firebase_dart/firebase_dart.dart';
//ignore: implementation_imports
import 'package:firebase_dart/src/auth/utils.dart' as fdu;
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:secure_application/secure_application.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:window_manager/window_manager.dart';

// final SentryClient _sentry = SentryClient(
//     dsn:
//         "https://3123d4f0d82d405190cb599d0e904adc@o373132.ingest.sentry.io/5372783");

bool get isInDebugMode {
  // Assume you're in production mode.
  bool inDebugMode = false;

  // Assert expressions are only evaluated during development. They are ignored
  // in production. Therefore, this code only sets `inDebugMode` to true
  // in a development environment.
  assert(inDebugMode = true);

  return inDebugMode;
}

FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
late SharedPreferences prefs;
late FirebaseApp app;
String? recentIntent;
final RxBool fontExistsOnDisk = false.obs;

Future<Null> _reportError(dynamic error, dynamic stackTrace) async {
  // Print the exception to the console.
  Logger.error('Caught error: $error');
  Logger.error(stackTrace.toString());
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // If there is a bad certificate callback, override it if the host is part of
      // your server URL
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        String serverUrl = getServerAddress() ?? "";
        return serverUrl.contains(host);
      }; // add your localhost detection logic here if you want
  }
}

Future<Null> main() async {
  HttpOverrides.global = MyHttpOverrides();

  // This captures errors reported by the Flutter framework.
  FlutterError.onError = (FlutterErrorDetails details) {
    Logger.error(details.exceptionAsString());
    Logger.error(details.stack.toString());
    if (isInDebugMode) {
      // In development mode simply print to console.
      FlutterError.dumpErrorToConsole(details);
    } else {
      // In production mode report to the application zone to report to
      // Sentry.
      Zone.current.handleUncaughtError(details.exception, details.stack!);
    }
  };

  WidgetsFlutterBinding.ensureInitialized();
  dynamic exception;
  try {
    prefs = await SharedPreferences.getInstance();
    if (!kIsWeb) await DBProvider.db.initDB();
    FirebaseDart.setup(
      platform: fdu.Platform.web(
        currentUrl: Uri.base.toString(),
        isMobile: false,
        isOnline: true,
      ),
    );
    var options = FirebaseOptions(
        appId: 'my_app_id',
        apiKey: 'apiKey',
        projectId: 'my_project',
        messagingSenderId: 'ignore',
        authDomain: 'my_project.firebaseapp.com');
    app = await Firebase.initializeApp(options: options);
    await initializeDateFormatting();
    await SettingsManager().init();
    await SettingsManager().getSavedSettings(headless: true);
    if (SettingsManager().settings.immersiveMode.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // this is to avoid a fade-in transition between the android native splash screen
    // and our dummy splash screen
    if (!SettingsManager().settings.finishedSetup.value && !kIsWeb && !kIsDesktop) {
      runApp(
        MaterialApp(
          home: SplashScreen(shouldNavigate: false),
          theme: ThemeData(
              backgroundColor: SchedulerBinding.instance!.window.platformBrightness == Brightness.dark
                  ? Colors.black : Colors.white
          )
        )
      );
    }
    Get.put(AttachmentDownloadService());
    if (!kIsWeb && !kIsDesktop) {
      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('ic_stat_icon');
      final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin!.initialize(initializationSettings);
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await FlutterNativeTimezone.getLocalTimezone()));
      if (!await GoogleMlKit.nlp.entityModelManager().isModelDownloaded(EntityExtractorOptions.ENGLISH)) {
        GoogleMlKit.nlp.entityModelManager().downloadModel(EntityExtractorOptions.ENGLISH, isWifiRequired: false);
      }
      await FlutterLibphonenumber().init();
    }
    if (kIsDesktop) {
      await WindowManager.instance.setTitle('BlueBubbles (Beta)');
      WindowManager.instance.addListener(DesktopWindowListener());
    }
    if (!kIsWeb) {
      try {
        DynamicCachedFonts.loadCachedFont("https://github.com/tneotia/tneotia/releases/download/ios-font-1/IOS.14.2.Daniel.L.ttf", fontFamily: "Apple Color Emoji").then((_) {
          fontExistsOnDisk.value = true;
        });
      } on StateError catch (_) {
        fontExistsOnDisk.value = false;
      }
    }
  } catch (e) {
    exception = e;
  }

  if (exception == null) {
    runZonedGuarded<Future<Null>>(() async {
      ThemeObject light = await ThemeObject.getLightTheme();
      ThemeObject dark = await ThemeObject.getDarkTheme();

      runApp(Main(
        lightTheme: light.themeData,
        darkTheme: dark.themeData,
      ));
    }, (Object error, StackTrace stackTrace) async {
      // Whenever an error occurs, call the `_reportError` function. This sends
      // Dart errors to the dev console or Sentry depending on the environment.
      await _reportError(error, stackTrace);
    });
  } else {
    runApp(FailureToStart(e: exception));
    throw Exception(exception);
  }
}

class DesktopWindowListener extends WindowListener {
  @override
  void onWindowFocus() {
    LifeCycleManager().opened();
  }

  @override
  void onWindowBlur() {
    LifeCycleManager().close();
  }
}

/// The [Main] app.
///
/// This is the entry for the whole app (when the app is visible or not fully closed in the background)
/// This main widget controls
///     - Theming
///     - [NavgatorManager]
///     - [Home] widget
class Main extends StatelessWidget with WidgetsBindingObserver {
  final ThemeData darkTheme;
  final ThemeData lightTheme;
  const Main({Key? key, required this.lightTheme, required this.darkTheme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      /// These are the default white and dark themes.
      /// These will be changed by [SettingsManager] when you set a custom theme
      light: lightTheme,
      dark: darkTheme,

      /// The default is that the dark and light themes will follow the system theme
      /// This will be changed by [SettingsManager]
      initial: AdaptiveThemeMode.system,
      builder: (theme, darkTheme) => GetMaterialApp(
        /// Hide the debug banner in debug mode
        debugShowCheckedModeBanner: false,

        title: 'BlueBubbles',

        /// Set the light theme from the [AdaptiveTheme]
        theme: theme.copyWith(appBarTheme: theme.appBarTheme.copyWith(elevation: 0.0)),

        /// Set the dark theme from the [AdaptiveTheme]
        darkTheme: darkTheme.copyWith(appBarTheme: darkTheme.appBarTheme.copyWith(elevation: 0.0)),

        /// [NavigatorManager] is set as the navigator key so that we can control navigation from anywhere
        navigatorKey: NavigatorManager().navigatorKey,

        /// [Home] is the starting widget for the app
        home: Home(),

        builder: (context, child) => SecureApplication(
          child: Builder(builder: (context) {
            if (SettingsManager().canAuthenticate && !LifeCycleManager().isAlive) {
              if (SettingsManager().settings.shouldSecure.value) {
                SecureApplicationProvider.of(context, listen: false)!.lock();
                if (SettingsManager().settings.securityLevel.value == SecurityLevel.locked_and_secured) {
                  SecureApplicationProvider.of(context, listen: false)!.secure();
                }
              }
            }
            return SecureGate(
              blurr: 0,
              opacity: 1.0,
              lockedBuilder: (context, controller) => Container(
                color: Theme.of(context).backgroundColor,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          "BlueBubbles is currently locked. Please unlock to access your messages.",
                          style: Theme.of(context).textTheme.bodyText1!.apply(fontSizeFactor: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Container(height: 20.0),
                      ClipOval(
                        child: Material(
                          color: Theme.of(context).primaryColor, // button color
                          child: InkWell(
                            child: SizedBox(width: 60, height: 60, child: Icon(Icons.lock_open, color: Colors.white)),
                            onTap: () async {
                              var localAuth = LocalAuthentication();
                              bool didAuthenticate = await localAuth.authenticate(
                                  localizedReason: 'Please authenticate to unlock BlueBubbles', stickyAuth: true);
                              if (didAuthenticate) {
                                controller!.authSuccess(unlock: true);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: child ?? Container(),
            );
          }),
        ),

        defaultTransition: Transition.cupertino,

        getPages: [
          GetPage(page: () => TestingMode(), name: "/testing-mode", binding: TestingModeBinding()),
        ],
      ),
    );
  }
}

/// [Home] widget is responsible for holding the main UI view.
///
/// It renders the main view and also initializes a few managers
///
/// The [LifeCycleManager] also is binded to the [WidgetsBindingObserver]
/// so that it can know when the app is closed, paused, or resumed
class Home extends StatefulWidget {
  Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  ReceivePort port = ReceivePort();
  bool serverCompatible = true;
  bool fullyLoaded = false;

  @override
  void initState() {
    super.initState();

    // we want to refresh the page rather than loading a new instance of [Home]
    // to avoid errors
    if (LifeCycleManager().isAlive && kIsWeb) {
      html.window.location.reload();
    }

    // Initalize a bunch of managers
    MethodChannelInterface().init();

    // We initialize the [LifeCycleManager] so that it is open, because [initState] occurs when the app is opened
    LifeCycleManager().opened();

    if (!kIsWeb && !kIsDesktop) {
      // This initialization sets the function address in the native code to be used later
      BackgroundIsolateInterface.initialize();

      // Create the notification in case it hasn't been already. Doing this multiple times won't do anything, so we just do it on every app start
      NotificationManager().createNotificationChannel(
        NotificationManager.NEW_MESSAGE_CHANNEL,
        "New Messages",
        "For new messages retreived",
      );
      NotificationManager().createNotificationChannel(
        NotificationManager.SOCKET_ERROR_CHANNEL,
        "Socket Connection Error",
        "Notifications that will appear when the connection to the server has failed",
      );

      // create a send port to receive messages from the background isolate when
      // the UI thread is active
      final result = IsolateNameServer.registerPortWithName(port.sendPort, 'bg_isolate');
      if (!result) {
        IsolateNameServer.removePortNameMapping('bg_isolate');
        IsolateNameServer.registerPortWithName(port.sendPort, 'bg_isolate');
      }
      port.listen((dynamic data) {
        Logger.info("SendPort received action ${data['action']}");
        if (data['action'] == 'new-message') {
          // Add it to the queue with the data as the item
          IncomingQueue().add(QueueItem(event: IncomingQueue.HANDLE_MESSAGE_EVENT, item: {"data": data}));
        } else if (data['action'] == 'update-message') {
          // Add it to the queue with the data as the item
          IncomingQueue().add(QueueItem(event: IncomingQueue.HANDLE_UPDATE_MESSAGE, item: {"data": data}));
        }
      });
    }

    // Get the saved settings from the settings manager after the first frame
    SchedulerBinding.instance!.addPostFrameCallback((_) async {
      await SettingsManager().getSavedSettings(context: context);

      if (SettingsManager().settings.colorsFromMedia.value) {
        try {
          await MethodChannelInterface().invokeMethod("start-notif-listener");
        } catch (_) {}
      }

      if (kIsWeb) {
        String? version = await SettingsManager().getServerVersion();
        int? sum = version?.split(".").mapIndexed((index, e) {
          if (index == 0) return int.parse(e) * 100;
          if (index == 1) return int.parse(e) * 21;
          return int.parse(e);
        }).sum;
        if (version == null || (sum ?? 0) < 42) {
          setState(() {
            serverCompatible = false;
          });
        }
      }

      if (!kIsWeb && !kIsDesktop) {
        // Get sharing media from files shared to the app from cold start
        // This one only handles files, not text
        ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) async {
          if (!SettingsManager().settings.finishedSetup.value) return;
          if (value.isEmpty) return;

          // If we don't have storage permission, we can't do anything
          if (!await Permission.storage.request().isGranted) return;

          // Add the attached files to a list
          List<PlatformFile> attachments = [];
          for (SharedMediaFile element in value) {
            attachments.add(PlatformFile(
              name: element.path.split("/").last,
              path: element.path,
              size: 0,
            ));
          }

          if (attachments.isEmpty) return;

          // Go to the new chat creator, with all of our attachments
          CustomNavigator.pushAndRemoveUntil(
            context,
            ConversationView(
              existingAttachments: attachments,
              isCreator: true,
            ),
                (route) => route.isFirst,
          );
        });

        // Same thing as [getInitialMedia] except for text
        ReceiveSharingIntent.getInitialText().then((String? text) {
          if (!SettingsManager().settings.finishedSetup.value) return;
          if (text == null) return;

          // Go to the new chat creator, with all of our text
          CustomNavigator.pushAndRemoveUntil(
            context,
            ConversationView(
              existingText: text,
              isCreator: true,
            ),
                (route) => route.isFirst,
          );
        });

        // Request native code to retreive what the starting intent was
        //
        // The starting intent will be set when you click on a notification
        // This is only really necessary when opening a notification and the app is fully closed
        MethodChannelInterface().invokeMethod("get-starting-intent").then((value) {
          if (!SettingsManager().settings.finishedSetup.value) return;
          if (value != null) {
            LifeCycleManager().isBubble = value['bubble'] == "true";
            MethodChannelInterface().openChat(value['guid'].toString());
          }
        });
      }
      if (!SettingsManager().settings.finishedSetup.value) {
        setState(() {
          fullyLoaded = true;
        });
      }
    });

    // Bind the lifecycle events
    WidgetsBinding.instance!.addObserver(this);
  }

  @override
  void didChangeDependencies() async {
    Locale myLocale = Localizations.localeOf(context);
    SettingsManager().countryCode = myLocale.countryCode;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    // Clean up observer when app is fully closed
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  /// Called when the app is either closed or opened or paused
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Call the [LifeCycleManager] events based on the [state]
    if (state == AppLifecycleState.paused) {
      SystemChannels.textInput.invokeMethod('TextInput.hide').catchError((e) {
        Logger.error("Error caught while hiding keyboard: ${e.toString()}");
      });
      LifeCycleManager().close();
    } else if (state == AppLifecycleState.resumed) {
      LifeCycleManager().opened();
    }
  }

  /// Render
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: SettingsManager().settings.immersiveMode.value ? Colors.transparent : Theme.of(context).backgroundColor, // navigation bar color
      systemNavigationBarIconBrightness:
          Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
      statusBarColor: Colors.transparent, // status bar color
    ));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: SettingsManager().settings.immersiveMode.value ? Colors.transparent : Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        // The stream builder connects to the [SocketManager] to check if the app has finished the setup or not
        body: Builder(
          builder: (BuildContext context) {
            if (SettingsManager().settings.finishedSetup.value) {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeRight,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ]);
              if (!serverCompatible && kIsWeb) {
                return FailureToStart(otherTitle: "Server version too low, please upgrade!", e: "Required Server Version: v0.2.0",);
              }
              return ConversationList(
                showArchivedChats: false,
                showUnknownSenders: false,
              );
            } else {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
              ]);
              return WillPopScope(
                onWillPop: () async => false,
                child: kIsWeb || kIsDesktop
                    ? SetupView() : SplashScreen(shouldNavigate: fullyLoaded),
              );
            }
          },
        ),
      ),
    );
  }
}
